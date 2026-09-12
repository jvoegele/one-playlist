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

**Friction worth logging** (not yet moved to `docs/supabase-notes.md` — that file doesn't
exist yet, first candidate for it):
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

**Friction worth logging** (candidate for `docs/supabase-notes.md`, alongside Spike 2's):
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

Status: not started.

## 5. `@supabase/ssr` magic link with `token_hash`

Status: not started.

## 6. `linkIdentity` provider-token capture

Status: not started.
