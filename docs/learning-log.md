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
