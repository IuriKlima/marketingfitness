-- AcadeAI: instalacao completa em projeto novo.
-- Gerado por npm run sql:bundle. Nao editar: fontes em supabase/migrations.
-- Execute SOMENTE este arquivo OU o outro instalador, nunca os dois.
-- SQL Editor do projeto correto, papel postgres. Tudo ocorre em uma transacao.
-- Sem usuarios, credenciais, dados de teste ou reset do banco.
begin;
set local lock_timeout = '10s';
select pg_advisory_xact_lock(726495110);
do $preflight$
declare item text;
begin
  if to_regclass('auth.users') is null or to_regclass('storage.objects') is null or to_regclass('storage.buckets') is null then
    raise exception 'Este SQL exige um projeto Supabase com Auth e Storage.';
  end if;

  foreach item in array array['organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events','organization_invitations','onboarding_field_definitions','onboarding_reviews','onboarding_attachments','crm_contacts','crm_opportunities','crm_appointments','channel_connections','conversations','messages','ai_assistant_configs','knowledge_sources','ai_runs'] loop
    if to_regclass('public.' || item) is not null then
      raise exception 'Instalacao interrompida: public.% ja existe. Se a fase 1 foi aplicada, revise 02_atualizar_fase1.sql.',item;
    end if;
  end loop;
  if to_regclass('private.platform_roles') is not null or to_regclass('private.outbox') is not null or
    to_regtype('public.platform_role') is not null then
    raise exception 'Objetos anteriores encontrados. Revise o schema antes de instalar.';
  end if;
end
$preflight$;

-- Fonte: 20260908000000_foundation.sql
-- SHA256 (UTF-8, LF): ee11dcdd0f0ff9a65a83e12fc3f450490fe8731c3fe747ce136d12ed63f3659a
create schema if not exists private;
revoke all on schema private from public, anon, authenticated;
grant usage on schema private to authenticated;
create type public.platform_role as enum ('supreme','support');
create type public.academy_role as enum ('academy_admin','marketing_operator','academy_attendant','viewer');
create type public.organization_status as enum ('active','suspended');
create type public.onboarding_status as enum ('draft','submitted','approved','rejected');
create type public.support_mode as enum ('read_only','read_write');
create table public.organizations (
 id uuid primary key default gen_random_uuid(), name text not null,
 status public.organization_status not null default 'active', plan text not null default 'trial'
);
create table private.platform_roles (
 user_id uuid references auth.users(id) on delete cascade, role public.platform_role not null,
 primary key(user_id,role)
);
create table public.units (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 name text not null, unique(organization_id,id)
);
create table public.memberships (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id), active boolean not null default true, all_units boolean not null default false,
 unique(organization_id,user_id), unique(organization_id,id)
);
create table public.membership_roles (
 organization_id uuid not null, membership_id uuid not null, role public.academy_role not null,
 primary key(organization_id,membership_id,role),
 foreign key(organization_id,membership_id) references public.memberships(organization_id,id)
);
create table public.membership_units (
 organization_id uuid not null, membership_id uuid not null, unit_id uuid not null,
 primary key(organization_id,membership_id,unit_id),
 foreign key(organization_id,membership_id) references public.memberships(organization_id,id),
 foreign key(organization_id,unit_id) references public.units(organization_id,id)
);
create table public.support_access_grants (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 user_id uuid not null references auth.users(id), granted_by uuid not null references auth.users(id),
 reason text not null check(length(trim(reason)) between 10 and 500), mode public.support_mode not null,
 starts_at timestamptz not null default now(), expires_at timestamptz not null,
 revoked_at timestamptz, check(expires_at > starts_at and expires_at <= starts_at + interval '24 hours')
);
create table public.onboarding_versions (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 unit_id uuid not null, version integer not null check(version > 0), schema_version integer not null check(schema_version > 0),
 status public.onboarding_status not null default 'draft', document jsonb not null default '{}',
 unique(organization_id,unit_id,version), unique(organization_id,unit_id,id),
 foreign key(organization_id,unit_id) references public.units(organization_id,id)
);
create table public.academy_facts (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 unit_id uuid not null, onboarding_id uuid not null, facts jsonb not null,
 confirmed_at timestamptz not null default now(),
 foreign key(organization_id,unit_id) references public.units(organization_id,id),
 foreign key(organization_id,unit_id,onboarding_id) references public.onboarding_versions(organization_id,unit_id,id)
);
create table public.audit_events (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 actor_id uuid, action text not null, entity_id uuid not null, created_at timestamptz not null default now()
);
create table private.outbox (
 id uuid primary key default gen_random_uuid(), organization_id uuid not null references public.organizations(id),
 unit_id uuid not null, idempotency_key text not null, event_type text not null, entity_id uuid not null,
 available_at timestamptz not null default now(), completed_at timestamptz, attempts integer not null default 0 check(attempts>=0),
 unique(organization_id,idempotency_key), foreign key(organization_id,unit_id) references public.units(organization_id,id)
);
create index on public.memberships(user_id,organization_id);
create index on public.membership_units(organization_id,unit_id);
create index on public.support_access_grants(user_id,organization_id,expires_at);
create index on public.academy_facts(organization_id,unit_id,onboarding_id);
create index on public.audit_events(organization_id,created_at);
create index on private.outbox(available_at) where completed_at is null;
create index on private.outbox(organization_id,unit_id);

create function private.can_access(org uuid, unit uuid default null, writing boolean default false)
returns boolean language sql stable security definer set search_path = '' as $$
 select exists(select 1 from public.organizations o where o.id=org and o.status='active') and (
 exists(select 1 from public.memberships m where m.organization_id=org and m.user_id=(select auth.uid()) and m.active
 and (unit is null or m.all_units or exists(select 1 from public.membership_units u where u.organization_id=org and u.membership_id=m.id and u.unit_id=unit))
 and exists(select 1 from public.membership_roles r where r.organization_id=org and r.membership_id=m.id
 and (not writing or r.role='academy_admin')))
 or exists(select 1 from public.support_access_grants g join private.platform_roles p on p.user_id=g.user_id
 where g.organization_id=org and g.user_id=(select auth.uid()) and p.role='support'
 and g.revoked_at is null and now() >= g.starts_at and now() < g.expires_at
 and (not writing or g.mode='read_write'))
 );
$$;
revoke all on function private.can_access(uuid,uuid,boolean) from public,anon;
grant execute on function private.can_access(uuid,uuid,boolean) to authenticated;

create function private.guard_onboarding() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op='DELETE' then raise exception 'Onboarding history cannot be deleted' using errcode='23514'; end if;
 if tg_op='UPDATE' then
  if (new.id,new.organization_id,new.unit_id,new.version,new.schema_version) is distinct from (old.id,old.organization_id,old.unit_id,old.version,old.schema_version) then
   raise exception 'Version identity is immutable' using errcode='23514';
  end if;
  if old.status <> 'draft' then
   if new.document is distinct from old.document or not (old.status='submitted' and new.status in ('approved','rejected') and current_user <> 'authenticated') then
    raise exception 'Submitted onboarding is immutable' using errcode='23514';
   end if;
  end if;
 end if;
 if current_user='authenticated' and new.status not in ('draft','submitted') then raise exception 'Approval requires backend' using errcode='42501'; end if;
 return new;
end $$;
create trigger guard_onboarding before insert or update or delete on public.onboarding_versions for each row execute function private.guard_onboarding();
create function private.guard_facts() returns trigger language plpgsql set search_path='' as $$
begin
 if tg_op <> 'INSERT' then raise exception 'Confirmed facts are append-only' using errcode='23514'; end if;
 if not exists(select 1 from public.onboarding_versions v where v.id=new.onboarding_id and v.organization_id=new.organization_id and v.unit_id=new.unit_id and v.status='approved') then
 raise exception 'Facts require approved onboarding' using errcode='23514'; end if;
 return new;
end $$;
create trigger guard_facts before insert or update or delete on public.academy_facts for each row execute function private.guard_facts();
create function private.audit_change() returns trigger language plpgsql security definer set search_path='' as $$
begin
 insert into public.audit_events(organization_id,actor_id,action,entity_id)
 values(new.organization_id,auth.uid(),tg_table_name || ':' || tg_op,new.id);
 return new;
end $$;
create trigger audit_support after insert or update on public.support_access_grants for each row execute function private.audit_change();
create trigger audit_onboarding after insert or update on public.onboarding_versions for each row execute function private.audit_change();
create trigger audit_facts after insert on public.academy_facts for each row execute function private.audit_change();
revoke all on function private.audit_change(), private.guard_onboarding(), private.guard_facts() from public,anon,authenticated;

do $$ declare t text; begin
 foreach t in array array['organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events'] loop
 execute format('alter table public.%I enable row level security',t);
 execute format('revoke all on public.%I from anon, authenticated',t);
 execute format('grant select on public.%I to authenticated',t);
 end loop;
end $$;
alter table private.platform_roles enable row level security;
alter table private.outbox enable row level security;
revoke all on all tables in schema private from public,anon,authenticated;
create policy organizations_read on public.organizations for select to authenticated using(private.can_access(id));
create policy units_read on public.units for select to authenticated using(private.can_access(organization_id,id));
create policy memberships_read on public.memberships for select to authenticated using(user_id=auth.uid() and private.can_access(organization_id));
create policy roles_read on public.membership_roles for select to authenticated using(exists(select 1 from public.memberships m where m.id=membership_id and m.organization_id=membership_roles.organization_id));
create policy membership_units_read on public.membership_units for select to authenticated using(exists(select 1 from public.memberships m where m.id=membership_id and m.organization_id=membership_units.organization_id));
create policy support_read on public.support_access_grants for select to authenticated using(user_id=auth.uid() and private.can_access(organization_id));
create policy onboarding_read on public.onboarding_versions for select to authenticated using(private.can_access(organization_id,unit_id));
create policy onboarding_insert on public.onboarding_versions for insert to authenticated with check(private.can_access(organization_id,unit_id,true) and status='draft');
create policy onboarding_update on public.onboarding_versions for update to authenticated using(private.can_access(organization_id,unit_id,true) and status='draft') with check(private.can_access(organization_id,unit_id,true) and status in ('draft','submitted'));
grant insert(organization_id,unit_id,version,schema_version,document), update(document,status) on public.onboarding_versions to authenticated;
create policy facts_read on public.academy_facts for select to authenticated using(private.can_access(organization_id,unit_id));
-- Audit and administrative writes deliberately have no browser policy.

-- Only backend identity can access private infrastructure; no browser write path.
grant usage on schema private to service_role;
grant select on private.platform_roles to service_role;
grant select, insert, update on private.outbox to service_role;
create function private.append_only() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'History is append-only' using errcode='23514'; end $$;
revoke all on function private.append_only() from public,anon,authenticated;
create trigger audit_append_only before update or delete on public.audit_events for each row execute function private.append_only();
create trigger support_no_delete before delete on public.support_access_grants for each row execute function private.append_only();

-- Fonte: 20260911000000_identity_onboarding.sql
-- SHA256 (UTF-8, LF): d09f50f47d8c5bea50d2fbd391702156f3953bdaad6a2b057dd867f92f9b2031
-- Phase 2: secure invitations, tenant context discovery, onboarding review and private attachments.

create type public.onboarding_scope as enum ('organization', 'unit');
create type public.onboarding_field_type as enum (
  'short_text', 'long_text', 'number', 'currency', 'boolean', 'single_select',
  'multi_select', 'date', 'url', 'email', 'phone'
);
create type public.onboarding_review_decision as enum ('approved', 'changes_requested');

alter table public.onboarding_versions
  add column submitted_at timestamptz,
  add column reviewed_at timestamptz,
  add column reviewed_by uuid references auth.users(id);

create table public.organization_invitations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  email text not null check (email = lower(trim(email)) and length(email) between 3 and 320),
  token_hash text not null unique check (token_hash ~ '^[a-f0-9]{64}$'),
  invited_by uuid not null references auth.users(id),
  role public.academy_role not null,
  all_units boolean not null default false,
  unit_id uuid,
  expires_at timestamptz not null,
  accepted_at timestamptz,
  accepted_by uuid references auth.users(id),
  revoked_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (organization_id, unit_id) references public.units(organization_id, id),
  check (expires_at > created_at and expires_at <= created_at + interval '7 days'),
  check (all_units or unit_id is not null),
  check (accepted_at is null or accepted_by is not null)
);

create table public.onboarding_field_definitions (
  id uuid primary key default gen_random_uuid(),
  schema_version integer not null check (schema_version > 0),
  field_key text not null check (field_key ~ '^[a-z][a-z0-9_]{1,63}$'),
  scope public.onboarding_scope not null,
  section text not null,
  label text not null,
  description text,
  field_type public.onboarding_field_type not null,
  required boolean not null default false,
  validation jsonb not null default '{}',
  options jsonb not null default '[]',
  sort_order integer not null default 0,
  active boolean not null default true,
  unique (schema_version, field_key)
);

create table public.onboarding_reviews (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  unit_id uuid not null,
  onboarding_id uuid not null,
  reviewer_id uuid not null references auth.users(id),
  decision public.onboarding_review_decision not null,
  notes text not null check (length(trim(notes)) between 3 and 5000),
  requested_fields text[] not null default '{}',
  created_at timestamptz not null default now(),
  foreign key (organization_id, unit_id) references public.units(organization_id, id),
  foreign key (organization_id, unit_id, onboarding_id)
    references public.onboarding_versions(organization_id, unit_id, id)
);

create table public.onboarding_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  unit_id uuid not null,
  onboarding_id uuid not null,
  storage_path text not null unique,
  filename text not null check (length(filename) between 1 and 255),
  mime_type text not null check (mime_type in ('image/jpeg','image/png','image/webp','application/pdf')),
  byte_size bigint not null check (byte_size between 1 and 10485760),
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  foreign key (organization_id, unit_id) references public.units(organization_id, id),
  foreign key (organization_id, unit_id, onboarding_id)
    references public.onboarding_versions(organization_id, unit_id, id)
);

create index organization_invitations_org_email_idx
  on public.organization_invitations(organization_id, email, expires_at);
create index onboarding_reviews_onboarding_idx
  on public.onboarding_reviews(organization_id, unit_id, onboarding_id, created_at);
create index onboarding_attachments_onboarding_idx
  on public.onboarding_attachments(organization_id, unit_id, onboarding_id);
create index onboarding_definitions_schema_idx
  on public.onboarding_field_definitions(schema_version, section, sort_order) where active;

