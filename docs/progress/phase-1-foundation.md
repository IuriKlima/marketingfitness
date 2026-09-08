# Checkpoint — fase 1: fundação

Data: 2026-09-08. Portão: **NÃO PRONTO PARA O PROMPT 2**.

## Estado inicial e diagnóstico

`C:\Users\laris\Desktop\acadeai` estava vazio, inclusive arquivos ocultos. `git status --short` retornou “not a git repository”; `rg --files` não encontrou arquivos. Não existiam AGENTS.md ou outras instruções no diretório, package.json, lockfile, aplicações, Supabase, migrações, testes, CI ou documentação. Também não foi encontrado AGENTS.md nos diretórios Desktop e do usuário consultados. Nenhuma alteração preexistente foi sobrescrita.

Assim, nenhuma das tabelas esperadas estava presente e nada da aplicação podia ser executado inicialmente. Não havia documentação anterior para comparar com código. O risco principal era tratar o schema esperado no pedido como se já existisse e como se tivesse sido validado. A correção segura foi construir a fundação do zero e separar resultado de código de comprovação integrada.

Git foi inicializado localmente em `main`, sem commit, staging, remoto, push, merge ou deploy. Todos os arquivos entregues permanecem não versionados até revisão/commit. Um endereço para clonagem ainda depende da publicação autorizada pelo responsável.

## Plano e progresso

1. Auditoria/inventário: concluídos.
2. Monorepo e esqueleto executável: concluídos e verificados localmente.
3. Schema e cenários negativos: escritos e revisados; execução integrada bloqueada.
4. Tipos do banco aplicado: gerador preparado, geração bloqueada.
5. CI, README e checkpoint: escritos; workflow remoto não executado.

## Decisões arquiteturais

- npm workspaces; Node 24, TypeScript 5.9.3, Vite 8.2.2, Supabase JS 2.116.0, jose 6.2.12, Supabase CLI 2.117.0, ESLint 10.10.0, typescript-eslint 8.70.0. Versões exatas e resolução transitiva no package-lock.json. TypeScript 5.9 preserva compatibilidade estável sem exigir migração ao compilador 7 nesta fundação.
- Web mínimo sem framework de UI; API e worker usam HTTP nativo. Não há funcionalidade de CRM, atendimento ou marketing.
- PostgreSQL 15 local configurado. Supabase é a referência integrada, não substituído por mocks de RLS.
- Papéis globais privados, cumulativos, separados de papéis da academia. Supreme não ganha bypass operacional. Suporte precisa de concessão por empresa, temporária, com justificativa e auditoria.
- Membership ativa + role + empresa ativa + escopo de unidade governam o acesso. Suspensão bloqueia acesso inclusive do suporte. No escopo desta fase, só academy_admin ou suporte read_write altera drafts autorizados; outros papéis leem.
- Tabelas de relação e operacionais têm organization_id; units é a entidade de unidade e possui chave (organization_id,id). Tabelas locais referenciam essa chave de forma composta. Organizations é a raiz tenant, não recebe referência a si própria. Platform roles são globais e constituem a exceção intencional sem tenant.
- Toda tabela pública criada tem RLS. Anon não recebe grants operacionais. Auditoria tem grant SELECT autenticado, mas nenhuma policy de leitura nesta fase, logo é negada por padrão. Private não é exposto pela Data API; apenas a função de autorização tem EXECUTE para authenticated.
- Funções SECURITY DEFINER têm search_path vazio e referências qualificadas. As funções de trigger não são invocáveis diretamente por clientes. A função de autorização responde apenas conforme auth.uid(), inclusive quando recebe organization_id arbitrário.
- Nenhuma escrita administrativa pelo navegador. Não há endpoint administrativo nem cliente com chave privilegiada. Aprovar documentos, conceder suporte e promover usuários exigirão fluxos autorizados/auditados no backend em fase posterior.
- Onboarding por unidade/version/schema_version; documento enviado é imutável. Backend pode resolver submitted -> approved/rejected; versões finais não mudam. Fatos confirmados são append-only e dependem de onboarding aprovado. Auditoria append-only registra IDs/ações, nunca documentos ou credenciais. Outbox privada tem unicidade (organization_id,idempotency_key) e payload por referência.
- Worker não consome mensagens; OutboxPort é somente interface. Leases, claim concorrente, retentativas reais e integrações não foram implementados.
- API valida JWT usando JWKS, issuer, audience, ES256/RS256, exp/iat/sub obrigatórios e role authenticated. Nenhum tenant é derivado automaticamente do token ou da URL. Tokens HS256 não são aceitos.
- Web aceita exclusivamente variáveis públicas explicitamente listadas, e somente o formato de chave publicável moderno. Variáveis VITE adicionais interrompem o build. Nenhum segredo é necessário para executar os esqueletos.

