-- Somente leitura: execute depois de UM dos instaladores, como postgres.
-- Confere estrutura e permissoes; nao substitui os testes pgTAP ou o teste de login.
with expected(name) as (values
  ('organizations'),('units'),('memberships'),('membership_roles'),('membership_units'),
  ('support_access_grants'),('onboarding_versions'),('academy_facts'),('audit_events'),
  ('organization_invitations'),('onboarding_field_definitions'),('onboarding_reviews'),('onboarding_attachments'),
  ('crm_contacts'),('crm_contact_identifiers'),('crm_contact_units'),('crm_consents'),('crm_pipelines'),
  ('crm_pipeline_stages'),('crm_opportunities'),('crm_opportunity_stage_history'),('crm_tasks'),('crm_appointments'),
  ('channel_connections'),('conversation_queues'),('conversations'),('messages'),('message_delivery_events'),
  ('ai_assistant_configs'),('knowledge_sources'),('knowledge_documents'),('knowledge_document_versions'),
  ('knowledge_chunks'),('ai_runs'),('ai_tool_calls'),('privacy_requests'),('data_retention_policies')
)
select e.name as tabela, c.oid is not null as existe, coalesce(c.relrowsecurity,false) as rls_ativo,
  case when c.oid is null then null else has_table_privilege('anon',c.oid,'SELECT,INSERT,UPDATE,DELETE') end as anon_tem_acesso
from expected e left join pg_class c on c.oid=to_regclass('public.' || e.name)
order by e.name;

select schema_version,count(*) as campos_cadastrados
from public.onboarding_field_definitions group by schema_version;
-- Esperado: schema_version=1 e campos_cadastrados=30.

select column_name,data_type,is_nullable,column_default from information_schema.columns
where table_schema='public' and table_name='onboarding_versions' and column_name='revision';

select id,public as publico,file_size_limit,allowed_mime_types
from storage.buckets where id in ('onboarding-private','crm-private') order by id;
-- Esperado: ambos publico=false; CRM aceita apenas os MIME types declarados na migration.

select policyname,cmd,roles from pg_policies
where schemaname='storage' and tablename='objects' and policyname like 'onboarding_objects_%'
order by policyname;

select p.oid::regprocedure as funcao,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_pode_executar,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as usuario_pode_executar,
  has_function_privilege('service_role',p.oid,'EXECUTE') as backend_pode_executar
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'provision_organization','create_organization_invitation','accept_organization_invitation',
  'review_onboarding','onboarding_review_queue','onboarding_review_detail','onboarding_review_attachment'
)
order by p.oid::regprocedure::text;
-- RPCs administrativas: false, false, true.

select p.oid::regprocedure as funcao,
  has_function_privilege('anon',p.oid,'EXECUTE') as anon_pode_executar,
  has_function_privilege('authenticated',p.oid,'EXECUTE') as usuario_pode_executar,
  has_function_privilege('service_role',p.oid,'EXECUTE') as backend_pode_executar
from pg_proc p join pg_namespace n on n.oid=p.pronamespace
where n.nspname='public' and p.proname in (
  'crm_authorize','configure_evolution_channel','revoke_channel','channel_runtime_secret','queue_webhook_event',
  'ingest_inbound_message','claim_outbox','complete_outbox','retry_outbox','ingest_knowledge_document',
  'upsert_crm_contact','create_crm_opportunity','move_crm_opportunity','takeover_conversation',
  'return_conversation_to_ai','queue_human_message','approve_knowledge_version'
)
order by p.oid::regprocedure::text;
