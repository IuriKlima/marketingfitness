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
