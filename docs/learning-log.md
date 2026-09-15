# Learning log

One line per concept, dated, with the file it first appeared in. See `docs/port-plan.md`
§3 for why this file exists.

- **2026-09-13** — pnpm workspaces: one `pnpm-workspace.yaml` + one root lockfile share a single
  `node_modules` across multiple packages (`apps/web` today; `packages/core` later), instead of
  each package installing its own dependencies independently. `pnpm-workspace.yaml`
- **2026-09-13** — `pnpm --filter <name> <script>` runs a script from one workspace member's
  `package.json` `scripts` map, resolved by that package's `name` field, without `cd`-ing into
  it. `apps/web/package.json`
- **2026-09-13** — Biome: one binary for both lint and format (replaces ESLint + Prettier).
  Chose 2-space indentation over its tab default to match ecosystem convention (set by
  Prettier) and Jason's own editor config. `biome.json`
- **2026-09-13** — `noUncheckedIndexedAccess`: makes array/object indexing return `T | undefined`
  instead of assuming the index exists — closest Elixir analogue is `Map.get/2` (maybe-nil)
  versus `Map.fetch!/2` (assumed present), except enforced at compile time here.
  `apps/web/tsconfig.json`
- **2026-09-13** — `exactOptionalPropertyTypes`: makes `{ foo?: string }` distinguish "key
  omitted" from "key present but `undefined`" — will matter once Zod is validating provider
  payloads where "absent" and "explicitly null" are different states. `apps/web/tsconfig.json`
- **2026-09-13** — Tailwind v4 configures itself in CSS via a native `@theme` block, rather than
  a `tailwind.config.js` (the v3 way) — Biome's CSS parser needs `tailwindDirectives: true` to
  parse it without erroring. `apps/web/src/app/globals.css`, `biome.json`
- **2026-09-13** — shadcn/ui isn't a component library, it's a generator: `shadcn add` copies a
  component's actual source into the repo (on Base UI primitives here), rather than installing
  an opaque package. You own and edit the generated file from day one.
  `apps/web/src/components/ui/button.tsx`
- **2026-09-13** — RLS migration convention for this port: every new `public` table gets `enable
  row level security`, an explicit `revoke all ... from anon, authenticated`, then only the
  grants actually needed. Unlike the Elixir app (which wrote through a privileged `postgres`
  connection and only exposed `authenticated` for reads), every read *and* write here goes
  through PostgREST with the user's own JWT — so a user-owned table needs full
  insert/update/delete grants and a `FOR ALL` policy, not just `SELECT`.
  `supabase/migrations/20260913140251_create_library_playlists.sql`
- **2026-09-13** — `moddatetime` (a Postgres contrib extension, installed to the `extensions`
  schema) + a `BEFORE UPDATE` trigger is the standard way to keep an `updated_at` column current
  — there's no ORM here to do it in application code the way Ecto did. Needs `id`/timestamp
  columns to also get real DB-side defaults (`gen_random_uuid()`, `now()`) for the same reason.
  same file
- **2026-09-13** — pgTAP tests impersonate a real user with `set local role authenticated;
  select set_config('request.jwt.claims', '{"sub":"<uuid>","role":"authenticated"}', true);` —
  this is what actually exercises RLS policies, as opposed to querying as the superuser role
  the test file runs under by default. `supabase/tests/library_playlists.test.sql`
- **2026-09-13** — Two pgTAP gotchas worth remembering: (1) `now()` is frozen for the whole
  transaction, so a test wrapped in one `begin`/`rollback` can't detect an `updated_at` bump by
  comparing "before" and "after" — instead, backdate a fixture value far enough in the past
  (e.g. year 2000) that the comparison holds regardless. (2) Verifying that a write against
  *another* user's row was blocked must be checked from a role that isn't itself restricted by
  the same policy (`reset role` before the check), or the check can pass for the wrong reason —
  the acting user's own `SELECT` policy would hide that row regardless of whether the write was
  actually blocked. same file
- **2026-09-14** — `supabase test db` recursively runs *every* `.sql` file under `supabase/tests/`
  as its own independent, un-transacted psql script — there's no `.test.sql` filter and no way to
  exclude a file via `config.toml` (checked: subdirectories and dotfiles are swept up too). So a
  shared "fixtures" file can't safely live in that directory: tried factoring the Alice/Bob setup
  out of `library_playlists.test.sql` and `provider_connections.test.sql` into one `\ir`-included
  file, and it got executed on its own, outside any transaction, and actually committed the
  fixture rows into the local dev database's `auth.users`. Moving it to a sibling directory
  avoided that but made it unreachable — only `supabase/tests/` itself is visible to `\ir` at
  runtime. Net effect: each pgTAP test file in this repo stays fully self-contained, duplicated
  fixture block and all. `supabase/tests/library_playlists.test.sql`,
  `supabase/tests/provider_connections.test.sql`
