import { createHash, createHmac, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { cursorPage, idempotencyKey, uuidValue } from '../../../packages/contracts/src/crm.ts';
import type { RuntimeConfig } from './config.ts';
import type { DomainArgs } from './domain-types.ts';
import { bodyString, correlationId, HttpError, rateLimit, send } from './http.ts';
import { assertSafeProviderUrl } from './network-security.ts';
import { EvolutionWhatsAppProvider } from './providers/evolution.ts';
import { randomToken, readJson, sha256 } from './security.ts';
import { adminSupabase, userSupabase } from './supabase.ts';

export const inboxRoutes=new Set([
  'GET /channels','POST /channels/evolution','POST /channels/pause','POST /channels/revoke','GET /inbox/conversations','GET /inbox/conversation',
  'POST /inbox/takeover','POST /inbox/return-to-ai','POST /inbox/messages','GET /queues','POST /queues'
]);

function databaseError(error:{code?:string}|null,code:string) {if(error)throw new HttpError(error.code==='42501'?403:503,code);}
async function authorized(config:RuntimeConfig,actor:string,org:string,unit:string,capability:string) {
  const result=await adminSupabase(config).rpc('crm_authorize',{p_actor_id:actor,p_organization_id:org,p_unit_id:unit,p_capability:capability});
  if(result.error||result.data!==true)throw new HttpError(403,'crm_access_denied');
}

export async function handleInbox(args:DomainArgs) {
  const {req,res,url,path,config,auth,tenant}=args;const org=tenant.context.organizationId,unit=tenant.context.unitId;
  const client=userSupabase(config,auth.accessToken),admin=adminSupabase(config);
  if(req.method==='GET'&&path==='/channels') {
    await authorized(config,auth.userId,org,unit,'configure');
    const result=await admin.from('channel_connections').select('id,provider,name,status,capabilities,health,last_synced_at,last_error_code,created_at')
      .eq('organization_id',org).eq('unit_id',unit).order('created_at');databaseError(result.error,'channels_unavailable');
    const configured=new Set((result.data??[]).map(row=>row.provider));
    const prepared=[...result.data??[],...(['whatsapp','instagram','tiktok'] as const).filter(provider=>!configured.has(provider)).map(provider=>({
      id:null,provider,name:provider==='whatsapp'?'WhatsApp Evolution':provider==='instagram'?'Instagram Direct':'TikTok',status:'unconfigured',capabilities:{},health:{},last_synced_at:null,last_error_code:null
    }))];
    return send(res,200,{channels:prepared});
  }
  if(req.method==='POST'&&path==='/channels/evolution') {
    await authorized(config,auth.userId,org,unit,'configure');
    if(!config.publicWebhookBaseUrl)throw new HttpError(409,'public_webhook_url_required');
    const body=await readJson(req,32768);const baseUrl=await assertSafeProviderUrl(body.baseUrl,!config.production);
    const name=bodyString(body,'name',2,100),instance=bodyString(body,'instance',1,120),apiKey=bodyString(body,'apiKey',20,500);
    const opaque=randomToken(32),webhookSecret=randomToken(32),hookUrl=config.publicWebhookBaseUrl+'/api/webhooks/evolution/'+opaque;
    const result=await admin.rpc('configure_evolution_channel',{p_actor_id:auth.userId,p_organization_id:org,p_unit_id:unit,p_name:name,
      p_base_url:baseUrl,p_instance:instance,p_api_key:apiKey,p_webhook_secret:webhookSecret,p_webhook_token_hash:sha256(opaque)});
    databaseError(result.error,'channel_save_failed');const id=String(result.data);
    const provider=new EvolutionWhatsAppProvider({baseUrl,instance,apiKey});
    let status='active',health:Record<string,unknown>={ok:true};let errorCode:string|null=null;
    try {await provider.configureWebhook(hookUrl,webhookSecret);health=await provider.health();if(!health.ok){status='degraded';errorCode='provider_unhealthy';}}
    catch(error){status='degraded';errorCode=error instanceof Error&&/^evolution_http_\d+$/.test(error.message)?error.message:'provider_configuration_failed';health={ok:false,status:errorCode};}
    await admin.from('channel_connections').update({status,health,last_error_code:errorCode,last_synced_at:new Date().toISOString()}).eq('id',id);
    return send(res,201,{channel:{id,name,provider:'whatsapp',status,health}});
  }
  if(req.method==='POST'&&path==='/channels/revoke') {
    await authorized(config,auth.userId,org,unit,'configure');const body=await readJson(req);
    const result=await admin.rpc('revoke_channel',{p_actor_id:auth.userId,p_connection_id:uuidValue(body.connectionId,'connection_id')});
    databaseError(result.error,'channel_revoke_failed');return send(res,200,{revoked:true});
  }
  if(req.method==='POST'&&path==='/channels/pause') {
    await authorized(config,auth.userId,org,unit,'configure');const body=await readJson(req);const id=uuidValue(body.connectionId,'connection_id');
    const connection=await admin.from('channel_connections').select('id,status').eq('organization_id',org).eq('unit_id',unit).eq('id',id).maybeSingle();
    databaseError(connection.error,'channel_unavailable');if(!connection.data||connection.data.status==='revoked')throw new HttpError(404,'channel_unavailable');
    let status='paused',health:Record<string,unknown>={ok:false,status:'paused'};
    if(body.paused!==true){const runtime=await admin.rpc('channel_runtime_secret',{p_connection_id:id});databaseError(runtime.error,'channel_unavailable');
      const secret=runtime.data as Record<string,unknown>,baseUrl=await assertSafeProviderUrl(String(secret.base_url),!config.production);
      health=await new EvolutionWhatsAppProvider({baseUrl,instance:String(secret.external_instance),apiKey:String(secret.api_key)}).health();status=health.ok?'active':'degraded';}
    const update=await admin.from('channel_connections').update({status,health,last_synced_at:new Date().toISOString(),last_error_code:status==='degraded'?'provider_unhealthy':null}).eq('id',id);
    databaseError(update.error,'channel_update_failed');await admin.from('audit_events').insert({organization_id:org,actor_id:auth.userId,action:status==='paused'?'channel:paused':'channel:resumed',entity_id:id});
    return send(res,200,{channel:{id,status,health}});
  }
  if(req.method==='GET'&&path==='/inbox/conversations') {
    const page=cursorPage(url.searchParams);const state=url.searchParams.get('state');
    if(state&&!['ai_active','waiting_human','human_active','paused','closed'].includes(state))throw new HttpError(400,'invalid_conversation_state');
    let query=client.from('conversations').select('id,state,priority,unread_count,last_message_at,assigned_to,subject,crm_contacts(id,display_name),channel_connections(provider,name),conversation_queues(name)')
      .eq('organization_id',org).eq('unit_id',unit).order('last_message_at',{ascending:false}).order('id',{ascending:false}).limit(page.limit+1);
    if(state)query=query.eq('state',state);if(page.cursor){const [at,id]=page.cursor.split('|');query=query.or(`last_message_at.lt.${at},and(last_message_at.eq.${at},id.lt.${id})`);}
    const result=await query;databaseError(result.error,'conversations_unavailable');const rows=result.data??[],items=rows.slice(0,page.limit),last=items.at(-1);
    return send(res,200,{items,nextCursor:rows.length>page.limit&&last?String(last.last_message_at)+'|'+String(last.id):null});
  }
  if(req.method==='GET'&&path==='/inbox/conversation') {
    const id=uuidValue(url.searchParams.get('id'),'conversation_id');
    const [conversation,messages,history]=await Promise.all([
      client.from('conversations').select('*,crm_contacts(*),crm_opportunities(*),channel_connections(provider,name,status),conversation_queues(name)').eq('organization_id',org).eq('unit_id',unit).eq('id',id).maybeSingle(),
      client.from('messages').select('*,message_attachments(id,filename,mime_type,byte_size),message_delivery_events(state,provider_at,error_code,created_at)').eq('organization_id',org).eq('unit_id',unit).eq('conversation_id',id).order('created_at',{ascending:false}).limit(100),
      client.from('conversation_assignment_history').select('*').eq('organization_id',org).eq('unit_id',unit).eq('conversation_id',id).order('created_at',{ascending:false}).limit(30)
    ]);databaseError(conversation.error,'conversation_unavailable');if(!conversation.data)throw new HttpError(404,'conversation_not_found');
    return send(res,200,{conversation:conversation.data,messages:(messages.data??[]).reverse(),assignmentHistory:history.data??[],truncated:(messages.data?.length??0)===100});
  }
  if(req.method==='POST'&&path==='/inbox/takeover') {
    const body=await readJson(req);const result=await client.rpc('takeover_conversation',{p_organization_id:org,p_unit_id:unit,
      p_conversation_id:uuidValue(body.conversationId,'conversation_id'),p_reason:bodyString(body,'reason',2,500),
      p_idempotency_key:idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey)});
    if(result.error?.code==='55P03')throw new HttpError(409,'conversation_already_owned');databaseError(result.error,'takeover_failed');return send(res,200,{conversation:result.data});
  }
  if(req.method==='POST'&&path==='/inbox/return-to-ai') {
    const body=await readJson(req);const result=await client.rpc('return_conversation_to_ai',{p_organization_id:org,p_unit_id:unit,
      p_conversation_id:uuidValue(body.conversationId,'conversation_id'),p_reason:bodyString(body,'reason',2,500)});
    databaseError(result.error,'handoff_failed');return send(res,200,{conversation:result.data});
  }
  if(req.method==='POST'&&path==='/inbox/messages') {
    const body=await readJson(req,32768);const result=await client.rpc('queue_human_message',{p_organization_id:org,p_unit_id:unit,
      p_conversation_id:uuidValue(body.conversationId,'conversation_id'),p_body:bodyString(body,'body',1,20000),
      p_reply_to:body.replyTo?uuidValue(body.replyTo,'reply_to'):null,p_idempotency_key:idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey)});
    databaseError(result.error,'message_queue_failed');return send(res,202,{message:result.data});
  }
  if(req.method==='GET'&&path==='/queues') {
    const result=await client.from('conversation_queues').select('*,queue_members(user_id,active,capacity)').eq('organization_id',org).eq('unit_id',unit).order('priority');
    databaseError(result.error,'queues_unavailable');return send(res,200,{queues:result.data??[]});
  }
  if(req.method==='POST'&&path==='/queues') {
    const body=await readJson(req);const result=await client.from('conversation_queues').insert({organization_id:org,unit_id:unit,
      name:bodyString(body,'name',2,80),priority:Number(body.priority??100),sla_first_response_seconds:Number(body.slaSeconds??900)}).select().single();
    databaseError(result.error,'queue_save_failed');return send(res,201,{queue:result.data});
  }
  return false;
}

