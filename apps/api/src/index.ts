import { createServer } from 'node:http';
import { serverConfig, port } from '../../../packages/config/src/server.ts';
import { verifier } from './auth.ts';
const config = serverConfig(process.env);
const verify = verifier(config.issuer, config.jwks);
createServer(async (req, res) => {
  res.setHeader('Content-Type','application/json');
  const reply = (status: number, body: object) => { res.writeHead(status); res.end(JSON.stringify(body)); };
  if (req.method !== 'GET') return reply(405,{error:'method_not_allowed'});
  if (req.url === '/health') return reply(200,{service:'api',status:'ok'});
  if (req.url === '/ready') {
    try {
      const result = await fetch(config.jwks,{signal:AbortSignal.timeout(3000)});
      const body = await result.json() as {keys?: unknown[]};
      if (!result.ok || !body.keys?.length) throw new Error('Unavailable');
      return reply(200,{service:'api',status:'ok'});
    } catch { return reply(503,{service:'api',status:'unavailable'}); }
  }
  if (req.url === '/session') {
    try { return reply(200,await verify(req.headers.authorization)); }
    catch { return reply(401,{error:'unauthorized'}); }
  }
  // No administrative operations until explicit authorization and audit are implemented.
  return reply(404,{error:'not_found'});
}).listen(port(process.env.API_PORT,3001),'127.0.0.1');
