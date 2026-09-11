import { existsSync, mkdirSync, writeFileSync } from 'node:fs';
import { generateKeyPairSync, randomUUID } from 'node:crypto';

const path='supabase/.local/signing_keys.json';
if (!existsSync(path)) {
  mkdirSync('supabase/.local',{recursive:true});
  const {privateKey}=generateKeyPairSync('ec',{namedCurve:'P-256'});
  const key={...privateKey.export({format:'jwk'}),kid:randomUUID(),alg:'ES256',use:'sig'};
  writeFileSync(path,JSON.stringify([key]),{flag:'wx',mode:0o600});
  console.log('Assinatura ES256 local preparada em arquivo ignorado pelo Git.');
}
