import { test } from 'node:test';
import assert from 'node:assert/strict';
import { port, serverConfig } from '../packages/config/src/server.ts';
import { validatePublicKey } from '../packages/config/src/public.ts';
test('rejects missing config, insecure remote URL and issuer substitution',()=>{
  assert.throws(()=>serverConfig({}));
  assert.throws(()=>serverConfig({SUPABASE_URL:'http://example.com'}));
  assert.throws(()=>serverConfig({SUPABASE_URL:'https://example.com',SUPABASE_JWT_ISSUER:'https://attacker.com'}));
  assert.equal(serverConfig({SUPABASE_URL:'http://127.0.0.1:54321'}).issuer,'http://127.0.0.1:54321/auth/v1');
});
test('rejects non-public credentials and invalid ports',()=>{
  for (const key of [undefined,'sb_secret_fake','eyJfake','sb_publishable_example_only']) assert.throws(()=>validatePublicKey(key));
  assert.throws(()=>port('0',3001)); assert.throws(()=>port('NaN',3001));
  assert.equal(port(undefined,3001),3001);
});

test('invalid configuration errors do not echo environment values',()=>{
  const marker='fictitious-invalid-input';
  assert.throws(()=>serverConfig({SUPABASE_URL:marker}),error=>{
    assert.ok(error instanceof Error);
    assert.equal(error.message,'SUPABASE_URL inválida');
    assert.ok(!error.stack?.includes(marker));
    return true;
  });
  assert.throws(()=>serverConfig({SUPABASE_URL:'https://example.com/path?value=fictitious'}));
});
