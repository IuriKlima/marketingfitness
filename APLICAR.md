# AcadeAI — Prompt 2

Este pacote contém somente os arquivos novos ou alterados da fase 2. Ele deve ser
aplicado sobre a raiz do repositório Marketing Fitness.

## Aplicação

1. Crie uma branch a partir da main:

       git switch -c codex/prompt-2-identity-onboarding

2. Copie o conteúdo deste pacote para a raiz do repositório, permitindo substituir
   os arquivos correspondentes.
3. Não copie arquivos .env reais e não versione credenciais.
4. Configure localmente as variáveis descritas em .env.example.
5. Execute:

       npm ci
       npm run lint
       npm run typecheck
       npm test
       npm run build
       npm run secrets:check
       npm run db:start
       npm run db:reset
       npm run db:test
       npm run db:lint
       npm run db:types

6. Revise docs/progress/phase-2-identity-onboarding.md antes do merge.

## Importante

- SUPABASE_SECRET_KEY e SESSION_CONTEXT_SECRET são exclusivamente server-side.
- Em produção, frontend e /api devem usar a mesma origem HTTPS.
- O cadastro público deve permanecer desativado no Supabase Auth.
- Configure os templates de convite e recuperação descritos no checkpoint.
- Não aplique migrações destrutivas em produção sem backup e plano de rollback.