create or replace function private.guard_onboarding()
returns trigger language plpgsql set search_path = '' as $$
begin
  if tg_op = 'DELETE' then
    raise exception 'Onboarding history cannot be deleted' using errcode = '23514';
  end if;
  if tg_op = 'UPDATE' then
    if (new.id,new.organization_id,new.unit_id,new.version,new.schema_version)
       is distinct from
       (old.id,old.organization_id,old.unit_id,old.version,old.schema_version) then
      raise exception 'Version identity is immutable' using errcode = '23514';
    end if;
    if old.status = 'draft' and new.status = 'submitted' and old.submitted_at is null then
      new.submitted_at := now();
    elsif old.status = 'draft' and new.status = 'draft' then
      null;
    elsif old.status = 'submitted'
      and current_user <> 'authenticated'
      and new.status in ('approved','rejected')
      and new.document is not distinct from old.document then
      new.reviewed_at := coalesce(new.reviewed_at, now());
    else
      raise exception 'Submitted and reviewed onboarding versions are immutable' using errcode = '23514';
    end if;
  end if;
  if current_user = 'authenticated' and new.status not in ('draft','submitted') then
    raise exception 'Review requires backend authorization' using errcode = '42501';
  end if;
  return new;
end
$$;

create function private.append_only_new_tables()
returns trigger language plpgsql set search_path = '' as $$
begin
  raise exception 'History is append-only' using errcode = '23514';
end
$$;
revoke all on function private.append_only_new_tables() from public, anon, authenticated;
create trigger onboarding_reviews_append_only
  before update or delete on public.onboarding_reviews
  for each row execute function private.append_only_new_tables();

create function public.my_platform_roles()
returns setof public.platform_role
language sql stable security definer set search_path = '' as $$
  select role from private.platform_roles where user_id = (select auth.uid());
$$;
revoke all on function public.my_platform_roles() from public, anon;
grant execute on function public.my_platform_roles() to authenticated;

create function public.my_accessible_contexts()
returns table (
  organization_id uuid,
  organization_name text,
  unit_id uuid,
  unit_name text,
  roles public.academy_role[]
)
language sql stable security definer set search_path = '' as $$
  select o.id, o.name, u.id, u.name,
    coalesce(array_agg(distinct r.role) filter (where r.role is not null), '{}'::public.academy_role[])
  from public.organizations o
  join public.units u on u.organization_id = o.id
  left join public.memberships m
    on m.organization_id = o.id and m.user_id = (select auth.uid()) and m.active
  left join public.membership_roles r
    on r.organization_id = m.organization_id and r.membership_id = m.id
  where o.status = 'active'
    and (
      (
        m.id is not null
        and exists(select 1 from public.membership_roles mr where mr.membership_id=m.id and mr.organization_id=m.organization_id)
        and (m.all_units or exists (
          select 1 from public.membership_units mu
          where mu.organization_id = m.organization_id
            and mu.membership_id = m.id and mu.unit_id = u.id
        ))
      )
      or exists (
        select 1
        from public.support_access_grants g
        join private.platform_roles pr on pr.user_id = g.user_id and pr.role = 'support'
        where g.organization_id = o.id
          and g.user_id = (select auth.uid())
          and g.revoked_at is null
          and now() >= g.starts_at and now() < g.expires_at
      )
    )
  group by o.id, o.name, u.id, u.name;
$$;
revoke all on function public.my_accessible_contexts() from public, anon;
grant execute on function public.my_accessible_contexts() to authenticated;

