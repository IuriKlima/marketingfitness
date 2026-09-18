begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(43);

insert into auth.users(id,email) values
 ('00000000-0000-4000-8000-000000000101','admin-a@example.test'),
 ('00000000-0000-4000-8000-000000000102','attendant-a@example.test'),
 ('00000000-0000-4000-8000-000000000103','marketing-a@example.test'),
 ('00000000-0000-4000-8000-000000000104','viewer-a@example.test'),
 ('00000000-0000-4000-8000-000000000105','admin-b@example.test'),
 ('00000000-0000-4000-8000-000000000106','supreme@example.test');
insert into public.organizations(id,name) values
 ('10000000-0000-4000-8000-000000000101','Tenant A'),
 ('10000000-0000-4000-8000-000000000102','Tenant B');
insert into public.units(id,organization_id,name) values
 ('20000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','A Centro'),
 ('20000000-0000-4000-8000-000000000102','10000000-0000-4000-8000-000000000101','A Sul'),
 ('20000000-0000-4000-8000-000000000103','10000000-0000-4000-8000-000000000102','B Centro');
insert into public.memberships(id,organization_id,user_id,all_units) values
 ('30000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000101',true),
 ('30000000-0000-4000-8000-000000000102','10000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000102',false),
 ('30000000-0000-4000-8000-000000000103','10000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000103',false),
 ('30000000-0000-4000-8000-000000000104','10000000-0000-4000-8000-000000000101','00000000-0000-4000-8000-000000000104',false),
 ('30000000-0000-4000-8000-000000000105','10000000-0000-4000-8000-000000000102','00000000-0000-4000-8000-000000000105',true);
insert into public.membership_roles values
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000101','academy_admin'),
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000102','academy_attendant'),
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000103','marketing_operator'),
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000104','viewer'),
 ('10000000-0000-4000-8000-000000000102','30000000-0000-4000-8000-000000000105','academy_admin');
insert into public.membership_units values
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000102','20000000-0000-4000-8000-000000000101'),
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000103','20000000-0000-4000-8000-000000000101'),
 ('10000000-0000-4000-8000-000000000101','30000000-0000-4000-8000-000000000104','20000000-0000-4000-8000-000000000101');
insert into private.platform_roles values('00000000-0000-4000-8000-000000000106','supreme');

select ok(private.crm_can_actor('00000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','configure'),'admin configures own unit');
select ok(private.crm_can_actor('00000000-0000-4000-8000-000000000102','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','write_crm'),'attendant writes CRM in granted unit');
select ok(private.crm_can_actor('00000000-0000-4000-8000-000000000103','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','attribution'),'marketing reads attribution');
select ok(not private.crm_can_actor('00000000-0000-4000-8000-000000000103','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','inbox'),'marketing cannot read private inbox');
select ok(private.crm_can_actor('00000000-0000-4000-8000-000000000104','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','aggregate'),'viewer receives aggregates');
select ok(not private.crm_can_actor('00000000-0000-4000-8000-000000000106','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','read_crm'),'supreme has no implicit operational access');
select ok(not private.crm_can_actor('00000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000102','20000000-0000-4000-8000-000000000103','read_crm'),'tenant A admin cannot read tenant B');

insert into public.crm_pipelines(id,organization_id,unit_id,name) values
 ('40000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','Matrículas');
insert into public.crm_pipeline_stages(id,organization_id,unit_id,pipeline_id,name,position,outcome) values
 ('41000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','40000000-0000-4000-8000-000000000101','Novo',0,null),
 ('41000000-0000-4000-8000-000000000102','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','40000000-0000-4000-8000-000000000101','Visita',1,null),
 ('41000000-0000-4000-8000-000000000103','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','40000000-0000-4000-8000-000000000101','Matriculado',2,'won');

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000101',true);
select lives_ok($$select public.upsert_crm_contact('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','Lead Exemplo','+5511900000101','LEAD@EXAMPLE.TEST','São Paulo','site',null,'contact-key-000000000001')$$,'contact can be created');
select is(
 (public.upsert_crm_contact('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','Lead Exemplo','+5511900000101','lead@example.test',null,'site',null,'contact-key-000000000001')->>'id'),
 (select contact_id::text from public.crm_contact_identifiers where normalized_value='+5511900000101'),'contact replay returns same identity');
