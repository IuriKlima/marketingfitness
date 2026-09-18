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
