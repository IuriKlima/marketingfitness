# Checkpoint — fase 2: identidade, painéis e onboarding

Data: 2026-09-11. Branch: `codex/prompt-2-identity-onboarding`.

**Implementação local entregue; portão integrado ainda pendente. Não liberar produção nem considerar a fase 2 validada no banco.**

## Origem e auditoria

O pacote `marketingfitness-prompt2.zip` continha 23 arquivos não vazios, todos lidos: APLICAR.md, dois checkpoints, README, exemplos de ambiente, código de API/web/UI, migração e testes. O Git estava no commit d97e88fe7746c8ee99f204186f42ee874cf68a3a, sem alterações rastreadas; somente o ZIP era novo. Não havia AGENTS.md no projeto. Foram preservados o ZIP e a migração original da fase 1.

A branch solicitada no APLICAR.md foi criada. Os 23 arquivos foram aplicados e revisados. O ZIP foi adicionado ao ignore para preservar o material recebido sem incorporá-lo ao código publicável. Não houve commit, push, merge ou deploy nesta execução.

A API pública do GitHub confirmou o workflow [Foundation 34232399381](https://github.com/IuriKlima/marketingfitness/actions/runs/34232399381): commit exato d97e88f, status completed/success, jobs local, database e secrets aprovados. Foram conferidos os passos npm ci, testes, build, reset, pgTAP, lint do banco, geração de tipos e Gitleaks. Essa evidência libera o início do Prompt 2; não valida suas novas migrações.

## Plano realizado

1. Leitura integral do pacote e inventário da base.
2. Criação da branch e aplicação dos arquivos.
3. Correções de compatibilidade, autorização, fluxos de convite/revisão e autosave.
4. Testes Node, build, verificação visual e varredura de credenciais.
5. Preparação do ambiente local e atualização da documentação.
6. Tentativa dos comandos Supabase: bloqueada pelo engine Docker Linux.

## Entregas

- Sessão BFF com cookies HttpOnly para access/refresh, host-only, prefixo __Host- e Secure em produção, Origin estrito e CSRF double-submit.
- Login, logout inclusive sem access cookie, refresh, recuperação, callbacks de convite/magic link e troca de senha.
- Contexto assinado, vinculado ao usuário e revalidado contra contexto autorizado e identidade do Auth.
- Painel Supremo de provisionamento, convites e fila/detalhe/revisão de onboarding. Painel da academia com seleção de unidade, convites e formulário.
- Onboarding por definições de dados, validação na API e no banco, autosave serializado, cancelamento ao sair, controle otimista por revision e bloqueio de versões enviadas/finais.
- Devolução com campos pendentes; próxima gravação cria nova versão. Aprovação cria academy_facts e auditoria dentro da mesma transação.
- Storage privado com metadados vinculados por empresa/unidade/versão. Upload por BFF e RLS do usuário; download administrativo exige RPC autorizada/auditada.
- Interface responsiva, tema claro/escuro, foco visível, redução de movimento/transparência e contraste corrigido no botão principal.
- Templates locais de convite, magic link para conta existente e recuperação; Mailpit local habilitado.
- Setup local sem exibição de credenciais, bootstrap de usuário supremo fictício restrito ao loopback/container do projeto e preparação idempotente de chave ES256 local ignorada pelo Git.

## Correções necessárias sobre o ZIP

- Classes de erro do backend tinham propriedades de parâmetro, incompatíveis com o strip-types do Node. Foram substituídas por campos explícitos.
- A interface apresentava erros de nulabilidade/tipagem de eventos e iteração de NodeList; foram corrigidos.
- Cliente Supabase Auth público era compartilhado entre requisições. Agora cada requisição recebe instância própria, evitando reutilização de sessão em memória.
- Troca de senha usava updateUser sem sessão interna. Agora chama Auth com o JWT do próprio usuário, preservando espaços da senha.
- Contexto assinado não tinha vínculo ao usuário; foi acrescentado userId e rejeição de contexto de outro usuário.
- O callback de convite não verificava OTP e contas existentes precisavam do tipo email. Ambos os caminhos agora são tratados, retirando o token_hash da URL antes da chamada.
- O Supremo não conseguia convidar a primeira pessoa sem membership. Convites administrativos usam alvo explícito com ator verificado e nova autorização na RPC.
- As telas de convite e revisão faltavam apesar de descritas no checkpoint. Foram implementadas.
- Revisão podia operar sobre empresa suspensa; uma checagem dentro da transação impede isso. A aprovação agora produz os fatos confirmados.
- O CASE de status precisava de cast para o enum do banco.
- Aceitar convite sobrescrevia all_units. Agora preserva escopo acumulado, confere e-mail do usuário real e revalida o alcance atual do convidante.
- Submissão validava somente presença superficial na API. Agora rejeita tipos, números fora de faixa, escolhas inválidas, whitespace e listas obrigatórias vazias; banco repete a validação para impedir bypass pelo PostgREST.
- Definições de schema em uso não podem ser alteradas ou ampliadas silenciosamente.
- URLs de upload assinadas com privilégio de backend continuariam válidas após fechar o documento. Foram substituídas por upload BFF sob RLS com checagem de estado e vínculo dos metadados, incluindo lock da versão no acesso de escrita ao objeto.
- Erro de autosave era absorvido e o envio podia prosseguir. Agora a falha interrompe a submissão; revision e contexto esperado protegem contra sobrescrita e troca de unidade.
- README ainda descrevia ausência de remoto, rotas e credenciais administrativas. Foi reescrito para o comportamento atual.

## Decisões e limites

Mantidos npm workspaces, Node 24, Vite, HTTP nativo e versões fixas existentes. Adicionado apenas o manifesto de packages/ui, com atualização do lockfile. Não há CRM, calendário de negócio, integrações de marketing ou consumidor da outbox.

`onboarding_field_definitions` é catálogo global versionado, portanto não recebe organization_id. Documentos continuam snapshots por unidade, como no pacote; campos marcados organization são capturados nesses snapshots. Não foi introduzido outro documento compartilhado por organização.

Supreme não ganha acesso operacional por RLS. A revisão usa RPCs exclusivas de service_role, que verificam novamente o ator e registram auditoria. Suporte depende de grant ativo; revisão exige read_write. Não foi criado endpoint de autoelevação ou concessão pública.

A terceira migração concentra o endurecimento adicional e preserva a primeira migração. A constraint de path é NOT VALID para não destruir possíveis registros legados; ela já se aplica a novos registros. Em instalação existente com metadados antigos, revisar e migrar paths antes de validá-la integralmente. Não há remoção de histórico nem down destrutivo automático.

## Componentes

```text
Web -> /api mesma origem -> API BFF
   cookies HttpOnly + Origin + CSRF
API -> JWKS + Auth -> identidade e contexto autorizados
API usuário -> PostgREST/Storage -> RLS por organização/unidade
API administração -> RPC service-only -> ator + status/grant + auditoria
Worker -> OutboxPort (somente contrato)
PostgreSQL public com RLS | private.platform_roles | private.outbox
```

## Arquivos criados/alterados

- API: apps/api/src/index.ts, handlers.ts, security.ts, config.ts, supabase.ts.
- Web/UI: apps/web/src/main.ts, api.ts, styles.css, index.html, vite.config.ts, .env.example; packages/ui/package.json e src/primitives.ts/tokens.css.
- Contratos: packages/contracts/src/onboarding.ts.
- Banco: supabase/config.toml; migrations/20260911000000_identity_onboarding.sql e 20260911001000_identity_hardening.sql; tests/002_identity_onboarding.test.sql e 003_identity_hardening.test.sql.
- Templates: supabase/templates/invite.html, magic-link.html, recovery.html.
- Testes: tests/health.test.ts, security.test.ts, runtime-config.test.ts, api-security.test.ts, onboarding-validation.test.ts. Os testes anteriores permanecem.
- Ferramentas: scripts/setup-local.mjs, bootstrap-local.mjs, init-local-signing.mjs e check-secrets.mjs.
- Configuração/documentação: package.json, package-lock.json, .gitignore, .env.example, README.md, APLICAR.md e checkpoints 1/2.

## Resultados reais

### Local sem Supabase

- npm ci inicial: passou. Depois de registrar packages/ui, o lockfile foi atualizado. A primeira reinstalação coincidiu com a prévia Vite e encontrou EPERM em seu binding nativo; a prévia foi encerrada. A repetição de npm ci passou: 133 pacotes instalados, 141 auditados, zero vulnerabilidades conhecidas.
- npm run typecheck: passou após corrigir os erros existentes no ZIP.
- npm run lint: passou.
- npm test: 13 testes passaram, zero falhas.
- npm run build: passou. O bundle não contém cliente administrativo; o frontend usa o BFF.
- npm run secrets:check: passou; varredura heurística local, inclusive do bundle, não substitui Gitleaks.
- Navegador real: login renderizado em desktop e em viewport 390×844; link de recuperação funcionou; não foram observados erros/warnings no console nessas telas. Não houve login real, recuperação enviada nem troca de senha de pessoa real.
- Git diff --check e conferência de arquivos ignorados foram executados; o ZIP permanece preservado.

Os testes Node cobrem JWT com assinatura real e rejeições, configuração sem vazamento de valores, restrições de bundle, cookies/contexto, Origin/CSRF, rejeição de contexto assinado para outro usuário, troca de senha com token do usuário, entradas inválidas, validação de campos, health/readiness e worker sem processamento. O upstream Supabase no teste BFF é simulado em loopback; isso não é prova integrada de Auth.

### Banco local

- docker version: engine Linux indisponível. Docker Desktop foi iniciado, mas o pipe dockerDesktopLinuxEngine não apareceu.
- npm run db:start: falhou com LegacyDockerLifecycleInspectError, engine ausente.
- npm run db:reset: falhou com LegacyLocalDbRunningError.
- npm run db:test e npm run db:lint: falharam por ECONNREFUSED em 127.0.0.1:54322.
- npm run db:types: falhou de forma controlada. Nenhum tipo manual ou tipo vazio foi criado.
- 64 asserções pgTAP estão preparadas: 26 da fundação, 26 do pacote e 12 adicionais. **Não foram executadas nesta fase.**
- O SQL novo recebeu revisão textual, mas não validação sintática/comportamental pelo PostgreSQL nesta sessão.

### Remoto

- CI da fase 1: aprovado e conferido via API do GitHub.
- CI da branch do Prompt 2, Gitleaks dessa branch, Supabase Advisors e integração Auth/Storage/e-mails: **não executados**.
- Nenhuma configuração, e-mail, alteração de banco ou implantação em produção foi realizada.

## Configurar e retomar

O README contém a sequência completa. Com Docker Linux disponível:

```sh
npm ci
npm run db:start
npm run db:reset
npm run db:test
npm run db:lint
npm run db:types
npm run setup:local
npm run bootstrap:local
```

Execute bootstrap apenas em um banco local novo. Abra o convite fictício no Mailpit, defina a senha e use a aplicação. Os helpers setup/bootstrap estão implementados, mas o caminho integrado de sucesso depende do Supabase e não foi executado. Não copie .env, signing_keys.json ou saídas privadas para Git/logs.

Antes de merge: executar a suíte de banco, corrigir eventuais falhas sem enfraquecer RLS, gerar/revisar os tipos e executar o CI da branch. Validar de ponta a ponta convite de usuário novo/existente, expiração/replay, login/refresh/logout, recuperação, roles/unidades, autosave concorrente, upload antes/depois do envio e revisão/fatos/auditoria.

Antes de produção: HTTPS na mesma origem; templates e redirects exatos no Auth; segredos em cofre; cadastro público desativado; configurações de senha/rate limit/MFA para plataforma. O pacote não trouxe tela de desafio MFA e ela não foi implementada; esse fluxo e sua exigência são uma pendência de produção. Configurar cabeçalhos de segurança e redigir/suprimir dados de autenticação e query strings de callbacks nos logs do proxy.

## Portão

**NÃO PRONTO PARA A PRÓXIMA FASE COMO VALIDAÇÃO INTEGRADA.** Código, testes locais e interface pública estão implementados/verificados; faltam o banco real, tipos gerados e fluxos integrados. O bloqueio local é a indisponibilidade do Docker, e a nova branch ainda não foi publicada para obter validação equivalente no CI.

## Continuação: ambiente hospedado e SQL Editor

Por solicitação posterior do usuário, foi configurado o `.env` local para o projeto Supabase informado e gerado um segredo de contexto com 32 bytes aleatórios. Os arquivos `.env` e `apps/web/.env.local` estão ignorados pelo Git. As credenciais fornecidas não foram copiadas para SQL, código, documentação ou bundle.

A API aceita agora `SUPABASE_ANON_KEY` como alternativa legada apenas quando não há `SUPABASE_PUBLISHABLE_KEY`. A configuração rejeita papel administrativo, referência de outro projeto, expiração vencida e formato inválido nesse campo. Isso classifica a configuração, sem substituir a validação de assinatura pelo Supabase. A validação de JWTs de usuários em JWKS permanece intacta.

`npm run sql:bundle` gera instalador completo e instalador de atualização da fase 1 a partir das migrações existentes. Cada instalador usa preflight e uma única transação. `supabase/sql-editor` inclui verificação estrutural somente de leitura, bootstrap opcional de supreme com UUID explícito e guia do Auth. Nenhum SQL foi executado no projeto hospedado nesta tarefa.

Verificações remotas somente por leitura: Auth settings HTTP 200, JWKS HTTP 200 com ES256; consultas sem registros a organizations, organization_invitations e onboarding_field_definitions retornaram HTTP 404/PGRST205 (objetos não encontrados no cache da API). Cadastro público ainda habilitado; desativação e templates/redirects foram documentados como passos no painel. A chave administrativa compartilhada deve ser substituída, atualizando o `.env` diretamente; não foi rotacionada automaticamente.

API iniciada com a configuração hospedada. Interface `/login`, API `/health` e proxy `/api/health` responderam HTTP 200. `/ready` respondeu 503 enquanto o schema permanece pendente. O uso desse projeto hospedado dispensa Docker para iniciar o app, mas ainda exige aplicação do SQL e configuração do Auth para concluir login e fluxos integrados.

Após a compatibilidade de configuração: lint, typecheck, 14 testes Node, build e varredura heurística de credenciais passaram. Os 64 testes pgTAP, execução das novas migrações, tipos e fluxos autenticados continuam pendentes. Sem novo commit, push, merge ou deploy.
