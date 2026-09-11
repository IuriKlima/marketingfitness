# AcadeAI — Marketing Fitness

Monorepo TypeScript para academias e redes. A fase 2 implementa identidade, painéis, convites e onboarding. CRM e automações de marketing permanecem para fases posteriores.

Estado e resultados: [fase 1](docs/progress/phase-1-foundation.md) e [fase 2](docs/progress/phase-2-identity-onboarding.md). A fundação passou no CI; a migração da fase 2 ainda exige validação no Supabase.

Para usar o projeto Supabase hospedado, os instaladores SQL, verificações e passos de primeiro acesso estão em [supabase/sql-editor/LEIA-ME.md](supabase/sql-editor/LEIA-ME.md). Gere os instaladores com `npm run sql:bundle`. A API aceita também `SUPABASE_ANON_KEY` como alternativa legada à chave publicável; essas chaves ficam somente no `.env` do backend.

## Preparar o projeto

Requisitos: Node.js 24, npm 11.8.0, Git e Docker Desktop com engine Linux disponível.

```sh
git clone https://github.com/IuriKlima/marketingfitness.git
cd marketingfitness
npm ci
npm run lint
npm run typecheck
npm test
npm run build
npm run secrets:check
```

As alterações deste pacote estão na branch local `codex/prompt-2-identity-onboarding`. Até essa branch ser publicada e integrada, um clone da main contém somente a fase 1. As dependências usam exclusivamente npm e o lockfile.

## Supabase de desenvolvimento

```sh
npm run db:start
npm run db:reset
npm run db:test
npm run db:lint
npm run db:types
npm run setup:local
```

`db:start` prepara uma chave ES256 de desenvolvimento em `supabase/.local/signing_keys.json`, ignorada pelo Git, antes de iniciar o Supabase. Não a exibe nem substitui uma chave existente. Isso mantém os tokens do Auth compatíveis com o verificador JWKS.

`db:reset --local` recria o banco local deste projeto e elimina seus dados locais. O schema usa três migrações aditivas. Os testes pgTAP usam dados inteiramente fictícios e rollback. Nenhum comando acima acessa produção.

`setup:local` lê o status do Supabase sem exibir credenciais e cria os arquivos ignorados `.env` e `apps/web/.env.local`. Não sobrescreve configuração existente. Exige que o CLI disponibilize as chaves modernas `PUBLISHABLE_KEY` e `SECRET_KEY`. Caso não estejam disponíveis, configure as variáveis abaixo a partir do seu ambiente de desenvolvimento.

| Ambiente | Variáveis |
| --- | --- |
| API | SUPABASE_URL, SUPABASE_JWT_ISSUER, SUPABASE_PUBLISHABLE_KEY (ou SUPABASE_ANON_KEY legada), SUPABASE_SECRET_KEY, SESSION_CONTEXT_SECRET, APP_ORIGIN, API_PORT |
| Web | VITE_API_BASE_URL=/api; VITE_SUPABASE_URL e VITE_SUPABASE_PUBLISHABLE_KEY são aceitas para compatibilidade |
| Worker | WORKER_PORT |

O navegador acessa a API da mesma origem e não armazena access/refresh tokens em JavaScript. Somente a API recebe SUPABASE_SECRET_KEY. SESSION_CONTEXT_SECRET deve ser aleatória e ter pelo menos 32 bytes. Os exemplos contêm apenas placeholders. Não cole valores privados em issues, documentação ou saídas de testes.

`db:types` gera `packages/database/src/database.types.ts` diretamente do schema aplicado. Geração com erro preserva o arquivo anterior. Não crie um substituto manual. O arquivo atualizado precisa ser gerado, revisado e versionado após a validação do banco.

## Executar a aplicação

Em terminais separados na raiz:

```sh
npm run dev:api
npm run dev:web
npm run dev:worker
```

- Web: http://127.0.0.1:5173/login
- API: http://127.0.0.1:3001/health e /ready
- Worker: http://127.0.0.1:3002/health
- Mailpit local: http://127.0.0.1:54324

O Vite encaminha /api ao backend. A API precisa das variáveis configuradas para iniciar. Health verifica o processo; readiness verifica JWKS e o catálogo de onboarding. O worker continua com `processing:false`.

Para o primeiro acesso **somente no ambiente local padrão**, com Supabase funcionando e configuração pronta:

```sh
npm run bootstrap:local
```

Esse comando convida `platform-admin@example.test` no Auth local e atribui supreme no container de banco deste projeto. O e-mail é capturado pelo Mailpit local. Abra o link ali, defina a senha e acesse o painel da plataforma. Execute uma vez em um banco local novo; ele não reconfigura usuário já existente. Nenhuma credencial é impressa. O comando não foi executado nesta máquina porque o Docker está indisponível.

