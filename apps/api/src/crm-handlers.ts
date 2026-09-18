import { randomUUID } from 'node:crypto';
import { appointmentStatuses, contactInput, cursorPage, enumValue, idempotencyKey, taskPriorities, uuidValue } from '../../../packages/contracts/src/crm.ts';
import { HttpError, send } from './http.ts';
import { readJson } from './security.ts';
import { userSupabase } from './supabase.ts';
import type { DomainArgs } from './domain-types.ts';

export const crmRoutes=new Set([
  'GET /crm/dashboard','GET /crm/contacts','POST /crm/contacts','GET /crm/contacts/detail',
  'GET /crm/pipelines','POST /crm/opportunities','POST /crm/opportunities/move',
  'GET /crm/tasks','POST /crm/tasks','GET /crm/appointments','POST /crm/appointments','POST /crm/appointments/result'
]);

function databaseError(error:{code?:string}|null,code='crm_unavailable') {
  if(error) throw new HttpError(error.code==='42501'?403:503,code);
}
function cursorOf(row:{created_at:string;id:string}|undefined){return row?row.created_at+'|'+row.id:null;}
function cursorOfField(row:Record<string,unknown>|undefined,field:string){return row?String(row[field])+'|'+String(row.id):null;}

export async function handleCrm(args:DomainArgs) {
  const {req,res,url,path,auth,tenant}=args;
  const client=userSupabase(args.config,auth.accessToken);
  const org=tenant.context.organizationId,unit=tenant.context.unitId;
  if(req.method==='GET'&&path==='/crm/dashboard') {
    const [summary,attribution,tasks,appointments,leads]=await Promise.all([
      client.rpc('crm_dashboard',{p_organization_id:org,p_unit_id:unit}),
      client.rpc('crm_attribution_summary',{p_organization_id:org,p_unit_id:unit}),
      client.from('crm_tasks').select('id,title,priority,due_at,status').eq('organization_id',org).eq('unit_id',unit).eq('status','open').order('due_at').limit(6),
      client.from('crm_appointments').select('id,kind,starts_at,status,crm_contacts(display_name)').eq('organization_id',org).eq('unit_id',unit).gte('starts_at',new Date().toISOString()).order('starts_at').limit(6),
      client.from('crm_opportunities').select('id,title,status,created_at,crm_contacts(display_name),crm_pipeline_stages(name)').eq('organization_id',org).eq('unit_id',unit).order('created_at',{ascending:false}).limit(6)
    ]);
    databaseError(summary.error,'dashboard_unavailable');
    return send(res,200,{summary:summary.data,attribution:attribution.data??[],tasks:tasks.data??[],appointments:appointments.data??[],recentLeads:leads.data??[]});
  }
  if(req.method==='GET'&&path==='/crm/contacts') {
    const page=cursorPage(url.searchParams); let query=client.from('crm_contacts')
      .select('id,display_name,city,source,created_at,crm_contact_identifiers(kind,normalized_value)')
      .eq('organization_id',org).is('anonymized_at',null).order('created_at',{ascending:false}).order('id',{ascending:false}).limit(page.limit+1);
    if(page.cursor){const [created,id]=page.cursor.split('|');query=query.or(`created_at.lt.${created},and(created_at.eq.${created},id.lt.${id})`);}
    if(page.query) query=query.ilike('display_name','%'+page.query.replace(/[%_,()]/g,'')+'%');
    const result=await query;databaseError(result.error,'contacts_unavailable');
    const rows=result.data??[];const more=rows.length>page.limit;const items=rows.slice(0,page.limit);
    return send(res,200,{items,nextCursor:more?cursorOf(items.at(-1)):null});
  }
  if(req.method==='POST'&&path==='/crm/contacts') {
    const body=await readJson(req);const contact=contactInput(body);const key=idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey??randomUUID());
    const result=await client.rpc('upsert_crm_contact',{p_organization_id:org,p_unit_id:unit,p_name:contact.name,p_phone:contact.phone??null,
      p_email:contact.email??null,p_city:contact.city??null,p_source:contact.source??null,p_external_key:contact.externalKey??null,p_idempotency_key:key});
    databaseError(result.error,'contact_save_failed');return send(res,201,{contact:result.data});
  }
  if(req.method==='GET'&&path==='/crm/contacts/detail') {
    const id=uuidValue(url.searchParams.get('id'),'contact_id');
    const [contact,opportunities,tasks,appointments,notes,activities]=await Promise.all([
      client.from('crm_contacts').select('*,crm_contact_identifiers(*),crm_consents(*)').eq('organization_id',org).eq('id',id).maybeSingle(),
      client.from('crm_opportunities').select('*,crm_pipeline_stages(name)').eq('organization_id',org).eq('unit_id',unit).eq('contact_id',id).order('updated_at',{ascending:false}).limit(50),
      client.from('crm_tasks').select('*').eq('organization_id',org).eq('unit_id',unit).eq('contact_id',id).order('due_at').limit(50),
      client.from('crm_appointments').select('*').eq('organization_id',org).eq('unit_id',unit).eq('contact_id',id).order('starts_at',{ascending:false}).limit(50),
      client.from('crm_notes').select('*').eq('organization_id',org).eq('unit_id',unit).eq('contact_id',id).order('created_at',{ascending:false}).limit(50),
      client.from('crm_activities').select('*').eq('organization_id',org).eq('unit_id',unit).eq('contact_id',id).order('occurred_at',{ascending:false}).limit(50)
    ]);databaseError(contact.error,'contact_unavailable');if(!contact.data)throw new HttpError(404,'contact_not_found');
    return send(res,200,{contact:contact.data,opportunities:opportunities.data??[],tasks:tasks.data??[],appointments:appointments.data??[],notes:notes.data??[],activities:activities.data??[]});
  }
  if(req.method==='GET'&&path==='/crm/pipelines') {
    const pipelines=await client.from('crm_pipelines').select('*,crm_pipeline_stages(*)').eq('organization_id',org).eq('unit_id',unit).eq('active',true).order('created_at').limit(20);
    databaseError(pipelines.error,'pipelines_unavailable');
    const selected=url.searchParams.get('pipeline')??pipelines.data?.[0]?.id;
    const opportunities=selected?await client.from('crm_opportunities').select('id,title,status,stage_id,owner_id,value_cents,updated_at,crm_contacts(id,display_name),crm_pipeline_stages(name)')
      .eq('organization_id',org).eq('unit_id',unit).eq('pipeline_id',selected).eq('status','open').order('updated_at',{ascending:false}).limit(100):{data:[],error:null};
    databaseError(opportunities.error,'opportunities_unavailable');return send(res,200,{pipelines:pipelines.data??[],opportunities:opportunities.data??[],truncated:(opportunities.data?.length??0)===100});
  }
  if(req.method==='POST'&&path==='/crm/opportunities') {
    const body=await readJson(req);const key=idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey??randomUUID());
    const result=await client.rpc('create_crm_opportunity',{p_organization_id:org,p_unit_id:unit,p_contact_id:uuidValue(body.contactId,'contact_id'),
      p_pipeline_id:uuidValue(body.pipelineId,'pipeline_id'),p_stage_id:uuidValue(body.stageId,'stage_id'),p_title:String(body.title??'').trim().slice(0,160),
      p_source:typeof body.source==='string'?body.source.slice(0,80):null,p_campaign:typeof body.campaign==='string'?body.campaign.slice(0,160):null,
      p_external_key:typeof body.externalKey==='string'?body.externalKey.slice(0,160):null,p_idempotency_key:key});
    databaseError(result.error,'opportunity_create_failed');return send(res,201,{opportunity:result.data});
  }
  if(req.method==='POST'&&path==='/crm/opportunities/move') {
    const body=await readJson(req);const result=await client.rpc('move_crm_opportunity',{p_organization_id:org,p_unit_id:unit,
      p_opportunity_id:uuidValue(body.opportunityId,'opportunity_id'),p_expected_stage_id:uuidValue(body.expectedStageId,'expected_stage_id'),
      p_to_stage_id:uuidValue(body.toStageId,'to_stage_id'),p_reason:typeof body.reason==='string'?body.reason.slice(0,500):null,
      p_idempotency_key:idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey)});
    if(result.error?.code==='40001')throw new HttpError(409,'opportunity_changed');databaseError(result.error,'opportunity_move_failed');return send(res,200,{opportunity:result.data});
  }
  if(req.method==='GET'&&path==='/crm/tasks') {
    const page=cursorPage(url.searchParams);let query=client.from('crm_tasks').select('*').eq('organization_id',org).eq('unit_id',unit)
      .order('due_at').order('id').limit(page.limit+1);if(page.cursor){const [due,id]=page.cursor.split('|');query=query.or(`due_at.gt.${due},and(due_at.eq.${due},id.gt.${id})`);}
    const result=await query;databaseError(result.error,'tasks_unavailable');const rows=result.data??[],items=rows.slice(0,page.limit);
    return send(res,200,{items,nextCursor:rows.length>page.limit?cursorOfField(items.at(-1),'due_at'):null});
  }
  if(req.method==='POST'&&path==='/crm/tasks') {
    const body=await readJson(req);const due=new Date(String(body.dueAt));if(!Number.isFinite(due.valueOf()))throw new HttpError(400,'invalid_due_at');
    const result=await client.from('crm_tasks').insert({organization_id:org,unit_id:unit,contact_id:body.contactId?uuidValue(body.contactId,'contact_id'):null,
      opportunity_id:body.opportunityId?uuidValue(body.opportunityId,'opportunity_id'):null,assignee_id:uuidValue(body.assigneeId??auth.userId,'assignee_id'),created_by:auth.userId,
      title:String(body.title??'').trim().slice(0,200),priority:enumValue(body.priority??'normal',taskPriorities,'priority'),due_at:due.toISOString(),
      remind_at:body.remindAt?new Date(String(body.remindAt)).toISOString():null,idempotency_key:idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey??randomUUID())}).select().single();
    databaseError(result.error,'task_create_failed');return send(res,201,{task:result.data});
  }
  if(req.method==='GET'&&path==='/crm/appointments') {
    const page=cursorPage(url.searchParams);const from=url.searchParams.get('from')??new Date().toISOString();
    let query=client.from('crm_appointments').select('*,crm_contacts(display_name)').eq('organization_id',org).eq('unit_id',unit).gte('starts_at',from).order('starts_at').order('id').limit(page.limit+1);
    if(page.cursor){const [starts,id]=page.cursor.split('|');query=query.or(`starts_at.gt.${starts},and(starts_at.eq.${starts},id.gt.${id})`);}
    const result=await query;databaseError(result.error,'appointments_unavailable');const rows=result.data??[],items=rows.slice(0,page.limit);
    return send(res,200,{items,nextCursor:rows.length>page.limit?cursorOfField(items.at(-1),'starts_at'):null});
  }
  if(req.method==='POST'&&path==='/crm/appointments') {
    const body=await readJson(req);const starts=new Date(String(body.startsAt)),ends=new Date(String(body.endsAt));if(!Number.isFinite(starts.valueOf())||!Number.isFinite(ends.valueOf())||ends<=starts)throw new HttpError(400,'invalid_schedule');
    const result=await client.from('crm_appointments').insert({organization_id:org,unit_id:unit,contact_id:uuidValue(body.contactId,'contact_id'),
      opportunity_id:body.opportunityId?uuidValue(body.opportunityId,'opportunity_id'):null,responsible_id:uuidValue(body.responsibleId??auth.userId,'responsible_id'),created_by:auth.userId,
      kind:enumValue(body.kind??'visit',['visit','trial_class','call','other'] as const,'kind'),starts_at:starts.toISOString(),ends_at:ends.toISOString(),
      notes:typeof body.notes==='string'?body.notes.slice(0,2000):null,idempotency_key:idempotencyKey(req.headers['idempotency-key']??body.idempotencyKey??randomUUID())}).select().single();
    databaseError(result.error,'appointment_create_failed');return send(res,201,{appointment:result.data});
  }
  if(req.method==='POST'&&path==='/crm/appointments/result') {
    const body=await readJson(req);const result=await client.rpc('record_appointment_result',{p_organization_id:org,p_unit_id:unit,
      p_appointment_id:uuidValue(body.appointmentId,'appointment_id'),p_status:enumValue(body.status,appointmentStatuses,'status'),
      p_target_stage_id:body.targetStageId?uuidValue(body.targetStageId,'target_stage_id'):null,p_reason:typeof body.reason==='string'?body.reason.slice(0,500):null});
    databaseError(result.error,'appointment_result_failed');return send(res,200,{appointment:result.data});
  }
  return false;
}
