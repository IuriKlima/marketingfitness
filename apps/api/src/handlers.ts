import type { IncomingMessage, ServerResponse } from 'node:http';
import type { RuntimeConfig } from './config.ts';
import { validateOnboardingDocument } from '../../../packages/contracts/src/onboarding.ts';
import { adminSupabase, publicSupabase, userSupabase } from './supabase.ts';
import {
  cookieNames, csrfIsValid, normalizedEmail, originIsValid, parseCookies,
  randomToken, readJson, requiredString, serializeCookie, sha256,
  signTenantContext, verifyTenantContext, type TenantContext
} from './security.ts';

type Verify = (header: string | undefined) => Promise<{userId:string}>;
type SessionShape = { access_token:string; refresh_token:string; expires_in:number };
type ContextRow = {
  organization_id:string;
  organization_name:string;
  unit_id:string;
  unit_name:string;
  roles:string[];
};

class HttpError extends Error {
  status: number;
  code: string;
  details?: unknown;
  constructor(status: number, code: string, details?: unknown) {
    super(code);
    this.status = status;
    this.code = code;
    this.details = details;
  }
}

function send(res: ServerResponse, status: number, body: unknown, cookies: string[] = []) {
  res.statusCode = status;
  res.setHeader('Content-Type','application/json; charset=utf-8');
  res.setHeader('Cache-Control','no-store');
  res.setHeader('X-Content-Type-Options','nosniff');
  res.setHeader('Referrer-Policy','no-referrer');
  if (cookies.length) res.setHeader('Set-Cookie',cookies);
  res.end(JSON.stringify(body));
}

function sessionCookies(config: RuntimeConfig, session: SessionShape) {
  const names = cookieNames(config.production);
  const csrf = randomToken(24);
  return [
    serializeCookie(names.access,session.access_token,{
      httpOnly:true,secure:config.production,maxAge:session.expires_in,sameSite:'Lax'
    }),
    serializeCookie(names.refresh,session.refresh_token,{
      httpOnly:true,secure:config.production,maxAge:2592000,sameSite:'Strict'
    }),
    serializeCookie(names.csrf,csrf,{
      secure:config.production,maxAge:2592000,sameSite:'Strict'
    })
  ];
}

function clearSessionCookies(config: RuntimeConfig) {
  const names = cookieNames(config.production);
  return [
    serializeCookie(names.access,'',{httpOnly:true,secure:config.production,maxAge:0}),
    serializeCookie(names.refresh,'',{httpOnly:true,secure:config.production,maxAge:0}),
    serializeCookie(names.context,'',{httpOnly:true,secure:config.production,maxAge:0}),
    serializeCookie(names.csrf,'',{secure:config.production,maxAge:0})
  ];
}

function requireOrigin(req: IncomingMessage, config: RuntimeConfig) {
  if (!originIsValid(req,config.appOrigin)) throw new HttpError(403,'invalid_origin');
}

async function authenticate(
  req: IncomingMessage,
  config: RuntimeConfig,
  verify: Verify
) {
  const cookies = parseCookies(req.headers.cookie);
  const names = cookieNames(config.production);
  const accessToken = cookies[names.access];
  if (!accessToken) throw new HttpError(401,'authentication_required');
  try {
    const identity = await verify('Bearer ' + accessToken);
    return { ...identity, accessToken, cookies, names };
  } catch {
    throw new HttpError(401,'session_expired');
  }
}

function requireCsrf(req: IncomingMessage, cookies: Record<string,string>, csrfName: string) {
  if (!csrfIsValid(req,cookies,csrfName)) throw new HttpError(403,'invalid_csrf');
}

async function contexts(config: RuntimeConfig, accessToken: string): Promise<ContextRow[]> {
  const { data, error } = await userSupabase(config,accessToken).rpc('my_accessible_contexts');
  if (error) throw new HttpError(503,'context_unavailable');
  return (data ?? []) as ContextRow[];
}

async function platformRoles(config: RuntimeConfig, accessToken: string): Promise<string[]> {
  const { data, error } = await userSupabase(config,accessToken).rpc('my_platform_roles');
  if (error) throw new HttpError(503,'role_resolution_failed');
  return (data ?? []) as string[];
}

