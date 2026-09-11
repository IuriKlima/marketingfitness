import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:http';
import { appHandler } from '../apps/api/src/handlers.ts';
import { runtimeConfig } from '../apps/api/src/config.ts';
import { signTenantContext } from '../apps/api/src/security.ts';

test('BFF rejects forged origins, CSRF, cross-user contexts and invalid inputs; password uses the user token', async () => {
  let lastPassword:unknown;
  let passwordIdentity='';
  const upstream=createServer(async (req,res)=>{
    res.setHeader('Content-Type','application/json');
    if(req.url==='/auth/v1/user'&&req.method==='PUT') {
      let body='';for await(const part of req)body+=String(part);
      lastPassword=JSON.parse(body).password;
      passwordIdentity=req.headers.authorization ?? '';
      res.end(JSON.stringify({id:'user-b'}));return;
    }
    if(req.url==='/auth/v1/user') {res.end(JSON.stringify({id:'user-b',email:'user@example.test'}));return;}
    if(req.url?.includes('my_accessible_contexts')) {res.end('[]');return;}
    if(req.url?.includes('my_platform_roles')) {res.end('[]');return;}
    if(req.url==='/auth/v1/logout') {res.statusCode=204;res.end();return;}
    res.statusCode=400;res.end('{}');
  });
  await new Promise<void>(resolve=>upstream.listen(0,'127.0.0.1',resolve));
  const upstreamAddress=upstream.address();assert.ok(upstreamAddress&&typeof upstreamAddress!=='string');
  const config=runtimeConfig({SUPABASE_URL:`http://127.0.0.1:${upstreamAddress.port}`,APP_ORIGIN:'http://127.0.0.1:5173',
    SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fictitious_public_key',SUPABASE_SECRET_KEY:'fictitious-server-only-secret-value',SESSION_CONTEXT_SECRET:'fictitious-context-secret-with-more-than-32-bytes'});
  const handler=appHandler(config,async()=>({userId:'user-b'}));
  const server=createServer((req,res)=>{void handler(req,res);});
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  const address=server.address();assert.ok(address&&typeof address!=='string');
  const base=`http://127.0.0.1:${address.port}/api`;
  const cookie='acadeai_access=fictitious-access; acadeai_csrf=fictitious-csrf';
  const headers={Origin:config.appOrigin,Cookie:cookie,'X-CSRF-Token':'fictitious-csrf','Content-Type':'application/json'};
  try {
    assert.equal((await fetch(base+'/auth/login',{method:'POST',headers:{Origin:'https://attacker.example'},body:'{}'})).status,403);
    assert.equal((await fetch(base+'/auth/password',{method:'POST',headers:{Origin:config.appOrigin,Cookie:cookie},body:'{}'})).status,403);
    const invalid=await fetch(base+'/auth/login',{method:'POST',headers,body:JSON.stringify({email:'invalid',password:'fictitious-pass'})});
    assert.equal(invalid.status,400);
    assert.deepEqual(await invalid.json(),{error:'invalid_email'});
    const password='  fictitious password with spaces  ';
    const response=await fetch(base+'/auth/password',{method:'POST',headers,body:JSON.stringify({password})});
    assert.equal(response.status,200);assert.equal(lastPassword,password);assert.equal(passwordIdentity,'Bearer fictitious-access');
    const context=signTenantContext({userId:'user-a',organizationId:'org-a',unitId:'unit-a',issuedAt:Date.now()},config.contextSecret);
    const crossUser=await fetch(base+'/onboarding/current',{headers:{Cookie:cookie+'; acadeai_context='+context}});
    assert.equal(crossUser.status,403);
    const forgedReview=await fetch(base+'/platform/onboarding');assert.equal(forgedReview.status,401);
    const logout=await fetch(base+'/auth/logout',{method:'POST',headers:{Origin:config.appOrigin,Cookie:'acadeai_csrf=fictitious-csrf','X-CSRF-Token':'fictitious-csrf'}});
    assert.equal(logout.status,200);assert.ok(logout.headers.getSetCookie().every(value=>value.includes('Max-Age=0')));
    const malformed=await fetch(base+'/auth/session',{headers:{Cookie:'acadeai_access=%ZZ'}});assert.equal(malformed.status,401);
  } finally {
    server.closeAllConnections();upstream.closeAllConnections();
    await Promise.all([new Promise<void>(resolve=>server.close(()=>resolve())),new Promise<void>(resolve=>upstream.close(()=>resolve()))]);
  }
});
