-- AcadeAI: atualizar uma instalacao aprovada da fase 2 para a fase 3.
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
    if to_regclass('public.' || item) is null then
      raise exception 'Fase 2 incompleta: public.% ausente. Corrija a fase anterior antes de continuar.',item;
    end if;
  end loop;
  if to_regtype('public.onboarding_scope') is null or to_regclass('private.platform_roles') is null then
    raise exception 'Fase 2 privada incompleta. Revise o schema antes de continuar.';
  end if;
  if to_regclass('public.crm_contacts') is not null or to_regclass('public.channel_connections') is not null or
    to_regclass('public.ai_assistant_configs') is not null or to_regtype('public.crm_identifier_kind') is not null then
    raise exception 'Fase 3 ja existe ou foi aplicada parcialmente. Nao reaplique este arquivo.';
  end if;
end
$preflight$;

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