async function requireTenantContext(
  config: RuntimeConfig,
  accessToken: string,
  cookies: Record<string,string>
): Promise<{context:TenantContext; available:ContextRow}> {
  const names = cookieNames(config.production);
  const context = verifyTenantContext(cookies[names.context],config.contextSecret);
  if (!context) throw new HttpError(409,'tenant_context_required');
  const { data: identity, error: identityError } = await userSupabase(config,accessToken).auth.getUser(accessToken);
  if (identityError || identity.user?.id !== context.userId) throw new HttpError(403,'tenant_context_revoked');
  const available = (await contexts(config,accessToken)).find(row =>
    row.organization_id === context.organizationId && row.unit_id === context.unitId
  );
  if (!available) throw new HttpError(403,'tenant_context_revoked');
  return {context,available};
}

function bodyString(body: Record<string,unknown>, name: string, min = 1, max = 5000) {
  if (name === 'password') {
    if (typeof body[name] !== 'string' || body[name].length < min || body[name].length > max) throw new HttpError(400,'invalid_password');
    return body[name];
  }
  return requiredString(body[name],name,min,max);
}

function bodyBoolean(body: Record<string,unknown>, name: string, fallback = false) {
  const value = body[name];
  if (value === undefined) return fallback;
  if (typeof value !== 'boolean') throw new HttpError(400,'invalid_' + name);
  return value;
}

async function validateOnboarding(
  config: RuntimeConfig,
  accessToken: string,
  schemaVersion: number,
  document: Record<string,unknown>
) {
  const { data, error } = await userSupabase(config,accessToken)
    .from('onboarding_field_definitions')
    .select('field_key,label,required,field_type,validation,options')
    .eq('schema_version',schemaVersion)
    .eq('active',true);
  if (error) throw new HttpError(503,'onboarding_definition_unavailable');
  if (!data?.length) throw new HttpError(400,'invalid_schema_version');
  return validateOnboardingDocument(data,document);
}

