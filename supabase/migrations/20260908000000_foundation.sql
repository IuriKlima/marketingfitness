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
