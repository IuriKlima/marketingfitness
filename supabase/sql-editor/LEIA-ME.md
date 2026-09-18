# Configurar o Supabase hospedado

Projeto desta configuracao: `aweehmmspdqdgxaayxaq`. O `.env` local usa a URL-base `https://aweehmmspdqdgxaayxaq.supabase.co`, sem `/rest/v1/`. Ele e `apps/web/.env.local` sao ignorados pelo Git. Nenhuma chave esta nos arquivos SQL.

## 1. Escolher um instalador

Abra o [SQL Editor do projeto](https://supabase.com/dashboard/project/aweehmmspdqdgxaayxaq/sql/new), selecione o papel `postgres` e execute o conteudo completo de **somente um** arquivo:

- **01_instalacao_completa.sql**: projeto novo, sem tabelas AcadeAI. Inclui as seis migracoes ate CRM, atendimento e IA.
- **02_atualizar_fase1.sql**: projeto que ja recebeu integralmente apenas `20260908000000_foundation.sql`. Inclui fases 2 e 3.
- **03_atualizar_fase2.sql**: projeto que ja recebeu integralmente as tres migracoes da fase 2. Inclui somente as tres migracoes da fase 3.

Nao execute os dois em sequencia. Cada arquivo usa uma unica transacao: um erro aborta suas alteracoes. Os instaladores detectam objetos existentes e interrompem execucoes indevidas; nao sao scripts para reaplicacao. Se houver uma instalacao parcial ou customizada, revise-a antes de executar. Eles nao apagam tabelas, contas nem historico. As policies de Storage do pacote sao substituidas dentro da mesma transacao para aplicar as restricoes novas.

Os arquivos sao gerados das fontes em `supabase/migrations` por `npm run sql:bundle`; o SHA256 de cada fonte normalizada para LF aparece no cabecalho da respectiva secao. Edite as migracoes e gere novamente, em vez de editar os instaladores. A execucao manual no SQL Editor nao registra as versoes no historico do Supabase CLI: antes de usar `supabase db push` nesse mesmo projeto, reconcilie o historico das migracoes que tiverem sido realmente aplicadas.

## 2. Conferir a instalacao

Execute **90_verificar.sql**. Todas as tabelas listadas devem existir com RLS ativo e sem acesso de `anon`. O catalogo deve ter 30 campos na versao 1; a coluna `revision` deve existir; os buckets devem ser privados. A verificacao separa RPCs administrativas exclusivas do backend das RPCs operacionais autenticadas.

Essa conferencia e estrutural e nao substitui os 106 testes pgTAP planejados. Nao execute scripts de reset nem o seed ficticio no projeto hospedado.

## 3. Configurar Authentication

No painel do mesmo projeto:

1. Em URL Configuration, defina **Site URL** como `http://127.0.0.1:5173` para o desenvolvimento local. Adicione `http://127.0.0.1:5173/**` aos redirects permitidos, somente para este ambiente de desenvolvimento.
2. Desative o cadastro publico (**Allow new users to sign up**). O app provisiona acesso por convite.
3. Em Email Templates, copie os modelos de `supabase/templates/invite.html` (Invite user), `magic-link.html` (Magic Link) e `recovery.html` (Reset Password). Os modelos usam `token_hash`; os callbacks do app verificam esse token.
4. Mantenha uma chave de assinatura de sessoes assimetrica **ES256 ou RS256** ativa. A verificacao remota desta tarefa encontrou ES256 disponivel no JWKS. As chaves legadas de API fornecidas nao sao tokens de sessao de usuario.

O `supabase/config.toml` so configura o Supabase local; ele nao altera estas opcoes do projeto hospedado. Na conferencia remota desta tarefa, o cadastro publico ainda estava habilitado.

Em producao, use a origem HTTPS real, redirects restritos e SMTP configurado para os destinatarios da aplicacao. O fluxo de desafio/exigencia de MFA da plataforma continua pendente antes de producao, conforme o checkpoint da fase 2.

## 4. Criar o primeiro acesso de plataforma

Em **Authentication > Users**, crie sua conta com seu e-mail, senha propria e e-mail confirmado. Copie o UUID dessa conta. Abra **99_primeiro_supremo.sql**, substitua o UUID zerado pelo UUID correto e execute o arquivo. O script recusa a execucao com placeholder, conta inexistente ou e-mail nao confirmado.

Entre em `http://127.0.0.1:5173/login` com o e-mail e a senha dessa conta. O papel `supreme` libera o painel de plataforma para provisionar academias e convidar os primeiros administradores. As chaves de API nao sao credenciais de login.

## 5. Ambiente local e chaves

A API agora aceita `SUPABASE_ANON_KEY` como alternativa legada quando `SUPABASE_PUBLISHABLE_KEY` nao esta definida. A configuracao rejeita chave com papel administrativo nesse campo, expiracao vencida ou referencia de outro projeto; o Supabase valida sua assinatura durante a conexao. A verificacao de sessoes de usuarios continua exigindo assinatura JWKS, issuer, audience e papel authenticated.

O `.env` contem as variaveis Supabase, `SESSION_CONTEXT_SECRET`, `APP_ORIGIN`, portas e, opcionalmente, `PUBLIC_WEBHOOK_BASE_URL` e as tres variaveis LLM. O frontend usa somente `VITE_API_BASE_URL=/api`; nenhuma chave e incorporada ao bundle.

Como a chave administrativa foi compartilhada na conversa, substitua-a no painel e atualize o `.env` diretamente, sem reenviar o segredo no chat. Prefira chaves modernas: preencha `SUPABASE_PUBLISHABLE_KEY` com a nova chave publicavel, remova `SUPABASE_ANON_KEY` e atualize `SUPABASE_SECRET_KEY` com uma nova chave secreta. Criar chaves modernas nao revoga as legadas: desative as antigas apos a substituicao. Veja a [documentacao oficial de chaves](https://supabase.com/docs/guides/getting-started/api-keys).

Depois de mudar o `.env`, reinicie `npm run dev:api`. Para iniciar manualmente, use terminais separados:

```sh
npm run dev:api
npm run dev:web
```

`http://127.0.0.1:3001/health` verifica o processo. `/ready` verifica JWKS e acesso ao catalogo do onboarding; so deve retornar 200 depois de aplicar o SQL corretamente. O desenvolvimento com este Supabase hospedado nao depende do Docker local.
