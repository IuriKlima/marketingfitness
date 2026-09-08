import { createServer } from 'node:http';
import { port } from '../../../packages/config/src/server.ts';
// OutboxPort is intentionally not instantiated: no integrations or claims in this phase.
createServer((req,res) => {
  res.setHeader('Content-Type','application/json');
  res.statusCode = req.method === 'GET' && req.url === '/health' ? 200 : 404;
  res.end(JSON.stringify(res.statusCode === 200 ? {service:'worker',status:'ok',processing:false} : {error:'not_found'}));
}).listen(port(process.env.WORKER_PORT,3002),'127.0.0.1');
