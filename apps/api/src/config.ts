import { serverConfig } from '../../../packages/config/src/server.ts';
import { decodeJwt, decodeProtectedHeader } from 'jose';

export type RuntimeConfig = ReturnType<typeof runtimeConfig>;

function required(env: NodeJS.ProcessEnv, name: string, minLength = 20) {
  const value = env[name];
  if (!value || value.length < minLength || value.includes('<') || value.includes('REPLACE')) {
    throw new Error(name + ' is not configured');
  }
  return value;
}

export function runtimeConfig(env: NodeJS.ProcessEnv) {
  const base = serverConfig(env);
  const keyName = env.SUPABASE_PUBLISHABLE_KEY ? 'SUPABASE_PUBLISHABLE_KEY' : 'SUPABASE_ANON_KEY';
  const publishableKey = required(env,keyName);
  if (keyName === 'SUPABASE_PUBLISHABLE_KEY') {
    if (!publishableKey.startsWith('sb_publishable_')) {
      throw new Error('SUPABASE_PUBLISHABLE_KEY must be a publishable key');
    }
  } else {
    // Classify a configured API key only. User sessions still require verified JWKS signatures.
    try {
      const claims = decodeJwt(publishableKey);
      const projectRef = new URL(base.url).hostname.split('.')[0];
      if (decodeProtectedHeader(publishableKey).alg !== 'HS256' || claims.role !== 'anon' ||
        claims.iss !== 'supabase' || claims.ref !== projectRef ||
        typeof claims.exp !== 'number' || claims.exp <= Date.now()/1000) throw new Error();
    } catch {
      throw new Error('SUPABASE_ANON_KEY must be an unexpired anon API key for the configured project');
    }
  }
  const secretKey = required(env,'SUPABASE_SECRET_KEY');
  if (secretKey === publishableKey) throw new Error('Server and browser keys must be different');
  const contextSecret = required(env,'SESSION_CONTEXT_SECRET',32);
  let appOrigin: URL;
  try { appOrigin = new URL(env.APP_ORIGIN ?? ''); }
  catch { throw new Error('APP_ORIGIN is invalid'); }
  if (appOrigin.pathname !== '/' || appOrigin.search || appOrigin.hash || appOrigin.username || appOrigin.password) {
    throw new Error('APP_ORIGIN must contain only scheme and host');
  }
  if (
    appOrigin.protocol !== 'https:' &&
    !(appOrigin.protocol === 'http:' && ['127.0.0.1','localhost'].includes(appOrigin.hostname))
  ) throw new Error('APP_ORIGIN must use HTTPS outside local development');
  const production = env.NODE_ENV === 'production';
  if (production && appOrigin.protocol !== 'https:') throw new Error('Production origin must use HTTPS');
  const optionalUrl = (name:string) => {
    const value=env[name]; if(!value) return undefined;
    let parsed:URL; try{parsed=new URL(value);}catch{throw new Error(name+' is invalid');}
    if(parsed.protocol!=='https:'||(parsed.pathname!=='/'&&parsed.pathname!=='')||parsed.search||parsed.hash||parsed.username||parsed.password) throw new Error(name+' is invalid');
    return parsed.origin;
  };
  return {
    ...base,
    publishableKey,
    secretKey,
    contextSecret,
    appOrigin: appOrigin.origin,
    production,
    publicWebhookBaseUrl:optionalUrl('PUBLIC_WEBHOOK_BASE_URL'),
    llmApiUrl:optionalUrl('LLM_API_URL'),
    llmApiKey:env.LLM_API_KEY && env.LLM_API_KEY.length>=20 && !env.LLM_API_KEY.includes('<') ? env.LLM_API_KEY : undefined,
    llmModel:env.LLM_MODEL && !env.LLM_MODEL.includes('<') ? env.LLM_MODEL.slice(0,120) : undefined
  };
}
