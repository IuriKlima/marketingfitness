# Pausa, rotação e revogação de canal

**Pausar** muda o canal para `paused` sem devolver credenciais ao browser. **Retomar** executa diagnóstico antes de marcar `active`; falha deixa `degraded`. Use pausa para manutenção curta.

Para rotacionar a API key, conecte uma nova credencial/instância validada, confirme o fluxo em desenvolvimento e revogue a conexão anterior. Não copie segredos entre linhas nem registre os valores em tickets.

**Revogar** é definitivo para a conexão: a RPC revalida administrador/grant `read_write`, muda o estado para `revoked`, remove as referências e apaga ambos os segredos do Vault, além de criar auditoria. O endpoint de webhook deixa de aceitar eventos porque só conexões não revogadas expõem segredo em runtime.

Se uma credencial vazar, revogue primeiro no provider e no Vault, depois investigue auditoria e webhooks recebidos. Trocar apenas o token opaco de URL não substitui a rotação da API key.
