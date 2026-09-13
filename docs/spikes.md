# Spikes (§14 of port-plan.md)

Each spike is a throwaway branch; the result recorded here is what carries forward. Written
2026-09-12 onward.

## 1. Shared code deploy

Status: done, on branch `spike/1-shared-code-deploy` (not merged — throwaway per §14).

**Setup:** `packages/core/index.ts` exports a trivial `pingCore()`. A `shared-code-test` Edge
Function imports it by relative path reaching outside `supabase/functions/`
(`../../../packages/core/index.ts`) and returns its result. Deployed with `supabase functions
deploy` against a real hosted project (free tier, org/project both named "One Playlist",
created under Jason's `jason.voegele@supabase.io` account — not necessarily the project that
ends up hosting the shipped app; that's still §17 Q1, unresolved).

**Confirmed:** the CLI's `functions deploy` bundles the whole resolved dependency graph, not
just the function's own directory — deploy logged "Bundling Function: shared-code-test (script
size: 1.0 kB)", and invoking the deployed function returned `{"core":"core-ok"}`. The import
across the `supabase/functions/` boundary works.

**Decision (§12): `packages/core` as planned**, with a `deno.json` import map in each function
mapping `@core/` to it, per §12's first branch. The fallback layout
(`supabase/functions/_shared/core/`) is not needed.

**Not exercised:** only a single-file, dependency-free export was tested. `packages/core` will
eventually import Zod and a fuzzy-matching library (§12 requires both be pure, no Node-only
APIs) — worth a quick recheck once those are actually in `packages/core`, but the mechanism
(relative imports outside the function directory bundle correctly) is what was in question, and
that's answered. The test function and its hosted deployment have been deleted from the
project; nothing was left running or billing.

## 2. pgmq → Edge Function round trip

Status: done, on branch `spike/2-pgmq-roundtrip` (not merged — throwaway per §14; the branch
itself is disposable, this write-up is the artefact that lasts).

**Setup:** a migration enables `pgmq`, `pg_cron`, `pg_net` (each lands in its own schema —
`pgmq`, `cron`, `net` — with no `with schema` needed) and creates `spike_queue`. A
`spike-worker` Edge Function reads with `pgmq.read`, "processes" (logs), and archives with
`pgmq.archive` — talking to Postgres directly via `postgres.js` (`npm:postgres`) rather than
`supabase-js`, because pgmq's schema isn't in `config.toml`'s `[api] schemas` and so isn't
reachable through PostgREST. This is the shape port-plan.md §9 prescribes for every real
worker ("the worker uses the service role over a direct SQL client"). A second migration
schedules `cron.schedule(..., '5 seconds', ...)` calling `net.http_post` against the function.

**Confirmed:**
- The full round trip works locally: cron fires → `net.http_post` → Kong → `spike-worker` →
  `pgmq.read` → archive, no manual invocation needed.
- **`pg_net`'s URL must be the Kong container's name on the compose network**
  (`http://supabase_kong_one-playlist:8000/...`), not `127.0.0.1:54321` — `pg_net` runs inside
  the `db` container, which can't see the host's port mapping. Same lesson the Elixir repo's
  `CLAUDE.md` already recorded for Storage pruning; it generalizes to every `pg_net` call, not
  just that one.
- **Redelivery works as designed.** Sent a message, had the worker artificially sleep 45s
  mid-processing, then `docker kill`ed the `supabase_edge_runtime_one-playlist` container
  partway through (simulating a crashed invocation). The in-flight HTTP request came back
  `502`. The message stayed un-archived with its `vt` in the future; once `vt` lapsed,
  `pgmq.read` returned the same message again with `read_ct` incremented 1 → 2. This is
  pgmq's equivalent of Oban/Lifeline's rescue: a lapsed visibility timeout is what makes a
  killed invocation safe to retry, and nothing had to detect the crash for that to be true.
- **Latency is bounded by the cron interval, not fixed.** Three messages sent 2s apart against
  a 5s cron cadence measured round trips of 140ms, 2.2s, and 3.1s — i.e., uniform over
  [0, interval), as expected for polling. This is the empirical basis for §9's suggestion that
  the Server Action creating a transfer should also fire a direct `fetch()` to the worker for
  a snappier feel, with cron only as the backstop; at the real 1-minute cadence, worst case is
  a 60s wait with no direct call.

