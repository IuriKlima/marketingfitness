# Evolution API e webhook

## Pré-requisitos

- Instância Evolution API de desenvolvimento acessível por HTTPS. HTTP é aceito somente para `localhost`/`127.0.0.1` fora de produção.
- `PUBLIC_WEBHOOK_BASE_URL` público e HTTPS apontando para a origem da API.
- API key da instância. Informe-a apenas no formulário autenticado de Canais; ela segue ao BFF e é gravada no Supabase Vault.

Ao conectar, o BFF cria um caminho opaco, um segredo próprio por conexão e solicita os eventos `MESSAGES_UPSERT`, `MESSAGES_UPDATE` e `CONNECTION_UPDATE`. O browser recebe apenas status e health redigidos. O domínio converte o payload pelo `WhatsAppProvider`; não persiste o formato bruto em tabelas públicas.

O endpoint aceita HMAC SHA-256 em `x-acadeai-signature`, calculado sobre `<timestamp>.<corpo>`, com `x-acadeai-timestamp` dentro de cinco minutos. Como compatibilidade inicial com Evolution, também aceita o segredo estático em `x-acadeai-webhook-secret`. Nesse caminho, o token opaco e a constraint única de evento protegem contra replay; prefira HMAC quando a versão instalada suportar headers e assinatura.

O webhook limita o corpo, valida schema e data, registra o hash e responde `202` depois de enfileirar. Repetições retornam `duplicate:true` e não criam outro job. Não registre URL completa, headers, telefone ou corpo de mensagem no proxy.

Para diagnosticar, confira `/health`, o estado redigido em Canais e o worker. `active` exige resposta do endpoint de estado da instância; falhas deixam `degraded`, nunca “conectado” por simulação. A integração real só está aprovada depois de enviar e receber uma mensagem fictícia em ambiente de desenvolvimento e observar os eventos de entrega.
