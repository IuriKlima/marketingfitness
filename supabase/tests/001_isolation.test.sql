begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(26);
insert into auth.users(id) values ('00000000-0000-0000-0000-000000000001'),('00000000-0000-0000-0000-000000000002'),('00000000-0000-0000-0000-000000000003');
insert into public.organizations(id,name) values ('10000000-0000-0000-0000-000000000001','Academia Fictícia A'),('10000000-0000-0000-0000-000000000002','Academia Fictícia B');
insert into public.units(id,organization_id,name) values
 ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','A1'),
 ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000001','A2'),
 ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000002','B1');
insert into public.memberships(id,organization_id,user_id) values
 ('30000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001'),
 ('30000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','00000000-0000-0000-0000-000000000002');
insert into public.membership_roles values
 ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','academy_admin'),
 ('10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','academy_admin');
insert into public.membership_units values
 ('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001'),
 ('10000000-0000-0000-0000-000000000002','30000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003');
insert into private.platform_roles values ('00000000-0000-0000-0000-000000000003','support');
insert into public.onboarding_versions(organization_id,unit_id,version,schema_version,status) values
 ('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',1,1,'approved'),
 ('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003',1,1,'draft');
select ok(not exists(select 1 from pg_tables where schemaname='public' and tablename in ('organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events') and not rowsecurity),'all operational tables have RLS');
select ok(not exists(select 1 from information_schema.role_table_grants where grantee='anon' and table_schema='public' and table_name in ('organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events')),'anon has no table grants');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000001',true);
select is((select count(*)::integer from public.organizations),1,'A cannot read B');
select ok(not private.can_access('10000000-0000-0000-0000-000000000002',null,true),'helper cannot authorize another academy');
with changed as (update public.onboarding_versions set document='{}' where organization_id='10000000-0000-0000-0000-000000000002' returning id) select is((select count(*)::integer from changed),0,'cross-tenant update changes zero rows');
select is((select count(*)::integer from public.units),1,'A1 cannot read A2 or B1');
select is((select count(*)::integer from public.onboarding_versions),1,'onboarding cross-read blocked');
select throws_ok($$insert into public.onboarding_versions(organization_id,unit_id,version,schema_version) values('10000000-0000-0000-0000-000000000002','20000000-0000-0000-0000-000000000003',2,1)$$,'42501',null,'cross-write denied');
select throws_ok($$insert into public.onboarding_versions(organization_id,unit_id,version,schema_version) values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000002',2,1)$$,'42501',null,'unit write denied');
select throws_ok($$update public.memberships set all_units=true$$,'42501',null,'membership escalation denied');
select throws_ok($$insert into public.membership_roles values('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','viewer')$$,'42501',null,'role escalation denied');
select throws_ok($$update public.organizations set plan='enterprise',status='active'$$,'42501',null,'plan and status protected');
select throws_ok($$insert into private.platform_roles values('00000000-0000-0000-0000-000000000001','supreme')$$,'42501',null,'platform escalation denied');
select throws_ok($$insert into public.support_access_grants(organization_id,user_id,granted_by,reason,mode,expires_at) values('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000001','Fictitious justification','read_write',now()+interval '1 hour')$$,'42501',null,'fabricated grant denied');
with changed as (update public.onboarding_versions set document='{}' where status='approved' returning id) select is((select count(*)::integer from changed),0,'approved version not writable');
select lives_ok($$insert into public.onboarding_versions(organization_id,unit_id,version,schema_version) values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',2,1)$$,'authorized draft insert works');
reset role;
select throws_ok($$update public.onboarding_versions set document='{"changed":true}' where status='approved'$$,'23514',null,'approved immutable even backend');
select throws_ok($$insert into public.membership_units values('10000000-0000-0000-0000-000000000001','30000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000003')$$,'23503',null,'composite FK blocks mixed tenant');
update public.organizations set status='suspended' where id='10000000-0000-0000-0000-000000000001';
set local role authenticated;
select is((select count(*)::integer from public.onboarding_versions),0,'suspended academy invisible');
select throws_ok($$insert into public.onboarding_versions(organization_id,unit_id,version,schema_version) values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',3,1)$$,'42501',null,'suspended academy cannot write');
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000003',true);
select is((select count(*)::integer from public.units),0,'support without grant denied');
reset role;
update public.organizations set status='active' where id='10000000-0000-0000-0000-000000000001';
insert into public.support_access_grants(organization_id,user_id,granted_by,reason,mode,expires_at) values('10000000-0000-0000-0000-000000000001','00000000-0000-0000-0000-000000000003','00000000-0000-0000-0000-000000000002','Fictitious test support','read_only',now()+interval '1 hour');
set local role authenticated;
select is((select count(*)::integer from public.units),2,'read_only sees authorized organization');
select throws_ok($$insert into public.onboarding_versions(organization_id,unit_id,version,schema_version) values('10000000-0000-0000-0000-000000000001','20000000-0000-0000-0000-000000000001',3,1)$$,'42501',null,'read_only cannot write');
reset role;
update public.support_access_grants set starts_at=now()-interval '2 hours',expires_at=now()-interval '1 hour';
set local role authenticated;
select is((select count(*)::integer from public.units),0,'expired grant denied');
select throws_ok($$select * from private.outbox$$,'42501',null,'private outbox denied');
reset role;
set local role anon;
select throws_ok($$select * from public.organizations$$,'42501',null,'anonymous operational read denied');
reset role;
select * from finish();
rollback;



