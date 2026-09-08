import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { generateKeyPair, exportJWK, SignJWT } from 'jose';
import { verifier } from '../apps/api/src/auth.ts';
test('JWKS validates signature, issuer, audience, expiry and user role', async () => {
 const {publicKey,privateKey} = await generateKeyPair('ES256');
 const jwk = {...await exportJWK(publicKey),kid:'test-key',alg:'ES256',use:'sig'};
 const server = createServer((_req,res)=>{ res.setHeader('Content-Type','application/json'); res.end(JSON.stringify({keys:[jwk]})); });
 await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
 const address = server.address();
 assert.ok(address && typeof address!=='string');
 const issuer=`http://127.0.0.1:${address.port}/auth/v1`;
 const verify=verifier(issuer,new URL(`${issuer}/.well-known/jwks.json`));
 const sign = (iss=issuer,aud='authenticated',exp='2m',role='authenticated')=> new SignJWT({role}).setProtectedHeader({alg:'ES256',kid:'test-key'}).setIssuedAt().setSubject('fictitious-user').setIssuer(iss).setAudience(aud).setExpirationTime(exp).sign(privateKey);
 try {
  assert.deepEqual(await verify(`Bearer ${await sign()}`),{userId:'fictitious-user'});
  await assert.rejects(()=>verify(undefined));
  for (const token of [await sign('https://invalid.example'),await sign(issuer,'other'),await sign(issuer,'authenticated','-1h'),await sign(issuer,'authenticated','2m','service_role')]) await assert.rejects(()=>verify(`Bearer ${token}`));
  const other = await generateKeyPair('ES256');
  const forged = await new SignJWT({role:'authenticated'}).setProtectedHeader({alg:'ES256',kid:'test-key'}).setIssuedAt().setSubject('fictitious-user').setIssuer(issuer).setAudience('authenticated').setExpirationTime('2m').sign(other.privateKey);
  await assert.rejects(()=>verify(`Bearer ${forged}`));
 } finally { await new Promise<void>((resolve,reject)=>server.close(error=>error?reject(error):resolve())); }
});

