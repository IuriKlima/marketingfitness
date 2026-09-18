# Checkpoint — fase 3: CRM, atendimento e IA

Data: 2026-09-18. Branch: `codex/prompt-3-crm-inbox-ai`.

**NÃO PRONTO PARA O PROMPT 4.** O código da fatia foi implementado e as verificações Node passam, mas a integração real Evolution/LLM e a validação integrada desta fase ainda precisam de evidência no commit final.

## Portão da fase 2

O script `scripts/init-local-signing.mjs` passou a gerar `alg: ES256`, `use: sig` e `key_ops: [sign]`. Arquivos locais legados recebem apenas correção desses metadados; a chave privada é preservada e nunca impressa. O commit `bbe7a83` passou no workflow [35141708000](https://github.com/IuriKlima/marketingfitness/actions/runs/35141708000): jobs local, database e secrets concluídos com sucesso, incluindo instalação, reset, 64 asserções pgTAP, lint do banco, tipos e novo typecheck.

## Implementado

- Schema CRM para contatos multiunidade, identificadores normalizados/deduplicados, consentimentos, tags, pipelines, etapas, oportunidades, histórico, notas, atividades, tarefas e agenda.
- RPCs transacionais e idempotentes para contato, oportunidade, movimentação e resultado de visita. Histórico e consentimento são append-only.
- Canais, filas, conversas, participantes, mensagens imutáveis, anexos, eventos de entrega e histórico de atribuição, com RLS por capacidade.
- Takeover concorrente com lock/lease e devolução explícita. Trigger bloqueia IA quando uma pessoa assumiu e quando não existe consentimento válido.
- Webhook opaco por conexão, segredo no Vault, HMAC quando disponível, compatibilidade por header secreto, limite, schema, janela temporal, hash, deduplicação e enqueue rápido.
- Worker real com `FOR UPDATE SKIP LOCKED`, lease, tentativas, backoff, jitter, dead-letter, correlation ID e isolamento de falha por job.
- Adapter Evolution para health, webhook, envio e eventos de entrega. Instagram e TikTok usam adapter de produção `unconfigured`, que nunca confirma envio.
- Proteção de download contra SSRF/redes privadas/metadata, redirects fora da origem, tamanho, MIME permitido e divergência entre header e magic bytes.
- Configuração de IA por unidade, fontes/documentos/versões/chunks, busca lexical, aprovação explícita, runs, ferramentas, uso, orçamento, loop limit e circuit breaker.
- Simulação OpenAI-compatible restrita a `academy_facts` e versões aprovadas; falta de fonte e prompt injection resultam em transferência, sem gravar raciocínio interno.
- Privacidade com consentimento, opt-out, retenção, solicitação, exportação e anonimização controlada, preservando trilhas.
- Frontend modular em `phase3.ts`: páginas pedidas, skeleton, estados vazios/erro/sucesso, busca, filtros básicos, paginação contratual, Kanban/tabela, atendimento responsivo, canais, IA, conhecimento e filas.
- Tokens/componentes reutilizáveis em `packages/ui`, temas claro/escuro, foco visível, redução de movimento/transparência e fallback sem blur.
- Instaladores SQL gerados, verificação estrutural, seed opcional fictício, matriz de acesso e runbooks.

## Testes preparados

- Node: normalização/validação, prompt injection, allowlist, adapter Evolution, URLs/SSRF/MIME, worker concorrente e retry, além das suites anteriores.
- pgTAP fase 3: 43 asserções para papéis/tenants, suspensão, deduplicação, funil, histórico, agenda, takeover, opt-out, webhook, worker, dead-letter, conhecimento e PII de visualizador.
- O conjunto das quatro suites de banco passa a planejar 107 asserções.

## Resultados locais atuais

- `npm test`: 21 testes, 21 aprovados.
- `npm run build`: aprovado; bundle web gerado.
- `npm run secrets:check`: aprovado pela verificação heurística.
- `npm run lint`: aprovado após corrigir imports e parâmetros sem uso identificados pela primeira execução.
- `npm run typecheck`: aprovado após corrigir dois fallbacks tipados como `unknown` e a assinatura do adapter não configurado.
- `npm run sql:bundle`: três instaladores gerados sem credenciais.

Docker Linux continua indisponível nesta máquina, portanto `db:start`, reset, pgTAP, lint e tipos desta fase dependem da CI. Nenhuma migration ou seed desta fase foi aplicado no Supabase hospedado e não houve deploy.

## Limitações e riscos abertos

- Não existe uma instância Evolution de desenvolvimento autorizada nesta tarefa. Health, envio, recebimento, entrega, assinatura oferecida pela versão instalada e revogação precisam de teste real com mensagens fictícias.
- Exatamente uma vez através de um provider externo não pode ser garantido na janela entre aceitação externa e persistência local sem idempotência comprovada pelo provider. O worker evita reenvio depois que a aceitação já foi persistida.
- O caminho de anexos externos possui o downloader seguro, bucket e metadados, mas o mapeamento de mídia de uma versão Evolution real ainda não foi conectado e validado.
- A IA está disponível apenas para simulação controlada. Não há provider LLM configurado nem execução automática de ferramentas no worker; ferramentas permanecem contratos allow-listed.
- O frontend não abriu uma sessão autenticada real desta fase nem recebeu eventos realtime. A atualização atual é por navegação/requisição e está limitada ao tenant pelo BFF/RLS.
- O arquivo de tipos só pode ser atualizado depois que a migration passar em PostgreSQL real.

Esses itens impedem a declaração `PRONTO PARA O PROMPT 4`, mesmo que a CI estrutural fique verde.
