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
