import { test } from 'node:test';
import assert from 'node:assert/strict';
import { runtimeConfig } from '../apps/api/src/config.ts';
import { SignJWT } from 'jose';

const valid = {
  SUPABASE_URL:'http://127.0.0.1:54321',
  SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fictitious_public_key',
  SUPABASE_SECRET_KEY:'fictitious-server-only-secret-value',
  SESSION_CONTEXT_SECRET:'fictitious-context-secret-with-more-than-32-bytes',
  APP_ORIGIN:'http://127.0.0.1:5173'
};

test('runtime config separates browser and server credentials',() => {
  const config = runtimeConfig(valid);
  assert.equal(config.appOrigin,'http://127.0.0.1:5173');
  assert.notEqual(config.publishableKey,config.secretKey);
  assert.throws(() => runtimeConfig({...valid,SUPABASE_SECRET_KEY:valid.SUPABASE_PUBLISHABLE_KEY}));
  assert.throws(() => runtimeConfig({...valid,SESSION_CONTEXT_SECRET:'short'}));
  assert.throws(() => runtimeConfig({...valid,APP_ORIGIN:'https://example.com/path'}));
});

test('legacy anon configuration rejects privileged, expired and foreign project API keys',async () => {
  const key = new TextEncoder().encode('fictitious-test-signing-key-at-least-32-bytes');
  const token = (role: string, ref = 'example-project', expired = false) => new SignJWT({role,ref})
    .setProtectedHeader({alg:'HS256'}).setIssuer('supabase')
    .setExpirationTime(expired ? 1 : '1h').sign(key);
  const env = {...valid,SUPABASE_URL:'https://example-project.supabase.co',SUPABASE_PUBLISHABLE_KEY:undefined,
    SUPABASE_ANON_KEY:await token('anon')};
  assert.equal(runtimeConfig(env).publishableKey,env.SUPABASE_ANON_KEY);
  for (const value of [await token('service_role'),await token('anon','another-project'),await token('anon','example-project',true),'invalid-key-format-with-enough-length']) {
    assert.throws(() => runtimeConfig({...env,SUPABASE_ANON_KEY:value}),error =>
      error instanceof Error && !error.message.includes(value));
  }
});
