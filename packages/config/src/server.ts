export function serverConfig(env: NodeJS.ProcessEnv) {
  let url: URL;
  try { url = new URL(env.SUPABASE_URL ?? ''); }
  catch { throw new Error('SUPABASE_URL inválida'); }
  if (url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Error('SUPABASE_URL inválida');
  if (url.protocol !== 'https:' && !(url.protocol === 'http:' && ['127.0.0.1','localhost'].includes(url.hostname))) throw new Error('SUPABASE_URL inválida');
  const issuer = env.SUPABASE_JWT_ISSUER ?? `${url.origin}/auth/v1`;
  if (issuer !== `${url.origin}/auth/v1`) throw new Error('Issuer deve corresponder ao Supabase configurado');
  return {url: url.origin, issuer, jwks: new URL(`${issuer}/.well-known/jwks.json`)};
}
export function port(value: string | undefined, fallback: number) {
  const result = Number(value ?? fallback);
  if (!Number.isInteger(result) || result < 1 || result > 65535) throw new Error('Porta inválida');
  return result;
}
