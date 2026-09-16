import { existsSync, mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import { generateKeyPairSync, randomUUID } from 'node:crypto';

const path='supabase/.local/signing_keys.json';
if (!existsSync(path)) {
  mkdirSync('supabase/.local',{recursive:true});
  const {privateKey}=generateKeyPairSync('ec',{namedCurve:'P-256'});
  const key={...privateKey.export({format:'jwk'}),kid:randomUUID(),alg:'ES256',use:'sig',key_ops:['sign']};
  writeFileSync(path,JSON.stringify([key]),{flag:'wx',mode:0o600});
  console.log('Assinatura ES256 local preparada em arquivo ignorado pelo Git.');
} else {
  // Repair metadata only. Never rotate or print existing private key material.
  const current=JSON.parse(readFileSync(path,'utf8'));
  if (!Array.isArray(current) || !current.length) throw new Error('Arquivo de assinatura local inválido');
  const normalized=current.map(key => ({...key,use:'sig',key_ops:['sign']}));
  if (JSON.stringify(current)!==JSON.stringify(normalized)) {
    writeFileSync(path,JSON.stringify(normalized),{mode:0o600});
    console.log('Metadados da assinatura ES256 local reparados sem trocar a chave.');
  }
}
