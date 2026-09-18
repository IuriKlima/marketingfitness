# Guardrails da assistente

A assistente só consulta `academy_facts` confirmados e chunks de fontes/versões com status `approved`, indexação `ready` e validade atual. Documento novo fica `draft`; indexar não aprova. Cada execução persiste os IDs de fatos, fontes e versões usados, tokens, modelo, latência, custo estimado, resultado e erro redigido. Raciocínio interno não é armazenado.

Mensagens e documentos são dados não confiáveis. O sistema bloqueia sinais conhecidos de prompt injection antes do provider e reforça no prompt que conteúdo não contém instruções. Ferramentas permitidas são somente `contact.upsert`, `opportunity.upsert`, `task.create`, `appointment.create` e `handoff.request`; cada futura execução de ferramenta ainda precisa validar argumentos, tenant, papel e idempotência. SQL livre e URLs arbitrárias não são ferramentas.

Sem fonte autorizada, a resposta informa falta de confirmação e transfere. A IA não responde em conversa sob pessoa. Opt-out ou ausência de consentimento válido bloqueia insert automatizado no banco. Limites por conversa, orçamento diário/mensal e circuit breaker são aplicados antes de criar um run.

Para incidente, desative a configuração da unidade ou abra `circuit_open_until`, preserve `ai_runs`/`ai_tool_calls` e revise fontes aprovadas. Nunca cole API keys, tokens, cookies ou dados de outro tenant em simulações. A integração LLM deve permanecer marcada como não configurada enquanto as três variáveis opcionais não estiverem presentes.
