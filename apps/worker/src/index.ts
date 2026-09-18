import { createServer } from 'node:http';
import { randomUUID } from 'node:crypto';
import { port } from '../../../packages/config/src/server.ts';
import { runtimeConfig } from '../../api/src/config.ts';
import { SupabaseOutbox } from './outbox.ts';
import { jobProcessor } from './processors.ts';
import { runOutboxBatch } from './runner.ts';

let processing=false;let lastError:string|null=null;let stopped=false;
const workerId=process.env.WORKER_ID?.slice(0,80)??'worker-'+randomUUID();
try {
  const config=runtimeConfig(process.env);const outbox=new SupabaseOutbox(config);const processJob=jobProcessor(config);processing=true;
  const poll=async()=>{
    if(stopped)return;
    try {
      await runOutboxBatch(outbox,processJob,workerId,10,60);lastError=null;
    } catch(error){lastError=error instanceof Error&&/^[a-z0-9_]+$/.test(error.message)?error.message:'worker_poll_failed';}
    setTimeout(()=>void poll(),jobsDelay()).unref();
  };
  const jobsDelay=()=>Math.min(Math.max(Number(process.env.WORKER_POLL_MS??1500),250),30000);
  void poll();
} catch { processing=false;lastError='worker_unconfigured'; }

const server=createServer((req,res) => {
  res.setHeader('Content-Type','application/json');
  res.setHeader('Cache-Control','no-store');
  res.statusCode = req.method === 'GET' && req.url === '/health' ? 200 : 404;
  res.end(JSON.stringify(res.statusCode === 200 ? {service:'worker',status:'ok',processing,lastError} : {error:'not_found'}));
});
server.listen(port(process.env.WORKER_PORT,3002),'127.0.0.1');
process.once('SIGTERM',()=>{
  stopped=true;
  processing=false;
  server.close(()=>{process.exitCode=0;});
});
