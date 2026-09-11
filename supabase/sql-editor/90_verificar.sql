-- Somente leitura: execute depois de UM dos instaladores, como postgres.
-- Confere estrutura e permissoes; nao substitui os testes pgTAP ou o teste de login.
with expected(name) as (values
  ('organizations'),('units'),('memberships'),('membership_roles'),('membership_units'),
  ('support_access_grants'),('onboarding_versions'),('academy_facts'),('audit_events'),
  ('organization_invitations'),('onboarding_field_definitions'),('onboarding_reviews'),('onboarding_attachments')
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
from storage.buckets where id='onboarding-private';
-- Esperado: publico=false, limite de 10485760 bytes, JPEG/PNG/WebP/PDF.

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
