import { test } from 'node:test';
import assert from 'node:assert/strict';
import {
  cookieNames, parseCookies, serializeCookie, sha256, signTenantContext,
  verifyTenantContext
} from '../apps/api/src/security.ts';

test('tenant context rejects tampering and expiry',() => {
  const secret = 'fictitious-context-secret-with-more-than-32-bytes';
  const context = {userId:'user-a',organizationId:'org-a',unitId:'unit-a',issuedAt:Date.now()};
  const signed = signTenantContext(context,secret);
  assert.deepEqual(verifyTenantContext(signed,secret),context);
  assert.equal(verifyTenantContext(signed + 'x',secret),null);
  assert.equal(verifyTenantContext(signed + '.extra',secret),null);
  const old = signTenantContext({...context,issuedAt:Date.now() - 9000000},secret);
  assert.equal(verifyTenantContext(old,secret,60),null);
});

test('invitation hash is deterministic without exposing raw token',() => {
  const token = 'fictitious-one-time-invitation-token';
  const digest = sha256(token);
  assert.equal(digest.length,64);
  assert.notEqual(digest,token);
  assert.equal(digest,sha256(token));
});

test('session cookies are host-only, scoped and production names are prefixed',() => {
  assert.equal(cookieNames(true).access,'__Host-acadeai_access');
  const value = serializeCookie('__Host-acadeai_access','token',{
    httpOnly:true,secure:true,maxAge:60,sameSite:'Strict'
  });
  assert.match(value,/Path=\//);
  assert.match(value,/HttpOnly/);
  assert.match(value,/Secure/);
  assert.match(value,/SameSite=Strict/);
  assert.ok(!value.includes('Domain='));
  assert.deepEqual(parseCookies('a=1; b=two'),{a:'1',b:'two'});
});
