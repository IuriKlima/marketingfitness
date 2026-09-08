import { spawnSync } from 'node:child_process';
import { mkdirSync, writeFileSync, renameSync } from 'node:fs';
const result = spawnSync(process.execPath,['node_modules/supabase/dist/supabase.js','gen','types','typescript','--local','--schema','public'],{encoding:'utf8'});
if (result.status !== 0 || !result.stdout?.includes('export type Database')) { console.error('Geração falhou: verifique o Supabase local.'); process.exit(1); }
mkdirSync('packages/database/src',{recursive:true});
writeFileSync('packages/database/src/database.types.ts.tmp', result.stdout);
renameSync('packages/database/src/database.types.ts.tmp','packages/database/src/database.types.ts');

