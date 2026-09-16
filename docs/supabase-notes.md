# Supabase notes — friction log

A running log of places `supabase-js`, the CLI, Edge Functions, or the platform generally
behaved surprisingly, each with an offline reproduction. Called for by `docs/port-plan.md` §18:
"reproduce offline, write it here, and consider filing it." This is the working source for
Jason's Supabase dogfood friction-log deliverable (presented to the team, in Notion) — keep
entries here as they're found; the Notion writeup is assembled from this file, not the other
way around. Realtime-specific friction goes in `docs/realtime-notes.md` instead, since that's
Jason's own team.

## `supabase functions serve` isn't implied by `supabase start`

**Found:** Spike 2 (pgmq → Edge Function round trip).

Local dev needs `supabase functions serve` running as its own persistent background process
for `pg_cron`/`pg_net` to have anything to invoke — `supabase start` does not serve functions
on its own. Easy to forget, and the failure is silent: `net.http_post` just fails with nothing
obviously wrong in `supabase start`'s own output.

## The Homebrew/mise CLI conflict

**Found:** Spike 2.

The Supabase CLI is only installable reliably via Homebrew (`supabase/tap/supabase`); a mise
plugin for it exists, but its shim wins on `$PATH` over the Homebrew binary, and there's no
clean way to disable just that one shim short of a mise config change. (Same shape of problem
the Elixir reference repo's `CLAUDE.md` already recorded, for a different tool.)

## Default-privilege auto-grants apply to functions, not just tables

**Found:** Spike 3 (Vault token round trip).

A fresh `SECURITY DEFINER` function created in `public` is auto-granted `EXECUTE` to `anon`,
`authenticated`, **and** `service_role` before any explicit grant runs — the same shape of
surprise the Elixir reference repo's `CLAUDE.md` already documents for new tables (`TRUNCATE`,
`REFERENCES`, `TRIGGER` landing on `anon`/`authenticated` unasked), but this time for functions.
`revoke all ... from public` does **not** remove it — these are separate explicit per-role
grants, not inherited through the `PUBLIC` pseudo-role. A function stayed callable by `anon`
even after `revoke all from public`, until the migration explicitly named
`revoke all ... from public, anon, authenticated, service_role` before granting back only what
was intended. Caught by an explicit `has_function_privilege(...)` check — not by the pgTAP
suite, since the tests never simulated `anon`. Worth carrying forward as a habit: **every
privileged function needs a per-role grant assertion, not just a happy-path test as the
intended caller.**

**Recurred:** 2026-09-16, `place_entry` — this time on a plain function, not a `SECURITY
DEFINER` one, which confirms the auto-grant isn't `DEFINER`-specific: it's every new function in
`public`, full stop. The agent wrote the same `revoke all ... from public`-only skeleton despite
this entry already existing, and it went unnoticed through a full review pass until a
`has_function_privilege('anon', ...)` check was run directly against the local DB while writing
the pgTAP suite — confirming the "every privileged function needs a per-role grant assertion"
habit above is worth actually holding to, not just recording once and moving on. Fixed the same
way: `revoke all ... from public, anon, authenticated, service_role`, then grant back only
`authenticated`/`service_role`. `place_entry.test.sql` now asserts both directions
(`authenticated` can execute, `anon` cannot) so a regression fails the suite, not a manual check.

## `vault.create_secret`'s `name` is globally unique

**Found:** Spike 3.

`name` is unique across the whole `vault.secrets` table (a real index, `secrets_name_idx`). A
fixed literal name across multiple calls (multiple users, or a rerun without a fresh
`db reset`) collides with `duplicate key value violates unique constraint`. Passing `null` (the
function's own default) sidesteps it; a real `store_connection_tokens` should derive a name
from the connection if it wants one to be discoverable, rather than hardcoding one.

## Temporary tables get no default privileges for other roles

**Found:** Spike 3. The mirror image of the auto-grant surprise above: a pgTAP fixture table
created as the connecting (superuser-ish) role needs an explicit
`grant select, insert on ... to authenticated, service_role` before a `set local role` switch
can touch it, or every subsequent statement fails with `permission denied for table`.

## `config.toml` email template changes need a full stop/start, and `content_path` is repo-root-relative

**Found:** Spike 5 (`@supabase/ssr` magic link).

- Adding a new `[auth.email.template.*]` section (`content_path`/`subject`) needs a full
  `supabase stop` then `supabase start`, not just a re-edit — `GOTRUE_MAILER_TEMPLATE_RELOADING_ENABLED=true`
  only hot-reloads a template *file's* contents at whatever `content_path` the container was
  already given; adding the config keys themselves means new container env vars, which only
  take effect when the container is recreated. A `stop` immediately followed by `start` was not
  sufficient here — suspect it raced the container's removal. Worth a `docker ps -a` check as a
  habit after `supabase stop`, if a config change doesn't seem to take.
- `content_path` is relative to the directory `supabase` is invoked from (the repo root here),
  not to `config.toml`'s own directory. `"./templates/magic_link.html"` (relative to
  `supabase/`, where the file lives) fails `supabase start` with `ENOENT`; the working value is
  `"./supabase/templates/magic_link.html"`.

## The emailed link's host must match how you navigate to it

**Found:** Spike 5. `auth.site_url` was `http://127.0.0.1:3000`, so that's what's in the
magic-link email — visiting `http://localhost:3000` instead is a different origin as far as
cookies are concerned, which misleadingly looks like the "opened on a different device" case
even on the same machine.

## `127.0.0.1` vs `localhost` silently breaks Next dev's client JS

**Found:** Spike 6 (`linkIdentity` with Spotify).

Spotify's OAuth rejects `localhost` as a redirect host outright, so the app has to be browsed
via `127.0.0.1` — but Next's dev server then logs (server-side only, not in the browser
console) "Blocked cross-origin request to Next.js dev resource ... from 127.0.0.1" and refuses
to serve the client JS bundle. The page still renders (SSR), so the symptom is a button that
looks normal but silently does nothing on click — no console error, no visible network
failure, because the block happens on page load, not on click. Fix:
`allowedDevOrigins: ["127.0.0.1"]` in `next.config.ts`.

## The official Next.js auth UI block still scaffolds the deprecated `middleware.ts`

**Found:** 2026-09-15, installing `npx shadcn add @supabase/password-based-auth-nextjs`.

The block (Supabase's own registry, `https://supabase.com/ui/r/{name}.json`) generates
`src/middleware.ts` + `src/lib/supabase/middleware.ts` implementing the session-refresh logic —
but Next.js 16 renamed `middleware` to `proxy` and hard-errors if both a `middleware.ts` and a
`proxy.ts` file exist in the same app ("Please use ./src/proxy.ts only"). A project that already
followed the (also Supabase-published) `@supabase/ssr` Next.js guide and has its own `proxy.ts`
breaks the moment this block is added, until the generated `middleware.ts` files are deleted by
hand and the redirect target patched into the existing `proxy.ts`. Two Supabase-maintained
surfaces — the SSR guide and this UI block — disagree with each other on a Next.js 16 project.
The block's `client.ts`/`server.ts` also silently overwrite any existing files at those paths
with versions that inline `process.env.X!` directly, dropping any project convention (e.g. a
shared `env.ts` helper with real runtime validation) for reading them — worth diffing with
`--diff` before accepting the overwrite.

## Not (yet) filed upstream

None of the above have been filed as GitHub issues / support tickets yet — port-plan.md §18
says "consider filing it" for anything that's a genuine defect rather than a documentation
gap. Worth a pass once the Notion friction log is being assembled, to decide which of these are
worth Supabase's own attention versus just "worth knowing."