create function public.provision_organization(
  p_actor_id uuid,
  p_name text,
  p_unit_name text,
  p_plan text default 'trial'
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_org uuid;
  v_unit uuid;
begin
  if not exists (
    select 1 from private.platform_roles
    where user_id = p_actor_id and role = 'supreme'
  ) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  if length(trim(p_name)) < 2 or length(trim(p_unit_name)) < 2 then
    raise exception 'Invalid organization data' using errcode = '22023';
  end if;
  insert into public.organizations(name, plan)
    values (trim(p_name), trim(p_plan)) returning id into v_org;
  insert into public.units(organization_id, name)
    values (v_org, trim(p_unit_name)) returning id into v_unit;
  insert into public.audit_events(organization_id, actor_id, action, entity_id)
    values (v_org, p_actor_id, 'organization:provision', v_org);
  return jsonb_build_object('organization_id', v_org, 'unit_id', v_unit);
end
$$;
revoke all on function public.provision_organization(uuid,text,text,text) from public, anon, authenticated;
grant execute on function public.provision_organization(uuid,text,text,text) to service_role;

create function public.create_organization_invitation(
  p_actor_id uuid,
  p_organization_id uuid,
  p_email text,
  p_token_hash text,
  p_role public.academy_role,
  p_all_units boolean,
  p_unit_id uuid,
  p_expires_at timestamptz
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_invitation uuid;
begin
  if not exists (
    select 1 from public.organizations
    where id = p_organization_id and status = 'active'
  ) then
    raise exception 'Organization unavailable' using errcode = '42501';
  end if;
  if not (
    exists (
      select 1 from private.platform_roles
      where user_id = p_actor_id and role = 'supreme'
    )
    or exists (
      select 1
      from public.memberships m
      join public.membership_roles r
        on r.organization_id = m.organization_id and r.membership_id = m.id
      where m.organization_id = p_organization_id
        and m.user_id = p_actor_id and m.active and r.role = 'academy_admin'
        and (
          (p_all_units and m.all_units)
          or (
            not p_all_units
            and (
              m.all_units
              or exists (
                select 1 from public.membership_units mu
                where mu.organization_id = m.organization_id
                  and mu.membership_id = m.id
                  and mu.unit_id = p_unit_id
              )
            )
          )
        )
    )
  ) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  insert into public.organization_invitations(
    organization_id,email,token_hash,invited_by,role,all_units,unit_id,expires_at
  ) values (
    p_organization_id,lower(trim(p_email)),p_token_hash,p_actor_id,p_role,
    p_all_units,case when p_all_units then null else p_unit_id end,p_expires_at
  ) returning id into v_invitation;
  insert into public.audit_events(organization_id,actor_id,action,entity_id)
    values (p_organization_id,p_actor_id,'invitation:create',v_invitation);
  return v_invitation;
end
$$;
revoke all on function public.create_organization_invitation(uuid,uuid,text,text,public.academy_role,boolean,uuid,timestamptz)
  from public, anon, authenticated;
grant execute on function public.create_organization_invitation(uuid,uuid,text,text,public.academy_role,boolean,uuid,timestamptz)
  to service_role;

create function public.accept_organization_invitation(
  p_token_hash text,
  p_user_id uuid,
  p_email text
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_inv public.organization_invitations%rowtype;
  v_membership uuid;
begin
  select * into v_inv
  from public.organization_invitations
  where token_hash = p_token_hash
  for update;
  if v_inv.id is null
    or v_inv.revoked_at is not null
    or v_inv.accepted_at is not null
    or v_inv.expires_at <= now()
    or v_inv.email <> lower(trim(p_email))
    or not exists (
      select 1 from public.organizations
      where id = v_inv.organization_id and status = 'active'
    ) then
    raise exception 'Invitation is invalid or expired' using errcode = '42501';
  end if;
  insert into public.memberships(organization_id,user_id,active,all_units)
    values (v_inv.organization_id,p_user_id,true,v_inv.all_units)
  on conflict (organization_id,user_id)
    do update set active = true, all_units = memberships.all_units or excluded.all_units
  returning id into v_membership;
  insert into public.membership_roles(organization_id,membership_id,role)
    values (v_inv.organization_id,v_membership,v_inv.role)
  on conflict do nothing;
  if not v_inv.all_units then
    insert into public.membership_units(organization_id,membership_id,unit_id)
      values (v_inv.organization_id,v_membership,v_inv.unit_id)
    on conflict do nothing;
  end if;
  update public.organization_invitations
    set accepted_at = now(), accepted_by = p_user_id
    where id = v_inv.id;
  insert into public.audit_events(organization_id,actor_id,action,entity_id)
    values (v_inv.organization_id,p_user_id,'invitation:accept',v_inv.id);
  return jsonb_build_object('organization_id',v_inv.organization_id,'membership_id',v_membership);
end
$$;
revoke all on function public.accept_organization_invitation(text,uuid,text) from public, anon, authenticated;
grant execute on function public.accept_organization_invitation(text,uuid,text) to service_role;

create function public.review_onboarding(
  p_onboarding_id uuid,
  p_actor_id uuid,
  p_decision public.onboarding_review_decision,
  p_notes text,
  p_requested_fields text[] default '{}'
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_doc public.onboarding_versions%rowtype;
  v_review uuid;
begin
  select * into v_doc from public.onboarding_versions
    where id = p_onboarding_id for update;
  if v_doc.id is null or v_doc.status <> 'submitted' then
    raise exception 'Onboarding is not awaiting review' using errcode = '22023';
  end if;
  if not (
    exists (
      select 1 from private.platform_roles
      where user_id = p_actor_id and role = 'supreme'
    )
    or exists (
      select 1
      from private.platform_roles pr
      join public.support_access_grants g on g.user_id = pr.user_id
      where pr.user_id = p_actor_id and pr.role = 'support'
        and g.organization_id = v_doc.organization_id
        and g.mode = 'read_write' and g.revoked_at is null
        and now() >= g.starts_at and now() < g.expires_at
    )
  ) then
    raise exception 'Forbidden' using errcode = '42501';
  end if;
  update public.onboarding_versions
    set status = (case when p_decision = 'approved' then 'approved' else 'rejected' end)::public.onboarding_status,
        reviewed_at = now(), reviewed_by = p_actor_id
    where id = v_doc.id;
  insert into public.onboarding_reviews(
    organization_id,unit_id,onboarding_id,reviewer_id,decision,notes,requested_fields
  ) values (
    v_doc.organization_id,v_doc.unit_id,v_doc.id,p_actor_id,p_decision,
    trim(p_notes),coalesce(p_requested_fields,'{}')
  ) returning id into v_review;
  insert into public.audit_events(organization_id,actor_id,action,entity_id)
    values (v_doc.organization_id,p_actor_id,'onboarding:review',v_doc.id);
  return v_review;
end
$$;
revoke all on function public.review_onboarding(uuid,uuid,public.onboarding_review_decision,text,text[])
  from public, anon, authenticated;
grant execute on function public.review_onboarding(uuid,uuid,public.onboarding_review_decision,text,text[])
  to service_role;

do $$
declare t text;
begin
  foreach t in array array[
    'organization_invitations','onboarding_field_definitions',
    'onboarding_reviews','onboarding_attachments'
  ] loop
    execute format('alter table public.%I enable row level security',t);
    execute format('revoke all on public.%I from anon, authenticated',t);
  end loop;
end
$$;

grant select on public.onboarding_field_definitions to authenticated;
grant select on public.onboarding_reviews, public.onboarding_attachments to authenticated;
grant insert(organization_id,unit_id,onboarding_id,storage_path,filename,mime_type,byte_size,uploaded_by),
  delete on public.onboarding_attachments to authenticated;

create policy onboarding_definitions_read
  on public.onboarding_field_definitions for select to authenticated using (active);
create policy onboarding_reviews_read
  on public.onboarding_reviews for select to authenticated
  using (private.can_access(organization_id,unit_id));
create policy onboarding_attachments_read
  on public.onboarding_attachments for select to authenticated
  using (private.can_access(organization_id,unit_id));
create policy onboarding_attachments_insert
  on public.onboarding_attachments for insert to authenticated
  with check (
    uploaded_by = auth.uid()
    and private.can_access(organization_id,unit_id,true)
    and exists (
      select 1 from public.onboarding_versions v
      where v.id = onboarding_id and v.organization_id = onboarding_attachments.organization_id
        and v.unit_id = onboarding_attachments.unit_id and v.status = 'draft'
    )
  );
create policy onboarding_attachments_delete
  on public.onboarding_attachments for delete to authenticated
  using (
    uploaded_by = auth.uid()
    and private.can_access(organization_id,unit_id,true)
    and exists (
      select 1 from public.onboarding_versions v
      where v.id = onboarding_id and v.organization_id = onboarding_attachments.organization_id
        and v.unit_id = onboarding_attachments.unit_id and v.status = 'draft'
    )
  );

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types)
values (
  'onboarding-private','onboarding-private',false,10485760,
  array['image/jpeg','image/png','image/webp','application/pdf']
)
on conflict (id) do update set
  public = false,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

create function private.safe_uuid(value text)
returns uuid language plpgsql immutable set search_path = '' as $$
begin
  return value::uuid;
exception when invalid_text_representation then
  return null;
end
$$;
revoke all on function private.safe_uuid(text) from public, anon;
grant execute on function private.safe_uuid(text) to authenticated;

create policy onboarding_objects_read
  on storage.objects for select to authenticated
  using (
    bucket_id = 'onboarding-private'
    and private.can_access(
      private.safe_uuid((storage.foldername(name))[1]),
      private.safe_uuid((storage.foldername(name))[2])
    )
  );
create policy onboarding_objects_insert
  on storage.objects for insert to authenticated
  with check (
    bucket_id = 'onboarding-private'
    and private.can_access(
      private.safe_uuid((storage.foldername(name))[1]),
      private.safe_uuid((storage.foldername(name))[2]),
      true
    )
  );
create policy onboarding_objects_delete
  on storage.objects for delete to authenticated
  using (
    bucket_id = 'onboarding-private'
    and private.can_access(
      private.safe_uuid((storage.foldername(name))[1]),
      private.safe_uuid((storage.foldername(name))[2]),
      true
    )
  );

insert into public.onboarding_field_definitions
  (schema_version,field_key,scope,section,label,description,field_type,required,validation,options,sort_order)
values
  (1,'legal_name','organization','Empresa','Razão social','Nome jurídico da empresa.','short_text',true,'{"minLength":2}','[]',10),
  (1,'brand_name','organization','Empresa','Nome da academia','Nome usado na comunicação.','short_text',true,'{"minLength":2}','[]',20),
  (1,'cnpj','organization','Empresa','CNPJ','Somente números.','short_text',true,'{"pattern":"^[0-9]{14}$"}','[]',30),
  (1,'website','organization','Presença digital','Site',null,'url',false,'{}','[]',40),
  (1,'instagram','organization','Presença digital','Instagram',null,'short_text',false,'{}','[]',50),
  (1,'facebook','organization','Presença digital','Facebook',null,'url',false,'{}','[]',60),
  (1,'tiktok','organization','Presença digital','TikTok',null,'short_text',false,'{}','[]',70),
  (1,'address','unit','Unidade','Endereço completo','Inclua CEP e referências locais.','long_text',true,'{"minLength":10}','[]',80),
  (1,'opening_hours','unit','Unidade','Horários de funcionamento',null,'long_text',true,'{}','[]',90),
  (1,'monthly_members','unit','Operação','Quantidade de alunos ativos',null,'number',true,'{"min":0}','[]',100),
  (1,'monthly_leads','unit','Operação','Média de leads por mês',null,'number',false,'{"min":0}','[]',110),
  (1,'average_ticket','unit','Operação','Ticket médio mensal',null,'currency',true,'{"min":0}','[]',120),
  (1,'plans','unit','Oferta','Planos, preços e condições',null,'long_text',true,'{"minLength":10}','[]',130),
  (1,'differentials','unit','Oferta','Principais diferenciais',null,'long_text',true,'{"minLength":10}','[]',140),
  (1,'main_goal','unit','Marketing','Meta principal para 90 dias',null,'single_select',true,'{}','["mais_matriculas","reduzir_churn","aumentar_ticket","fortalecer_marca"]',150),
  (1,'target_audience','unit','Público','Público-alvo atual',null,'long_text',true,'{"minLength":10}','[]',160),
  (1,'desired_audience','unit','Público','Público que deseja atrair',null,'long_text',true,'{"minLength":10}','[]',170),
  (1,'competitors','unit','Mercado','Concorrentes conhecidos','Nome, endereço e redes sociais.','long_text',true,'{"minLength":3}','[]',180),
  (1,'local_context','unit','Mercado','Entorno da unidade','Condomínios, empresas, escolas, fluxo e bairros.','long_text',true,'{"minLength":10}','[]',190),
  (1,'brand_voice','organization','Marca','Tom de voz da marca',null,'multi_select',true,'{}','["motivador","premium","popular","tecnico","acolhedor","divertido"]',200),
  (1,'brand_colors','organization','Marca','Cores oficiais',null,'short_text',true,'{}','[]',210),
  (1,'restrictions','organization','Marca','Restrições de comunicação','O que não deve ser publicado.','long_text',false,'{}','[]',220),
  (1,'available_assets','unit','Conteúdo','Materiais disponíveis','Fotos, vídeos, depoimentos e banco de imagens.','long_text',true,'{}','[]',230),
  (1,'content_operator','unit','Equipe','Responsável local pelo marketing',null,'short_text',true,'{}','[]',240),
  (1,'filming_days','unit','Equipe','Dias disponíveis para gravação',null,'short_text',false,'{}','[]',250),
  (1,'monthly_media_budget','unit','Mídia paga','Orçamento mensal de tráfego',null,'currency',true,'{"min":0}','[]',260),
  (1,'promotion_rules','unit','Mídia paga','Limites para campanhas e promoções',null,'long_text',false,'{}','[]',270),
  (1,'sales_process','unit','Vendas','Como funciona o atendimento e fechamento',null,'long_text',true,'{"minLength":10}','[]',280),
  (1,'crm_stages','unit','Vendas','Etapas atuais do funil',null,'long_text',false,'{}','[]',290),
  (1,'success_metrics','unit','Métricas','Indicadores acompanhados',null,'multi_select',true,'{}','["leads","agendamentos","visitas","matriculas","cac","churn","ticket","roi"]',300);

-- Fonte: 20260911001000_identity_hardening.sql
-- SHA256 (UTF-8, LF): d6be5af7eb366b1bca6951374cfd063898116db95814f4e25dbb68cb6f67d00b
-- Close authorization gaps found while integrating the supplied phase 2 package.

alter table public.onboarding_versions add column revision integer not null default 0 check(revision>=0);
create function private.increment_onboarding_revision() returns trigger language plpgsql set search_path='' as $$
begin new.revision := old.revision+1; return new; end $$;
revoke all on function private.increment_onboarding_revision() from public,anon,authenticated;
create trigger increment_onboarding_revision before update on public.onboarding_versions
  for each row execute function private.increment_onboarding_revision();

create function private.can_review_onboarding(actor uuid, org uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.organizations where id=org and status='active') and (
    exists(select 1 from private.platform_roles where user_id=actor and role='supreme')
    or exists(select 1 from private.platform_roles p join public.support_access_grants g on g.user_id=p.user_id
      where p.user_id=actor and p.role='support' and g.organization_id=org
      and g.mode='read_write' and g.revoked_at is null and now()>=g.starts_at and now()<g.expires_at)
  );
$$;
revoke all on function private.can_review_onboarding(uuid,uuid) from public,anon,authenticated;

create function private.validate_onboarding_submission()
returns trigger language plpgsql set search_path='' as $$
declare f record; v jsonb; missing boolean; valid boolean;
begin
  if old.status <> 'draft' or new.status <> 'submitted' then return new; end if;
  if jsonb_typeof(new.document) <> 'object' or not exists(
    select 1 from public.onboarding_field_definitions where schema_version=new.schema_version and active
  ) then raise exception 'Invalid onboarding schema' using errcode='23514'; end if;
  for f in select * from public.onboarding_field_definitions where schema_version=new.schema_version and active loop
    v := new.document -> f.field_key;
    missing := v is null or v='null'::jsonb or v='[]'::jsonb or (jsonb_typeof(v)='string' and btrim(v #>> '{}')='');
    if missing then
      if f.required then raise exception 'Required onboarding field is missing' using errcode='23514'; end if;
      continue;
    end if;
    valid := true;
    if f.field_type in ('number','currency') then
      valid := jsonb_typeof(v)='number';
      if valid and f.validation ? 'min' then valid := (v #>> '{}')::numeric >= (f.validation->>'min')::numeric; end if;
    elsif f.field_type='boolean' then valid := jsonb_typeof(v)='boolean';
    elsif f.field_type='multi_select' then
      valid := jsonb_typeof(v)='array';
      if valid then valid := not exists(select 1 from jsonb_array_elements(v) item where not f.options @> jsonb_build_array(item)); end if;
    else
      valid := jsonb_typeof(v)='string';
      if valid and f.validation ? 'minLength' then valid := length(btrim(v #>> '{}')) >= (f.validation->>'minLength')::integer; end if;
      if valid and f.validation ? 'pattern' then valid := (v #>> '{}') ~ (f.validation->>'pattern'); end if;
      if valid and f.field_type='single_select' then valid := f.options @> jsonb_build_array(v); end if;
      if valid and f.field_type='url' then valid := (v #>> '{}') ~ '^https?://[^[:space:]]+$'; end if;
      if valid and f.field_type='email' then valid := (v #>> '{}') ~ '^[^@[:space:]]+@[^@[:space:]]+\.[^@[:space:]]+$'; end if;
    end if;
    if not valid then raise exception 'Invalid onboarding field value' using errcode='23514'; end if;
  end loop;
  return new;
end $$;
revoke all on function private.validate_onboarding_submission() from public,anon,authenticated;
create trigger validate_onboarding_submission before update on public.onboarding_versions
  for each row execute function private.validate_onboarding_submission();

create function private.freeze_onboarding_definition()
returns trigger language plpgsql set search_path='' as $$
begin
  if exists(select 1 from public.onboarding_versions where schema_version=case when tg_op='INSERT' then new.schema_version else old.schema_version end) then
    raise exception 'Used schema versions are immutable; create a new version' using errcode='23514';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end $$;
revoke all on function private.freeze_onboarding_definition() from public,anon,authenticated;
create trigger freeze_onboarding_definition before insert or update or delete on public.onboarding_field_definitions
  for each row execute function private.freeze_onboarding_definition();

create function private.review_guard_and_facts()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if not private.can_review_onboarding(new.reviewer_id,new.organization_id) then
    raise exception 'Review access denied' using errcode='42501';
  end if;
  if new.decision='changes_requested' and cardinality(new.requested_fields)=0 then
    raise exception 'Requested changes must identify fields' using errcode='23514';
  end if;
  if new.decision='approved' then
    insert into public.academy_facts(organization_id,unit_id,onboarding_id,facts)
      select organization_id,unit_id,id,document from public.onboarding_versions where id=new.onboarding_id and status='approved';
  end if;
  return new;
end $$;
revoke all on function private.review_guard_and_facts() from public,anon,authenticated;
create trigger review_guard_and_facts after insert on public.onboarding_reviews
  for each row execute function private.review_guard_and_facts();

create function public.onboarding_review_queue(p_actor_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare result jsonb;
begin
  select coalesce(jsonb_agg(jsonb_build_object('id',v.id,'organization_name',o.name,'unit_name',u.name,'version',v.version)),'[]') into result
    from public.onboarding_versions v join public.organizations o on o.id=v.organization_id
    join public.units u on u.id=v.unit_id and u.organization_id=v.organization_id
    where v.status='submitted' and private.can_review_onboarding(p_actor_id,v.organization_id);
  insert into public.audit_events(organization_id,actor_id,action,entity_id)
    select organization_id,p_actor_id,'onboarding:review_queue',id from public.onboarding_versions
    where status='submitted' and private.can_review_onboarding(p_actor_id,organization_id);
  return jsonb_build_object('onboardings',result);
end $$;

create function public.onboarding_review_detail(p_actor_id uuid,p_onboarding_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v public.onboarding_versions%rowtype;
begin
  select * into v from public.onboarding_versions where id=p_onboarding_id;
  if v.id is null or not private.can_review_onboarding(p_actor_id,v.organization_id) then raise exception 'Forbidden' using errcode='42501'; end if;
  insert into public.audit_events(organization_id,actor_id,action,entity_id) values(v.organization_id,p_actor_id,'onboarding:review_read',v.id);
  return jsonb_build_object('onboarding',to_jsonb(v),
    'fields',(select coalesce(jsonb_agg(to_jsonb(d) order by sort_order),'[]') from public.onboarding_field_definitions d where schema_version=v.schema_version),
    'attachments',(select coalesce(jsonb_agg(jsonb_build_object('id',id,'filename',filename)),'[]') from public.onboarding_attachments where onboarding_id=v.id));
end $$;

create function public.onboarding_review_attachment(p_actor_id uuid,p_attachment_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare a public.onboarding_attachments%rowtype;
begin
  select * into a from public.onboarding_attachments where id=p_attachment_id;
  if a.id is null or not private.can_review_onboarding(p_actor_id,a.organization_id) then raise exception 'Forbidden' using errcode='42501'; end if;
  insert into public.audit_events(organization_id,actor_id,action,entity_id) values(a.organization_id,p_actor_id,'onboarding:attachment_read',a.id);
  return jsonb_build_object('storage_path',a.storage_path,'filename',a.filename,'mime_type',a.mime_type);
end $$;
revoke all on function public.onboarding_review_queue(uuid),public.onboarding_review_detail(uuid,uuid),public.onboarding_review_attachment(uuid,uuid) from public,anon,authenticated;
grant execute on function public.onboarding_review_queue(uuid),public.onboarding_review_detail(uuid,uuid),public.onboarding_review_attachment(uuid,uuid) to service_role;

-- One immutable path binds the metadata, tenant, unit and onboarding version.
alter table public.onboarding_attachments add constraint attachment_path_matches_context check (
  split_part(storage_path,'/',1)=organization_id::text and split_part(storage_path,'/',2)=unit_id::text
  and split_part(storage_path,'/',3)=onboarding_id::text and split_part(storage_path,'/',4)<>''
  and array_length(string_to_array(storage_path,'/'),1)=4
) not valid;

create function private.onboarding_object_allowed(object_name text,writing boolean)
returns boolean language plpgsql security definer set search_path='' as $$
declare a public.onboarding_attachments%rowtype; state public.onboarding_status;
begin
  select * into a from public.onboarding_attachments where storage_path=object_name;
  if a.id is null or not private.can_access(a.organization_id,a.unit_id,writing) then return false; end if;
  if writing then
    -- Serialize storage mutation and submission, so a closed version cannot acquire late attachments.
    select status into state from public.onboarding_versions where id=a.onboarding_id for share;
    return state='draft' and a.uploaded_by=auth.uid();
  end if;
  return true;
end $$;
revoke all on function private.onboarding_object_allowed(text,boolean) from public,anon;
grant execute on function private.onboarding_object_allowed(text,boolean) to authenticated;
drop policy onboarding_objects_read on storage.objects;
drop policy onboarding_objects_insert on storage.objects;
drop policy onboarding_objects_delete on storage.objects;
create policy onboarding_objects_read on storage.objects for select to authenticated
  using(bucket_id='onboarding-private' and private.onboarding_object_allowed(name,false));
create policy onboarding_objects_insert on storage.objects for insert to authenticated
  with check(bucket_id='onboarding-private' and private.onboarding_object_allowed(name,true));
create policy onboarding_objects_delete on storage.objects for delete to authenticated
  using(bucket_id='onboarding-private' and private.onboarding_object_allowed(name,true));

create function private.invitation_acceptance_guard()
returns trigger language plpgsql security definer set search_path='' as $$
declare recipient public.memberships%rowtype; inviter public.memberships%rowtype; permitted boolean;
begin
  if old.accepted_at is not null or old.revoked_at is not null then
    raise exception 'Closed invitations are immutable' using errcode='23514';
  end if;
  if (new.organization_id,new.email,new.token_hash,new.role,new.all_units,new.unit_id,new.invited_by,new.expires_at)
    is distinct from (old.organization_id,old.email,old.token_hash,old.role,old.all_units,old.unit_id,old.invited_by,old.expires_at) then
    raise exception 'Invitation identity is immutable' using errcode='23514';
  end if;
  if new.accepted_at is null then return new; end if;
  if not exists(select 1 from auth.users where id=new.accepted_by and lower(email)=new.email) then
    raise exception 'Verified user and invitation email do not match' using errcode='42501';
  end if;
  if exists(select 1 from private.platform_roles where user_id=new.invited_by and role='supreme') then return new; end if;
  select * into inviter from public.memberships where organization_id=new.organization_id and user_id=new.invited_by and active;
  permitted := inviter.id is not null and exists(select 1 from public.membership_roles where membership_id=inviter.id and role='academy_admin');
  select * into recipient from public.memberships where organization_id=new.organization_id and user_id=new.accepted_by;
  if not permitted or (recipient.all_units and not inviter.all_units) or (not inviter.all_units and exists(
    select 1 from public.membership_units r where r.membership_id=recipient.id and not exists(
      select 1 from public.membership_units i where i.membership_id=inviter.id and i.unit_id=r.unit_id
    )
  )) then raise exception 'Inviter no longer controls the resulting scope' using errcode='42501'; end if;
  return new;
end $$;
revoke all on function private.invitation_acceptance_guard() from public,anon,authenticated;
create trigger invitation_acceptance_guard before update on public.organization_invitations
  for each row execute function private.invitation_acceptance_guard();

create index on public.organization_invitations(invited_by);
create index on public.organization_invitations(accepted_by);
create index on public.organization_invitations(organization_id,unit_id);
create index on public.onboarding_versions(reviewed_by);
create index on public.onboarding_reviews(reviewer_id);
create index on public.onboarding_attachments(uploaded_by);

-- Fonte: 20260916000000_crm_agenda.sql
-- SHA256 (UTF-8, LF): 720ec202340a517a3b87ab4dc44180c63a5c53fd8c72b82a491c86beedb97667
-- Phase 3A: tenant-safe CRM, configurable pipelines, tasks and commercial agenda.

create type public.crm_identifier_kind as enum ('phone','email','external');
create type public.crm_opportunity_status as enum ('open','won','lost');
create type public.crm_task_priority as enum ('low','normal','high','urgent');
create type public.crm_task_status as enum ('open','done','cancelled');
create type public.crm_appointment_status as enum (
  'scheduled','confirmed','attended','no_show','rescheduled','cancelled','enrolled','lost'
);

create table public.crm_contacts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  display_name text not null check(length(btrim(display_name)) between 2 and 160),
  city text check(city is null or length(btrim(city)) between 1 and 120),
  source text check(source is null or length(source) between 1 and 80),
  anonymized_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,id)
);

create table public.crm_contact_identifiers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  contact_id uuid not null,
  kind public.crm_identifier_kind not null,
  normalized_value text not null check(length(normalized_value) between 3 and 320),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  unique(organization_id,kind,normalized_value),
  unique(organization_id,id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id)
);

create table public.crm_contact_units (
  organization_id uuid not null,
  contact_id uuid not null,
  unit_id uuid not null,
  first_seen_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  primary key(organization_id,contact_id,unit_id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.crm_consents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  contact_id uuid not null,
  channel text not null check(channel in ('whatsapp','email','sms','phone','all')),
  purpose text not null check(length(purpose) between 2 and 120),
  legal_basis text not null check(length(legal_basis) between 2 and 120),
  source text not null check(length(source) between 2 and 160),
  proof jsonb not null default '{}',
  granted_at timestamptz,
  revoked_at timestamptz,
  valid_until timestamptz,
  created_at timestamptz not null default now(),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  check(granted_at is not null or revoked_at is not null),
  check(valid_until is null or granted_at is null or valid_until > granted_at)
);

create table public.crm_tags (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  name text not null check(length(btrim(name)) between 1 and 60),
  color text check(color is null or color ~ '^#[0-9a-fA-F]{6}$'),
  unique(organization_id,id)
);

create table public.crm_contact_tags (
  organization_id uuid not null,
  contact_id uuid not null,
  tag_id uuid not null,
  created_at timestamptz not null default now(),
  created_by uuid not null references auth.users(id),
  primary key(organization_id,contact_id,tag_id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  foreign key(organization_id,tag_id) references public.crm_tags(organization_id,id)
);

create table public.crm_pipelines (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  name text not null check(length(btrim(name)) between 2 and 100),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  unique(organization_id,unit_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.crm_pipeline_stages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  pipeline_id uuid not null,
  name text not null check(length(btrim(name)) between 1 and 80),
  position integer not null check(position >= 0),
  outcome public.crm_opportunity_status,
  active boolean not null default true,
  unique(organization_id,unit_id,id),
  unique(organization_id,unit_id,pipeline_id,position),
  foreign key(organization_id,unit_id,pipeline_id) references public.crm_pipelines(organization_id,unit_id,id)
);

create table public.crm_opportunities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  contact_id uuid not null,
  pipeline_id uuid not null,
  stage_id uuid not null,
  owner_id uuid references auth.users(id),
  title text not null check(length(btrim(title)) between 2 and 160),
  status public.crm_opportunity_status not null default 'open',
  value_cents bigint check(value_cents is null or value_cents >= 0),
  source text check(source is null or length(source) <= 80),
  campaign text check(campaign is null or length(campaign) <= 160),
  external_key text,
  loss_reason text check(loss_reason is null or length(loss_reason) <= 500),
  enrolled_at timestamptz,
  lost_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,unit_id,id),
  unique(organization_id,unit_id,external_key),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,contact_id,unit_id) references public.crm_contact_units(organization_id,contact_id,unit_id),
  foreign key(organization_id,unit_id,pipeline_id) references public.crm_pipelines(organization_id,unit_id,id),
  foreign key(organization_id,unit_id,stage_id) references public.crm_pipeline_stages(organization_id,unit_id,id)
);

create table public.crm_opportunity_stage_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  opportunity_id uuid not null,
  from_stage_id uuid,
  to_stage_id uuid not null,
  actor_id uuid not null references auth.users(id),
  reason text check(reason is null or length(reason) <= 500),
  idempotency_key text not null check(length(idempotency_key) between 16 and 128),
  created_at timestamptz not null default now(),
  unique(organization_id,opportunity_id,idempotency_key),
  foreign key(organization_id,unit_id,opportunity_id) references public.crm_opportunities(organization_id,unit_id,id),
  foreign key(organization_id,unit_id,from_stage_id) references public.crm_pipeline_stages(organization_id,unit_id,id),
  foreign key(organization_id,unit_id,to_stage_id) references public.crm_pipeline_stages(organization_id,unit_id,id)
);

create table public.crm_notes (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  contact_id uuid not null,
  author_id uuid not null references auth.users(id),
  body text not null check(length(btrim(body)) between 1 and 5000),
  created_at timestamptz not null default now(),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id)
);

create table public.crm_activities (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  contact_id uuid not null,
  opportunity_id uuid,
  actor_id uuid references auth.users(id),
  activity_type text not null check(length(activity_type) between 2 and 80),
  summary text not null check(length(summary) between 1 and 500),
  metadata jsonb not null default '{}',
  occurred_at timestamptz not null default now(),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  foreign key(organization_id,unit_id,opportunity_id) references public.crm_opportunities(organization_id,unit_id,id)
);

create table public.crm_tasks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  contact_id uuid,
  opportunity_id uuid,
  assignee_id uuid not null references auth.users(id),
  created_by uuid not null references auth.users(id),
  title text not null check(length(btrim(title)) between 2 and 200),
  priority public.crm_task_priority not null default 'normal',
  status public.crm_task_status not null default 'open',
  due_at timestamptz not null,
  remind_at timestamptz,
  idempotency_key text not null check(length(idempotency_key) between 16 and 128),
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  foreign key(organization_id,unit_id,opportunity_id) references public.crm_opportunities(organization_id,unit_id,id),
  check(remind_at is null or remind_at <= due_at)
);

create table public.crm_appointments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  contact_id uuid not null,
  opportunity_id uuid,
  responsible_id uuid not null references auth.users(id),
  kind text not null check(kind in ('visit','trial_class','call','other')),
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  status public.crm_appointment_status not null default 'scheduled',
  notes text check(notes is null or length(notes) <= 2000),
  idempotency_key text not null check(length(idempotency_key) between 16 and 128),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,idempotency_key),
  unique(organization_id,unit_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  foreign key(organization_id,unit_id,opportunity_id) references public.crm_opportunities(organization_id,unit_id,id),
  check(ends_at > starts_at)
);

create table public.crm_appointment_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  appointment_id uuid not null,
  from_status public.crm_appointment_status,
  to_status public.crm_appointment_status not null,
  actor_id uuid not null references auth.users(id),
  reason text check(reason is null or length(reason) <= 500),
  created_at timestamptz not null default now(),
  foreign key(organization_id,unit_id,appointment_id) references public.crm_appointments(organization_id,unit_id,id)
);

create table private.crm_idempotency (
  organization_id uuid not null references public.organizations(id),
  operation text not null,
  idempotency_key text not null,
  response jsonb not null,
  created_at timestamptz not null default now(),
  primary key(organization_id,operation,idempotency_key)
);

create index crm_contacts_created_idx on public.crm_contacts(organization_id,created_at desc,id);
create unique index crm_tags_name_unique on public.crm_tags(organization_id,lower(name));
create unique index crm_pipelines_name_unique on public.crm_pipelines(organization_id,unit_id,lower(name));
create index crm_contact_units_unit_idx on public.crm_contact_units(organization_id,unit_id,last_seen_at desc);
create index crm_opportunities_board_idx on public.crm_opportunities(organization_id,unit_id,pipeline_id,stage_id,updated_at desc);
create index crm_tasks_due_idx on public.crm_tasks(organization_id,unit_id,status,due_at);
create index crm_appointments_time_idx on public.crm_appointments(organization_id,unit_id,starts_at);
create index crm_consents_contact_idx on public.crm_consents(organization_id,contact_id,channel,created_at desc);

create function private.crm_can_actor(actor uuid,org uuid,unit uuid,capability text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.organizations where id=org and status='active') and (
    exists(
      select 1 from public.memberships m join public.membership_roles r
        on r.organization_id=m.organization_id and r.membership_id=m.id
      where m.organization_id=org and m.user_id=actor and m.active
        and (unit is null or m.all_units or exists(
          select 1 from public.membership_units mu where mu.organization_id=org and mu.membership_id=m.id and mu.unit_id=unit
        ))
        and (
          r.role='academy_admin'
          or (r.role='academy_attendant' and capability in ('aggregate','read_crm','write_crm','inbox','read_ai'))
          or (r.role='marketing_operator' and capability in ('aggregate','attribution'))
          or (r.role='viewer' and capability='aggregate')
        )
    ) or exists(
      select 1 from private.platform_roles p join public.support_access_grants g on g.user_id=p.user_id
      where p.user_id=actor and p.role='support' and g.organization_id=org
        and g.revoked_at is null and now()>=g.starts_at and now()<g.expires_at
        and (capability not in ('write_crm','inbox','configure') or g.mode='read_write')
    )
  );
$$;
revoke all on function private.crm_can_actor(uuid,uuid,uuid,text) from public,anon,authenticated;

create function private.crm_can(org uuid,unit uuid,capability text)
returns boolean language sql stable security definer set search_path='' as $$
  select private.crm_can_actor((select auth.uid()),org,unit,capability);
$$;
revoke all on function private.crm_can(uuid,uuid,text) from public,anon;
grant execute on function private.crm_can(uuid,uuid,text) to authenticated;

create function private.crm_contact_allowed(org uuid,contact uuid,capability text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.crm_contact_units cu where cu.organization_id=org and cu.contact_id=contact
    and private.crm_can(org,cu.unit_id,capability));
$$;
revoke all on function private.crm_contact_allowed(uuid,uuid,text) from public,anon;
grant execute on function private.crm_contact_allowed(uuid,uuid,text) to authenticated;

create function public.crm_authorize(p_actor_id uuid,p_organization_id uuid,p_unit_id uuid,p_capability text)
returns boolean language sql stable security definer set search_path='' as $$
  select private.crm_can_actor(p_actor_id,p_organization_id,p_unit_id,p_capability);
$$;
revoke all on function public.crm_authorize(uuid,uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.crm_authorize(uuid,uuid,uuid,text) to service_role;

create function public.crm_dashboard(p_organization_id uuid,p_unit_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.crm_can(p_organization_id,p_unit_id,'aggregate') then raise exception 'Forbidden' using errcode='42501'; end if;
  return jsonb_build_object(
    'open_opportunities',(select count(*) from public.crm_opportunities where organization_id=p_organization_id and unit_id=p_unit_id and status='open'),
    'won_this_month',(select count(*) from public.crm_opportunities where organization_id=p_organization_id and unit_id=p_unit_id and status='won' and enrolled_at>=date_trunc('month',now())),
    'tasks_due',(select count(*) from public.crm_tasks where organization_id=p_organization_id and unit_id=p_unit_id and status='open' and due_at<now()+interval '24 hours'),
    'next_visits',(select count(*) from public.crm_appointments where organization_id=p_organization_id and unit_id=p_unit_id and status in ('scheduled','confirmed') and starts_at between now() and now()+interval '7 days')
  );
end $$;
revoke all on function public.crm_dashboard(uuid,uuid) from public,anon;
grant execute on function public.crm_dashboard(uuid,uuid) to authenticated;

create function public.upsert_crm_contact(
  p_organization_id uuid,p_unit_id uuid,p_name text,p_phone text,p_email text,p_city text,p_source text,
  p_external_key text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare contact uuid; cached jsonb; result jsonb;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'write_crm') then raise exception 'Forbidden' using errcode='42501'; end if;
  if length(p_idempotency_key) not between 16 and 128 then raise exception 'Invalid idempotency key' using errcode='22023'; end if;
  select response into cached from private.crm_idempotency where organization_id=p_organization_id and operation='contact.upsert' and idempotency_key=p_idempotency_key;
  if cached is not null then return cached; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_organization_id::text,0));
  select ci.contact_id into contact from public.crm_contact_identifiers ci where ci.organization_id=p_organization_id and (
    (p_phone is not null and ci.kind='phone' and ci.normalized_value=p_phone) or
    (p_email is not null and ci.kind='email' and ci.normalized_value=lower(p_email)) or
    (p_external_key is not null and ci.kind='external' and ci.normalized_value=p_external_key)
  ) limit 1;
  if contact is null then
    insert into public.crm_contacts(organization_id,display_name,city,source) values(p_organization_id,btrim(p_name),nullif(btrim(p_city),''),nullif(btrim(p_source),'')) returning id into contact;
  else
    update public.crm_contacts set display_name=btrim(p_name),city=coalesce(nullif(btrim(p_city),''),city),updated_at=now()
      where organization_id=p_organization_id and id=contact and anonymized_at is null;
  end if;
  insert into public.crm_contact_units(organization_id,contact_id,unit_id) values(p_organization_id,contact,p_unit_id)
    on conflict(organization_id,contact_id,unit_id) do update set last_seen_at=now();
  if p_phone is not null then insert into public.crm_contact_identifiers(organization_id,contact_id,kind,normalized_value)
    values(p_organization_id,contact,'phone',p_phone) on conflict(organization_id,kind,normalized_value) do nothing; end if;
  if p_email is not null then insert into public.crm_contact_identifiers(organization_id,contact_id,kind,normalized_value)
    values(p_organization_id,contact,'email',lower(p_email)) on conflict(organization_id,kind,normalized_value) do nothing; end if;
  if p_external_key is not null then insert into public.crm_contact_identifiers(organization_id,contact_id,kind,normalized_value)
    values(p_organization_id,contact,'external',p_external_key) on conflict(organization_id,kind,normalized_value) do nothing; end if;
  result=jsonb_build_object('id',contact,'created_or_updated',true);
  insert into private.crm_idempotency values(p_organization_id,'contact.upsert',p_idempotency_key,result,now()) on conflict do nothing;
  return result;
end $$;
revoke all on function public.upsert_crm_contact(uuid,uuid,text,text,text,text,text,text,text) from public,anon;
grant execute on function public.upsert_crm_contact(uuid,uuid,text,text,text,text,text,text,text) to authenticated;

create function public.create_crm_opportunity(
  p_organization_id uuid,p_unit_id uuid,p_contact_id uuid,p_pipeline_id uuid,p_stage_id uuid,
  p_title text,p_source text,p_campaign text,p_external_key text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare item public.crm_opportunities%rowtype; cached jsonb; result jsonb;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'write_crm') then raise exception 'Forbidden' using errcode='42501'; end if;
  select response into cached from private.crm_idempotency where organization_id=p_organization_id and operation='opportunity.create' and idempotency_key=p_idempotency_key;
  if cached is not null then return cached; end if;
  if not exists(select 1 from public.crm_pipeline_stages where organization_id=p_organization_id and unit_id=p_unit_id and pipeline_id=p_pipeline_id and id=p_stage_id and active) then
    raise exception 'Invalid stage' using errcode='23514'; end if;
  insert into public.crm_opportunities(organization_id,unit_id,contact_id,pipeline_id,stage_id,title,source,campaign,external_key)
    values(p_organization_id,p_unit_id,p_contact_id,p_pipeline_id,p_stage_id,btrim(p_title),p_source,p_campaign,p_external_key)
    returning * into item;
  insert into public.crm_opportunity_stage_history(organization_id,unit_id,opportunity_id,to_stage_id,actor_id,reason,idempotency_key)
    values(p_organization_id,p_unit_id,item.id,p_stage_id,auth.uid(),'created',p_idempotency_key);
  result=jsonb_build_object('id',item.id,'stage_id',item.stage_id,'status',item.status);
  insert into private.crm_idempotency values(p_organization_id,'opportunity.create',p_idempotency_key,result,now()) on conflict do nothing;
  return result;
end $$;
revoke all on function public.create_crm_opportunity(uuid,uuid,uuid,uuid,uuid,text,text,text,text,text) from public,anon;
grant execute on function public.create_crm_opportunity(uuid,uuid,uuid,uuid,uuid,text,text,text,text,text) to authenticated;

create function public.move_crm_opportunity(
  p_organization_id uuid,p_unit_id uuid,p_opportunity_id uuid,p_expected_stage_id uuid,p_to_stage_id uuid,
  p_reason text,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare item public.crm_opportunities%rowtype; target public.crm_pipeline_stages%rowtype; existing uuid;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'write_crm') then raise exception 'Forbidden' using errcode='42501'; end if;
  select to_stage_id into existing from public.crm_opportunity_stage_history where organization_id=p_organization_id and opportunity_id=p_opportunity_id and idempotency_key=p_idempotency_key;
  if existing is not null then return jsonb_build_object('id',p_opportunity_id,'stage_id',existing,'replayed',true); end if;
  select * into item from public.crm_opportunities where organization_id=p_organization_id and unit_id=p_unit_id and id=p_opportunity_id for update;
  if item.id is null then raise exception 'Not found' using errcode='P0002'; end if;
  if item.stage_id<>p_expected_stage_id then raise exception 'Opportunity changed' using errcode='40001'; end if;
  select * into target from public.crm_pipeline_stages where organization_id=p_organization_id and unit_id=p_unit_id and id=p_to_stage_id and pipeline_id=item.pipeline_id and active;
  if target.id is null then raise exception 'Invalid stage' using errcode='23514'; end if;
  update public.crm_opportunities set stage_id=target.id,status=coalesce(target.outcome,'open'),
    enrolled_at=case when target.outcome='won' then now() else enrolled_at end,
    lost_at=case when target.outcome='lost' then now() else lost_at end,
    loss_reason=case when target.outcome='lost' then nullif(btrim(p_reason),'') else null end,updated_at=now()
    where id=item.id;
  insert into public.crm_opportunity_stage_history(organization_id,unit_id,opportunity_id,from_stage_id,to_stage_id,actor_id,reason,idempotency_key)
    values(p_organization_id,p_unit_id,item.id,item.stage_id,target.id,auth.uid(),nullif(btrim(p_reason),''),p_idempotency_key);
  return jsonb_build_object('id',item.id,'stage_id',target.id,'status',coalesce(target.outcome,'open'),'replayed',false);
end $$;
revoke all on function public.move_crm_opportunity(uuid,uuid,uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.move_crm_opportunity(uuid,uuid,uuid,uuid,uuid,text,text) to authenticated;

create function public.record_appointment_result(
  p_organization_id uuid,p_unit_id uuid,p_appointment_id uuid,p_status public.crm_appointment_status,
  p_target_stage_id uuid,p_reason text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare item public.crm_appointments%rowtype; prior public.crm_appointment_status; moved jsonb;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'write_crm') then raise exception 'Forbidden' using errcode='42501'; end if;
  select * into item from public.crm_appointments where organization_id=p_organization_id and unit_id=p_unit_id and id=p_appointment_id for update;
  if item.id is null then raise exception 'Not found' using errcode='P0002'; end if;
  prior=item.status;
  update public.crm_appointments set status=p_status,updated_at=now() where id=item.id;
  insert into public.crm_appointment_events(organization_id,unit_id,appointment_id,from_status,to_status,actor_id,reason)
    values(p_organization_id,p_unit_id,item.id,prior,p_status,auth.uid(),nullif(btrim(p_reason),''));
  if item.opportunity_id is not null and p_target_stage_id is not null then
    select public.move_crm_opportunity(p_organization_id,p_unit_id,item.opportunity_id,
      (select stage_id from public.crm_opportunities where id=item.opportunity_id),p_target_stage_id,p_reason,'appointment:'||item.id::text||':'||p_status::text) into moved;
  end if;
  return jsonb_build_object('id',item.id,'status',p_status,'opportunity',moved);
end $$;
revoke all on function public.record_appointment_result(uuid,uuid,uuid,public.crm_appointment_status,uuid,text) from public,anon;
grant execute on function public.record_appointment_result(uuid,uuid,uuid,public.crm_appointment_status,uuid,text) to authenticated;

create function private.append_only_crm() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'CRM history is append-only' using errcode='23514'; end $$;
revoke all on function private.append_only_crm() from public,anon,authenticated;
create trigger opportunity_history_append_only before update or delete on public.crm_opportunity_stage_history for each row execute function private.append_only_crm();
create trigger appointment_events_append_only before update or delete on public.crm_appointment_events for each row execute function private.append_only_crm();
create trigger crm_activities_append_only before update or delete on public.crm_activities for each row execute function private.append_only_crm();
create trigger crm_consents_append_only before update or delete on public.crm_consents for each row execute function private.append_only_crm();

do $$ declare t text; begin
  foreach t in array array[
    'crm_contacts','crm_contact_identifiers','crm_contact_units','crm_consents','crm_tags','crm_contact_tags',
    'crm_pipelines','crm_pipeline_stages','crm_opportunities','crm_opportunity_stage_history','crm_notes',
    'crm_activities','crm_tasks','crm_appointments','crm_appointment_events'
  ] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon,authenticated',t); end loop;
end $$;
alter table private.crm_idempotency enable row level security;
revoke all on private.crm_idempotency from public,anon,authenticated;

create policy crm_contacts_read on public.crm_contacts for select to authenticated using(private.crm_contact_allowed(organization_id,id,'read_crm'));
create policy crm_contacts_update on public.crm_contacts for update to authenticated using(private.crm_contact_allowed(organization_id,id,'write_crm')) with check(private.crm_contact_allowed(organization_id,id,'write_crm'));
create policy crm_identifiers_read on public.crm_contact_identifiers for select to authenticated using(private.crm_contact_allowed(organization_id,contact_id,'read_crm'));
create policy crm_contact_units_read on public.crm_contact_units for select to authenticated using(private.crm_can(organization_id,unit_id,'read_crm'));
create policy crm_consents_read on public.crm_consents for select to authenticated using(private.crm_contact_allowed(organization_id,contact_id,'read_crm'));
create policy crm_consents_insert on public.crm_consents for insert to authenticated with check(private.crm_contact_allowed(organization_id,contact_id,'write_crm'));
create policy crm_tags_read on public.crm_tags for select to authenticated using(private.crm_can(organization_id,null,'read_crm'));
create policy crm_tags_insert on public.crm_tags for insert to authenticated with check(private.crm_can(organization_id,null,'write_crm'));
create policy crm_tags_update on public.crm_tags for update to authenticated using(private.crm_can(organization_id,null,'write_crm')) with check(private.crm_can(organization_id,null,'write_crm'));
create policy crm_tags_delete on public.crm_tags for delete to authenticated using(private.crm_can(organization_id,null,'write_crm'));
create policy crm_contact_tags_read on public.crm_contact_tags for select to authenticated using(private.crm_contact_allowed(organization_id,contact_id,'read_crm'));
create policy crm_contact_tags_insert on public.crm_contact_tags for insert to authenticated with check(private.crm_contact_allowed(organization_id,contact_id,'write_crm') and created_by=auth.uid());
create policy crm_contact_tags_delete on public.crm_contact_tags for delete to authenticated using(private.crm_contact_allowed(organization_id,contact_id,'write_crm'));

do $$ declare t text; begin
  foreach t in array array['crm_pipelines','crm_pipeline_stages','crm_opportunities','crm_notes','crm_activities','crm_tasks','crm_appointments'] loop
    execute format('create policy %I_read on public.%I for select to authenticated using(private.crm_can(organization_id,unit_id,''read_crm''))',t,t);
    execute format('create policy %I_insert on public.%I for insert to authenticated with check(private.crm_can(organization_id,unit_id,''write_crm''))',t,t);
    execute format('create policy %I_update on public.%I for update to authenticated using(private.crm_can(organization_id,unit_id,''write_crm'')) with check(private.crm_can(organization_id,unit_id,''write_crm''))',t,t);
  end loop;
end $$;
create policy crm_stage_history_read on public.crm_opportunity_stage_history for select to authenticated using(private.crm_can(organization_id,unit_id,'read_crm'));
create policy crm_appointment_events_read on public.crm_appointment_events for select to authenticated using(private.crm_can(organization_id,unit_id,'read_crm'));

grant select,update(display_name,city,updated_at) on public.crm_contacts to authenticated;
grant select on public.crm_contact_identifiers,public.crm_contact_units,public.crm_opportunity_stage_history,public.crm_appointment_events to authenticated;
grant select,insert on public.crm_consents to authenticated;
grant select,insert,update,delete on public.crm_tags,public.crm_contact_tags to authenticated;
grant select,insert,update on public.crm_pipelines,public.crm_pipeline_stages,public.crm_opportunities,public.crm_notes,public.crm_activities,public.crm_tasks,public.crm_appointments to authenticated;

-- Safe aggregate for marketing operators: attribution without contact identifiers or message bodies.
create function public.crm_attribution_summary(p_organization_id uuid,p_unit_id uuid)
returns table(source text,campaign text,open_count bigint,won_count bigint,lost_count bigint)
language plpgsql stable security definer set search_path='' as $$
begin
  if not private.crm_can(p_organization_id,p_unit_id,'attribution') and not private.crm_can(p_organization_id,p_unit_id,'read_crm') then
    raise exception 'Forbidden' using errcode='42501'; end if;
  return query select coalesce(o.source,'Não informado'),coalesce(o.campaign,'Não informada'),
    count(*) filter(where o.status='open'),count(*) filter(where o.status='won'),count(*) filter(where o.status='lost')
    from public.crm_opportunities o where o.organization_id=p_organization_id and o.unit_id=p_unit_id
    group by o.source,o.campaign order by count(*) desc;
end $$;
revoke all on function public.crm_attribution_summary(uuid,uuid) from public,anon;
grant execute on function public.crm_attribution_summary(uuid,uuid) to authenticated;

-- Fonte: 20260916001000_inbox_worker.sql
-- SHA256 (UTF-8, LF): 5487a12f79e7dc7f819e52507034442c5a69671fffb36cea9ba05a2700740bd2
-- Phase 3B: unified inbox, channel vault references, transactional handoff and durable worker outbox.

create extension if not exists supabase_vault with schema vault;
create type public.messaging_provider as enum ('whatsapp','instagram','tiktok');
create type public.channel_connection_status as enum ('unconfigured','connecting','active','paused','degraded','revoked');
create type public.conversation_state as enum ('ai_active','waiting_human','human_active','paused','closed');
create type public.message_direction as enum ('inbound','outbound');
create type public.message_author_kind as enum ('contact','human','ai','system');
create type public.message_delivery_state as enum ('pending','accepted','sent','delivered','read','failed');

create table public.channel_connections (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  provider public.messaging_provider not null,
  name text not null check(length(btrim(name)) between 2 and 100),
  status public.channel_connection_status not null default 'unconfigured',
  base_url text,
  external_instance text,
  capabilities jsonb not null default '{}',
  health jsonb not null default '{}',
  secret_id uuid,
  webhook_secret_id uuid,
  webhook_token_hash text not null check(webhook_token_hash ~ '^[a-f0-9]{64}$'),
  last_synced_at timestamptz,
  last_error_code text,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,unit_id,id),
  unique(organization_id,unit_id,provider,name),
  unique(webhook_token_hash),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  check(base_url is null or base_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$' or base_url ~ '^http://(127[.]0[.]0[.]1|localhost)(:[0-9]+)?/?$'),
  check(last_error_code is null or length(last_error_code)<=120)
);

create table public.conversation_queues (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  name text not null check(length(btrim(name)) between 2 and 80),
  priority integer not null default 100 check(priority between 0 and 1000),
  sla_first_response_seconds integer not null default 900 check(sla_first_response_seconds between 30 and 86400),
  active boolean not null default true,
  unique(organization_id,unit_id,id),
  unique(organization_id,unit_id,name),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.queue_members (
  organization_id uuid not null,
  unit_id uuid not null,
  queue_id uuid not null,
  user_id uuid not null references auth.users(id),
  active boolean not null default true,
  capacity integer not null default 10 check(capacity between 1 and 100),
  primary key(organization_id,queue_id,user_id),
  foreign key(organization_id,unit_id,queue_id) references public.conversation_queues(organization_id,unit_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.conversations (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  channel_connection_id uuid not null,
  contact_id uuid not null,
  queue_id uuid,
  assigned_to uuid references auth.users(id),
  state public.conversation_state not null default 'ai_active',
  priority integer not null default 100 check(priority between 0 and 1000),
  external_thread_id text not null check(length(external_thread_id) between 1 and 320),
  subject text,
  unread_count integer not null default 0 check(unread_count>=0),
  first_response_due_at timestamptz,
  assignment_lease_until timestamptz,
  last_message_at timestamptz not null default now(),
  closed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(organization_id,unit_id,id),
  unique(channel_connection_id,external_thread_id),
  foreign key(organization_id,unit_id,channel_connection_id) references public.channel_connections(organization_id,unit_id,id),
  foreign key(organization_id,contact_id,unit_id) references public.crm_contact_units(organization_id,contact_id,unit_id),
  foreign key(organization_id,unit_id,queue_id) references public.conversation_queues(organization_id,unit_id,id)
);

create table public.conversation_participants (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  conversation_id uuid not null,
  contact_id uuid,
  user_id uuid references auth.users(id),
  external_address text,
  participant_kind text not null check(participant_kind in ('contact','agent','bot','system')),
  created_at timestamptz not null default now(),
  foreign key(organization_id,unit_id,conversation_id) references public.conversations(organization_id,unit_id,id),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  check(num_nonnulls(contact_id,user_id,external_address)=1)
);

create table public.messages (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  conversation_id uuid not null,
  channel_connection_id uuid not null,
  direction public.message_direction not null,
  author_kind public.message_author_kind not null,
  author_user_id uuid references auth.users(id),
  provider public.messaging_provider not null,
  external_message_id text,
  idempotency_key text not null check(length(idempotency_key) between 16 and 160),
  body text check(body is null or length(body)<=20000),
  delivery_state public.message_delivery_state not null default 'pending',
  reply_to_message_id uuid,
  provider_at timestamptz,
  created_at timestamptz not null default now(),
  unique(organization_id,unit_id,id),
  unique(channel_connection_id,external_message_id),
  unique(organization_id,idempotency_key),
  foreign key(organization_id,unit_id,conversation_id) references public.conversations(organization_id,unit_id,id),
  foreign key(organization_id,unit_id,channel_connection_id) references public.channel_connections(organization_id,unit_id,id),
  foreign key(organization_id,unit_id,reply_to_message_id) references public.messages(organization_id,unit_id,id),
  check((author_kind='human' and author_user_id is not null) or (author_kind<>'human' and author_user_id is null)),
  check(body is not null)
);

create table public.message_attachments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  message_id uuid not null,
  storage_path text not null unique,
  filename text not null check(length(filename) between 1 and 255),
  mime_type text not null check(mime_type in ('image/jpeg','image/png','image/webp','audio/ogg','audio/mpeg','application/pdf')),
  byte_size bigint not null check(byte_size between 1 and 15728640),
  sha256 text not null check(sha256 ~ '^[a-f0-9]{64}$'),
  created_at timestamptz not null default now(),
  foreign key(organization_id,unit_id,message_id) references public.messages(organization_id,unit_id,id)
);

create table public.message_delivery_events (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  message_id uuid not null,
  state public.message_delivery_state not null,
  provider_event_id text,
  provider_at timestamptz,
  error_code text,
  created_at timestamptz not null default now(),
  unique(organization_id,message_id,provider_event_id),
  foreign key(organization_id,unit_id,message_id) references public.messages(organization_id,unit_id,id)
);

create table public.conversation_assignment_history (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  conversation_id uuid not null,
  from_user_id uuid references auth.users(id),
  to_user_id uuid references auth.users(id),
  from_state public.conversation_state not null,
  to_state public.conversation_state not null,
  actor_id uuid not null references auth.users(id),
  reason text not null check(length(btrim(reason)) between 2 and 500),
  created_at timestamptz not null default now(),
  foreign key(organization_id,unit_id,conversation_id) references public.conversations(organization_id,unit_id,id)
);

create table private.webhook_receipts (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  channel_connection_id uuid not null,
  external_event_id text not null,
  payload_sha256 text not null check(payload_sha256 ~ '^[a-f0-9]{64}$'),
  provider_at timestamptz not null,
  correlation_id uuid not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  unique(channel_connection_id,external_event_id),
  foreign key(organization_id,unit_id,channel_connection_id) references public.channel_connections(organization_id,unit_id,id)
);

alter table private.outbox
  add column payload jsonb not null default '{}',
  add column correlation_id uuid not null default gen_random_uuid(),
  add column locked_by text,
  add column locked_until timestamptz,
  add column last_error_code text,
  add column failed_at timestamptz;
create index outbox_claim_idx on private.outbox(available_at,id) where completed_at is null and failed_at is null;

create index conversations_queue_idx on public.conversations(organization_id,unit_id,state,priority,last_message_at desc);
create index messages_timeline_idx on public.messages(organization_id,unit_id,conversation_id,created_at,id);
create index assignment_history_conversation_idx on public.conversation_assignment_history(organization_id,unit_id,conversation_id,created_at);
create index webhook_receipts_time_idx on private.webhook_receipts(received_at);

create function public.configure_evolution_channel(
  p_actor_id uuid,p_organization_id uuid,p_unit_id uuid,p_name text,p_base_url text,p_instance text,
  p_api_key text,p_webhook_secret text,p_webhook_token_hash text
) returns uuid language plpgsql security definer set search_path='' as $$
declare connection uuid:=gen_random_uuid(); api_secret uuid; hook_secret uuid;
begin
  if not private.crm_can_actor(p_actor_id,p_organization_id,p_unit_id,'configure') then raise exception 'Forbidden' using errcode='42501'; end if;
  if length(p_api_key)<20 or length(p_webhook_secret)<32 or p_webhook_token_hash !~ '^[a-f0-9]{64}$' then raise exception 'Invalid secret material' using errcode='22023'; end if;
  if not (p_base_url ~ '^https://[A-Za-z0-9.-]+(:[0-9]+)?/?$' or p_base_url ~ '^http://(127[.]0[.]0[.]1|localhost)(:[0-9]+)?/?$') then raise exception 'Invalid provider URL' using errcode='22023'; end if;
  api_secret=vault.create_secret(p_api_key,'channel-api-'||connection::text,'Evolution API credential');
  hook_secret=vault.create_secret(p_webhook_secret,'channel-webhook-'||connection::text,'Webhook HMAC credential');
  insert into public.channel_connections(id,organization_id,unit_id,provider,name,status,base_url,external_instance,
    capabilities,secret_id,webhook_secret_id,webhook_token_hash,created_by)
  values(connection,p_organization_id,p_unit_id,'whatsapp',btrim(p_name),'connecting',rtrim(p_base_url,'/'),p_instance,
    '{"send_text":true,"receive_text":true,"delivery_events":true}'::jsonb,api_secret,hook_secret,p_webhook_token_hash,p_actor_id);
  insert into public.audit_events(organization_id,actor_id,action,entity_id) values(p_organization_id,p_actor_id,'channel:configured',connection);
  return connection;
end $$;
revoke all on function public.configure_evolution_channel(uuid,uuid,uuid,text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.configure_evolution_channel(uuid,uuid,uuid,text,text,text,text,text,text) to service_role;

create function public.revoke_channel(p_actor_id uuid,p_connection_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare c public.channel_connections%rowtype;
begin
  select * into c from public.channel_connections where id=p_connection_id for update;
  if c.id is null or not private.crm_can_actor(p_actor_id,c.organization_id,c.unit_id,'configure') then raise exception 'Forbidden' using errcode='42501'; end if;
  update public.channel_connections set status='revoked',secret_id=null,webhook_secret_id=null,updated_at=now() where id=c.id;
  delete from vault.secrets where id in (c.secret_id,c.webhook_secret_id);
  insert into public.audit_events(organization_id,actor_id,action,entity_id) values(c.organization_id,p_actor_id,'channel:revoked',c.id);
  return true;
end $$;
revoke all on function public.revoke_channel(uuid,uuid) from public,anon,authenticated;
grant execute on function public.revoke_channel(uuid,uuid) to service_role;

create function public.channel_runtime_secret(p_connection_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare c public.channel_connections%rowtype; api text; hook text;
begin
  select * into c from public.channel_connections where id=p_connection_id and status<>'revoked';
  if c.id is null then raise exception 'Not found' using errcode='P0002'; end if;
  select decrypted_secret into api from vault.decrypted_secrets where id=c.secret_id;
  select decrypted_secret into hook from vault.decrypted_secrets where id=c.webhook_secret_id;
  return jsonb_build_object('id',c.id,'organization_id',c.organization_id,'unit_id',c.unit_id,'provider',c.provider,
    'base_url',c.base_url,'external_instance',c.external_instance,'api_key',api,'webhook_secret',hook,'status',c.status);
end $$;
revoke all on function public.channel_runtime_secret(uuid) from public,anon,authenticated;
grant execute on function public.channel_runtime_secret(uuid) to service_role;

create function public.queue_webhook_event(
  p_connection_id uuid,p_external_event_id text,p_payload_sha256 text,p_provider_at timestamptz,p_payload jsonb,p_correlation_id uuid
) returns boolean language plpgsql security definer set search_path='' as $$
declare c public.channel_connections%rowtype; receipt uuid;
begin
  select * into c from public.channel_connections where id=p_connection_id and status in ('active','connecting','degraded');
  if c.id is null then raise exception 'Connection unavailable' using errcode='P0002'; end if;
  insert into private.webhook_receipts(organization_id,unit_id,channel_connection_id,external_event_id,payload_sha256,provider_at,correlation_id)
    values(c.organization_id,c.unit_id,c.id,p_external_event_id,p_payload_sha256,p_provider_at,p_correlation_id)
    on conflict(channel_connection_id,external_event_id) do nothing returning id into receipt;
  if receipt is null then return false; end if;
  insert into private.outbox(organization_id,unit_id,idempotency_key,event_type,entity_id,payload,correlation_id)
    values(c.organization_id,c.unit_id,'webhook:'||c.id::text||':'||p_external_event_id,'evolution.webhook',receipt,p_payload,p_correlation_id)
    on conflict(organization_id,idempotency_key) do nothing;
  return true;
end $$;
revoke all on function public.queue_webhook_event(uuid,text,text,timestamptz,jsonb,uuid) from public,anon,authenticated;
grant execute on function public.queue_webhook_event(uuid,text,text,timestamptz,jsonb,uuid) to service_role;

create function public.ingest_inbound_message(
  p_connection_id uuid,p_receipt_id uuid,p_external_message_id text,p_external_thread_id text,
  p_sender_e164 text,p_sender_name text,p_body text,p_provider_at timestamptz,p_idempotency_key text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.channel_connections%rowtype; contact uuid; conversation uuid; message uuid; created boolean:=false;
begin
  select * into c from public.channel_connections where id=p_connection_id and status in ('active','connecting','degraded') for share;
  if c.id is null or p_sender_e164 !~ '^[+][1-9][0-9]{7,14}$' or length(p_body) not between 1 and 20000 then raise exception 'Invalid inbound message' using errcode='22023'; end if;
  select id into message from public.messages where channel_connection_id=c.id and external_message_id=p_external_message_id;
  if message is not null then return jsonb_build_object('message_id',message,'created',false); end if;
  perform pg_advisory_xact_lock(hashtextextended(c.organization_id::text||p_sender_e164,0));
  select contact_id into contact from public.crm_contact_identifiers where organization_id=c.organization_id and kind='phone' and normalized_value=p_sender_e164;
  if contact is null then
    insert into public.crm_contacts(organization_id,display_name,source) values(c.organization_id,coalesce(nullif(btrim(p_sender_name),''),p_sender_e164),'whatsapp') returning id into contact;
    insert into public.crm_contact_identifiers(organization_id,contact_id,kind,normalized_value) values(c.organization_id,contact,'phone',p_sender_e164);
  end if;
  insert into public.crm_contact_units(organization_id,contact_id,unit_id) values(c.organization_id,contact,c.unit_id)
    on conflict(organization_id,contact_id,unit_id) do update set last_seen_at=now();
  select id into conversation from public.conversations where channel_connection_id=c.id and external_thread_id=p_external_thread_id;
  if conversation is null then
    insert into public.conversations(organization_id,unit_id,channel_connection_id,contact_id,external_thread_id,state,unread_count,last_message_at)
      values(c.organization_id,c.unit_id,c.id,contact,p_external_thread_id,'ai_active',0,p_provider_at) returning id into conversation;
  end if;
  insert into public.messages(organization_id,unit_id,conversation_id,channel_connection_id,direction,author_kind,provider,
    external_message_id,idempotency_key,body,delivery_state,provider_at)
    values(c.organization_id,c.unit_id,conversation,c.id,'inbound','contact',c.provider,p_external_message_id,p_idempotency_key,p_body,'delivered',p_provider_at)
    on conflict(channel_connection_id,external_message_id) do nothing returning id into message;
  if message is not null then
    created=true;
    update public.conversations set unread_count=unread_count+1,last_message_at=greatest(last_message_at,p_provider_at),updated_at=now() where id=conversation;
    insert into public.message_delivery_events(organization_id,unit_id,message_id,state,provider_event_id,provider_at)
      values(c.organization_id,c.unit_id,message,'delivered','inbound:'||p_external_message_id,p_provider_at);
  else select id into message from public.messages where channel_connection_id=c.id and external_message_id=p_external_message_id;
  end if;
  update private.webhook_receipts set processed_at=coalesce(processed_at,now()) where id=p_receipt_id and channel_connection_id=c.id;
  return jsonb_build_object('conversation_id',conversation,'message_id',message,'created',created);
end $$;
revoke all on function public.ingest_inbound_message(uuid,uuid,text,text,text,text,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.ingest_inbound_message(uuid,uuid,text,text,text,text,text,timestamptz,text) to service_role;

create function public.record_delivery_event(p_message_id uuid,p_state public.message_delivery_state,p_provider_event_id text,p_provider_at timestamptz,p_error_code text)
returns boolean language plpgsql security definer set search_path='' as $$
declare m public.messages%rowtype;
begin
  select * into m from public.messages where id=p_message_id;
  if m.id is null then raise exception 'Not found' using errcode='P0002'; end if;
  insert into public.message_delivery_events(organization_id,unit_id,message_id,state,provider_event_id,provider_at,error_code)
    values(m.organization_id,m.unit_id,m.id,p_state,p_provider_event_id,p_provider_at,left(p_error_code,120)) on conflict do nothing;
  return true;
end $$;
revoke all on function public.record_delivery_event(uuid,public.message_delivery_state,text,timestamptz,text) from public,anon,authenticated;
grant execute on function public.record_delivery_event(uuid,public.message_delivery_state,text,timestamptz,text) to service_role;

create function public.takeover_conversation(p_organization_id uuid,p_unit_id uuid,p_conversation_id uuid,p_reason text,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype; prior public.conversation_state; cached jsonb; result jsonb;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'inbox') then raise exception 'Forbidden' using errcode='42501'; end if;
  select response into cached from private.crm_idempotency where organization_id=p_organization_id and operation='conversation.takeover' and idempotency_key=p_idempotency_key;
  if cached is not null then return cached; end if;
  select * into c from public.conversations where organization_id=p_organization_id and unit_id=p_unit_id and id=p_conversation_id for update;
  if c.id is null then raise exception 'Not found' using errcode='P0002'; end if;
  if c.state='human_active' and c.assigned_to<>auth.uid() and c.assignment_lease_until>now() then raise exception 'Conversation already owned' using errcode='55P03'; end if;
  prior=c.state;
  update public.conversations set state='human_active',assigned_to=auth.uid(),assignment_lease_until=now()+interval '15 minutes',updated_at=now() where id=c.id;
  insert into public.conversation_assignment_history(organization_id,unit_id,conversation_id,from_user_id,to_user_id,from_state,to_state,actor_id,reason)
    values(p_organization_id,p_unit_id,c.id,c.assigned_to,auth.uid(),prior,'human_active',auth.uid(),btrim(p_reason));
  result=jsonb_build_object('id',c.id,'state','human_active','assigned_to',auth.uid());
  insert into private.crm_idempotency values(p_organization_id,'conversation.takeover',p_idempotency_key,result,now()) on conflict do nothing;
  return result;
end $$;
revoke all on function public.takeover_conversation(uuid,uuid,uuid,text,text) from public,anon;
grant execute on function public.takeover_conversation(uuid,uuid,uuid,text,text) to authenticated;

create function public.return_conversation_to_ai(p_organization_id uuid,p_unit_id uuid,p_conversation_id uuid,p_reason text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'inbox') then raise exception 'Forbidden' using errcode='42501'; end if;
  select * into c from public.conversations where organization_id=p_organization_id and unit_id=p_unit_id and id=p_conversation_id for update;
  if c.id is null or c.state<>'human_active' or (c.assigned_to<>auth.uid() and not private.crm_can(p_organization_id,p_unit_id,'configure')) then raise exception 'Forbidden' using errcode='42501'; end if;
  update public.conversations set state='ai_active',assigned_to=null,assignment_lease_until=null,updated_at=now() where id=c.id;
  insert into public.conversation_assignment_history(organization_id,unit_id,conversation_id,from_user_id,to_user_id,from_state,to_state,actor_id,reason)
    values(p_organization_id,p_unit_id,c.id,c.assigned_to,null,'human_active','ai_active',auth.uid(),btrim(p_reason));
  return jsonb_build_object('id',c.id,'state','ai_active');
end $$;
revoke all on function public.return_conversation_to_ai(uuid,uuid,uuid,text) from public,anon;
grant execute on function public.return_conversation_to_ai(uuid,uuid,uuid,text) to authenticated;

create function public.queue_human_message(p_organization_id uuid,p_unit_id uuid,p_conversation_id uuid,p_body text,p_reply_to uuid,p_idempotency_key text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype; m uuid; cached jsonb; result jsonb;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'inbox') then raise exception 'Forbidden' using errcode='42501'; end if;
  select response into cached from private.crm_idempotency where organization_id=p_organization_id and operation='message.send' and idempotency_key=p_idempotency_key;
  if cached is not null then return cached; end if;
  select * into c from public.conversations where organization_id=p_organization_id and unit_id=p_unit_id and id=p_conversation_id for update;
  if c.id is null or c.state<>'human_active' or c.assigned_to<>auth.uid() or c.assignment_lease_until<now() then raise exception 'Takeover required' using errcode='42501'; end if;
  insert into public.messages(organization_id,unit_id,conversation_id,channel_connection_id,direction,author_kind,author_user_id,provider,idempotency_key,body,reply_to_message_id)
    select p_organization_id,p_unit_id,c.id,c.channel_connection_id,'outbound','human',auth.uid(),cc.provider,p_idempotency_key,btrim(p_body),p_reply_to
    from public.channel_connections cc where cc.id=c.channel_connection_id returning id into m;
  insert into private.outbox(organization_id,unit_id,idempotency_key,event_type,entity_id,payload)
    values(p_organization_id,p_unit_id,'send:'||p_idempotency_key,'message.send',m,jsonb_build_object('message_id',m));
  result=jsonb_build_object('id',m,'delivery_state','pending');
  insert into private.crm_idempotency values(p_organization_id,'message.send',p_idempotency_key,result,now());
  return result;
end $$;
revoke all on function public.queue_human_message(uuid,uuid,uuid,text,uuid,text) from public,anon;
grant execute on function public.queue_human_message(uuid,uuid,uuid,text,uuid,text) to authenticated;

create function public.claim_outbox(p_worker_id text,p_limit integer,p_lease_seconds integer)
returns table(id uuid,organization_id uuid,unit_id uuid,event_type text,entity_id uuid,payload jsonb,attempts integer,correlation_id uuid)
language sql security definer set search_path='' as $$
  with selected as (
    select o.id from private.outbox o where o.completed_at is null and o.failed_at is null and o.available_at<=now()
      and (o.locked_until is null or o.locked_until<now()) order by o.available_at,o.id for update skip locked limit least(greatest(p_limit,1),50)
  ), claimed as (
    update private.outbox o set locked_by=p_worker_id,locked_until=now()+make_interval(secs=>least(greatest(p_lease_seconds,10),300)),attempts=o.attempts+1
    from selected s where o.id=s.id returning o.*
  ) select c.id,c.organization_id,c.unit_id,c.event_type,c.entity_id,c.payload,c.attempts,c.correlation_id from claimed c;
$$;
create function public.complete_outbox(p_id uuid,p_worker_id text) returns boolean language sql security definer set search_path='' as $$
  with changed as (update private.outbox set completed_at=now(),locked_by=null,locked_until=null where id=p_id and locked_by=p_worker_id and completed_at is null returning 1)
  select exists(select 1 from changed);
$$;
create function public.retry_outbox(p_id uuid,p_worker_id text,p_error_code text) returns boolean language sql security definer set search_path='' as $$
  with changed as (
    update private.outbox set locked_by=null,locked_until=null,last_error_code=left(p_error_code,120),
      failed_at=case when attempts>=10 then now() else null end,
      available_at=case when attempts>=10 then available_at else now()+make_interval(secs=>(least(3600,power(2,least(attempts,10))::integer)+floor(random()*10)::integer)) end
    where id=p_id and locked_by=p_worker_id and completed_at is null returning 1
  ) select exists(select 1 from changed);
$$;
revoke all on function public.claim_outbox(text,integer,integer),public.complete_outbox(uuid,text),public.retry_outbox(uuid,text,text) from public,anon,authenticated;
grant execute on function public.claim_outbox(text,integer,integer),public.complete_outbox(uuid,text),public.retry_outbox(uuid,text,text) to service_role;

-- The immutable-message trigger permits only this transaction-scoped LGPD
-- anonymization path. It must exist before the trigger function is compiled.
create table private.anonymization_context (
  transaction_id bigint primary key,
  request_id uuid not null,
  created_at timestamptz not null default now()
);
revoke all on private.anonymization_context from public,anon,authenticated,service_role;

create function private.immutable_message() returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='UPDATE' and exists(select 1 from private.anonymization_context where transaction_id=txid_current())
    and new.body='[conteúdo anonimizado]' and (to_jsonb(new)-'body')=(to_jsonb(old)-'body') then return new; end if;
  raise exception 'Messages are immutable; append a delivery event' using errcode='23514';
end $$;
revoke all on function private.immutable_message() from public,anon,authenticated;
create trigger messages_immutable before update or delete on public.messages for each row execute function private.immutable_message();
create trigger delivery_events_append_only before update or delete on public.message_delivery_events for each row execute function private.append_only_crm();
create trigger assignment_history_append_only before update or delete on public.conversation_assignment_history for each row execute function private.append_only_crm();

do $$ declare t text; begin foreach t in array array[
  'channel_connections','conversation_queues','queue_members','conversations','conversation_participants','messages',
  'message_attachments','message_delivery_events','conversation_assignment_history'
] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon,authenticated',t); end loop; end $$;
alter table private.webhook_receipts enable row level security;
revoke all on private.webhook_receipts from public,anon,authenticated;

-- Channel rows contain vault identifiers and opaque hashes, so browsers never receive table access.
create policy queues_read on public.conversation_queues for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy queues_write on public.conversation_queues for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure'));
create policy queue_members_read on public.queue_members for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy queue_members_write on public.queue_members for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure'));
create policy conversations_read on public.conversations for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy participants_read on public.conversation_participants for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy messages_read on public.messages for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy attachments_read on public.message_attachments for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy delivery_events_read on public.message_delivery_events for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
create policy assignment_history_read on public.conversation_assignment_history for select to authenticated using(private.crm_can(organization_id,unit_id,'inbox'));
grant select,insert,update on public.conversation_queues,public.queue_members to authenticated;
grant select on public.conversations,public.conversation_participants,public.messages,public.message_attachments,public.message_delivery_events,public.conversation_assignment_history to authenticated;

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values(
  'crm-private','crm-private',false,15728640,array['image/jpeg','image/png','image/webp','audio/ogg','audio/mpeg','application/pdf']
) on conflict(id) do update set public=false,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;

-- Fonte: 20260916002000_ai_privacy.sql
-- SHA256 (UTF-8, LF): 645be4410a8c7f6f9723e9c68fc94b90a9d02cf580e6fd4f76d4194759b984ab
-- Phase 3C: governed assistant, approved knowledge, usage controls and LGPD workflows.

create type public.knowledge_status as enum ('draft','approved','expired','revoked');
create type public.indexing_status as enum ('pending','processing','ready','failed');
create type public.ai_run_status as enum ('started','completed','blocked','failed','transferred');

create table public.ai_assistant_configs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  assistant_name text not null default 'Assistente' check(length(assistant_name) between 2 and 80),
  enabled boolean not null default false,
  tone text not null default 'acolhedor e objetivo' check(length(tone) between 2 and 500),
  business_hours jsonb not null default '{}',
  objectives jsonb not null default '[]',
  qualification_questions jsonb not null default '[]',
  welcome_messages jsonb not null default '[]',
  commercial_rules jsonb not null default '[]',
  transfer_triggers jsonb not null default '[]',
  queue_id uuid,
  max_messages_per_conversation integer not null default 30 check(max_messages_per_conversation between 1 and 200),
  daily_budget_cents integer not null default 1000 check(daily_budget_cents between 0 and 10000000),
  monthly_budget_cents integer not null default 20000 check(monthly_budget_cents between 0 and 100000000),
  circuit_open_until timestamptz,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  unique(organization_id,unit_id),
  unique(organization_id,unit_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,unit_id,queue_id) references public.conversation_queues(organization_id,unit_id,id)
);

create table public.knowledge_sources (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  unit_id uuid,
  source_kind text not null check(source_kind in ('academy_facts','document','manual','url_import')),
  name text not null check(length(btrim(name)) between 2 and 160),
  origin text check(origin is null or length(origin)<=500),
  status public.knowledge_status not null default 'draft',
  valid_from timestamptz,
  valid_until timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  check(valid_until is null or valid_from is null or valid_until>valid_from)
);

create table public.knowledge_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid,
  source_id uuid not null,
  title text not null check(length(btrim(title)) between 2 and 200),
  current_version integer not null default 0 check(current_version>=0),
  created_at timestamptz not null default now(),
  unique(organization_id,id),
  foreign key(organization_id,source_id) references public.knowledge_sources(organization_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.knowledge_document_versions (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid,
  document_id uuid not null,
  version integer not null check(version>0),
  storage_path text,
  content_sha256 text not null check(content_sha256 ~ '^[a-f0-9]{64}$'),
  status public.knowledge_status not null default 'draft',
  indexing_status public.indexing_status not null default 'pending',
  valid_from timestamptz,
  valid_until timestamptz,
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  unique(organization_id,document_id,version),
  unique(organization_id,id),
  foreign key(organization_id,document_id) references public.knowledge_documents(organization_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  check((status='approved')=(approved_at is not null and approved_by is not null)),
  check(valid_until is null or valid_from is null or valid_until>valid_from)
);

create table public.knowledge_chunks (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid,
  version_id uuid not null,
  position integer not null check(position>=0),
  content text not null check(length(content) between 1 and 8000),
  lexical tsvector generated always as (to_tsvector('portuguese'::regconfig,content)) stored,
  created_at timestamptz not null default now(),
  unique(organization_id,version_id,position),
  foreign key(organization_id,version_id) references public.knowledge_document_versions(organization_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.ai_runs (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  conversation_id uuid,
  provider text not null check(length(provider) between 2 and 80),
  model text not null check(length(model) between 1 and 120),
  status public.ai_run_status not null default 'started',
  input_tokens integer not null default 0 check(input_tokens>=0),
  output_tokens integer not null default 0 check(output_tokens>=0),
  estimated_cost_cents integer not null default 0 check(estimated_cost_cents>=0),
  latency_ms integer check(latency_ms is null or latency_ms>=0),
  sources_used jsonb not null default '[]',
  result_code text,
  error_code text,
  transfer_reason text,
  correlation_id uuid not null default gen_random_uuid(),
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  unique(organization_id,unit_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,unit_id,conversation_id) references public.conversations(organization_id,unit_id,id),
  check(result_code is null or length(result_code)<=120),
  check(error_code is null or length(error_code)<=120),
  check(transfer_reason is null or length(transfer_reason)<=500)
);

create table public.ai_tool_calls (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  unit_id uuid not null,
  ai_run_id uuid not null,
  tool_name text not null check(tool_name in ('contact.upsert','opportunity.upsert','task.create','appointment.create','handoff.request')),
  arguments_sha256 text not null check(arguments_sha256 ~ '^[a-f0-9]{64}$'),
  status text not null check(status in ('requested','authorized','completed','rejected','failed')),
  result_code text,
  created_at timestamptz not null default now(),
  foreign key(organization_id,unit_id) references public.units(organization_id,id),
  foreign key(organization_id,unit_id,ai_run_id) references public.ai_runs(organization_id,unit_id,id)
);

create table public.ai_usage_daily (
  organization_id uuid not null,
  unit_id uuid not null,
  usage_date date not null,
  run_count integer not null default 0 check(run_count>=0),
  input_tokens bigint not null default 0 check(input_tokens>=0),
  output_tokens bigint not null default 0 check(output_tokens>=0),
  estimated_cost_cents bigint not null default 0 check(estimated_cost_cents>=0),
  primary key(organization_id,unit_id,usage_date),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.privacy_requests (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  unit_id uuid,
  contact_id uuid not null,
  request_kind text not null check(request_kind in ('export','anonymize','correct','restrict')),
  status text not null default 'requested' check(status in ('requested','verified','processing','completed','rejected')),
  requested_at timestamptz not null default now(),
  verified_at timestamptz,
  completed_at timestamptz,
  handled_by uuid references auth.users(id),
  notes text check(notes is null or length(notes)<=2000),
  foreign key(organization_id,contact_id) references public.crm_contacts(organization_id,id),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create table public.data_retention_policies (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id),
  unit_id uuid,
  data_class text not null check(data_class in ('contact','conversation','attachment','ai_run','webhook_receipt')),
  retention_days integer not null check(retention_days between 30 and 3650),
  active boolean not null default true,
  updated_by uuid not null references auth.users(id),
  updated_at timestamptz not null default now(),
  unique nulls not distinct(organization_id,unit_id,data_class),
  foreign key(organization_id,unit_id) references public.units(organization_id,id)
);

create index knowledge_chunks_lexical_idx on public.knowledge_chunks using gin(lexical);
create index knowledge_versions_current_idx on public.knowledge_document_versions(organization_id,unit_id,status,valid_until);
create index ai_runs_usage_idx on public.ai_runs(organization_id,unit_id,started_at);
create index privacy_requests_status_idx on public.privacy_requests(organization_id,status,requested_at);

create function public.ingest_knowledge_document(
  p_actor_id uuid,p_organization_id uuid,p_unit_id uuid,p_source_id uuid,p_title text,p_content_sha256 text,p_chunks jsonb
) returns jsonb language plpgsql security definer set search_path='' as $$
declare source public.knowledge_sources%rowtype; document uuid; version uuid; invalid_chunks integer;
begin
  if not private.crm_can_actor(p_actor_id,p_organization_id,p_unit_id,'configure') then raise exception 'Forbidden' using errcode='42501'; end if;
  select * into source from public.knowledge_sources where organization_id=p_organization_id and id=p_source_id
    and (unit_id is null or unit_id=p_unit_id) for update;
  if source.id is null then raise exception 'Source not found' using errcode='P0002'; end if;
  if length(btrim(p_title)) not between 2 and 200 or p_content_sha256 !~ '^[a-f0-9]{64}$'
    or jsonb_typeof(p_chunks)<>'array' or jsonb_array_length(p_chunks) not between 1 and 250
  then raise exception 'Invalid document' using errcode='22023'; end if;
  select count(*) into invalid_chunks from jsonb_array_elements_text(p_chunks) as part(content) where length(part.content) not between 1 and 8000;
  if invalid_chunks>0 then raise exception 'Invalid chunks' using errcode='22023'; end if;
  insert into public.knowledge_documents(organization_id,unit_id,source_id,title,current_version)
    values(p_organization_id,source.unit_id,source.id,btrim(p_title),1) returning id into document;
  insert into public.knowledge_document_versions(organization_id,unit_id,document_id,version,content_sha256,status,indexing_status,created_by)
    values(p_organization_id,source.unit_id,document,1,p_content_sha256,'draft','ready',p_actor_id) returning id into version;
  insert into public.knowledge_chunks(organization_id,unit_id,version_id,position,content)
    select p_organization_id,source.unit_id,version,part.ordinality-1,part.content
    from jsonb_array_elements_text(p_chunks) with ordinality as part(content,ordinality);
  return jsonb_build_object('document_id',document,'version_id',version,'chunks',jsonb_array_length(p_chunks),'indexing_status','ready');
end $$;
revoke all on function public.ingest_knowledge_document(uuid,uuid,uuid,uuid,text,text,jsonb) from public,anon,authenticated;
grant execute on function public.ingest_knowledge_document(uuid,uuid,uuid,uuid,text,text,jsonb) to service_role;

create function public.approve_knowledge_version(
  p_organization_id uuid,p_unit_id uuid,p_source_id uuid,p_version_id uuid,p_valid_until timestamptz
) returns jsonb language plpgsql security definer set search_path='' as $$
declare source public.knowledge_sources%rowtype; version public.knowledge_document_versions%rowtype;
begin
  if not private.crm_can(p_organization_id,p_unit_id,'configure') then raise exception 'Forbidden' using errcode='42501'; end if;
  select s.* into source from public.knowledge_sources s where s.organization_id=p_organization_id and s.id=p_source_id
    and (s.unit_id is null or s.unit_id=p_unit_id) for update;
  select v.* into version from public.knowledge_document_versions v join public.knowledge_documents d
    on d.organization_id=v.organization_id and d.id=v.document_id
    where v.organization_id=p_organization_id and v.id=p_version_id and d.source_id=p_source_id
      and (v.unit_id is null or v.unit_id=p_unit_id) for update of v;
  if source.id is null or version.id is null then raise exception 'Knowledge not found' using errcode='P0002'; end if;
  if version.indexing_status<>'ready' then raise exception 'Version is not indexed' using errcode='55000'; end if;
  update public.knowledge_sources set status='approved',valid_from=coalesce(valid_from,now()),valid_until=p_valid_until where id=source.id;
  update public.knowledge_document_versions set status='approved',valid_from=coalesce(valid_from,now()),valid_until=p_valid_until,
    approved_by=auth.uid(),approved_at=now() where id=version.id;
  return jsonb_build_object('source_id',source.id,'version_id',version.id,'status','approved');
end $$;
revoke all on function public.approve_knowledge_version(uuid,uuid,uuid,uuid,timestamptz) from public,anon;
grant execute on function public.approve_knowledge_version(uuid,uuid,uuid,uuid,timestamptz) to authenticated;

create function private.guard_automated_message()
returns trigger language plpgsql security definer set search_path='' as $$
declare c public.conversations%rowtype; v_channel text;
begin
  if new.author_kind<>'ai' then return new; end if;
  select * into c from public.conversations where id=new.conversation_id for share;
  if c.id is null or c.state<>'ai_active' then raise exception 'AI is not active for this conversation' using errcode='42501'; end if;
  v_channel=case when new.provider='whatsapp' then 'whatsapp' else new.provider::text end;
  if not exists(
    select 1 from public.crm_consents cs where cs.organization_id=new.organization_id and cs.contact_id=c.contact_id
      and cs.channel in (v_channel,'all') and cs.granted_at is not null and cs.revoked_at is null
      and (cs.valid_until is null or cs.valid_until>now())
      and not exists(select 1 from public.crm_consents revoked where revoked.organization_id=cs.organization_id and revoked.contact_id=cs.contact_id
        and revoked.channel in (v_channel,'all') and revoked.revoked_at is not null and revoked.created_at>cs.created_at)
  ) then raise exception 'Automated messaging requires valid consent' using errcode='42501'; end if;
  return new;
end $$;
revoke all on function private.guard_automated_message() from public,anon,authenticated;
create trigger guard_automated_message before insert on public.messages for each row execute function private.guard_automated_message();

create function private.enforce_ai_budget()
returns trigger language plpgsql security definer set search_path='' as $$
declare cfg public.ai_assistant_configs%rowtype; daily bigint; monthly bigint; count_runs bigint;
begin
  select * into cfg from public.ai_assistant_configs where organization_id=new.organization_id and unit_id=new.unit_id for share;
  if cfg.id is null or not cfg.enabled or (cfg.circuit_open_until is not null and cfg.circuit_open_until>now()) then
    raise exception 'Assistant unavailable' using errcode='42501'; end if;
  select coalesce(sum(estimated_cost_cents),0),count(*) into daily,count_runs from public.ai_runs
    where organization_id=new.organization_id and unit_id=new.unit_id and started_at>=date_trunc('day',now());
  select coalesce(sum(estimated_cost_cents),0) into monthly from public.ai_runs
    where organization_id=new.organization_id and unit_id=new.unit_id and started_at>=date_trunc('month',now());
  if daily>=cfg.daily_budget_cents or monthly>=cfg.monthly_budget_cents then raise exception 'Assistant budget reached' using errcode='54000'; end if;
  if new.conversation_id is not null and (select count(*) from public.ai_runs where conversation_id=new.conversation_id and started_at>=now()-interval '24 hours')>=cfg.max_messages_per_conversation then
    raise exception 'Assistant loop limit reached' using errcode='54000'; end if;
  return new;
end $$;
revoke all on function private.enforce_ai_budget() from public,anon,authenticated;
create trigger enforce_ai_budget before insert on public.ai_runs for each row execute function private.enforce_ai_budget();

create function private.aggregate_ai_usage() returns trigger language plpgsql security definer set search_path='' as $$
begin
  if old.status='started' and new.status<>'started' then
    insert into public.ai_usage_daily(organization_id,unit_id,usage_date,run_count,input_tokens,output_tokens,estimated_cost_cents)
      values(new.organization_id,new.unit_id,new.started_at::date,1,new.input_tokens,new.output_tokens,new.estimated_cost_cents)
    on conflict(organization_id,unit_id,usage_date) do update set
      run_count=ai_usage_daily.run_count+1,input_tokens=ai_usage_daily.input_tokens+excluded.input_tokens,
      output_tokens=ai_usage_daily.output_tokens+excluded.output_tokens,
      estimated_cost_cents=ai_usage_daily.estimated_cost_cents+excluded.estimated_cost_cents;
  end if;
  return new;
end $$;
revoke all on function private.aggregate_ai_usage() from public,anon,authenticated;
create trigger aggregate_ai_usage after update on public.ai_runs for each row execute function private.aggregate_ai_usage();

create function public.search_authorized_knowledge(p_organization_id uuid,p_unit_id uuid,p_query text,p_limit integer)
returns table(source_id uuid,version_id uuid,content text,rank real)
language sql stable security definer set search_path='' as $$
  select s.id,v.id,c.content,ts_rank(c.lexical,websearch_to_tsquery('portuguese'::regconfig,p_query))
  from public.knowledge_chunks c join public.knowledge_document_versions v on v.organization_id=c.organization_id and v.id=c.version_id
  join public.knowledge_documents d on d.organization_id=v.organization_id and d.id=v.document_id
  join public.knowledge_sources s on s.organization_id=d.organization_id and s.id=d.source_id
  where c.organization_id=p_organization_id and (c.unit_id is null or c.unit_id=p_unit_id)
    and v.status='approved' and v.indexing_status='ready' and s.status='approved'
    and (v.valid_from is null or v.valid_from<=now()) and (v.valid_until is null or v.valid_until>now())
    and (s.valid_from is null or s.valid_from<=now()) and (s.valid_until is null or s.valid_until>now())
    and c.lexical @@ websearch_to_tsquery('portuguese'::regconfig,p_query)
  order by 4 desc limit least(greatest(p_limit,1),12);
$$;
revoke all on function public.search_authorized_knowledge(uuid,uuid,text,integer) from public,anon,authenticated;
grant execute on function public.search_authorized_knowledge(uuid,uuid,text,integer) to service_role;

create function public.export_crm_contact(p_organization_id uuid,p_contact_id uuid)
returns jsonb language plpgsql stable security definer set search_path='' as $$
begin
  if not private.crm_contact_allowed(p_organization_id,p_contact_id,'read_crm') then raise exception 'Forbidden' using errcode='42501'; end if;
  return jsonb_build_object(
    'contact',(select to_jsonb(c) from public.crm_contacts c where c.organization_id=p_organization_id and c.id=p_contact_id),
    'identifiers',(select coalesce(jsonb_agg(to_jsonb(i)),'[]') from public.crm_contact_identifiers i where i.organization_id=p_organization_id and i.contact_id=p_contact_id),
    'consents',(select coalesce(jsonb_agg(to_jsonb(cs)),'[]') from public.crm_consents cs where cs.organization_id=p_organization_id and cs.contact_id=p_contact_id),
    'opportunities',(select coalesce(jsonb_agg(to_jsonb(o)),'[]') from public.crm_opportunities o where o.organization_id=p_organization_id and o.contact_id=p_contact_id),
    'appointments',(select coalesce(jsonb_agg(to_jsonb(a)),'[]') from public.crm_appointments a where a.organization_id=p_organization_id and a.contact_id=p_contact_id)
  );
end $$;
revoke all on function public.export_crm_contact(uuid,uuid) from public,anon;
grant execute on function public.export_crm_contact(uuid,uuid) to authenticated;

create function public.anonymize_crm_contact(p_actor_id uuid,p_organization_id uuid,p_contact_id uuid,p_request_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare req public.privacy_requests%rowtype;
begin
  select * into req from public.privacy_requests where id=p_request_id and organization_id=p_organization_id and contact_id=p_contact_id and request_kind='anonymize' and status='verified' for update;
  if req.id is null or not exists(select 1 from public.crm_contact_units cu where cu.organization_id=p_organization_id and cu.contact_id=p_contact_id and private.crm_can_actor(p_actor_id,p_organization_id,cu.unit_id,'configure')) then
    raise exception 'Forbidden' using errcode='42501'; end if;
  update public.crm_contacts set display_name='Contato anonimizado',city=null,source=null,anonymized_at=now(),updated_at=now() where organization_id=p_organization_id and id=p_contact_id;
  update public.crm_contact_identifiers set normalized_value='anon:'||id::text,verified_at=null where organization_id=p_organization_id and contact_id=p_contact_id;
  insert into private.anonymization_context(transaction_id,request_id) values(txid_current(),req.id);
  update public.messages set body='[conteúdo anonimizado]' where organization_id=p_organization_id and conversation_id in (select id from public.conversations where contact_id=p_contact_id);
  delete from private.anonymization_context where transaction_id=txid_current();
  update public.privacy_requests set status='completed',completed_at=now(),handled_by=p_actor_id where id=req.id;
  insert into public.audit_events(organization_id,actor_id,action,entity_id) values(p_organization_id,p_actor_id,'privacy:anonymized',p_contact_id);
  return true;
end $$;
revoke all on function public.anonymize_crm_contact(uuid,uuid,uuid,uuid) from public,anon,authenticated;
grant execute on function public.anonymize_crm_contact(uuid,uuid,uuid,uuid) to service_role;

create function private.append_only_ai() returns trigger language plpgsql set search_path='' as $$
begin raise exception 'AI history is append-only' using errcode='23514'; end $$;
revoke all on function private.append_only_ai() from public,anon,authenticated;
create trigger ai_tool_calls_append_only before update or delete on public.ai_tool_calls for each row execute function private.append_only_ai();
create trigger ai_usage_append_only before delete on public.ai_usage_daily for each row execute function private.append_only_ai();

do $$ declare t text; begin foreach t in array array[
  'ai_assistant_configs','knowledge_sources','knowledge_documents','knowledge_document_versions','knowledge_chunks',
  'ai_runs','ai_tool_calls','ai_usage_daily','privacy_requests','data_retention_policies'
] loop execute format('alter table public.%I enable row level security',t); execute format('revoke all on public.%I from anon,authenticated',t); end loop; end $$;

create policy assistant_config_read on public.ai_assistant_configs for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy assistant_config_write on public.ai_assistant_configs for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure') and updated_by=auth.uid());
create policy knowledge_sources_read on public.knowledge_sources for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy knowledge_sources_write on public.knowledge_sources for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure'));
create policy knowledge_documents_read on public.knowledge_documents for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy knowledge_documents_write on public.knowledge_documents for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure'));
create policy knowledge_versions_read on public.knowledge_document_versions for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy knowledge_versions_write on public.knowledge_document_versions for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure'));
create policy knowledge_chunks_read on public.knowledge_chunks for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy ai_runs_read on public.ai_runs for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy ai_tools_read on public.ai_tool_calls for select to authenticated using(private.crm_can(organization_id,unit_id,'read_ai'));
create policy ai_usage_read on public.ai_usage_daily for select to authenticated using(private.crm_can(organization_id,unit_id,'aggregate'));
create policy privacy_requests_all on public.privacy_requests for all to authenticated using(private.crm_contact_allowed(organization_id,contact_id,'read_crm')) with check(private.crm_contact_allowed(organization_id,contact_id,'configure'));
create policy retention_all on public.data_retention_policies for all to authenticated using(private.crm_can(organization_id,unit_id,'configure')) with check(private.crm_can(organization_id,unit_id,'configure'));

grant select,insert,update on public.ai_assistant_configs,public.knowledge_sources,public.knowledge_documents,public.knowledge_document_versions to authenticated;
grant select on public.knowledge_chunks,public.ai_runs,public.ai_tool_calls,public.ai_usage_daily to authenticated;
grant select,insert,update on public.privacy_requests,public.data_retention_policies to authenticated;

-- Private attachment access is tied to message metadata and current inbox authorization.
create function private.crm_object_allowed(object_name text)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.message_attachments a where a.storage_path=object_name and private.crm_can(a.organization_id,a.unit_id,'inbox'));
$$;
revoke all on function private.crm_object_allowed(text) from public,anon;
grant execute on function private.crm_object_allowed(text) to authenticated;
create policy crm_objects_read on storage.objects for select to authenticated using(bucket_id='crm-private' and private.crm_object_allowed(name));

notify pgrst, 'reload schema';
commit;
select 'Instalacao concluida. Execute 90_verificar.sql e configure o Auth conforme LEIA-ME.md.' as resultado;
