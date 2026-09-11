import { createClient } from '@supabase/supabase-js';
import type { RuntimeConfig } from './config.ts';

const authOptions = {
  persistSession: false,
  autoRefreshToken: false,
  detectSessionInUrl: false
} as const;

export function publicSupabase(config: RuntimeConfig) {
  return createClient(config.url,config.publishableKey,{auth:authOptions});
}

export function userSupabase(config: RuntimeConfig, accessToken: string) {
  return createClient(config.url,config.publishableKey,{
    auth: authOptions,
    global: { headers: { Authorization: 'Bearer ' + accessToken } }
  });
}

export function adminSupabase(config: RuntimeConfig) {
  return createClient(config.url,config.secretKey,{auth:authOptions});
}