async function rawBody(req:IncomingMessage,max=262144) {
  const chunks:Buffer[]=[];let size=0;for await(const value of req){const chunk=Buffer.from(value);size+=chunk.length;if(size>max)throw new HttpError(413,'payload_too_large');chunks.push(chunk);}return Buffer.concat(chunks);
}
function safeEqual(a:string,b:string){const aa=Buffer.from(a),bb=Buffer.from(b);return aa.length===bb.length&&timingSafeEqual(aa,bb);}

export async function handleEvolutionWebhook(req:IncomingMessage,res:ServerResponse,url:URL,config:RuntimeConfig) {
  const prefix=url.pathname.startsWith('/api/webhooks/evolution/')?'/api/webhooks/evolution/':
    url.pathname.startsWith('/webhooks/evolution/')?'/webhooks/evolution/':null;
  if(req.method!=='POST'||!prefix)return false;
  const correlation=correlationId(req);res.setHeader('X-Correlation-ID',correlation);
  rateLimit('webhook:'+String(req.socket.remoteAddress),120,60000);
  const opaque=url.pathname.slice(prefix.length);if(!/^[A-Za-z0-9_-]{32,128}$/.test(opaque))throw new HttpError(404,'webhook_not_found');
  const admin=adminSupabase(config);const connection=await admin.from('channel_connections').select('id').eq('webhook_token_hash',sha256(opaque)).maybeSingle();
  if(connection.error||!connection.data)throw new HttpError(404,'webhook_not_found');
  const secretResult=await admin.rpc('channel_runtime_secret',{p_connection_id:connection.data.id});databaseError(secretResult.error,'webhook_unavailable');
  const secret=String((secretResult.data as Record<string,unknown>).webhook_secret??'');const body=await rawBody(req);const text=body.toString('utf8');
  const timestamp=String(req.headers['x-acadeai-timestamp']??'');const signature=String(req.headers['x-acadeai-signature']??req.headers['x-evolution-signature']??'');
  const staticSecret=String(req.headers['x-acadeai-webhook-secret']??'');const seconds=Number(timestamp);
  const hmacValid=Number.isFinite(seconds)&&Math.abs(Date.now()/1000-seconds)<=300&&safeEqual(signature,createHmac('sha256',secret).update(timestamp+'.'+text).digest('hex'));
  if(!hmacValid&&!safeEqual(staticSecret,secret))throw new HttpError(401,'invalid_webhook_signature');
  let payload:Record<string,unknown>;try{payload=JSON.parse(text) as Record<string,unknown>;}catch{throw new HttpError(400,'invalid_json');}
  if(!payload||Array.isArray(payload)||typeof payload.event!=='string'||payload.data===undefined)throw new HttpError(400,'invalid_webhook_payload');
  const digest=createHash('sha256').update(body).digest('hex');const external=typeof payload.eventId==='string'?payload.eventId:
    typeof payload.id==='string'?payload.id:digest;
  const providerAt=new Date(typeof payload.date_time==='string'?payload.date_time:Date.now());if(!Number.isFinite(providerAt.valueOf())||Math.abs(Date.now()-providerAt.valueOf())>86400000)throw new HttpError(400,'invalid_webhook_timestamp');
  const queued=await admin.rpc('queue_webhook_event',{p_connection_id:connection.data.id,p_external_event_id:external.slice(0,320),p_payload_sha256:digest,
    p_provider_at:providerAt.toISOString(),p_payload:{connectionId:connection.data.id,event:payload},p_correlation_id:correlation});databaseError(queued.error,'webhook_queue_failed');
  send(res,202,{accepted:true,duplicate:queued.data===false});return true;
}
