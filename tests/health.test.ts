import { spawn } from 'node:child_process';
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createServer } from 'node:net';

async function freePort() {
  const server=createServer();
  await new Promise<void>(resolve=>server.listen(0,'127.0.0.1',resolve));
  const address=server.address();
  assert.ok(address && typeof address!=='string');
  await new Promise<void>(resolve=>server.close(()=>resolve()));
  return address.port;
}

async function withProcess(app:string,env:NodeJS.ProcessEnv,run:(base:string)=>Promise<void>) {
  const port=await freePort();
  const child=spawn(process.execPath,['--experimental-strip-types','apps/' + app + '/src/index.ts'],{
    env:{...process.env,...env,API_PORT:String(port),WORKER_PORT:String(port)},
    stdio:'ignore'
  });
  const base='http://127.0.0.1:' + port;
  try {
    let started=false;
    for(let i=0;i<100;i++) {
      if(child.exitCode!==null) throw new Error(app + ' exited before health');
      try {
        if((await fetch(base + '/health')).ok) {started=true;break;}
      } catch { /* startup */ }
      await new Promise(resolve=>setTimeout(resolve,50));
    }
    assert.ok(started,app + ' starts');
    await run(base);
  } finally {
    if(child.exitCode===null) {
      const exited=new Promise(resolve=>child.once('exit',resolve));
      child.kill();
      await exited;
    }
  }
}

test('API health, unavailable readiness, protected session and absent admin route',async() => {
  const offline=await freePort();
  await withProcess('api',{
    SUPABASE_URL:'http://127.0.0.1:' + offline,
    SUPABASE_JWT_ISSUER:'http://127.0.0.1:' + offline + '/auth/v1',
    SUPABASE_PUBLISHABLE_KEY:'sb_publishable_fictitious_public_key',
    SUPABASE_SECRET_KEY:'fictitious-server-only-secret-value',
    SESSION_CONTEXT_SECRET:'fictitious-context-secret-with-more-than-32-bytes',
    APP_ORIGIN:'http://127.0.0.1:5173'
  },async base => {
    assert.equal((await fetch(base + '/health')).status,200);
    assert.equal((await fetch(base + '/ready')).status,503);
    assert.equal((await fetch(base + '/session')).status,404);
    assert.equal((await fetch(base + '/auth/session')).status,401);
    assert.equal((await fetch(base + '/admin')).status,404);
    assert.equal((await fetch(base + '/health',{method:'POST'})).status,405);
  });
});

test('worker health does not enable processing',async() => {
  await withProcess('worker',{},async base => {
    const response=await fetch(base + '/health');
    assert.equal(response.status,200);
    assert.equal((await response.json() as {processing:boolean}).processing,false);
    assert.equal((await fetch(base + '/run')).status,404);
  });
});