## Componentes

```text
apps/web ── chave publicável ──> Supabase Auth / Data API + RLS
    └──── JWT ────────────────> apps/api (JWKS; health/readiness/session)
apps/worker ── OutboxPort ────> sem adaptador/consumo nesta fase
packages/contracts : contratos HTTP/outbox
packages/config    : configuração pública e backend separadas
packages/database  : destino de tipos gerados do banco aplicado
Supabase PostgreSQL
  public  : organizations, units, memberships, membership_roles,
            membership_units, support_access_grants, onboarding_versions,
            academy_facts, audit_events
  private : platform_roles, outbox, funções de autorização/triggers
```

## Arquivos criados por finalidade

- Monorepo/configuração: package.json, package-lock.json, tsconfig.json, eslint.config.js, .gitignore, .env.example; package.json em cada app/pacote.
- Web: apps/web/index.html, src/main.ts, vite.config.ts, .env.example.
- API: apps/api/src/index.ts e auth.ts. Worker: apps/worker/src/index.ts.
- Pacotes: packages/config/src/public.ts e server.ts; packages/contracts/src/index.ts; packages/database/README.md.
- Banco: supabase/config.toml; supabase/migrations/20260908000000_foundation.sql; supabase/tests/001_isolation.test.sql (26 asserções planejadas).
- Verificação: tests/config.test.ts, auth.test.ts, health.test.ts, build-boundary.test.ts; scripts/check-secrets.mjs e generate-types.mjs.
- CI/documentação: .github/workflows/ci.yml, README.md, este checkpoint.
- O arquivo packages/database/src/database.types.ts NÃO foi criado: não existe schema aplicado acessível do qual gerar tipos com fidelidade.

## Comandos executados e resultados reais

