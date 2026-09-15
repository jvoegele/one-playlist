import { createBrowserClient } from "@supabase/ssr";
import { getSupabasePublishableKey, getSupabaseUrl } from "./env";

// For use in Client Components ("use client"). Call this once per component/hook
// that needs it — it's cheap, no need to memoize or hoist to a module-level singleton.
export function createClient() {
  return createBrowserClient(getSupabaseUrl(), getSupabasePublishableKey());
}
