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

  foreach item in array array['organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events','organization_invitations','onboarding_field_definitions','onboarding_reviews','onboarding_attachments'] loop
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

notify pgrst, 'reload schema';
commit;
select 'Instalacao concluida. Execute 90_verificar.sql e configure o Auth conforme LEIA-ME.md.' as resultado;