**Friction worth logging** (filed in `docs/supabase-notes.md`):
- Local dev needs `supabase functions serve` running as its own persistent background process
  for cron/pg_net to have anything to invoke — `supabase start` does not serve functions by
  itself. Easy to forget and get silent `net.http_post` failures with nothing obviously wrong
  in `supabase start`'s own output.
- The Supabase CLI is only installable reliably via Homebrew (`supabase/tap/supabase`); the
  mise plugin for it exists but its shim wins on `$PATH` over the Homebrew binary and there's
  no clean way to disable just that one shim short of a mise config change. Same shape of
  problem the Elixir repo's `CLAUDE.md` already recorded, different tool. Left unfixed for
  now — used the full path `/opt/homebrew/bin/supabase` throughout this spike.

## 3. Vault token round trip

Status: done, on branch `spike/3-vault-token-roundtrip` (not merged — throwaway per §14).

**Setup:** a migration creates `spike_vault_rows` (`owner uuid`, `secret_id uuid`, RLS on,
policies scoped to `owner = (select auth.uid())`) plus two `SECURITY DEFINER` functions —
`spike_store_token(p_token)`, granted to `authenticated`, which calls `vault.create_secret` and
writes the row itself (owner = the caller); and `spike_read_token(p_row_id)`, granted only to
`service_role`, which joins the row to `vault.decrypted_secrets` and returns the plaintext. This
is a smaller stand-in for §8's `store_connection_tokens` / `connection_tokens` pair — no
`provider_connections` table yet, just enough surface to test the Vault mechanism and the grant
boundary around it. pgTAP tests (`supabase/tests/database/spike_vault_roundtrip_test.sql`, run
with `supabase test db --local`) exercise it as `authenticated` (two different simulated users,
via `set local role` + `set local request.jwt.claim.sub`) and as `service_role`.

**Confirmed**, all 8 pgTAP assertions passing:
- The full round trip works: `authenticated` stores a token through the rpc, `service_role`
  reads back the exact plaintext through `spike_read_token`.
- **`authenticated` cannot read `vault.decrypted_secrets` directly** — `permission denied for
  schema vault`, not merely a denied column or row. `anon`/`authenticated` have no grant on the
  `vault` schema at all locally, so this holds even before any policy is written; §8's design
  (only `service_role`-granted functions touch the view) is enforcing a boundary Vault already
  defaults to, not one this app has to build from scratch.
- **RLS on `spike_vault_rows` scopes correctly**: the owner sees their row, a second simulated
  user sees zero rows, and that second user's attempt to *insert* a row claiming `owner =` the
  first user's id is rejected (`42501`, the RLS-violation code, same as a straight permission
  denial) by the `with check` policy — this is the mechanism behind §8's "granted to
  `authenticated` with a check that the connection belongs to `auth.uid()`".

**Friction worth logging** (filed in `docs/supabase-notes.md`, alongside Spike 2's):
- **Supabase's default-privilege auto-grants apply to functions, not just tables.** The Elixir
  repo's `CLAUDE.md` already documents this for new tables in `public` (`TRUNCATE`,
  `REFERENCES`, `TRIGGER` land on `anon`/`authenticated` unasked). The same thing happens for
  *functions*: a fresh `SECURITY DEFINER` function in `public` is auto-granted `EXECUTE` to
  `anon`, `authenticated` **and** `service_role` before any explicit grant runs. `revoke all ...
  from public` does **not** remove this — those are separate explicit per-role grants, not
  inherited through the `PUBLIC` pseudo-role, so `spike_store_token` was callable by `anon` even
  after a `revoke all from public` until the migration was corrected to `revoke all ... from
  public, anon, authenticated, service_role` by name before granting back only what was
  intended. Caught here by an explicit `has_function_privilege(...)` check, not by the pgTAP
  suite — the tests never simulated `anon`, which is itself worth carrying forward: **every
  privileged function needs a per-role grant assertion, not just a happy-path test as the
  intended caller.**
