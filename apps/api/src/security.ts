import { createHash, createHmac, randomBytes, timingSafeEqual } from 'node:crypto';
import type { IncomingMessage } from 'node:http';

export type TenantContext = {
  userId: string;
  organizationId: string;
  unitId: string;
  issuedAt: number;
};

export function parseCookies(header: string | undefined): Record<string,string> {
  const result: Record<string,string> = {};
  for (const part of (header ?? '').split(';')) {
    const index = part.indexOf('=');
    if (index < 1) continue;
    const name = part.slice(0,index).trim();
    const value = part.slice(index + 1).trim();
    if (name) {
      try { result[name] = decodeURIComponent(value); }
      catch { /* Ignore malformed cookies without disclosing their values. */ }
    }
  }
  return result;
}

export function cookieNames(production: boolean) {
  const prefix = production ? '__Host-' : '';
  return {
    access: prefix + 'acadeai_access',
    refresh: prefix + 'acadeai_refresh',
    context: prefix + 'acadeai_context',
    csrf: prefix + 'acadeai_csrf'
  };
}

export function serializeCookie(
  name: string,
  value: string,
  options: { httpOnly?: boolean; secure?: boolean; maxAge?: number; sameSite?: 'Strict'|'Lax' } = {}
) {
  const parts = [name + '=' + encodeURIComponent(value),'Path=/'];
  if (options.httpOnly) parts.push('HttpOnly');
  if (options.secure) parts.push('Secure');
  if (options.maxAge !== undefined) parts.push('Max-Age=' + Math.max(0,Math.floor(options.maxAge)));
  parts.push('SameSite=' + (options.sameSite ?? 'Lax'));
  return parts.join('; ');
}

export function randomToken(bytes = 32) {
  return randomBytes(bytes).toString('base64url');
}

export function sha256(value: string) {
  return createHash('sha256').update(value,'utf8').digest('hex');
}

export function signTenantContext(context: TenantContext, secret: string) {
  const payload = Buffer.from(JSON.stringify(context),'utf8').toString('base64url');
  const signature = createHmac('sha256',secret).update(payload).digest('base64url');
  return payload + '.' + signature;
}

export function verifyTenantContext(value: string | undefined, secret: string, maxAgeSeconds = 28800): TenantContext | null {
  if (!value) return null;
  const segments = value.split('.');
  if (segments.length !== 2) return null;
  const [payload,provided] = segments;
  if (!payload || !provided) return null;
  const expected = createHmac('sha256',secret).update(payload).digest('base64url');
  const a = Buffer.from(provided);
  const b = Buffer.from(expected);
  if (a.length !== b.length || !timingSafeEqual(a,b)) return null;
  try {
    const parsed = JSON.parse(Buffer.from(payload,'base64url').toString('utf8')) as Partial<TenantContext>;
    if (
      typeof parsed.userId !== 'string' ||
      typeof parsed.organizationId !== 'string' ||
      typeof parsed.unitId !== 'string' ||
      typeof parsed.issuedAt !== 'number' || !Number.isFinite(parsed.issuedAt) ||
      parsed.issuedAt > Date.now() + 30000 ||
      Date.now() - parsed.issuedAt > maxAgeSeconds * 1000
    ) return null;
    return parsed as TenantContext;
  } catch {
    return null;
  }
}

export function csrfIsValid(req: IncomingMessage, cookies: Record<string,string>, name: string) {
  const header = req.headers['x-csrf-token'];
  const provided = Array.isArray(header) ? header[0] : header;
  const stored = cookies[name];
  if (!provided || !stored) return false;
  const a = Buffer.from(provided);
  const b = Buffer.from(stored);
  return a.length === b.length && timingSafeEqual(a,b);
}

export function originIsValid(req: IncomingMessage, allowedOrigin: string) {
  const origin = req.headers.origin;
  return typeof origin === 'string' && origin === allowedOrigin;
}

export async function readJson(req: IncomingMessage, maxBytes = 65536): Promise<Record<string,unknown>> {
  const chunks: Buffer[] = [];
  let size = 0;
  for await (const chunk of req) {
    const value = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
    size += value.length;
    if (size > maxBytes) throw new Error('payload_too_large');
    chunks.push(value);
  }
  if (!chunks.length) return {};
  const parsed: unknown = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) throw new Error('invalid_json');
  return parsed as Record<string,unknown>;
}

export function normalizedEmail(value: unknown) {
  if (typeof value !== 'string') throw new Error('invalid_email');
  const email = value.trim().toLowerCase();
  if (email.length < 3 || email.length > 320 || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    throw new Error('invalid_email');
  }
  return email;
}

export function requiredString(value: unknown, name: string, min = 1, max = 5000) {
  if (typeof value !== 'string') throw new Error('invalid_' + name);
  const result = value.trim();
  if (result.length < min || result.length > max) throw new Error('invalid_' + name);
  return result;
}
