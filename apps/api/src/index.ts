import { createServer } from 'node:http';
import { port } from '../../../packages/config/src/server.ts';
import { verifier } from './auth.ts';
import { runtimeConfig } from './config.ts';
import { appHandler } from './handlers.ts';

const config = runtimeConfig(process.env);
const verify = verifier(config.issuer,config.jwks);
const handle = appHandler(config,verify);

createServer((req,res) => {
  void handle(req,res);
}).listen(port(process.env.API_PORT,3001),'127.0.0.1');