select is((select count(*)::integer from public.crm_contacts where organization_id='10000000-0000-4000-8000-000000000101'),1,'deduplication leaves one contact');
select is((select normalized_value from public.crm_contact_identifiers where kind='email'),'lead@example.test','email is normalized');
select throws_ok($$select public.upsert_crm_contact('10000000-0000-4000-8000-000000000102','20000000-0000-4000-8000-000000000103','Cross Tenant','+5511900000102',null,null,null,null,'contact-key-000000000002')$$,'42501',null,'cross-tenant write is rejected');
select lives_ok($$select public.create_crm_opportunity('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101',(select contact_id from public.crm_contact_identifiers where normalized_value='+5511900000101'),'40000000-0000-4000-8000-000000000101','41000000-0000-4000-8000-000000000101','Plano anual','site','campaign-a','external-opportunity-a','opportunity-key-00000001')$$,'opportunity is created');
select ok((public.create_crm_opportunity('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101',(select contact_id from public.crm_contact_identifiers where normalized_value='+5511900000101'),'40000000-0000-4000-8000-000000000101','41000000-0000-4000-8000-000000000101','Plano anual','site','campaign-a','external-opportunity-a','opportunity-key-00000001')->>'id') is not null,'opportunity replay returns cached result');
select is((select count(*)::integer from public.crm_opportunities),1,'opportunity replay does not duplicate');
select is((select count(*)::integer from public.crm_opportunity_stage_history),1,'creation writes append-only history');
select throws_ok($$select public.move_crm_opportunity('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101',(select id from public.crm_opportunities),'41000000-0000-4000-8000-000000000102','41000000-0000-4000-8000-000000000103','stale','move-key-00000000000001')$$,'40001',null,'optimistic move rejects stale stage');
select lives_ok($$select public.move_crm_opportunity('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101',(select id from public.crm_opportunities),'41000000-0000-4000-8000-000000000101','41000000-0000-4000-8000-000000000102','visit scheduled','move-key-00000000000002')$$,'valid move succeeds');
select is((select stage_id::text from public.crm_opportunities),'41000000-0000-4000-8000-000000000102','opportunity reaches visit stage');
select is((select count(*)::integer from public.crm_opportunity_stage_history),2,'move appends history');
select throws_ok($$delete from public.crm_opportunity_stage_history$$,'42501',null,'authenticated users cannot delete commercial history');
reset role;
select throws_ok($$delete from public.crm_opportunity_stage_history$$,'23514',null,'commercial history trigger is append-only');

insert into public.crm_appointments(id,organization_id,unit_id,contact_id,opportunity_id,responsible_id,kind,starts_at,ends_at,idempotency_key,created_by) values
 ('42000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101',(select contact_id from public.crm_contact_identifiers where normalized_value='+5511900000101'),(select id from public.crm_opportunities),'00000000-0000-4000-8000-000000000101','visit',now()+interval '1 day',now()+interval '25 hours','appointment-key-00000001','00000000-0000-4000-8000-000000000101');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000101',true);
select lives_ok($$select public.record_appointment_result('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','42000000-0000-4000-8000-000000000101','enrolled','41000000-0000-4000-8000-000000000103','matrícula confirmada')$$,'appointment result and opportunity move are atomic');
select is((select status::text from public.crm_opportunities),'won','appointment result wins opportunity');
select is((select count(*)::integer from public.crm_appointment_events),1,'appointment result appends event');
reset role;

insert into public.channel_connections(id,organization_id,unit_id,provider,name,status,webhook_token_hash,created_by) values
 ('50000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','whatsapp','WhatsApp Test','active',repeat('a',64),'00000000-0000-4000-8000-000000000101');
insert into public.conversations(id,organization_id,unit_id,channel_connection_id,contact_id,state,external_thread_id) values
 ('51000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','50000000-0000-4000-8000-000000000101',(select contact_id from public.crm_contact_identifiers where normalized_value='+5511900000101'),'ai_active','thread-a'),
 ('51000000-0000-4000-8000-000000000102','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','50000000-0000-4000-8000-000000000101',(select contact_id from public.crm_contact_identifiers where normalized_value='+5511900000101'),'ai_active','thread-b');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000101',true);
