# AcadeAI — fundação

Monorepo TypeScript, sem CRM, atendimento ou marketing. Leia [o checkpoint](docs/progress/phase-1-foundation.md) antes de continuar. O diretório entregue inicialmente estava vazio e sem `.git`; não existia implementação anterior.

## Pré-requisitos

- Node.js 24 e npm 11.8.0 (único gerenciador; versões fixas no package-lock.json).
- Docker Desktop com engine Linux funcionando. No Windows, habilite WSL2 conforme a instalação oficial do Docker. `docker info` precisa funcionar antes do Supabase.
- Git para clonar o futuro repositório. Não há remoto configurado nesta entrega.

## Instalar e validar

Na raiz do checkout:

```sh
npm ci
npm run lint
npm run typecheck
npm test
npm run build
npm run secrets:check
```

Os testes unitários usam somente Node e um servidor JWKS efêmero em loopback. Não exigem conta Supabase. A varredura local é heurística; Gitleaks verifica o histórico no CI. Nenhum resultado substitui revisão humana de credenciais.

## Banco local

```sh
npm run db:start
npm run db:reset
npm run db:test
npm run db:lint
npm run db:types
```

`db:reset --local` recria somente o banco de desenvolvimento deste projeto e elimina dados locais. Não execute em um ambiente com dados que precise preservar. As fixtures são inteiramente fictícias e os testes usam transação com rollback. Não há seed de dados reais.

Os tipos são gerados em `packages/database/src/database.types.ts` exclusivamente a partir do schema aplicado. Não existem tipos manuais substitutos. Após gerar, revise e versione o arquivo; no CI ele é publicado como artefato. A geração malsucedida preserva o arquivo anterior. Não execute Prompt 2 sem validar banco e tipos.

Supabase Advisors remotos exigem um projeto de desenvolvimento explicitamente configurado e acesso autorizado. Não foi configurado projeto remoto; o CI testa Supabase local e não altera produção.

## Executar os esqueletos

Copie `.env.example` para `.env` e `apps/web/.env.example` para `apps/web/.env.local` (no PowerShell, use `Copy-Item`). Substitua somente a chave publicável fictícia pela chave publicável do Supabase local, obtida no painel local ou nas informações da instância. Não cole saídas contendo credenciais em issues, logs ou documentação.

Variáveis da API: `SUPABASE_URL`, `SUPABASE_JWT_ISSUER`, `API_PORT`. Worker: `WORKER_PORT`. Web: `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY`. Nenhuma chave administrativa é necessária ou consumida nesta fase. Credenciais privadas futuras devem vir de um cofre de segredos exclusivo do backend.

Em três terminais, na raiz:

```sh
npm run dev:web
npm run dev:api
npm run dev:worker
```

- Web: http://127.0.0.1:5173 — health da configuração pública e conectividade com Supabase Auth; não comprova acesso ao banco.
- API: http://127.0.0.1:3001/health — processo; `/ready` — disponibilidade de JWKS com chaves assimétricas; `/session` — exige JWT válido. Readiness não comprova migrações nem RLS.
- Worker: http://127.0.0.1:3002/health — processo ativo, `processing:false`.

JWT: issuer exato `${SUPABASE_URL}/auth/v1`, audience `authenticated`, ES256/RS256 e subject obrigatório. Tokens legados HS256 são recusados: configure chave de assinatura assimétrica no Supabase antes da autenticação do Prompt 2. `userId` identifica o usuário, não autoriza um tenant. Não existem rotas administrativas; retornam 404. Rotas futuras precisam resolver membership/unidade usando identidade validada e RLS. Nenhuma entrada tenant da requisição é confiável por si só.

## Segurança e arquitetura

```text
web (chave publicável) -> Supabase Auth / API de dados com RLS
web -> API (JWT verificado por JWKS) -> autorização futura por membership
API administrativa futura -> auditoria + banco (sem rota implementada)
worker -> OutboxPort (contrato somente; nenhum consumo)
PostgreSQL: public com RLS | private.platform_roles | private.outbox
```

Organizations, units e memberships modelam empresa/unidade. Roles da academia são cumulativos e distintos dos papéis globais privados. `supreme` não recebe acesso operacional implícito; suporte exige concessão ativa, justificada e de até 24 horas. Suspensão invalida leitura e escrita de membros e suporte. A fase permite apenas a academy_admin (ou suporte read_write concedido) inserir/editar drafts de onboarding nas unidades autorizadas. Demais papéis são somente leitura nesta fundação.

Memberships, roles, plano, status, fatos, auditoria e concessões não têm escrita pelo navegador. A concessão se aplica à empresa inteira, inclusive suas unidades; toda alteração é auditada. Ainda não há fluxo backend para conceder acesso, aprovar onboarding ou promover usuários. Nunca implemente esse fluxo apenas com a chave privilegiada sem autorização explícita e auditoria.

Onboarding é versionado por unidade, com schema_version. Documento enviado não pode mudar; backend pode decidir submitted -> approved/rejected. Versões aprovadas/rejeitadas são imutáveis e não são apagadas. Correção exige nova versão. Fatos confirmados exigem origem aprovada e são append-only. Auditoria contém apenas IDs, ação e tempo. Outbox guarda referência de entidade, chave idempotente por organização e agendamento; não contém documentos ou tokens. Claim concorrente, leases e processadores são trabalho futuro.

Storage permanece sem buckets/policies operacionais: nenhuma liberação foi criada. Não adicione policy genérica de acesso público para contornar autorização.

## CI e continuidade

`.github/workflows/ci.yml` separa verificações Node, integração Supabase/Docker e Gitleaks. Não há execução remota comprovada até publicar o código em um repositório e executar o workflow. Comandos oficiais: [Supabase CLI](https://supabase.com/docs/reference/cli/usage), [desenvolvimento local](https://supabase.com/docs/guides/local-development), [Vite](https://vite.dev/guide/).

