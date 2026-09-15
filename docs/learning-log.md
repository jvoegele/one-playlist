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
- **2026-09-15** — Supabase's own "declarative schemas" (`supabase/schemas/*.sql` + `supabase db
  diff`) is the CLI's recommended alternative to hand-writing migrations, but its diff engine
  doesn't track RLS policy renames or column grants cleanly (documented `migra`/`pg-delta`
  caveats) — decided to keep writing migrations by hand, so RLS stays individually reviewable.
  Decision, no file.
- **2026-09-15** — `@supabase/ssr`'s browser/server clients are two different factories on
  purpose: `createBrowserClient` needs no cookie plumbing (the browser handles its own), while
  `createServerClient` takes a cookie adapter (`getAll`/`setAll`) backed by `next/headers`'s
  `cookies()` — which is itself `async` in this Next version, so the server factory has to be
  `async` too. `apps/web/src/lib/supabase/client.ts`, `apps/web/src/lib/supabase/server.ts`
- **2026-09-15** — `NEXT_PUBLIC_*` env vars reach the browser bundle by Next statically replacing
  the literal `process.env.NEXT_PUBLIC_X` expression at build time — it does not ship all of
  `process.env`. A shared helper that does `process.env[name]` with a dynamic `name` would
  silently return `undefined` in browser code; the fix is a helper that takes the
  already-dereferenced *value*, not the variable *name*. `apps/web/src/lib/supabase/env.ts`
- **2026-09-15** — TypeScript's non-null assertion (`value!`) is compile-time only — it erases to
  nothing at runtime, so a wrong assertion just lets `undefined` flow through to fail confusingly
  downstream. Biome's `noNonNullAssertion` (mirrors `@typescript-eslint/no-non-null-assertion`)
  flags it for that reason; `env.ts`'s `required()` does the equivalent check for real, at
  runtime. `apps/web/src/lib/supabase/env.ts`
- **2026-09-15** — Concise-body arrow functions (`(x) => f(x)`, no braces) implicitly `return` the
  expression's value — easy to trip Biome's "callback passed to forEach() should not return a
  value" lint by accident, since `.forEach()`'s contract is side-effects-only. Fix: wrap the body
  in `{ }`. `apps/web/src/lib/supabase/proxy.ts`
- **2026-09-15** — Next.js renamed "middleware" to "proxy": a root `proxy.ts` (exporting
  `proxy()`) is now the convention, and the Supabase guide splits the actual logic into
  `lib/supabase/proxy.ts`'s `updateSession()`, mirroring the existing
  `client.ts`/`server.ts`/`env.ts` split. `apps/web/src/proxy.ts`,
  `apps/web/src/lib/supabase/proxy.ts`
- **2026-09-15** — `getClaims()` vs `getSession()`: only `getClaims()` revalidates the JWT
  (against Supabase Auth's JWKS) rather than trusting whatever's in the cookie, so it's the one to
  use for any check that gates access — `getSession()` is for reading claims when nothing
  security-sensitive rides on them. `apps/web/src/lib/supabase/proxy.ts`
- **2026-09-15** — Next.js 16 auto-generates `AGENTS.md`/`CLAUDE.md` per app on `next dev` (a
  short "this Next version may differ from your training data, check
  `node_modules/next/dist/docs/`" note) and recreates them if deleted; its own guidance is to
  commit them. Doesn't touch the repo-root `CLAUDE.md`. `apps/web/AGENTS.md`, `apps/web/CLAUDE.md`
- **2026-09-15** — First Server Action: an `async` function marked `'use server'`, handed
  directly to `<form action={fn}>`. React/Next turns it into a POST endpoint and passes the
  submitted `FormData` as the function's argument — the browser posts the form natively (works
  without JS), no client-side `onSubmit` wiring needed. Closest Phoenix analogue: a controller
  action colocated with the template that renders its form, with the routing auto-wired.
  `apps/web/src/app/auth/login/actions.ts`
- **2026-09-15** — `redirect()` (from `next/navigation`) throws a control-flow exception to
  short-circuit the action — code after it never runs, and calling it from inside an unawaited
  `.then()` callback breaks it (the throw happens outside the call stack Next is watching to
  catch it). `revalidatePath()` doesn't throw, so it must be called *before* `redirect()`, not
  after, or the revalidation never executes. same file
- **2026-09-15** — `searchParams` (and `params`) on a Server Component page are `Promise`s in
  this Next version, not plain objects — `const { error } = await searchParams;` before use.
  `apps/web/src/app/auth/login/page.tsx`
- **2026-09-15** — shadcn's CLI isn't limited to single UI primitives: `npx shadcn add
  <registry>/<block-name>` can install a whole multi-file feature (pages, Server/Client
  Components, route handlers, a new lib file) from a third-party registry — Supabase publishes
  one at `https://supabase.com/ui/r/{name}.json`, wired into `components.json`'s `registries`
  map. `--dry-run`, `--diff <file>`, and `--view <file>` preview exactly what it would
  create/overwrite before committing to it — worth using every time, since a block this size can
  silently overwrite hand-written files. `apps/web/components.json`
- **2026-09-15** — Confirmed hands-on (not just read in the changelog): Next 16 hard-errors if
  both a `middleware.ts` and a `proxy.ts` exist in the same app ("Both middleware file ... and
  proxy file ... are detected. Please use ./src/proxy.ts only") — the dev server's own log
  showed the exact error the moment the Supabase auth block's generated `middleware.ts` landed
  next to our existing `proxy.ts`. `apps/web/src/lib/supabase/proxy.ts`