select lives_ok($$select public.takeover_conversation('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','51000000-0000-4000-8000-000000000101','Atendimento humano','takeover-key-0000000001')$$,'human can take over conversation');
select is((select state::text from public.conversations where id='51000000-0000-4000-8000-000000000101'),'human_active','takeover immediately blocks AI state');
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000102',true);
select throws_ok($$select public.takeover_conversation('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','51000000-0000-4000-8000-000000000101','Concorrente','takeover-key-0000000002')$$,'55P03',null,'second attendant cannot silently steal lease');
reset role;
select throws_ok($$insert into public.messages(organization_id,unit_id,conversation_id,channel_connection_id,direction,author_kind,provider,idempotency_key,body) values('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','51000000-0000-4000-8000-000000000101','50000000-0000-4000-8000-000000000101','outbound','ai','whatsapp','ai-message-key-00000001','Resposta automática')$$,'42501',null,'AI cannot answer after human takeover');
insert into public.crm_consents(organization_id,contact_id,channel,purpose,legal_basis,source,revoked_at) values
 ('10000000-0000-4000-8000-000000000101',(select contact_id from public.crm_contact_identifiers where normalized_value='+5511900000101'),'whatsapp','atendimento','revogação','cliente',now());
select throws_ok($$insert into public.messages(organization_id,unit_id,conversation_id,channel_connection_id,direction,author_kind,provider,idempotency_key,body) values('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','51000000-0000-4000-8000-000000000102','50000000-0000-4000-8000-000000000101','outbound','ai','whatsapp','ai-message-key-00000002','Resposta automática')$$,'42501',null,'opt-out blocks automated messaging');
select ok(public.queue_webhook_event('50000000-0000-4000-8000-000000000101','event-a',repeat('b',64),now(),'{}','52000000-0000-4000-8000-000000000101'),'first webhook is queued');
select ok(not public.queue_webhook_event('50000000-0000-4000-8000-000000000101','event-a',repeat('b',64),now(),'{}','52000000-0000-4000-8000-000000000102'),'duplicate webhook is acknowledged without requeue');
select is((select count(*)::integer from private.outbox where event_type='evolution.webhook'),1,'webhook outbox is idempotent');
update private.outbox set attempts=9 where event_type='evolution.webhook';
select is((select count(*)::integer from public.claim_outbox('worker-a',10,60)),1,'worker claims available job once');
select is((select count(*)::integer from public.claim_outbox('worker-b',10,60)),0,'concurrent worker skips leased job');
select ok(public.retry_outbox((select id from private.outbox where event_type='evolution.webhook'),'worker-a','provider_unavailable'),'worker records retry result');
select ok((select failed_at is not null from private.outbox where event_type='evolution.webhook'),'tenth failure moves job to dead letter');

insert into public.knowledge_sources(id,organization_id,unit_id,source_kind,name,created_by) values
 ('60000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','manual','Horários aprovados','00000000-0000-4000-8000-000000000101');
select lives_ok($$select public.ingest_knowledge_document('00000000-0000-4000-8000-000000000101','10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','60000000-0000-4000-8000-000000000101','Horários',repeat('c',64),'["A academia abre às 06 horas."]')$$,'authorized content is chunked transactionally');
select ok(exists(select 1 from public.knowledge_document_versions where status='draft' and indexing_status='ready'),'indexed content remains draft until approval');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000101',true);
select lives_ok($$select public.approve_knowledge_version('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','60000000-0000-4000-8000-000000000101',(select id from public.knowledge_document_versions),now()+interval '30 days')$$,'admin explicitly approves indexed version');
reset role;
select is((select count(*)::integer from public.search_authorized_knowledge('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','academia abre',8)),1,'assistant search returns only approved current knowledge');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000104',true);
select is((select count(*)::integer from public.crm_contacts),0,'viewer cannot read contact PII');
reset role;
update public.organizations set status='suspended' where id='10000000-0000-4000-8000-000000000101';
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-4000-8000-000000000101',true);
select throws_ok($$select public.upsert_crm_contact('10000000-0000-4000-8000-000000000101','20000000-0000-4000-8000-000000000101','Suspenso','+5511900000199',null,null,null,null,'contact-key-000000000099')$$,'42501',null,'suspended organization cannot operate CRM');
reset role;

select * from finish();
rollback;