- `vault.create_secret`'s `name` argument is unique across the whole `vault.secrets` table (a
  real index, `secrets_name_idx`). A fixed literal name across multiple calls (multiple users,
  or a rerun without a fresh `db reset`) collides with `duplicate key value violates unique
  constraint`. Passing `null` (the function's own default) sidesteps it; a real
  `store_connection_tokens` should derive a name from the connection if it wants one to be
  discoverable, not hardcode one.
- Temporary tables get **no default privileges for other roles**, unlike `public`-schema
  functions above — the opposite gotcha. A pgTAP fixture table created as the connecting
  (superuser-ish) role needs an explicit `grant select, insert on ... to authenticated,
  service_role` before a `set local role` switch can touch it, or every subsequent statement
  fails with `permission denied for table`.
- pgTAP's `throws_ok`/`lives_ok`/`results_eq` honour whatever role is currently set
  (`set local role ...` + `set local request.jwt.claim.sub ...`) at the point they're called,
  since the SQL under test runs as a plain `EXECUTE` in the same session — no special handling
  needed to test RLS or grants across simulated users within one pgTAP transaction, as long as
  the fixture-table privileges above are sorted out first.

## 4. Broadcast from Database on a private channel

Status: done, on branch `spike/4-broadcast-private-channel` (not merged — throwaway per §14).

**Setup:** a migration creates `spike_topics` (owned, RLS) and `spike_events` (RLS, scoped
through its parent topic), a trigger on `spike_events` calling `realtime.broadcast_changes`
onto `'spike:' || topic_id`, and — the actual question — a `FOR SELECT TO authenticated` policy
on `realtime.messages` authorizing a join to that topic only for its owner. A throwaway
`apps/web` (Next.js 16, App Router) is the first real code in this repo outside `supabase/`:
`/spike/[topicId]` is a Server Component (`@supabase/ssr`, cookie-based session, redirects to
`/login` if signed out) rendering a Client Component that calls
`await supabase.realtime.setAuth()` then subscribes to `spike:<topicId>` as a `{ private: true }`
channel, per §10's sketch. Two real local users were created via `supabase.auth.signUp`
(`enable_confirmations = false` locally, so it's immediate). `apps/web/scripts/spike4-probe.mjs`
drives it with Playwright — a real browser against the real dev server and the real local
Realtime container, not a mock of any of the three.

**Confirmed:**
- **The owner's subscribe succeeds** (`SUBSCRIBED`) and the broadcast arrives over the channel
  with no page reload, carrying exactly what the trigger sent.
- **A different signed-in user's subscribe to the same topic fails closed, loudly**: channel
  status `CHANNEL_ERROR`, with an explicit error — `Unauthorized: You do not have permissions to
  read from this Channel topic: spike:<id>` — surfaced straight from `.subscribe()`'s callback.
  This is exactly what §14 asked to confirm: not silently receiving nothing, an actual refused
  join. Re-ran twice for reproducibility, both clean.
  While that user's channel sits in `CHANNEL_ERROR`, the owner posting another event confirms
  the non-owner never receives it — the failed join isn't a soft/delayed one.
- **An anon visitor (no session at all) never reaches the channel code**: the Server Component's
  own `auth.getUser()` redirects to `/login` before the Client Component mounts. A second,
  independent layer ahead of Realtime's own check — worth keeping both, since they answer
  different questions (signed in at all vs. authorized for *this* topic).
- **pgTAP** (`supabase/tests/database/spike_broadcast_private_channel_test.sql`, 5 assertions)
  tests the `realtime.messages` policy expression directly: the owner sees a seeded message on
  their topic, a different user does not, that same user does on their *own* topic, the policy
  never matches outside the `spike:` namespace, and `anon` is refused regardless — since the
  policy is `TO authenticated` only. This tests the policy's logic; the live-refusal behaviour
  above (that Realtime enforces it at join time, and fails the join rather than the delivery) is
  what the Playwright probe is for, since pgTAP runs inside one Postgres transaction and can't
  drive a real websocket handshake.

**A real finding, not just spike mechanics — port-plan.md §10's own draft policy needed
tightening.** The prescribed shape (`realtime.topic() like 'transfer:%' and exists (...)`) never
compares the *row's own* `topic` column to the `realtime.topic()` GUC — it's a per-session
boolean ("is the caller authorized for *some* topic they own right now"), not a per-row filter.
Caught by writing the pgTAP test to expect a topic-scoped count and instead getting the whole
table's row count back — every leftover message from every topic the owner had ever touched,
across unrelated topics, because the `exists` clause was satisfied by any one of them. Adding
`topic = realtime.topic()` to the `USING` clause fixed it, confirmed by both the pgTAP suite and
a re-run of the live probe. This didn't change Realtime's own real join-time behaviour — its
dry-run check is already scoped to the one topic being joined — but the *policy itself* was
silently wrong by ordinary RLS standards, exactly the "passes for months while leaking" §10
already worried about. Worth carrying the `topic = realtime.topic()` clause into the real
`transfers` policy in Phase 5.

**Friction worth logging** (filed in `docs/realtime-notes.md`, since Jason is on this team — §10 says to):
- Per Supabase's own Realtime Authorization docs: the join-time check "performs a query on the
  `realtime.messages` table and then rolls it back" — no pre-existing row is required, and
  `realtime.topic()` is set to the topic being joined only for the duration of that check. This
  means a pgTAP test can validate the *policy expression* but not the live dry-run mechanism
  itself; that needs an actual client against a running Realtime server, which is what
  `spike4-probe.mjs` is for.
- **Next.js 16 renamed `middleware.ts` to `proxy.ts`** (functionality unchanged) — `next dev`
  logs a deprecation warning and names the exact codemod
  (`npx @next/codemod middleware-to-proxy .`), which worked cleanly. A freshly scaffolded app
  also carries a generated `AGENTS.md` warning that "this is NOT the Next.js you know" and to
  read `node_modules/next/dist/docs/` before writing code — worth doing for real in Phase 1
  rather than relying on training-data conventions, since a fresh session would otherwise write
  the outdated `middleware.ts` convention by default, as this spike initially did.
- **Server Actions can't be exercised with plain `curl`** — the request needs the RSC
  action-id protocol a real page load sets up, not just matching form field names. A raw POST
  gets `Failed to find Server Action`. Anything that exercises a Server Action needs a real
  browser; Playwright (added as a throwaway devDependency here) filled in for the missing
  claude-in-chrome extension this session, and is worth keeping in mind generally as the
  fallback for driving Server Actions/RSC flows headlessly.

## 5. `@supabase/ssr` magic link with `token_hash`

Status: done, on branch `spike/5-magic-link-token-hash` (not merged — throwaway per §14).
Spike 4's `apps/web` is gone with its branch, so this one re-scaffolds Next.js 16 from
scratch (`npx create-next-app` — mechanical) rather than building on anything left on `main`.

**Setup:** `/sign-in` (Client Component) posts to two Server Actions —
`requestOtp` calls `supabase.auth.signInWithOtp({ email, options: { shouldCreateUser: true } })`,
`verifyCode` calls `supabase.auth.verifyOtp({ email, token, type: 'email' })` — using a
`createServerClient` from `src/lib/supabase/server.ts` (cookie-based, per the SSR guide).
`src/app/auth/confirm/route.ts` is a Route Handler for the link: it calls
`supabase.auth.verifyOtp({ token_hash, type })`, **never** `exchangeCodeForSession`, per §8.
`src/proxy.ts` refreshes the session on every request via `getClaims()`. A protected
`/spike` Server Component page (mirrors spike 4's pattern) reads `getClaims()` and shows the
signed-in email, or redirects to `/sign-in`. `supabase/templates/magic_link.html` and
`confirmation.html` both carry the `{{ .SiteURL }}/auth/confirm?token_hash={{ .TokenHash
}}&type=email` link and the `{{ .Token }}` six-digit code, wired into `config.toml`'s
`[auth.email.template.magic_link]` / `[auth.email.template.confirmation]`.
`apps/web/scripts/spike5-probe.mjs` drives it with Playwright against local Mailpit's API
(`/api/v1/messages`, `/api/v1/message/{id}`) — two independent flows, each its own email
address: the token_hash link opened in a Playwright `browser.newContext()` sharing no
cookies with the one that requested it (the "different device" case), and the six-digit
code entered back in the requesting tab.

**Confirmed:**
- **Both flows land signed in.** The link, opened in a browser context with zero cookie
  overlap with the requesting one, reaches `/spike` and shows the right email — no PKCE
  verifier cookie is available to it, yet `verifyOtp({ token_hash, type: 'email' })`
  succeeds anyway. This is the concrete answer to §8's warning: the failure mode belongs to
  `exchangeCodeForSession` (the PKCE code-exchange route), not to the `token_hash` +
  `verifyOtp` route this plan already chose. Confirmed **even though** `signInWithOtp`
  from `@supabase/ssr`'s `createServerClient` generates a `token_hash` value with a literal
  `pkce_` prefix (visible in the emailed link and in server logs) — that prefix is
  GoTrue's internal naming for how the hash was derived, not a marker that `verifyOtp`
  needs a matching verifier cookie to succeed.
- **The six-digit code path works independently**, entered back in the same tab that
  requested it, via `verifyOtp({ email, token, type: 'email' })`.
- **Both templates loaded without error** — `supabase start` set
  `GOTRUE_MAILER_TEMPLATES_MAGIC_LINK` / `_CONFIRMATION` and `GOTRUE_MAILER_SUBJECTS_*` on
  the `auth` container from `config.toml`'s new sections. Only `magic_link.html` was
  exercised by a live flow, though: this project's local config sets
  `enable_confirmations = false`, which maps to `GOTRUE_MAILER_AUTOCONFIRM=true` on the
  container, so GoTrue never needs the separate signup-confirmation step even for a
  brand-new address — every `signInWithOtp` here sends the `magic_link` template. §8's
  reasoning ("which one GoTrue sends depends on `enable_confirmations`") still holds; this
  local config just always lands on one side of that switch. `confirmation.html` is
  presumably what a hosted project with `enable_confirmations = true` (or the first-touch
  signup case) would send — not empirically checked here.

**Friction worth logging** (filed in `docs/supabase-notes.md`, alongside spikes 2 and 3's):
- **A `config.toml` `[auth.email.template.*]` addition needs a full `supabase stop` then
  `supabase start`, not just a re-edit.** `GOTRUE_MAILER_TEMPLATE_RELOADING_ENABLED=true`
  hot-reloads a template *file's contents* at whatever `content_path` the container was
  already given, but adding the `content_path`/`subject` config keys themselves means new
  container env vars, which only get set when the container is recreated. A `supabase stop`
  immediately followed by `supabase start` was not sufficient here — the auth container came
  back up with the *old* env (no template vars set at all) until a `docker ps` check
  confirmed the containers were actually gone before starting again. Suspect the first
  `stop`/`start` pair raced the container's removal; worth a `docker ps -a` check as a habit
  after `supabase stop` when a config change doesn't seem to take.
- **`content_path` in `config.toml` is relative to the directory `supabase` is invoked
  from (the repo root here), not to `config.toml`'s own directory.** Using
  `"./templates/magic_link.html"` (relative to `supabase/`, where the file actually lives)
  failed `supabase start` with `ENOENT`; the working value is
  `"./supabase/templates/magic_link.html"`, matching the commented-out stock example the
  scaffolded `config.toml` already carried for `invite.html`.
- **The emailed link's host must match how you navigate to it.** `auth.site_url` here is
  `http://127.0.0.1:3000`, so that's what's in the link — a probe or a person visiting
  `http://localhost:3000` instead sees a different origin as far as cookies are concerned,
  which can misleadingly look like the "different device" case even on the same machine.
  Cost one debugging pass here before switching the probe's own `APP_URL` to match.
- **`npx create-next-app apps/web` failed** with "path not writable" (even with the
  sandbox's write restrictions lifted) when run from the repo root; running it as `cd apps
  && npx create-next-app web` succeeded. Not chased further — possibly specific to this
  agent's sandboxed shell rather than a general `create-next-app` issue — but worth trying
  the `cd`-into-parent form first if it recurs.
- Next.js 16's generated `AGENTS.md`/`CLAUDE.md` "this is NOT the Next.js you know" note
  reappeared, as in spike 4. Read `node_modules/next/dist/docs/01-app/02-guides/
  authentication.md` and `.../01-getting-started/{15-route-handlers,16-proxy}.md` this time
  — confirmed `proxy.ts` (not `middleware.ts`) and the Route Handler conventions are
  unchanged from spike 4's findings.

## 6. `linkIdentity` provider-token capture

Status: done, on branch `spike/6-linkidentity-spotify` (not merged — throwaway per §14). Last
of the six pre-Phase-1 spikes. Reuses the Elixir project's existing Spotify app (its dashboard
gained `http://127.0.0.1:54321/auth/v1/callback` as an extra redirect URI), rather than a new
one, since it's still a personal/5-user Development Mode app either way.

**Setup:** password sign-in (simplest way to a real session; magic link was already proven in
spike 5) plus a `/spike` page with a "Connect Spotify" button (Client Component — `linkIdentity`
needs the SDK's own browser redirect, so it can't run from a Server Action). Per port-plan.md
§8: `linkIdentity({ provider: 'spotify' })`, **never** `signInWithOAuth`, so it attaches to the
signed-in user instead of risking a silent sign-in to a different account. `/auth/callback`
(Route Handler) calls `exchangeCodeForSession(code)`, checks `session.provider_token` /
`provider_refresh_token`, then immediately calls Spotify's own `/api/token` endpoint with
`grant_type=refresh_token` and the app's client secret to prove the refresh token is real and
usable — not just present. `config.toml` gained `enable_manual_linking = true` and
`[auth.external.spotify]` (`env(SUPABASE_AUTH_EXTERNAL_SPOTIFY_CLIENT_ID/SECRET)`, via a new
gitignored `supabase/.env`, `supabase/.env.example` as the committed template — same pattern
the Elixir repo uses for its own local credentials). No Playwright here: the actual Spotify
login/consent screen was driven by Jason, live, in his own browser — not something to script
against a real third-party account.

**Confirmed**, all four checks true on the results page:
- `provider_token` and `provider_refresh_token` are both present in the `exchangeCodeForSession`
  result, server-side, immediately after the redirect back from Spotify.
- **The refresh token is real**: POSTing it to `https://accounts.spotify.com/api/token` with
  the app's client secret returns `200`. This is the load-bearing confirmation for §8 — it's not
  enough that GoTrue hands the token over once; the token itself has to work against Spotify's
  own endpoint, since this application (not Supabase) owns refreshing it from here on.
- **They don't survive a session refresh.** The first attempt at this check read `getSession()`
  immediately after `exchangeCodeForSession()` in the same request and got a false negative
  (still `true`/present) — that's just re-reading the same still-valid JWT, not a real test.
  Forcing an actual refresh with `supabase.auth.refreshSession()` and checking *that* result
  is what actually answers the question, and it came back correctly empty. Matches the Elixir
  `CLAUDE.md`'s hard constraint verbatim: "`provider_token` and `provider_refresh_token` appear
  once in the session and are then gone."
- **One Spotify identity can only be linked to one Supabase user at a time.** A second local
  test account's `linkIdentity` attempt failed closed and loudly —
  `identity_already_exists` / "Identity is already linked to another user" — surfaced in the
  callback URL's fragment, not silently. This is §8's own "one identity per provider per user"
  constraint enforced by Auth itself, not just a planning assumption; freeing it up for re-test
  meant deleting the row from `auth.identities` directly.

**Decision: §8's hybrid holds for Spotify.** The refresh token arrives and works, so Spotify
stays on the Supabase Auth (`linkIdentity`) path rather than falling back to an own flow.

**Friction worth logging** (filed in `docs/supabase-notes.md`):
- **Browsing via `127.0.0.1` instead of `localhost` silently breaks client-side JS in Next
  dev.** `auth.site_url` and the Spotify redirect URI both need `127.0.0.1` (Spotify rejects
  `localhost` outright, per the Elixir `CLAUDE.md`), so that's how the app has to be browsed —
  but Next's dev server logged (server-side, not in the browser console) "Blocked cross-origin
  request to Next.js dev resource ... from 127.0.0.1" and refused to serve the client JS bundle.
  The page still rendered (SSR), so the symptom was a button that looked normal but silently did
  nothing on click — no console error, no visible network failure, because the block happened on
  page load, not on click. Fix: `allowedDevOrigins: ["127.0.0.1"]` in `next.config.ts`.
- A quick, wrong probe is worse than no probe: the first "absent afterward" check technically
  ran and returned an answer, and the answer was misleading rather than obviously broken — worth
  remembering that a passing check still needs to be checking the right thing.
