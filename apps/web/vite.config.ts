import { defineConfig, loadEnv } from 'vite';
export default defineConfig(({mode})=>{
 const env=loadEnv(mode,process.cwd(),'VITE_');
 const allowed=new Set(['VITE_SUPABASE_URL','VITE_SUPABASE_PUBLISHABLE_KEY']);
 for(const name of Object.keys({...process.env,...env})) {
  if(name.startsWith('VITE_') && !allowed.has(name)) throw new Error(`Unapproved browser variable: ${name}`);
 }
 const key=env.VITE_SUPABASE_PUBLISHABLE_KEY ?? process.env.VITE_SUPABASE_PUBLISHABLE_KEY;
 if(key && (!key.startsWith('sb_publishable_') || key.includes('example'))) throw new Error('Only real publishable keys may be bundled');
 return {};
});
