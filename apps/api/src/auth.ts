import { createRemoteJWKSet, jwtVerify } from 'jose';
export function verifier(issuer: string, jwks: URL) {
  const keys = createRemoteJWKSet(jwks);
  return async (header: string | undefined) => {
    if (!header?.startsWith('Bearer ')) throw new Error('Unauthorized');
    const { payload } = await jwtVerify(header.slice(7), keys, {issuer, audience:'authenticated', algorithms:['ES256','RS256'], requiredClaims:['exp','iat','sub']});
    if (!payload.sub || payload.role !== 'authenticated') throw new Error('Unauthorized');
    return { userId: payload.sub };
  };
}

