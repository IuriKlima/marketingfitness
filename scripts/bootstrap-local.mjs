import { createClient } from '@supabase/supabase-js';
import { spawnSync } from 'node:child_process';

// Explicit developer command, restricted to this project's local Auth and Docker database.
if (process.env.SUPABASE_URL!=='http://127.0.0.1:54321' || process.env.APP_ORIGIN!=='http://127.0.0.1:5173' || process.env.NODE_ENV==='production') {
  console.error('Bootstrap permitido somente no ambiente local padrão.');process.exit(1);
}
try {
  if(!process.env.SUPABASE_SECRET_KEY) throw new Error();
  const client=createClient(process.env.SUPABASE_URL,process.env.SUPABASE_SECRET_KEY,{auth:{persistSession:false,autoRefreshToken:false}});
  const {data,error}=await client.auth.admin.inviteUserByEmail('platform-admin@example.test',{
    redirectTo:'http://127.0.0.1:5173/invite?bootstrap=true'
  });
  if(error || !data.user || !/^[a-f0-9-]{36}$/i.test(data.user.id)) throw new Error();
  const result=spawnSync('docker',['exec','-i','supabase_db_acadeai','psql','-U','postgres','-d','postgres','-v','ON_ERROR_STOP=1'],{
    input:"insert into private.platform_roles(user_id,role) values ('"+data.user.id+"','supreme') on conflict do nothing;",encoding:'utf8'
  });
  if(result.status!==0) throw new Error();
  console.log('Administrador fictício criado. Abra o convite no Mailpit local: http://127.0.0.1:54324');
} catch {
  console.error('Bootstrap não concluído. Confira o Auth local, o Docker e se o usuário fictício já existe. Nenhuma credencial foi exibida.');
  process.exitCode=1;
}
