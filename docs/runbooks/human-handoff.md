# Handoff entre IA e pessoa

Estados válidos: `ai_active`, `waiting_human`, `human_active`, `paused` e `closed`.

1. O atendente escolhe **Assumir** e informa o motivo. A RPC bloqueia a conversa, confere escopo e cria lease de 15 minutos.
2. Se outro atendente já possui lease vigente, a RPC devolve conflito; a interface não substitui o responsável silenciosamente.
3. O estado muda para `human_active` e o trigger recusa imediatamente novas mensagens de autor IA.
4. O atendente só envia enquanto possui o lease. A mensagem fica `pending` até o worker obter aceitação do provider.
5. **Devolver à IA** é uma ação explícita. Somente o responsável ou um administrador pode fazê-la; o histórico registra ator, estado anterior, destino e motivo.

Em incidente, não altere `assigned_to` diretamente. Verifique o histórico append-only e o correlation ID. Um lease expirado pode ser adquirido por outro atendente pela mesma RPC. Para impedir automação durante análise, use `paused` e mantenha consentimento e configuração intactos.
