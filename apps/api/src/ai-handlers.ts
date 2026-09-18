import { createHash } from 'node:crypto';
import { detectsPromptInjection, safeAssistantSystem, untrustedContent } from '../../../packages/contracts/src/ai.ts';
import type { DomainArgs } from './domain-types.ts';
import { bodyString, HttpError, send } from './http.ts';
import { OpenAICompatibleProvider } from './providers/llm.ts';
import { readJson } from './security.ts';
import { adminSupabase, userSupabase } from './supabase.ts';

export const aiRoutes=new Set([
  'GET /ai/config','PUT /ai/config','POST /ai/simulate','GET /ai/history',
  'GET /knowledge','POST /knowledge/sources','POST /knowledge/documents','POST /knowledge/approve',
  'GET /privacy/requests','POST /privacy/requests'
]);
function databaseError(error:{code?:string}|null,code:string){if(error)throw new HttpError(error.code==='42501'?403:503,code);}

export async function handleAi(args:DomainArgs) {
  const {req,res,url,path,config,auth,tenant}=args;const org=tenant.context.organizationId,unit=tenant.context.unitId;
  const client=userSupabase(config,auth.accessToken),admin=adminSupabase(config);
  if(req.method==='GET'&&path==='/ai/config') {
    const result=await client.from('ai_assistant_configs').select('*').eq('organization_id',org).eq('unit_id',unit).maybeSingle();
    databaseError(result.error,'assistant_config_unavailable');return send(res,200,{config:result.data,providerConfigured:Boolean(config.llmApiUrl&&config.llmApiKey&&config.llmModel)});
  }
  if(req.method==='PUT'&&path==='/ai/config') {
    const body=await readJson(req,65536);const row={organization_id:org,unit_id:unit,assistant_name:bodyString(body,'assistantName',2,80),
      enabled:body.enabled===true,tone:bodyString(body,'tone',2,500),business_hours:objectValue(body.businessHours),objectives:arrayValue(body.objectives,30),
      qualification_questions:arrayValue(body.qualificationQuestions,30),welcome_messages:arrayValue(body.welcomeMessages,20),
      commercial_rules:arrayValue(body.commercialRules,50),transfer_triggers:arrayValue(body.transferTriggers,30),
      queue_id:typeof body.queueId==='string'?body.queueId:null,max_messages_per_conversation:bounded(body.maxMessages,1,200,30),
      daily_budget_cents:bounded(body.dailyBudgetCents,0,10000000,1000),monthly_budget_cents:bounded(body.monthlyBudgetCents,0,100000000,20000),updated_by:auth.userId,updated_at:new Date().toISOString()};
    const result=await client.from('ai_assistant_configs').upsert(row,{onConflict:'organization_id,unit_id'}).select().single();databaseError(result.error,'assistant_config_save_failed');return send(res,200,{config:result.data});
  }
  if(req.method==='POST'&&path==='/ai/simulate') {
    if(!config.llmApiUrl||!config.llmApiKey||!config.llmModel)throw new HttpError(409,'llm_provider_not_configured');
    const body=await readJson(req,32768);const message=untrustedContent(body.message,4000);
    const cfg=await client.from('ai_assistant_configs').select('*').eq('organization_id',org).eq('unit_id',unit).maybeSingle();databaseError(cfg.error,'assistant_config_unavailable');
    if(!cfg.data?.enabled)throw new HttpError(409,'assistant_disabled');
    const started=Date.now();const run=await admin.from('ai_runs').insert({organization_id:org,unit_id:unit,provider:'openai-compatible',model:config.llmModel,status:'started'}).select('id').single();
    databaseError(run.error,'ai_run_rejected');if(!run.data)throw new HttpError(503,'ai_run_rejected');const runId=run.data.id;
    if(detectsPromptInjection(message)) {
      await admin.from('ai_runs').update({status:'blocked',result_code:'prompt_injection_blocked',transfer_reason:'Conteúdo solicitou violação das regras.',completed_at:new Date().toISOString(),latency_ms:Date.now()-started}).eq('id',runId);
      return send(res,200,{status:'transferred',answer:'Vou chamar uma pessoa da equipe para continuar este atendimento.',sources:[]});
    }
    const [facts,knowledge]=await Promise.all([
      admin.from('academy_facts').select('id,facts,confirmed_at').eq('organization_id',org).eq('unit_id',unit).order('confirmed_at',{ascending:false}).limit(1),
      admin.rpc('search_authorized_knowledge',{p_organization_id:org,p_unit_id:unit,p_query:message,p_limit:8})
    ]);databaseError(facts.error,'facts_unavailable');databaseError(knowledge.error,'knowledge_unavailable');
    const factLines=facts.data?.[0]?Object.entries(facts.data[0].facts as Record<string,unknown>).map(([key,value])=>key+': '+String(value)).slice(0,80):[];
    const excerpts=(knowledge.data??[]) as {source_id:string;version_id:string;content:string}[];
    if(!factLines.length&&!excerpts.length) {
      await admin.from('ai_runs').update({status:'transferred',result_code:'no_authorized_source',transfer_reason:'Nenhuma fonte aprovada respondeu à pergunta.',completed_at:new Date().toISOString(),latency_ms:Date.now()-started}).eq('id',runId);
      return send(res,200,{status:'transferred',answer:'Ainda não tenho uma informação confirmada sobre isso. Vou chamar uma pessoa da equipe.',sources:[]});
    }
    const sourceLines=[...factLines,...excerpts.map(item=>item.content)];const system=safeAssistantSystem(sourceLines,arrayValue(cfg.data.commercial_rules,50));
    const provider=new OpenAICompatibleProvider({baseUrl:config.llmApiUrl,apiKey:config.llmApiKey,model:config.llmModel});
    try {
      const answer=await provider.complete({system,messages:[{role:'user',content:message}],tools:[]});
      const sources=[...(facts.data?.[0]?[{kind:'academy_facts',id:facts.data[0].id}]:[]),...excerpts.map(item=>({kind:'document',sourceId:item.source_id,versionId:item.version_id}))];
      await admin.from('ai_runs').update({status:'completed',input_tokens:answer.inputTokens,output_tokens:answer.outputTokens,
        estimated_cost_cents:0,latency_ms:Date.now()-started,sources_used:sources,result_code:'answered',completed_at:new Date().toISOString()}).eq('id',runId);
      return send(res,200,{status:'answered',answer:answer.text,sources});
    } catch(error) {
      const code=error instanceof Error&&/^llm_[a-z0-9_]+$/.test(error.message)?error.message:'llm_failed';
      await admin.from('ai_runs').update({status:'failed',error_code:code,completed_at:new Date().toISOString(),latency_ms:Date.now()-started}).eq('id',runId);
      throw new HttpError(502,'assistant_provider_failed');
    }
  }
  if(req.method==='GET'&&path==='/ai/history') {
    const limit=Math.min(Math.max(Number(url.searchParams.get('limit')??25),1),100);const result=await client.from('ai_runs')
      .select('id,provider,model,status,input_tokens,output_tokens,estimated_cost_cents,latency_ms,result_code,error_code,transfer_reason,sources_used,started_at,completed_at')
      .eq('organization_id',org).eq('unit_id',unit).order('started_at',{ascending:false}).limit(limit);databaseError(result.error,'ai_history_unavailable');return send(res,200,{items:result.data??[]});
  }
  if(req.method==='GET'&&path==='/knowledge') {
    const [sources,documents]=await Promise.all([
      client.from('knowledge_sources').select('*').eq('organization_id',org).or(`unit_id.is.null,unit_id.eq.${unit}`).order('created_at',{ascending:false}).limit(100),
      client.from('knowledge_documents').select('*,knowledge_document_versions(*)').eq('organization_id',org).or(`unit_id.is.null,unit_id.eq.${unit}`).order('created_at',{ascending:false}).limit(100)
    ]);databaseError(sources.error,'knowledge_unavailable');return send(res,200,{sources:sources.data??[],documents:documents.data??[]});
  }
  if(req.method==='POST'&&path==='/knowledge/sources') {
    const body=await readJson(req);const result=await client.from('knowledge_sources').insert({organization_id:org,unit_id:body.organizationWide===true?null:unit,
      source_kind:enumText(body.kind,['academy_facts','document','manual','url_import'],'source_kind'),name:bodyString(body,'name',2,160),
      origin:typeof body.origin==='string'?body.origin.slice(0,500):null,status:'draft',created_by:auth.userId}).select().single();databaseError(result.error,'knowledge_source_save_failed');return send(res,201,{source:result.data});
  }
  if(req.method==='POST'&&path==='/knowledge/documents') {
    const body=await readJson(req,262144);const content=untrustedContent(body.content,200000);const sourceId=bodyString(body,'sourceId',36,36);const sha=createHash('sha256').update(content).digest('hex');
    const authorization=await admin.rpc('crm_authorize',{p_actor_id:auth.userId,p_organization_id:org,p_unit_id:unit,p_capability:'configure'});
    if(authorization.error||authorization.data!==true)throw new HttpError(403,'knowledge_write_denied');
    const chunks=chunkContent(content);const result=await admin.rpc('ingest_knowledge_document',{p_actor_id:auth.userId,p_organization_id:org,p_unit_id:unit,
      p_source_id:sourceId,p_title:bodyString(body,'title',2,200),p_content_sha256:sha,p_chunks:chunks});
    databaseError(result.error,'knowledge_document_save_failed');return send(res,201,{document:result.data,indexing:'ready',status:'draft'});
  }
  if(req.method==='POST'&&path==='/knowledge/approve') {
    const body=await readJson(req);const result=await client.rpc('approve_knowledge_version',{p_organization_id:org,p_unit_id:unit,
      p_source_id:bodyString(body,'sourceId',36,36),p_version_id:bodyString(body,'versionId',36,36),
      p_valid_until:body.validUntil?new Date(String(body.validUntil)).toISOString():null});
    databaseError(result.error,'knowledge_approval_failed');return send(res,200,{knowledge:result.data});
  }
  if(req.method==='GET'&&path==='/privacy/requests') {
    const result=await client.from('privacy_requests').select('*').eq('organization_id',org).order('requested_at',{ascending:false}).limit(100);databaseError(result.error,'privacy_requests_unavailable');return send(res,200,{items:result.data??[]});
  }
  if(req.method==='POST'&&path==='/privacy/requests') {
    const body=await readJson(req);const result=await client.from('privacy_requests').insert({organization_id:org,unit_id:unit,contact_id:bodyString(body,'contactId',36,36),
      request_kind:enumText(body.kind,['export','anonymize','correct','restrict'],'request_kind'),status:'requested',notes:typeof body.notes==='string'?body.notes.slice(0,2000):null}).select().single();databaseError(result.error,'privacy_request_save_failed');return send(res,201,{request:result.data});
  }
  return false;
}

