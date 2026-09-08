import { readdirSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
const patterns = [/sb_secret_[A-Za-z0-9_-]{16,}/, /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/, /(?:postgres(?:ql)?:\/\/)[^\s:]+:[^\s@]+@/, /eyJ[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}\.[A-Za-z0-9_-]{20,}/];
let failed = false;
function scan(dir) {
 for (const entry of readdirSync(dir,{withFileTypes:true})) {
  if (['node_modules','.git','.env','.temp','.branches'].includes(entry.name) || (entry.name.startsWith('.env.') && entry.name!=='.env.example')) continue;
  const path=join(dir,entry.name);
  if (entry.isDirectory()) scan(path);
  else if (patterns.some(p=>p.test(readFileSync(path,'utf8')))) { console.error(`Potential credential: ${path}`); failed=true; }
 }
}
scan('.');
if(failed) process.exit(1);
console.log('No matching credential patterns found (heuristic; CI also uses Gitleaks).');
