import { createServerClient } from "@supabase/ssr";
import { cookies } from "next/headers";
import { getSupabasePublishableKey, getSupabaseUrl } from "./env";

// For use in Server Components, Server Actions, and Route Handlers.
// Must be called fresh on every request — the cookie store it reads is
// request-scoped, so (unlike the browser client) this can't be hoisted
// or reused across requests.
export async function createClient() {
  const cookieStore = await cookies();

  return createServerClient(getSupabaseUrl(), getSupabasePublishableKey(), {
    cookies: {
      getAll() {
        return cookieStore.getAll();
      },
      setAll(cookiesToSet) {
        try {
          cookiesToSet.forEach(({ name, value, options }) => {
            cookieStore.set(name, value, options);
          });
        } catch {
          // ignore errors, e.g. "cookies can only be set in middleware or route handlers"
        }
      },
    },
  });
}