function bounded(value:unknown,min:number,max:number,fallback:number){const number=Number(value??fallback);if(!Number.isInteger(number)||number<min||number>max)throw new HttpError(400,'invalid_number');return number;}
function objectValue(value:unknown){if(value===undefined)return {};if(!value||typeof value!=='object'||Array.isArray(value))throw new HttpError(400,'invalid_object');return value;}
function arrayValue(value:unknown,max:number):string[]{if(value===undefined)return [];if(!Array.isArray(value)||value.length>max||value.some(item=>typeof item!=='string'||item.length>500))throw new HttpError(400,'invalid_list');return value.map(String);}
function enumText<T extends string>(value:unknown,allowed:readonly T[],name:string):T{if(typeof value!=='string'||!allowed.includes(value as T))throw new HttpError(400,'invalid_'+name);return value as T;}
function chunkContent(content:string) {
  const paragraphs=content.split(/\n{2,}/).map(value=>value.trim()).filter(Boolean);const chunks:string[]=[];let current='';
  for(const paragraph of paragraphs){if(paragraph.length>7600){if(current)chunks.push(current);current='';for(let index=0;index<paragraph.length;index+=7600)chunks.push(paragraph.slice(index,index+7600));continue;}
    if(current&&current.length+paragraph.length+2>7600){chunks.push(current);current=paragraph;}else current+=(current?'\n\n':'')+paragraph;
  }
  if(current)chunks.push(current);return chunks.slice(0,250);
}
