# AcadeAI — Marketing Fitness

Monorepo TypeScript de uma aplicação SaaS multi-tenant para academias. A base atual reúne identidade e onboarding, CRM e agenda, caixa de atendimento, WhatsApp via Evolution API, outbox/worker e uma assistente governada por fontes aprovadas.

Checkpoints: [fase 1](docs/progress/phase-1-foundation.md), [fase 2](docs/progress/phase-2-identity-onboarding.md) e [fase 3](docs/progress/phase-3-crm-inbox-ai.md). Consulte o checkpoint antes de tratar uma integração como aprovada.

## Requisitos e validação local

- Node.js 24 e npm 11.8.0
- Git
- Docker Desktop com engine Linux para o Supabase local

```sh
npm ci
npm run lint
npm run typecheck
npm test
npm run build
npm run secrets:check
```

As dependências usam npm workspaces e versões fixadas no lockfile. O browser conversa apenas com o BFF na mesma origem; credenciais administrativas nunca entram no bundle.

## Ambiente

Copie `.env.example` para `.env` sem versionar. Os placeholders não são credenciais.

| Processo | Variáveis |
| --- | --- |
| API e worker | `SUPABASE_URL`, `SUPABASE_JWT_ISSUER`, `SUPABASE_PUBLISHABLE_KEY` ou `SUPABASE_ANON_KEY`, `SUPABASE_SECRET_KEY`, `SESSION_CONTEXT_SECRET`, `APP_ORIGIN` |
| API | `API_PORT`, `PUBLIC_WEBHOOK_BASE_URL` opcional |
| Worker | `WORKER_PORT`, `WORKER_ID` e `WORKER_POLL_MS` opcionais |
| IA | `LLM_API_URL`, `LLM_API_KEY` e `LLM_MODEL`, todas opcionais e somente no backend |
| Web | `VITE_API_BASE_URL=/api` |

`SESSION_CONTEXT_SECRET` deve ter ao menos 32 bytes aleatórios. `PUBLIC_WEBHOOK_BASE_URL` deve ser HTTPS e alcançável pela Evolution API. Sem as três variáveis LLM, a interface informa que o provider não está configurado e a simulação recusa a operação. Sem configuração completa do backend, o worker inicia health com `processing:false`.

## Supabase

```sh
npm run db:start
npm run db:reset
npm run db:test
npm run db:lint
npm run db:types
npm run setup:local
```

`db:start` cria ou repara somente os metadados públicos da chave ES256 local (`alg`, `use` e `key_ops`), preservando e não imprimindo o material criptográfico. `db:reset` destrói apenas o banco local deste projeto. Os testes pgTAP usam dados `example.test` e rollback.

`db:types` gera `packages/database/src/database.types.ts` a partir do schema aplicado. Não mantenha tipos manuais como substituto de uma geração que falhou.

Para SQL Editor, execute `npm run sql:bundle` e siga [supabase/sql-editor/LEIA-ME.md](supabase/sql-editor/LEIA-ME.md). Há instaladores distintos para projeto novo, atualização da fase 1 e atualização da fase 2. Execute somente o que corresponde ao estado real do banco. Nenhum instalador contém chaves ou seed.

O seed em [supabase/seeds/phase3-dev.sql](supabase/seeds/phase3-dev.sql) é opcional, idempotente, fictício e exige uma flag explícita na mesma transação. Ele não participa de migrations nem do reset por padrão e deve permanecer fora de produção.

## Executar

Use terminais separados:

```sh
npm run dev:api
npm run dev:web
npm run dev:worker
```

- Web: `http://127.0.0.1:5173/login`
- API: `http://127.0.0.1:3001/health` e `/ready`
- Worker: `http://127.0.0.1:3002/health`
- Mailpit local: `http://127.0.0.1:54324`

O primeiro acesso local pode ser criado com `npm run bootstrap:local` depois que o Supabase estiver pronto. O comando é restrito ao ambiente local, usa um endereço fictício e não imprime credenciais.

## Módulos da fase 3

- `/app/crm`: indicadores, leads, tarefas, visitas e contatos paginados.
- `/app/crm/pipelines`: Kanban acessível por botões/teclado, tabela e rollback após falha.
- `/app/crm/contatos/:id`: identificadores, consentimentos, oportunidades, agenda e linha do tempo.
- `/app/agenda`: calendário/lista comercial.
- `/app/atendimento` e `/app/atendimento/:id`: caixa, mensagens, contexto do lead, takeover e devolução à IA.
- `/app/canais`: estados honestos de WhatsApp, Instagram e TikTok; conexão, diagnóstico, pausa e revogação da Evolution.
- `/app/assistente-ia`: configuração, limites, simulação restrita e histórico.
- `/app/base-conhecimento`: fontes, conteúdo versionado, indexação e aprovação explícita.
- `/app/filas`: prioridade, membros, capacidade e SLA.

Os handlers estão separados por domínio em `apps/api/src`. O worker usa claim concorrente, lease, backoff, jitter e dead-letter. A [matriz de acesso](docs/access-matrix.md) descreve os papéis. Runbooks cobrem [Evolution/webhook](docs/runbooks/evolution-webhook.md), [outbox](docs/runbooks/outbox-dead-letter.md), [handoff](docs/runbooks/human-handoff.md), [revogação](docs/runbooks/channel-revocation.md) e [IA](docs/runbooks/ai-guardrails.md).

## Segurança

```text
Web -> BFF na mesma origem -> cookies HttpOnly + Origin + CSRF
BFF -> JWT por JWKS -> usuário + contexto assinado e revalidado
Cliente do usuário -> PostgREST/Storage sob RLS
Operação administrativa -> RPC service-only -> ator + organização + unidade + auditoria
Webhook opaco -> autenticação + deduplicação -> outbox
Worker -> provider -> evento append-only de entrega
```

Toda tabela operacional inclui organização; registros de unidade usam foreign keys compostas. Supremo não recebe acesso operacional implícito. Suporte exige grant temporário. Organização suspensa não opera. Visualizador não recebe PII ou corpo de mensagens. Credenciais de canal ficam no Vault.

Mensagens e históricos comerciais são imutáveis; status são eventos. Contatos são deduplicados por identificador normalizado. Operações críticas usam idempotency keys. Downloads externos têm bloqueio de redes privadas/metadata, redirects, tamanho, allowlist e assinatura real de MIME.

A IA usa apenas fatos e versões aprovadas e registra as fontes. Prompt injection é bloqueada antes do provider, ferramentas são allow-listed e opt-out impede mensagens automáticas. Este controle não autoriza um modelo ou provider específico por si só; valide a integração de desenvolvimento descrita no checkpoint.

## Produção

Não aplique os comandos locais nem o seed em produção. Configure HTTPS na mesma origem, CSP e headers no proxy, Auth sem cadastro público, redirects exatos, SMTP, backups, retenção, rotação de segredos e MFA para operadores de plataforma. Não registre cookies, Authorization, tokens de convite, query strings de callback, telefones, e-mails ou corpos de mensagens.

Uma chave administrativa que tenha sido compartilhada fora do cofre deve ser rotacionada no Supabase e substituída diretamente no ambiente. Não a reenvie em chat, commit ou log.
