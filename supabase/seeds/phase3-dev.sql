-- Optional, idempotent development seed. It refuses to run unless the caller
-- explicitly marks the transaction as local development:
--   begin; set local app.acadeai_seed = 'development'; \i supabase/seeds/phase3-dev.sql
-- Never include this file in a production migration or SQL Editor bundle.

do $$ begin
  if current_setting('app.acadeai_seed',true) is distinct from 'development' then
    raise exception 'Development seed disabled. Set app.acadeai_seed=development in this transaction.';
  end if;
end $$;

insert into public.organizations(id,name,status,plan) values
  ('d0000000-0000-4000-8000-000000000001','Academia Horizonte Fictícia','active','development')
on conflict(id) do update set name=excluded.name,status='active',plan='development';

insert into public.units(id,organization_id,name) values
  ('d1000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Unidade Centro Fictícia')
on conflict(id) do update set name=excluded.name;

insert into public.crm_contacts(id,organization_id,display_name,city,source) values
  ('d2000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','Marina Exemplo','São Paulo','site'),
  ('d2000000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','Rafael Teste','São Paulo','indicação')
on conflict(id) do update set display_name=excluded.display_name,city=excluded.city,source=excluded.source;

insert into public.crm_contact_identifiers(id,organization_id,contact_id,kind,normalized_value) values
  ('d2100000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','phone','+5511900000001'),
  ('d2100000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','email','marina@example.test'),
  ('d2100000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002','phone','+5511900000002')
on conflict(organization_id,kind,normalized_value) do nothing;

insert into public.crm_contact_units(organization_id,contact_id,unit_id) values
  ('d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001'),
  ('d0000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000002','d1000000-0000-4000-8000-000000000001')
on conflict do nothing;

insert into public.crm_pipelines(id,organization_id,unit_id,name) values
  ('d3000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Funil de matrículas')
on conflict(id) do update set name=excluded.name,active=true;

insert into public.crm_pipeline_stages(id,organization_id,unit_id,pipeline_id,name,position,outcome) values
  ('d3100000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','Novo lead',0,null),
  ('d3100000-0000-4000-8000-000000000002','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Visita agendada',1,null),
  ('d3100000-0000-4000-8000-000000000003','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Matriculado',2,'won'),
  ('d3100000-0000-4000-8000-000000000004','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','Perdido',3,'lost')
on conflict(id) do update set name=excluded.name,position=excluded.position,outcome=excluded.outcome,active=true;

insert into public.crm_opportunities(id,organization_id,unit_id,contact_id,pipeline_id,stage_id,title,status,value_cents,source,external_key) values
  ('d4000000-0000-4000-8000-000000000001','d0000000-0000-4000-8000-000000000001','d1000000-0000-4000-8000-000000000001','d2000000-0000-4000-8000-000000000001','d3000000-0000-4000-8000-000000000001','d3100000-0000-4000-8000-000000000001','Plano anual de Marina','open',149900,'site','dev-opportunity-1')
on conflict(id) do update set stage_id=excluded.stage_id,title=excluded.title,status='open',value_cents=excluded.value_cents;