- `Get-ChildItem -Force`, `git status --short`, `rg --files`: auditoria inicial vazia, Git ausente. `git init -b main`: concluído. `git status --short` final: arquivos novos, sem alterações anteriores.
- `node --version`: v24.13.1; `npm --version`: 11.8.0.
- `npm view` para versões: primeira tentativa bloqueada por permissões de rede/cache do sandbox; consulta com permissão ampliada concluída. Dependências inicialmente antigas foram substituídas pelas versões fixadas acima.
- `npm install` inicial e atualização explícita: concluídos. Relatório final npm: zero vulnerabilidades conhecidas. Não foi usado `npm audit fix --force`.
- `npm ci`: concluído; 132 pacotes instalados, 139 auditados, zero vulnerabilidades conhecidas. Lockfile reproduzível nesta máquina.
- `npm run lint`, `npm run typecheck`, `npm test`, `npm run build`, `npm run secrets:check`: aprovados. Rodada final: lint e typecheck com saída 0; 7 testes locais aprovados (0 falhas); build web aprovado (48 módulos); varredura local sem padrões de credenciais. O teste adicional de configuração confirma que valores inválidos do ambiente não aparecem no erro. Falhas intermediárias de lint/build por arquivos ausentes ocorreram durante atualização de dependências e foram resolvidas ao repetir após a instalação completa.
- Testes locais já executados: configuração/portas/chave pública, JWKS com assinatura real e rejeição de issuer/audience/expiração/role/assinatura inválidos, HTTP real da API e worker. Sem serviços externos. API respondeu 200 em health, 503 em readiness sem JWKS, 401 sem sessão, 404 em admin, 405 para POST; worker respondeu com processing:false.
- `docker info`, `docker version`: falharam porque engine Linux não está disponível. Tentativas de iniciar Docker Desktop via processo oculto e `docker desktop start` não disponibilizaram o pipe nesta sessão. O comando de espera de inicialização foi interrompido com Ctrl+C; nenhum serviço de produção foi tocado.
- `npm run db:start`: falhou, LegacyDockerLifecycleInspectError, pipe dockerDesktopLinuxEngine inexistente. O aviso de configuração [inbucket] obsoleta foi corrigido para [local_smtp].
- `npm run db:reset`: falhou, LegacyLocalDbRunningError, mesmo engine ausente. Nenhuma migração aplicada.
- `npm run db:test`: falhou na conexão, ECONNREFUSED 127.0.0.1:54322. As 26 asserções pgTAP NÃO foram executadas.
- `npm run db:lint`: falhou na conexão, ECONNREFUSED 127.0.0.1:54322. O SQL NÃO tem validação sintática/comportamental comprovada pelo PostgreSQL.
- `npm run db:types`: falhou de forma controlada; nenhum tipo manual ou arquivo gerado vazio foi deixado.
- Uma tentativa de comandos do banco coincidiu com npm ci e não encontrou o binário. A repetição após instalação concluída confirmou os bloqueios reais acima.
- `git diff --check`: sem saída, mas como arquivos estão não versionados não substitui validação dos arquivos novos.

## Cobertura RLS preparada, ainda não executada

Duas academias fictícias, três unidades e três identidades. Leitura e escrita cruzadas (insert/update), consulta direta à função auxiliar, restrição por unidade, empresa suspensa (leitura/escrita), suporte sem grant, read_only (leitura permitida/escrita negada), expiração, autoelevação via membership/roles/platform roles, alteração de plano/status, fabricação de concessão, documento aprovado imutável no browser e backend, FK composta, acesso anônimo e outbox privada. Um insert autorizado serve como controle positivo para evitar uma suíte que passe apenas por negar tudo.

## Pendências e riscos

- Bloqueio principal: Docker Linux indisponível; responsável precisa normalizar Docker/WSL2 e repetir os comandos do README. Não foram alteradas configurações de virtualização nem reiniciado o computador.
- Migração, pgTAP e lint do banco precisam rodar antes de confiar na segurança descrita. Revisão textual não comprova isolamento. Tipos precisam ser gerados do schema realmente aplicado.
- Supabase Advisors remotos, CI GitHub e Gitleaks remoto não executados: nenhum projeto remoto/repositório remoto autorizado está configurado. A varredura local é heurística e não equivale a Gitleaks.
- Nenhuma integração com credenciais reais, login ou onboarding de produto foi implementada. Configure assinatura assimétrica do Auth para Prompt 2; readiness somente verifica JWKS e não o estado das migrações.
- Storage não possui buckets/policies de negócio. Futuros módulos precisam estender RLS por empresa/unidade e manter negação por padrão.
- As 26 asserções não esgotam o espaço de autorização: ampliar controles positivos para outros papéis, read_write/revogação e concorrência quando seus fluxos forem implementados.
- Esta é a primeira migração em um diretório vazio; nenhum histórico preexistente foi removido. Não existe down destrutivo automático. Em ambientes persistentes, corrigir por migração aditiva; qualquer remoção futura requer expandir-migrar-contrair e autorização.

## Portão da fase

**NÃO PRONTO.** A camada Node é executável localmente e o pipeline está preparado, mas os critérios essenciais de migrações aplicadas, isolamento RLS comprovado e tipos gerados permanecem bloqueados. Para continuar: resolver Docker, executar db:start/reset/test/lint/types, corrigir eventuais falhas sem enfraquecer políticas, repetir typecheck e registrar os resultados neste arquivo. Só então avaliar Prompt 2.

