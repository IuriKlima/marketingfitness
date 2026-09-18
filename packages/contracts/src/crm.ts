export const opportunityStatuses = ['open','won','lost'] as const;
export const taskPriorities = ['low','normal','high','urgent'] as const;
export const appointmentStatuses = [
  'scheduled','confirmed','attended','no_show','rescheduled','cancelled','enrolled','lost'
] as const;

export type CursorPage = { cursor?: string; limit: number; query?: string };
export type ContactInput = {
  name: string;
  phone?: string;
  email?: string;
  city?: string;
  source?: string;
  externalKey?: string;
};

function stringValue(value: unknown, name: string, min: number, max: number, optional = false) {
  if (optional && (value === undefined || value === null || value === '')) return undefined;
  if (typeof value !== 'string') throw new Error('invalid_' + name);
  const normalized = value.trim();
  if (normalized.length < min || normalized.length > max) throw new Error('invalid_' + name);
  return normalized;
}

export function uuidValue(value: unknown, name: string) {
  const result=stringValue(value,name,36,36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(result!)) {
    throw new Error('invalid_' + name);
  }
  return result!;
}

export function cursorPage(params: URLSearchParams): CursorPage {
  const limit = Number(params.get('limit') ?? '25');
  if (!Number.isInteger(limit) || limit < 1 || limit > 100) throw new Error('invalid_limit');
  const cursor=params.get('cursor') || undefined;
  if (cursor && !/^\d{4}-\d{2}-\d{2}T[^|]{1,40}\|[0-9a-f-]{36}$/i.test(cursor)) throw new Error('invalid_cursor');
  const query=params.get('q')?.trim();
  if (query && query.length > 120) throw new Error('invalid_query');
  return {limit,cursor,query};
}

export function e164(value: unknown) {
  if (value === undefined || value === null || value === '') return undefined;
  if (typeof value !== 'string') throw new Error('invalid_phone');
  const normalized='+'+value.replace(/[^0-9]/g,'');
  if (!/^\+[1-9][0-9]{7,14}$/.test(normalized)) throw new Error('invalid_phone');
  return normalized;
}

export function lowerEmail(value: unknown) {
  if (value === undefined || value === null || value === '') return undefined;
  const email=stringValue(value,'email',3,320)!.toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new Error('invalid_email');
  return email;
}

export function contactInput(value: unknown): ContactInput {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw new Error('invalid_contact');
  const body=value as Record<string,unknown>;
  const phone=e164(body.phone);
  const email=lowerEmail(body.email);
  if (!phone && !email && !body.externalKey) throw new Error('contact_identifier_required');
  return {
    name:stringValue(body.name,'name',2,160)!,phone,email,
    city:stringValue(body.city,'city',1,120,true),
    source:stringValue(body.source,'source',1,80,true),
    externalKey:stringValue(body.externalKey,'external_key',1,160,true)
  };
}

export function enumValue<T extends readonly string[]>(value: unknown, values: T, name: string): T[number] {
  if (typeof value !== 'string' || !values.includes(value)) throw new Error('invalid_' + name);
  return value as T[number];
}

export function idempotencyKey(value: unknown) {
  if (typeof value !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9_.:-]{15,127}$/.test(value)) {
    throw new Error('invalid_idempotency_key');
  }
  return value;
}
