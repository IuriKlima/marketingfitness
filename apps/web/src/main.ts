import { createClient } from '@supabase/supabase-js';
import { validatePublicKey } from '../../../packages/config/src/public.ts';
const output = document.querySelector('output')!;
try {
  const url = new URL(import.meta.env.VITE_SUPABASE_URL);
  const key = validatePublicKey(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY);
  const supabase = createClient(url.href, key);
  output.textContent = 'Web disponível. Verificando Supabase…';
  const [{ error }, health] = await Promise.all([
    supabase.auth.getSession(),
    fetch(new URL('/auth/v1/health', url), { headers: { apikey: key }, signal: AbortSignal.timeout(3000) })
  ]);
  output.textContent = error || !health.ok ? 'Web disponível; Supabase Auth indisponível.' : 'Web e Supabase Auth disponíveis.';
} catch { output.textContent = 'Web disponível. Verifique a configuração pública e a conexão com o Supabase.'; }