export function appHandler(config: RuntimeConfig, verify: Verify) {
  const admin = adminSupabase(config);

  return async function handle(req: IncomingMessage, res: ServerResponse) {
    try {
      // Supabase Auth clients retain in-memory sessions; never share them between requests.
      const publicClient = publicSupabase(config);
      const url = new URL(req.url ?? '/',config.appOrigin);
      const path = url.pathname.startsWith('/api/') ? url.pathname.slice(4) : url.pathname;
      if (req.method === 'GET' && path === '/health') {
        return send(res,200,{service:'api',status:'ok'});
      }
      if (req.method === 'GET' && path === '/ready') {
        try {
          const result = await fetch(config.jwks,{signal:AbortSignal.timeout(3000)});
          const body = await result.json() as {keys?:unknown[]};
          if (!result.ok || !body.keys?.length) throw new Error('unavailable');
          const schema = await admin.from('onboarding_field_definitions').select('schema_version').limit(1);
          if (schema.error || !schema.data?.length) throw new Error('unavailable');
          return send(res,200,{service:'api',status:'ok'});
        } catch {
          return send(res,503,{service:'api',status:'unavailable'});
        }
      }
      if (path === '/health' || path === '/ready') {
        return send(res,405,{error:'method_not_allowed'});
      }

      if (req.method === 'POST' && path === '/auth/login') {
        requireOrigin(req,config);
        const body = await readJson(req);
        const email = normalizedEmail(body.email);
        const password = bodyString(body,'password',8,256);
        const { data, error } = await publicClient.auth.signInWithPassword({email,password});
        if (error || !data.session) throw new HttpError(401,'invalid_credentials');
        return send(res,200,{userId:data.user.id},sessionCookies(config,data.session));
      }

      if (req.method === 'POST' && path === '/auth/recover') {
        requireOrigin(req,config);
        const body = await readJson(req);
        const email = normalizedEmail(body.email);
        await publicClient.auth.resetPasswordForEmail(email,{
          redirectTo:config.appOrigin + '/recovery/callback'
        });
        return send(res,202,{accepted:true});
      }

      if (req.method === 'POST' && path === '/auth/verify-otp') {
        requireOrigin(req,config);
        const body = await readJson(req);
        const tokenHash = bodyString(body,'tokenHash',20,512);
        if (!['invite','recovery','email'].includes(String(body.type))) throw new HttpError(400,'invalid_otp_type');
        const type = body.type as 'invite'|'recovery'|'email';
        const { data, error } = await publicClient.auth.verifyOtp({token_hash:tokenHash,type});
        if (error || !data.session) throw new HttpError(401,'invalid_or_expired_link');
        return send(res,200,{verified:true},sessionCookies(config,data.session));
      }

      if (req.method === 'POST' && path === '/auth/refresh') {
        requireOrigin(req,config);
        const cookies = parseCookies(req.headers.cookie);
        const names = cookieNames(config.production);
        requireCsrf(req,cookies,names.csrf);
        const refreshToken = cookies[names.refresh];
        if (!refreshToken) throw new HttpError(401,'refresh_required');
        const { data, error } = await publicClient.auth.refreshSession({refresh_token:refreshToken});
        if (error || !data.session) throw new HttpError(401,'refresh_failed');
        return send(res,200,{refreshed:true},sessionCookies(config,data.session));
      }

      if (req.method === 'POST' && path === '/auth/logout') {
        requireOrigin(req,config);
        const cookies = parseCookies(req.headers.cookie);
        const names = cookieNames(config.production);
        requireCsrf(req,cookies,names.csrf);
        if (cookies[names.access]) await fetch(config.url + '/auth/v1/logout',{
          method:'POST',
          headers:{apikey:config.publishableKey,Authorization:'Bearer ' + cookies[names.access]},
          signal:AbortSignal.timeout(5000)
        }).catch(() => undefined);
        return send(res,200,{loggedOut:true},clearSessionCookies(config));
      }

      const protectedRoute = new Set([
        'GET /auth/session',
        'POST /auth/password',
        'GET /contexts',
        'POST /context/select',
        'GET /platform/organizations',
        'GET /platform/onboarding',
        'GET /platform/onboarding/detail',
        'POST /platform/organizations',
        'POST /invitations',
        'POST /invitations/accept',
        'GET /onboarding/definition',
        'GET /onboarding/current',
        'PUT /onboarding/draft',
        'POST /onboarding/submit',
        'POST /onboarding/review',
        'POST /onboarding/attachments/upload-url'
        ,'PUT /onboarding/attachments/content'
        ,'GET /onboarding/attachments/content'
      ]);
      if (!protectedRoute.has((req.method ?? 'GET') + ' ' + path)) {
        return send(res,404,{error:'not_found'});
      }

      const auth = await authenticate(req,config,verify);

      if (req.method === 'GET' && path === '/auth/session') {
        const [roles,available] = await Promise.all([
          platformRoles(config,auth.accessToken),
          contexts(config,auth.accessToken)
        ]);
        const signed = verifyTenantContext(auth.cookies[auth.names.context],config.contextSecret);
        const current = signed?.userId === auth.userId && available.some(row =>
          row.organization_id === signed.organizationId && row.unit_id === signed.unitId
        ) ? signed : null;
        return send(res,200,{userId:auth.userId,platformRoles:roles,contexts:available,currentContext:current});
      }

      if (req.method === 'POST' && path === '/auth/password') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const body = await readJson(req);
        const password = bodyString(body,'password',12,256);
        const result = await fetch(config.url + '/auth/v1/user',{
          method:'PUT',headers:{apikey:config.publishableKey,Authorization:'Bearer '+auth.accessToken,'Content-Type':'application/json'},
          body:JSON.stringify({password}),signal:AbortSignal.timeout(10000)
        });
        if (!result.ok) throw new HttpError(400,'password_update_failed');
        return send(res,200,{updated:true});
      }

      if (req.method === 'GET' && path === '/contexts') {
        return send(res,200,{contexts:await contexts(config,auth.accessToken)});
      }

      if (req.method === 'POST' && path === '/context/select') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const body = await readJson(req);
        const organizationId = bodyString(body,'organizationId',36,36);
        const unitId = bodyString(body,'unitId',36,36);
        const selected = (await contexts(config,auth.accessToken)).find(row =>
          row.organization_id === organizationId && row.unit_id === unitId
        );
        if (!selected) throw new HttpError(403,'context_not_allowed');
        const signed = signTenantContext({userId:auth.userId,organizationId,unitId,issuedAt:Date.now()},config.contextSecret);
        const cookie = serializeCookie(auth.names.context,signed,{
          httpOnly:true,secure:config.production,maxAge:28800,sameSite:'Strict'
        });
        return send(res,200,{context:selected},[cookie]);
      }

      if (req.method === 'GET' && path === '/platform/organizations') {
        const roles = await platformRoles(config,auth.accessToken);
        if (!roles.includes('supreme') && !roles.includes('support')) {
          throw new HttpError(403,'platform_role_required');
        }
        let query = admin.from('organizations')
          .select('id,name,status,plan,units(id,name)')
          .order('name');
        if (!roles.includes('supreme')) {
          const ids = [...new Set((await contexts(config,auth.accessToken)).map(row => row.organization_id))];
          if (!ids.length) return send(res,200,{organizations:[]});
          query = query.in('id',ids);
        }
        const { data, error } = await query;
        if (error) throw new HttpError(503,'organizations_unavailable');
        return send(res,200,{organizations:data});
      }

      if (req.method === 'POST' && path === '/platform/organizations') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const roles = await platformRoles(config,auth.accessToken);
        if (!roles.includes('supreme')) throw new HttpError(403,'supreme_required');
        const body = await readJson(req);
        const { data, error } = await admin.rpc('provision_organization',{
          p_actor_id:auth.userId,
          p_name:bodyString(body,'name',2,160),
          p_unit_name:bodyString(body,'unitName',2,160),
          p_plan:typeof body.plan === 'string' ? body.plan.slice(0,80) : 'trial'
        });
        if (error) throw new HttpError(400,'organization_provision_failed');
        return send(res,201,{organization:data});
      }

      if (req.method === 'POST' && path === '/invitations') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const roles = await platformRoles(config,auth.accessToken);
        const body = await readJson(req);
        const selected = roles.includes('supreme') ? null : await requireTenantContext(config,auth.accessToken,auth.cookies);
        if (selected && !selected.available.roles.includes('academy_admin')) {
          throw new HttpError(403,'invitation_not_allowed');
        }
        const context = selected?.context ?? {
          organizationId:bodyString(body,'organizationId',36,36),
          unitId:typeof body.unitId === 'string' ? body.unitId : ''
        };
        const email = normalizedEmail(body.email);
        const role = bodyString(body,'role',4,40);
        if (!['academy_admin','marketing_operator','academy_attendant','viewer'].includes(role)) {
          throw new HttpError(400,'invalid_role');
        }
        const allUnits = bodyBoolean(body,'allUnits');
        const unitId = allUnits ? null : (
          typeof body.unitId === 'string' ? body.unitId : context.unitId
        );
        const token = randomToken(32);
        const tokenHash = sha256(token);
        const { data:invitationId, error:createError } = await admin.rpc('create_organization_invitation',{
          p_actor_id:auth.userId,
          p_organization_id:context.organizationId,
          p_email:email,
          p_token_hash:tokenHash,
          p_role:role,
          p_all_units:allUnits,
          p_unit_id:unitId,
          p_expires_at:new Date(Date.now() + 72 * 3600000).toISOString()
        });
        if (createError || !invitationId) throw new HttpError(400,'invitation_create_failed');
        const redirectTo = config.appOrigin + '/invite?invitation=' + encodeURIComponent(token);
        let { error:deliveryError } = await admin.auth.admin.inviteUserByEmail(email,{redirectTo});
        if (deliveryError) {
          const existingUserDelivery = await publicClient.auth.signInWithOtp({
            email,
            options:{shouldCreateUser:false,emailRedirectTo:redirectTo}
          });
          deliveryError = existingUserDelivery.error;
        }
        if (deliveryError) {
          await admin.from('organization_invitations')
            .update({revoked_at:new Date().toISOString()})
            .eq('id',invitationId);
          throw new HttpError(502,'invitation_delivery_failed');
        }
        return send(res,201,{invitationId,expiresInHours:72});
      }

      if (req.method === 'POST' && path === '/invitations/accept') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const body = await readJson(req);
        const token = bodyString(body,'token',30,200);
        const { data:userData, error:userError } = await admin.auth.getUser(auth.accessToken);
        if (userError || !userData.user?.email) throw new HttpError(401,'user_email_required');
        const { data, error } = await admin.rpc('accept_organization_invitation',{
          p_token_hash:sha256(token),
          p_user_id:auth.userId,
          p_email:userData.user.email
        });
        if (error) throw new HttpError(403,'invitation_invalid_or_expired');
        return send(res,200,{accepted:true,membership:data});
      }

      if (req.method === 'GET' && path === '/onboarding/definition') {
        await requireTenantContext(config,auth.accessToken,auth.cookies);
        const schemaVersion = Number(url.searchParams.get('schemaVersion') ?? '1');
        const { data, error } = await userSupabase(config,auth.accessToken)
          .from('onboarding_field_definitions')
          .select('*')
          .eq('schema_version',schemaVersion)
          .eq('active',true)
          .order('sort_order');
        if (error) throw new HttpError(503,'onboarding_definition_unavailable');
        return send(res,200,{schemaVersion,fields:data});
      }

      if (req.method === 'GET' && (path === '/platform/onboarding' || path === '/platform/onboarding/detail')) {
        const roles = await platformRoles(config,auth.accessToken);
        if (!roles.some(role => ['supreme','support'].includes(role))) throw new HttpError(403,'platform_role_required');
        const result = path.endsWith('/detail')
          ? await admin.rpc('onboarding_review_detail',{p_actor_id:auth.userId,p_onboarding_id:requiredString(url.searchParams.get('id'),'id',36,36)})
          : await admin.rpc('onboarding_review_queue',{p_actor_id:auth.userId});
        if (result.error) throw new HttpError(403,'review_not_allowed');
        return send(res,200,result.data);
      }

      if (req.method === 'GET' && path === '/onboarding/current') {
        const {context} = await requireTenantContext(config,auth.accessToken,auth.cookies);
        const client = userSupabase(config,auth.accessToken);
        const { data, error } = await client.from('onboarding_versions')
          .select('*')
          .eq('organization_id',context.organizationId)
          .eq('unit_id',context.unitId)
          .order('version',{ascending:false})
          .limit(1)
          .maybeSingle();
        if (error) throw new HttpError(503,'onboarding_unavailable');
        let attachments:unknown[] = [];
        let reviews:unknown[] = [];
        if (data) {
          const [attachmentResult,reviewResult] = await Promise.all([
            client.from('onboarding_attachments').select('*').eq('onboarding_id',data.id),
            client.from('onboarding_reviews').select('*').eq('onboarding_id',data.id).order('created_at')
          ]);
          attachments = attachmentResult.data ?? [];
          reviews = reviewResult.data ?? [];
        }
        return send(res,200,{onboarding:data,attachments,reviews});
      }

      if (req.method === 'PUT' && path === '/onboarding/draft') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const {context,available} = await requireTenantContext(config,auth.accessToken,auth.cookies);
        if (!available.roles.includes('academy_admin')) throw new HttpError(403,'academy_admin_required');
        const body = await readJson(req,262144);
        if (body.expectedOrganizationId !== context.organizationId || body.expectedUnitId !== context.unitId) throw new HttpError(409,'context_changed');
        if (!body.document || typeof body.document !== 'object' || Array.isArray(body.document)) {
          throw new HttpError(400,'invalid_document');
        }
        const schemaVersion = Number(body.schemaVersion ?? 1);
        if (!Number.isInteger(schemaVersion) || schemaVersion < 1) throw new HttpError(400,'invalid_schema_version');
        const client = userSupabase(config,auth.accessToken);
        const { data:latest, error:latestError } = await client.from('onboarding_versions')
          .select('id,version,status,revision')
          .eq('organization_id',context.organizationId)
          .eq('unit_id',context.unitId)
          .order('version',{ascending:false})
          .limit(1)
          .maybeSingle();
        if (latestError) throw new HttpError(503,'onboarding_unavailable');
        if ((latest?.id ?? null) !== body.expectedVersionId || (latest && latest.revision !== body.expectedRevision)) throw new HttpError(409,'onboarding_changed');
        let result;
        if (latest?.status === 'draft') {
          result = await client.from('onboarding_versions')
            .update({document:body.document})
            .eq('id',latest.id)
            .eq('revision',latest.revision)
            .select('*')
            .single();
        } else if (latest?.status === 'submitted') {
          throw new HttpError(409,'onboarding_awaiting_review');
        } else {
          result = await client.from('onboarding_versions')
            .insert({
              organization_id:context.organizationId,
              unit_id:context.unitId,
              version:(latest?.version ?? 0) + 1,
              schema_version:schemaVersion,
              document:body.document
            })
            .select('*')
            .single();
        }
        if (result.error) throw new HttpError(409,'onboarding_save_failed');
        return send(res,200,{onboarding:result.data});
      }

      if (req.method === 'POST' && path === '/onboarding/submit') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const {context,available} = await requireTenantContext(config,auth.accessToken,auth.cookies);
        if (!available.roles.includes('academy_admin')) throw new HttpError(403,'academy_admin_required');
        const body = await readJson(req);
        const client = userSupabase(config,auth.accessToken);
        const { data:draft, error } = await client.from('onboarding_versions')
          .select('*')
          .eq('organization_id',context.organizationId)
          .eq('unit_id',context.unitId)
          .eq('status','draft')
          .order('version',{ascending:false})
          .limit(1)
          .maybeSingle();
        if (error || !draft) throw new HttpError(404,'draft_not_found');
        if (draft.id !== body.expectedVersionId || draft.revision !== body.expectedRevision) throw new HttpError(409,'onboarding_changed');
        const missing = await validateOnboarding(
          config,auth.accessToken,draft.schema_version,draft.document as Record<string,unknown>
        );
        if (missing.length) throw new HttpError(422,'onboarding_incomplete',{missing});
        const result = await client.from('onboarding_versions')
          .update({status:'submitted'})
          .eq('id',draft.id)
          .eq('revision',draft.revision)
          .select('*')
          .single();
        if (result.error) throw new HttpError(400,'onboarding_submit_failed');
        return send(res,200,{submitted:true,onboarding:result.data});
      }

      if (req.method === 'POST' && path === '/onboarding/review') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const body = await readJson(req);
        if (!['approved','changes_requested'].includes(String(body.decision))) throw new HttpError(400,'invalid_decision');
        const decision = body.decision;
        const requestedFields = Array.isArray(body.requestedFields)
          ? body.requestedFields.filter(value => typeof value === 'string').slice(0,100)
          : [];
        const { data, error } = await admin.rpc('review_onboarding',{
          p_onboarding_id:bodyString(body,'onboardingId',36,36),
          p_actor_id:auth.userId,
          p_decision:decision,
          p_notes:bodyString(body,'notes',3,5000),
          p_requested_fields:requestedFields
        });
        if (error) throw new HttpError(403,'review_not_allowed');
        return send(res,200,{reviewId:data,decision});
      }

      if (req.method === 'POST' && path === '/onboarding/attachments/upload-url') {
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const {context,available} = await requireTenantContext(config,auth.accessToken,auth.cookies);
        if (!available.roles.includes('academy_admin')) throw new HttpError(403,'academy_admin_required');
        const body = await readJson(req);
        const onboardingId = bodyString(body,'onboardingId',36,36);
        const filename = bodyString(body,'filename',1,255).replace(/[^a-zA-Z0-9._-]/g,'_');
        const mimeType = bodyString(body,'mimeType',3,100);
        const byteSize = Number(body.byteSize);
        if (
          !['image/jpeg','image/png','image/webp','application/pdf'].includes(mimeType) ||
          !Number.isInteger(byteSize) || byteSize < 1 || byteSize > 10485760
        ) throw new HttpError(400,'invalid_attachment');
        const client = userSupabase(config,auth.accessToken);
        const { data:draft } = await client.from('onboarding_versions')
          .select('id').eq('id',onboardingId).eq('organization_id',context.organizationId).eq('unit_id',context.unitId).eq('status','draft').maybeSingle();
        if (!draft) throw new HttpError(403,'attachment_requires_draft');
        const pathValue = [
          context.organizationId,context.unitId,onboardingId,randomToken(12) + '-' + filename
        ].join('/');
        const metadata = await client.from('onboarding_attachments').insert({
          organization_id:context.organizationId,
          unit_id:context.unitId,
          onboarding_id:onboardingId,
          storage_path:pathValue,
          filename,
          mime_type:mimeType,
          byte_size:byteSize,
          uploaded_by:auth.userId
        }).select('id').single();
        if (metadata.error) throw new HttpError(400,'attachment_metadata_failed');
        return send(res,201,{
          attachmentId:metadata.data.id,
          uploadUrl:'/api/onboarding/attachments/content?id='+metadata.data.id
        });
      }

      if (path === '/onboarding/attachments/content') {
        const id = requiredString(url.searchParams.get('id'),'id',36,36);
        const client = userSupabase(config,auth.accessToken);
        if (req.method === 'GET') {
          const row = url.searchParams.get('review') === 'true'
            ? await admin.rpc('onboarding_review_attachment',{p_actor_id:auth.userId,p_attachment_id:id})
            : await client.from('onboarding_attachments').select('storage_path,filename,mime_type').eq('id',id).maybeSingle();
          if (row.error || !row.data) throw new HttpError(404,'attachment_not_found');
          const storage = url.searchParams.get('review') === 'true' ? admin.storage : client.storage;
          const file = await storage.from('onboarding-private').download(row.data.storage_path);
          if (file.error || !file.data) throw new HttpError(404,'attachment_not_found');
          res.setHeader('Content-Type',row.data.mime_type);
          res.setHeader('Content-Disposition','attachment; filename="'+row.data.filename.replace(/[^a-zA-Z0-9._-]/g,'_')+'"');
          res.setHeader('Cache-Control','no-store');
          res.setHeader('X-Content-Type-Options','nosniff');
          res.end(Buffer.from(await file.data.arrayBuffer()));
          return;
        }
        requireOrigin(req,config);
        requireCsrf(req,auth.cookies,auth.names.csrf);
        const {context,available} = await requireTenantContext(config,auth.accessToken,auth.cookies);
        if (!available.roles.includes('academy_admin')) throw new HttpError(403,'academy_admin_required');
        const row = await client.from('onboarding_attachments').select('*').eq('id',id)
          .eq('organization_id',context.organizationId).eq('unit_id',context.unitId).maybeSingle();
        if (row.error || !row.data) throw new HttpError(404,'attachment_not_found');
        const chunks:Buffer[] = [];
        let length = 0;
        for await (const chunk of req) {
          const part = Buffer.from(chunk); length += part.length;
          if (length > row.data.byte_size || length > 10485760) throw new HttpError(413,'invalid_attachment');
          chunks.push(part);
        }
        if (length !== row.data.byte_size || req.headers['content-type'] !== row.data.mime_type) throw new HttpError(400,'invalid_attachment');
        const result = await client.storage.from('onboarding-private').upload(row.data.storage_path,Buffer.concat(chunks),{contentType:row.data.mime_type,upsert:false});
        if (result.error) throw new HttpError(409,'attachment_upload_rejected');
        return send(res,201,{uploaded:true});
      }

      return send(res,404,{error:'not_found'});
    } catch (error) {
      if (error instanceof HttpError) {
        return send(res,error.status,{error:error.code,details:error.details});
      }
      if (error instanceof SyntaxError) return send(res,400,{error:'invalid_json'});
      if (error instanceof Error && /^invalid_[a-z_]+$/.test(error.message)) return send(res,400,{error:error.message});
      if (error instanceof Error && error.message === 'payload_too_large') {
        return send(res,413,{error:'payload_too_large'});
      }
      return send(res,500,{error:'internal_error'});
    }
  };
}