Em um projeto hospedado de desenvolvimento, o responsável cria/convida o primeiro usuário de plataforma pelo Auth, usa redirect `https://SEU_APP/invite?bootstrap=true` e atribui o papel global em uma sessão administrativa auditada:

```sql
-- Substituir pelo UUID do usuário de plataforma verificado pelo responsável.
insert into private.platform_roles(user_id, role)
values ('<UUID_DO_USUARIO_VERIFICADO>', 'supreme')
on conflict do nothing;
```

Essa é uma ação de bootstrap restrita ao operador. Não há endpoint público para ganhar papel global.

## Fluxos da fase 2

- Login, logout, renovação, recuperação, convite e troca de senha usam cookies HttpOnly e proteção de origem/CSRF. Chaves de assinatura do Auth devem ser assimétricas (ES256/RS256); JWTs HS256 são recusados.
- O painel Supremo provisiona academia/unidade, envia convites e revisa onboardings. Ele não recebe membership nem bypass operacional implícito.
- Admins de academia convidam pessoas apenas no escopo autorizado. O papel e as unidades existentes são preservados; aceite de convite não pode ampliar o escopo controlado pelo convidante.
- Contexto de academia/unidade é assinado, vinculado ao usuário e revalidado contra memberships/grants ativos.
- Onboarding usa definições versionadas, autosave serializado, revisão otimista para detectar outra edição, validação de campos na API e no banco, envio imutável e revisão com campos pendentes.
- Aprovar cria fatos confirmados e auditoria na mesma transação. Devolver encerra a versão; a próxima gravação cria outra versão.
- Anexos privados usam metadados vinculados à empresa, unidade e versão. O upload atravessa a API com cookies/CSRF e o Storage com o JWT do usuário. Não há URL de upload privilegiada no navegador. Downloads de revisores exigem autorização e auditoria.

## Segurança e produção

```text
Web -> /api na mesma origem -> cookies HttpOnly / Origin / CSRF
API -> JWT verificado em JWKS -> usuário e contexto autorizado
API -> cliente do usuário -> PostgREST e Storage sob RLS
API administrativa -> RPC service-only -> ator revalidado + auditoria
Worker -> contrato OutboxPort (sem consumidor)
PostgreSQL public com RLS | private.platform_roles | private.outbox
```

A suspensão impede operação de membros e suporte; suporte exige grant ativo, e revisão exige read_write. Papéis globais e de academia são separados. Convites guardam somente o hash SHA-256, expiram e só podem ser aceitos uma vez. RLS e grants negam alterações de plano, status, papéis e concessões pelo navegador.

`onboarding_field_definitions` é catálogo global de configuração, por schema_version; não é uma tabela operacional de academia. Os documentos, revisões, convites e anexos têm organization_id e vínculos de unidade apropriados.

Antes de produção: configure HTTPS e web/API na mesma origem; NODE_ENV=production; segredos em cofre; Auth sem cadastro público; limites de Auth apropriados; proteção contra senhas vazadas; MFA para operadores de plataforma; backups e políticas de retenção. O pacote não implementa uma tela de desafio MFA — esse fluxo e sua imposição devem ser resolvidos antes de liberar acesso de plataforma em produção.

O proxy de produção deve enviar CSP e X-Frame-Options, preservar cookies e não registrar corpos, cookies, cabeçalhos de autenticação nem query strings dos callbacks. Não exponha os tokens de convite em logs de acesso. O CSP no HTML não substitui os cabeçalhos do proxy.

Templates locais estão em `supabase/templates`, referenciados no config.toml. Configure os mesmos templates no Auth hospedado. O template de magic link também é necessário para convites de usuários que já possuem conta. Os redirects de convite carregam um parâmetro inicial; use URLs exatas autorizadas em produção, sem o wildcard local.

Referências oficiais para esse comportamento: [templates de e-mail](https://supabase.com/docs/guides/auth/auth-email-templates), [templates locais](https://supabase.com/docs/guides/local-development/customizing-email-templates) e [redirects](https://supabase.com/docs/guides/auth/redirect-urls).

## Verificação e continuidade

O workflow `.github/workflows/ci.yml` separa testes Node, Supabase/Docker e Gitleaks. A suite atual contém 14 testes Node e 64 asserções pgTAP planejadas. A varredura local de credenciais é heurística e inclui o bundle.

No momento da entrega, lint, typecheck, testes Node e build passaram. Banco local, geração de tipos, envio real de e-mail e fluxos integrados Auth/Storage não foram validados nesta máquina. O CI da fase 1 passou; o CI da fase 2 ainda não foi executado. Consulte o checkpoint antes de avançar.
