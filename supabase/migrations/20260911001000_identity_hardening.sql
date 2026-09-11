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
