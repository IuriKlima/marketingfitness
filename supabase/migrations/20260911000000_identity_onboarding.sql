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
