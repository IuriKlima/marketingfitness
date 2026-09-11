begin;
create extension if not exists pgtap with schema extensions;
set local search_path = public, extensions;
select plan(26);

insert into auth.users(id,email) values
  ('00000000-0000-0000-0000-000000000011','admin-a@example.test'),
  ('00000000-0000-0000-0000-000000000012','invitee@example.test'),
  ('00000000-0000-0000-0000-000000000013','supreme@example.test');
insert into public.organizations(id,name) values
  ('10000000-0000-0000-0000-000000000011','Academia A'),
  ('10000000-0000-0000-0000-000000000012','Academia B');
insert into public.units(id,organization_id,name) values
  ('20000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011','Unidade A'),
  ('20000000-0000-0000-0000-000000000012','10000000-0000-0000-0000-000000000012','Unidade B');
insert into public.memberships(id,organization_id,user_id) values
  ('30000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011','00000000-0000-0000-0000-000000000011');
insert into public.membership_roles values
  ('10000000-0000-0000-0000-000000000011','30000000-0000-0000-0000-000000000011','academy_admin');
insert into public.membership_units values
  ('10000000-0000-0000-0000-000000000011','30000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000011');
insert into private.platform_roles values
  ('00000000-0000-0000-0000-000000000013','supreme');
insert into public.onboarding_versions(id,organization_id,unit_id,version,schema_version,status,document) values
  ('40000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000011',1,1,'draft','{}'),
  ('40000000-0000-0000-0000-000000000012','10000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000011',2,1,'submitted','{"ready":true}'),
  ('40000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000011',3,1,'submitted','{"needs":true}');

select ok((select count(*) from public.onboarding_field_definitions) >= 25,'complete onboarding definition set exists');
set local role anon;
select throws_ok($$select * from public.onboarding_field_definitions$$,'42501',null,'anonymous definitions read denied');
reset role;

set local role authenticated;
select set_config('request.jwt.claim.sub','00000000-0000-0000-0000-000000000011',true);
select is((select count(*)::integer from public.my_accessible_contexts()),1,'member receives only the authorized unit context');
select ok(not private.can_access('10000000-0000-0000-0000-000000000012',null,false),'cross-tenant helper access denied');
select is((select count(*)::integer from public.my_platform_roles()),0,'tenant user has no platform role');
select throws_ok(
  $$insert into public.organization_invitations(organization_id,email,token_hash,invited_by,role,all_units,expires_at)
    values('10000000-0000-0000-0000-000000000011','x@example.test',repeat('b',64),'00000000-0000-0000-0000-000000000011','viewer',true,now()+interval '1 day')$$,
  '42501',null,'browser cannot create invitation records'
);
select throws_ok(
  $$insert into public.onboarding_attachments(organization_id,unit_id,onboarding_id,storage_path,filename,mime_type,byte_size,uploaded_by)
    values('10000000-0000-0000-0000-000000000012','20000000-0000-0000-0000-000000000012','40000000-0000-0000-0000-000000000011','cross/path','x.pdf','application/pdf',10,'00000000-0000-0000-0000-000000000011')$$,
  '42501',null,'cross-tenant attachment metadata is rejected'
);
select lives_ok(
  $$insert into public.onboarding_attachments(organization_id,unit_id,onboarding_id,storage_path,filename,mime_type,byte_size,uploaded_by)
    values('10000000-0000-0000-0000-000000000011','20000000-0000-0000-0000-000000000011','40000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011/20000000-0000-0000-0000-000000000011/40000000-0000-0000-0000-000000000011/proof.pdf','proof.pdf','application/pdf',10,'00000000-0000-0000-0000-000000000011')$$,
  'authorized academy admin can attach metadata to a draft'
);
select throws_ok(
  $$select public.create_organization_invitation(
    '00000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011',
    'x@example.test',repeat('c',64),'viewer',true,null,now()+interval '1 day')$$,
  '42501',null,'authenticated role cannot execute service-only invitation RPC'
);
reset role;

set local role service_role;
select throws_ok(
  $$select public.create_organization_invitation(
    '00000000-0000-0000-0000-000000000011','10000000-0000-0000-0000-000000000011',
    'scope@example.test',repeat('d',64),'viewer',true,null,now()+interval '1 day')$$,
  '42501',null,'unit-scoped admin cannot invite a user to all units'
);
select throws_ok(
  $$select public.provision_organization('00000000-0000-0000-0000-000000000011','Unauthorized','Unit','trial')$$,
  '42501',null,'non-supreme actor cannot provision an organization'
);
select lives_ok(
  $$select public.provision_organization('00000000-0000-0000-0000-000000000013','New Academy','Main Unit','trial')$$,
  'supreme actor can provision an organization'
);
select lives_ok(
  $$select public.create_organization_invitation(
    '00000000-0000-0000-0000-000000000013','10000000-0000-0000-0000-000000000011',
    'invitee@example.test',repeat('a',64),'viewer',true,null,now()+interval '1 day')$$,
  'supreme can create a hashed invitation'
);
select is(
  (select length(token_hash) from public.organization_invitations where email='invitee@example.test'),
  64,'only the fixed-length token hash is persisted'
);
select throws_ok(
  $$select public.accept_organization_invitation(repeat('a',64),'00000000-0000-0000-0000-000000000012','wrong@example.test')$$,
  '42501',null,'invitation email binding is enforced'
);
select lives_ok(
  $$select public.accept_organization_invitation(repeat('a',64),'00000000-0000-0000-0000-000000000012','invitee@example.test')$$,
  'valid invitation is accepted atomically'
);
select ok(
  exists(select 1 from public.memberships where organization_id='10000000-0000-0000-0000-000000000011' and user_id='00000000-0000-0000-0000-000000000012'),
  'accepted invitation creates membership'
);
select throws_ok(
  $$select public.accept_organization_invitation(repeat('a',64),'00000000-0000-0000-0000-000000000012','invitee@example.test')$$,
  '42501',null,'invitation cannot be replayed'
);
select lives_ok(
  $$select public.review_onboarding(
    '40000000-0000-0000-0000-000000000012','00000000-0000-0000-0000-000000000013',
    'approved','Approved after review','{}')$$,
  'supreme can approve a submitted onboarding'
);
select is(
  (select status::text from public.onboarding_versions where id='40000000-0000-0000-0000-000000000012'),
  'approved','approval updates the version status'
);
select throws_ok(
  $$update public.onboarding_reviews set notes='tampered'$$,
  '23514',null,'review history is append-only'
);
select lives_ok(
  $$select public.review_onboarding(
    '40000000-0000-0000-0000-000000000013','00000000-0000-0000-0000-000000000013',
    'changes_requested','Complete the missing fields',array['plans'])$$,
  'reviewer can return onboarding with explicit pending fields'
);
select is(
  (select status::text from public.onboarding_versions where id='40000000-0000-0000-0000-000000000013'),
  'rejected','changes request closes the immutable version'
);
select ok(
  not (select public from storage.buckets where id='onboarding-private'),
  'onboarding storage bucket is private'
);
select ok(
  exists(select 1 from public.audit_events where action='invitation:accept' and actor_id='00000000-0000-0000-0000-000000000012'),
  'invitation acceptance is audited with its actor'
);
select ok(
  exists(select 1 from public.audit_events where action='onboarding:review' and actor_id='00000000-0000-0000-0000-000000000013'),
  'onboarding review is audited with its actor'
);
reset role;

select * from finish();
rollback;
