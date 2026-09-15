import { createClient } from "@/lib/supabase/server";

// TEMPORARY smoke test for the proxy/session plumbing (step 6 of the
// @supabase/ssr setup) — not the real login page. Replace with an actual
// sign-in form once that work starts.
export default async function LoginPage() {
  const supabase = await createClient();
  const { data, error } = await supabase.auth.getClaims();

  return (
    <div className="flex flex-1 flex-col items-center justify-center gap-4">
      <h1 className="text-3xl font-semibold">Login (placeholder)</h1>
      <pre className="text-sm">
        {JSON.stringify({ claims: data?.claims ?? null, error }, null, 2)}
      </pre>
    </div>
  );
}
