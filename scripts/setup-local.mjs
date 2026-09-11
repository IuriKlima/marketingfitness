import { existsSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';

if (existsSync('.env') || existsSync('apps/web/.env.local')) {
  console.error('Configuração existente preservada. Ajuste manualmente somente as variáveis necessárias.');
  process.exit(1);
}
const result=spawnSync(process.execPath,['node_modules/supabase/dist/supabase.js','status','--output','json'],{encoding:'utf8'});
try {
  if(result.status!==0) throw new Error();
  const config=JSON.parse(result.stdout);
  if(config.API_URL!=='http://127.0.0.1:54321' || !config.PUBLISHABLE_KEY?.startsWith('sb_publishable_') || !config.SECRET_KEY) throw new Error();
  writeFileSync('.env',[
    'SUPABASE_URL='+config.API_URL,'SUPABASE_JWT_ISSUER='+config.API_URL+'/auth/v1',
    'SUPABASE_PUBLISHABLE_KEY='+config.PUBLISHABLE_KEY,'SUPABASE_SECRET_KEY='+config.SECRET_KEY,
    'SESSION_CONTEXT_SECRET='+randomBytes(32).toString('base64url'),'APP_ORIGIN=http://127.0.0.1:5173','API_PORT=3001','WORKER_PORT=3002',''
  ].join('\n'),{flag:'wx',mode:0o600});
  writeFileSync('apps/web/.env.local',[
    'VITE_SUPABASE_URL='+config.API_URL,'VITE_SUPABASE_PUBLISHABLE_KEY='+config.PUBLISHABLE_KEY,'VITE_API_BASE_URL=/api',''
  ].join('\n'),{flag:'wx',mode:0o600});
  console.log('Configuração local criada. Nenhuma credencial foi exibida.');
} catch {
  console.error('Configuração local indisponível. Inicie o Supabase local com chaves publicáveis modernas; arquivos existentes são preservados.');
  process.exitCode=1;
}
