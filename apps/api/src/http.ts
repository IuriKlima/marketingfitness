import type { IncomingMessage, ServerResponse } from 'node:http';
import { randomUUID } from 'node:crypto';
import type { RuntimeConfig } from './config.ts';
import { cookieNames, csrfIsValid, originIsValid, requiredString } from './security.ts';

export class HttpError extends Error {
  status:number;
  code:string;
  details?:unknown;
  constructor(status:number,code:string,details?:unknown) {
    super(code); this.status=status; this.code=code; this.details=details;
  }
}

export function correlationId(req:IncomingMessage) {
  const supplied=req.headers['x-correlation-id'];
  return typeof supplied==='string' && /^[0-9a-f-]{36}$/i.test(supplied) ? supplied : randomUUID();
}

export function send(res:ServerResponse,status:number,body:unknown,cookies:string[]=[]) {
  res.statusCode=status;
  res.setHeader('Content-Type','application/json; charset=utf-8');
  res.setHeader('Cache-Control','no-store');
  res.setHeader('X-Content-Type-Options','nosniff');
  res.setHeader('Referrer-Policy','no-referrer');
  if(cookies.length) res.setHeader('Set-Cookie',cookies);
  res.end(JSON.stringify(body));
}

export function requireMutation(req:IncomingMessage,config:RuntimeConfig,cookies:Record<string,string>) {
  if(!originIsValid(req,config.appOrigin)) throw new HttpError(403,'invalid_origin');
  const name=cookieNames(config.production).csrf;
  if(!csrfIsValid(req,cookies,name)) throw new HttpError(403,'invalid_csrf');
}

export function bodyString(body:Record<string,unknown>,name:string,min=1,max=5000) {
  if(name==='password') {
    if(typeof body[name]!=='string'||body[name].length<min||body[name].length>max) throw new HttpError(400,'invalid_password');
    return body[name];
  }
  return requiredString(body[name],name,min,max);
}

export function bodyBoolean(body:Record<string,unknown>,name:string,fallback=false) {
  const value=body[name];
  if(value===undefined) return fallback;
  if(typeof value!=='boolean') throw new HttpError(400,'invalid_'+name);
  return value;
}

const windows=new Map<string,{count:number;reset:number}>();
export function rateLimit(key:string,limit:number,windowMs:number) {
  const now=Date.now();
  const current=windows.get(key);
  if(!current||current.reset<=now) { windows.set(key,{count:1,reset:now+windowMs}); return; }
  current.count+=1;
  if(current.count>limit) throw new HttpError(429,'rate_limited');
  if(windows.size>10000) for(const [entry,value] of windows) if(value.reset<=now) windows.delete(entry);
}
