begin;
create extension if not exists pgtap with schema extensions;
set local search_path=public,extensions;
select plan(12);
insert into auth.users(id,email) values
 ('00000000-0000-0000-0000-000000000021','admin@example.test'),
 ('00000000-0000-0000-0000-000000000022','support@example.test'),
 ('00000000-0000-0000-0000-000000000023','supreme@example.test');
insert into public.organizations(id,name) values
 ('10000000-0000-0000-0000-000000000021','Fictitious A'),
 ('10000000-0000-0000-0000-000000000022','Fictitious B');
insert into public.units(id,organization_id,name) values
 ('20000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021','A'),
 ('20000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000022','B');
insert into public.memberships(id,organization_id,user_id,all_units) values
 ('30000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000021',true);
insert into public.membership_roles values('10000000-0000-0000-0000-000000000021','30000000-0000-0000-0000-000000000021','academy_admin');
insert into private.platform_roles values('00000000-0000-0000-0000-000000000022','support'),('00000000-0000-0000-0000-000000000023','supreme');
insert into public.onboarding_versions(id,organization_id,unit_id,version,schema_version,status) values
 ('40000000-0000-0000-0000-000000000021','10000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000021',1,1,'draft'),
 ('40000000-0000-0000-0000-000000000022','10000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000021',2,1,'submitted');
set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000021',true);
select throws_ok($$update public.onboarding_versions set status='submitted' where id='40000000-0000-0000-0000-000000000021'$$,'23514',null,'direct API cannot bypass required field validation');
select throws_ok($$select public.onboarding_review_detail('00000000-0000-0000-0000-000000000023','40000000-0000-0000-0000-000000000022')$$,'42501',null,'browser cannot forge review actor');
select ok(not private.onboarding_object_allowed('10000000-0000-0000-0000-000000000022/20000000-0000-0000-0000-000000000022/x/file.pdf',true),'storage cannot cross tenant or use missing metadata');
reset role;
select throws_ok($$update public.onboarding_field_definitions set label='Changed' where field_key='brand_name' and schema_version=1$$,'23514',null,'used field definitions cannot change');
insert into public.onboarding_attachments(organization_id,unit_id,onboarding_id,storage_path,filename,mime_type,byte_size,uploaded_by) values
 ('10000000-0000-0000-0000-000000000021','20000000-0000-0000-0000-000000000021','40000000-0000-0000-0000-000000000022',
 '10000000-0000-0000-0000-000000000021/20000000-0000-0000-0000-000000000021/40000000-0000-0000-0000-000000000022/closed.pdf','closed.pdf','application/pdf',10,'00000000-0000-0000-0000-000000000021');
set local role authenticated;
select ok(not private.onboarding_object_allowed('10000000-0000-0000-0000-000000000021/20000000-0000-0000-0000-000000000021/40000000-0000-0000-000000000022/closed.pdf',true),'closed onboarding forbids new storage objects');
reset role;
set local role service_role;
select throws_ok($$select public.onboarding_review_detail('00000000-0000-0000-0000-000000000022','40000000-0000-0000-0000-000000000022')$$,'42501',null,'support without grant cannot load review');
reset role;
insert into public.support_access_grants(organization_id,user_id,granted_by,reason,mode,expires_at) values
 ('10000000-0000-0000-0000-000000000021','00000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000023','Fictitious support review','read_only',now()+interval '1 hour');
set local role service_role;
select throws_ok($$select public.review_onboarding('40000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000022','approved','Reviewed','{}')$$,'42501',null,'read_only cannot approve');
reset role;
update public.support_access_grants set mode='read_write';
update public.organizations set status='suspended' where id='10000000-0000-0000-0000-000000000021';
set local role service_role;
select throws_ok($$select public.review_onboarding('40000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000022','approved','Reviewed','{}')$$,'42501',null,'suspended organization denies privileged review');
reset role;
update public.organizations set status='active';
update public.support_access_grants set revoked_at=now();
set local role service_role;
select throws_ok($$select public.onboarding_review_detail('00000000-0000-0000-0000-000000000022','40000000-0000-0000-0000-000000000022')$$,'42501',null,'revoked support cannot load review');
select lives_ok($$select public.review_onboarding('40000000-0000-0000-0000-000000000022','00000000-0000-0000-0000-000000000023','approved','Reviewed','{}')$$,'supreme review creates confirmed facts atomically');
select is((select count(*)::integer from public.academy_facts where onboarding_id='40000000-0000-0000-0000-000000000022'),1,'approved version creates exactly one facts record');
select ok(exists(select 1 from public.audit_events where action='onboarding:review'),'review audit exists');
reset role;
select * from finish();
rollback;
