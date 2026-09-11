import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { resolve } from 'node:path';

const root = resolve(import.meta.dirname,'..');
const output = resolve(root,'supabase/sql-editor');
const names = [
  '20260908000000_foundation.sql',
  '20260911000000_identity_onboarding.sql',
  '20260911001000_identity_hardening.sql'
];
const sources = names.map(name => ({name,sql:readFileSync(resolve(root,'supabase/migrations',name),'utf8').replace(/\r\n/g,'\n')}));
const foundationTables = ['organizations','units','memberships','membership_roles','membership_units','support_access_grants','onboarding_versions','academy_facts','audit_events'];
const allTables = [...foundationTables,'organization_invitations','onboarding_field_definitions','onboarding_reviews','onboarding_attachments'];
const quotedList = names => names.map(name => "'" + name + "'").join(',');

function bundle(upgrade) {
  const migrations = upgrade ? sources.slice(1) : sources;
  const guard = upgrade ? `
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
  return `-- AcadeAI: ${upgrade ? 'atualizar uma instalacao existente da fase 1' : 'instalacao completa em projeto novo'}.
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
writeFileSync(resolve(output,'01_instalacao_completa.sql'),bundle(false));
writeFileSync(resolve(output,'02_atualizar_fase1.sql'),bundle(true));
console.log('SQL Editor: dois instaladores gerados a partir das migracoes, sem credenciais.');
