# Matriz de acesso operacional

O banco nega por padrão. Toda decisão combina usuário autenticado, organização ativa, membership ou grant vigente, unidade e capacidade solicitada. `organization_id` e `unit_id` recebidos do navegador nunca bastam.

| Capacidade | Supremo | Suporte | Admin da academia | Atendente | Marketing | Visualizador |
| --- | --- | --- | --- | --- | --- | --- |
| Administrar plataforma | Sim | Leitura operacional da plataforma | Não | Não | Não | Não |
| Ver PII do CRM | Não implícito | Só com grant vigente | Unidades autorizadas | Unidades autorizadas | Não | Não |
| Alterar CRM, tarefas e agenda | Não implícito | Grant `read_write` | Sim | Sim | Não | Não |
| Ler atribuição/campanha | Não implícito | Grant vigente | Sim | Sim | Sim | Somente agregados |
| Ler e responder conversas | Não implícito | Grant `read_write` | Sim | Sim | Não | Não |
| Assumir/devolver conversa | Não implícito | Grant `read_write` | Sim | Sim | Não | Não |
| Configurar canais, filas e IA | Não implícito | Grant `read_write` | Sim | Não | Não | Não |
| Ver métricas agregadas | Não implícito | Grant vigente | Sim | Sim | Sim | Sim |

O papel Supremo não atravessa RLS operacional. Suporte precisa de `support_access_grants` com justificativa, janela máxima, modo e revogação. Organização suspensa falha antes da avaliação do papel. Segredos de canal não possuem grants de tabela para o navegador; somente RPCs exclusivas de `service_role` acessam o Vault após revalidar o ator.

As capacidades centrais estão em `private.crm_can_actor` e `private.crm_can`. Operações administrativas chamadas pelo BFF usam `public.crm_authorize` ou uma RPC específica que repete a autorização dentro da transação. Visualizadores recebem `crm_dashboard` e `crm_attribution_summary`, sem linhas de contatos ou mensagens.
