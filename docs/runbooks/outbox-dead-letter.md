# Outbox, retries e dead-letter

O worker chama `claim_outbox` com identidade e lease. O PostgreSQL usa `FOR UPDATE SKIP LOCKED`; dois workers não recebem a mesma linha durante o lease. Cada tentativa incrementa `attempts`. Falhas recebem somente um código estável e redigido, liberam o lease e usam backoff exponencial com jitter, limitado a uma hora.

Na décima falha, `failed_at` é preenchido. Essa linha é a dead-letter e deixa de ser elegível. Investigue o provider e os metadados redigidos, corrija a causa e crie uma nova operação idempotente; não zere tentativas silenciosamente. Preserve o `correlation_id` na investigação.

Envio de mensagem consulta antes os eventos `accepted`, `sent`, `delivered` ou `read`. Se a aceitação já foi persistida, o retry não chama o provider novamente. Existe uma janela inevitável se o processo cair depois da aceitação externa e antes do evento local; só um identificador idempotente aceito pelo provider pode fechar essa janela. Até a versão Evolution usada no desenvolvimento comprovar esse recurso, não declare entrega externa exatamente uma vez.

Falhas de uma organização ficam no job correspondente e não interrompem as demais, pois o lote usa resultados independentes. Health do processo informa `processing` e último código; não expõe payloads.
