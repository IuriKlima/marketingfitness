export class ApiError extends Error {
  constructor(public status:number, public code:string, public details?:unknown) {
    super(code);
  }
}

const base = (import.meta.env.VITE_API_BASE_URL ?? '/api').replace(/\/$/,'');
if (!/^\/(?!\/)[a-zA-Z0-9/_-]+$/.test(base)) throw new Error('API must use a same-origin path');
let refreshInFlight: Promise<unknown> | null = null;

function cookie(name:string) {
  const candidates = [name,'__Host-' + name];
  for (const part of document.cookie.split(';')) {
    const index = part.indexOf('=');
    if (index < 1) continue;
    const key = part.slice(0,index).trim();
    if (candidates.includes(key)) return decodeURIComponent(part.slice(index + 1).trim());
  }
  return '';
}

async function execute<T>(path:string, init:RequestInit = {}):Promise<T> {
  const headers = new Headers(init.headers);
  if (typeof init.body === 'string' && !headers.has('Content-Type')) headers.set('Content-Type','application/json');
  const method = (init.method ?? 'GET').toUpperCase();
  if (!['GET','HEAD','OPTIONS'].includes(method)) {
    const csrf = cookie('acadeai_csrf');
    if (csrf) headers.set('X-CSRF-Token',csrf);
  }
  const response = await fetch(base + path,{...init,headers,credentials:'include'});
  const payload = await response.json().catch(() => ({error:'invalid_response'})) as {
    error?:string;
    details?:unknown;
  };
  if (!response.ok) throw new ApiError(response.status,payload.error ?? 'request_failed',payload.details);
  return payload as T;
}

export async function api<T>(path:string, init:RequestInit = {}, retry = true):Promise<T> {
  try {
    return await execute<T>(path,init);
  } catch (error) {
    if (
      retry && error instanceof ApiError && error.status === 401 &&
      !path.startsWith('/auth/login') && !path.startsWith('/auth/refresh')
    ) {
      if (!refreshInFlight) refreshInFlight = execute('/auth/refresh',{method:'POST'}).finally(() => {refreshInFlight=null;});
      await refreshInFlight;
      return execute<T>(path,init);
    }
    throw error;
  }
}

export function jsonBody(value:unknown) {
  return JSON.stringify(value);
}
