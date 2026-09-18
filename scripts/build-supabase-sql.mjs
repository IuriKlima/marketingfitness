import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname,'..');
const output = resolve(root,'supabase/sql-editor');
const names = [
  '20260908000000_foundation.sql',
  '20260911000000_identity_onboarding.sql',
  '20260911001000_identity_hardening.sql',
  '20260916000000_crm_agenda.sql',
  '20260916001000_inbox_worker.sql',
  '20260916002000_ai_privacy.sql'
];
const sources = names.map(name => ({name,sql:readFileSync(resolve(root,'supabase/migrations',name),'utf8').replace(/\r\n/g,'\n')}));
const foundationTables = ['organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events'];
const identityTables = ['organization_invitations','onboarding_field_definitions','onboarding_reviews','onboarding_attachments'];
const phase3Tables = ['crm_contacts','crm_opportunities','crm_appointments','channel_connections','conversations','messages','ai_assistant_configs','knowledge_sources','ai_runs'];
const allTables = [...foundationTables,...identityTables,...phase3Tables];
const quotedList = names => names.map(name => "'" + name + "'").join(',');

function bundle(mode) {
  const migrations = mode === 'phase1' ? sources.slice(1) : mode === 'phase2' ? sources.slice(3) : sources;
  const guard = mode === 'phase1' ? `
  foreach item in array array[${quotedList(foundationTables)}] loop
    if to_regclass('public.' || item) is null then
      raise exception 'Fundacao incompleta: public.% ausente. Use 01_instalacao_completa.sql apenas em projeto novo.',item;
    end if;
  end loop;
  if to_regclass('private.platform_roles') is null or to_regclass('private.outbox') is null then
    raise exception 'Fundacao privada incompleta. Revise o schema antes de continuar.';
  end if;
  if to_regclass('public.organization_invitations') is not null or to_regtype('public.onboarding_scope') is not null then
    raise exception 'Fase 2 ja existe ou foi aplicada parcialmente. Nao reaplique este arquivo.';
  end if;
  if to_regclass('public.crm_contacts') is not null or to_regtype('public.conversation_state') is not null then
    raise exception 'Fase 3 ja existe ou foi aplicada parcialmente. Nao reaplique este arquivo.';
  end if;` : mode === 'phase2' ? `
  foreach item in array array[${quotedList([...foundationTables,...identityTables])}] loop
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
  end if;` : `
  foreach item in array array[${quotedList(allTables)}] loop
    if to_regclass('public.' || item) is not null then
      raise exception 'Instalacao interrompida: public.% ja existe. Se a fase 1 foi aplicada, revise 02_atualizar_fase1.sql.',item;
    end if;
  end loop;
  if to_regclass('private.platform_roles') is not null or to_regclass('private.outbox') is not null or
    to_regtype('public.platform_role') is not null then
    raise exception 'Objetos anteriores encontrados. Revise o schema antes de instalar.';
  end if;`;
  const title = mode === 'phase1' ? 'atualizar uma instalacao existente da fase 1' : mode === 'phase2' ? 'atualizar uma instalacao aprovada da fase 2 para a fase 3' : 'instalacao completa em projeto novo';
  return `-- AcadeAI: ${title}.
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
${guard}
end
$preflight$;

` + migrations.map(({name,sql}) => `-- Fonte: ${name}
-- SHA256 (UTF-8, LF): ${createHash('sha256').update(sql).digest('hex')}
${sql.trimEnd()}
`).join('\n') + `
notify pgrst, 'reload schema';
commit;
select 'Instalacao concluida. Execute 90_verificar.sql e configure o Auth conforme LEIA-ME.md.' as resultado;
`;
}

mkdirSync(output,{recursive:true});
writeFileSync(resolve(output,'01_instalacao_completa.sql'),bundle('full'));
writeFileSync(resolve(output,'02_atualizar_fase1.sql'),bundle('phase1'));
writeFileSync(resolve(output,'03_atualizar_fase2.sql'),bundle('phase2'));
console.log('SQL Editor: tres instaladores gerados a partir das migracoes, sem credenciais.');
