# Realtime notes — friction log

Realtime-specific friction, kept separate from `docs/supabase-notes.md` because Jason is on
the Realtime team — port-plan.md §10 asks for this split explicitly: "If something about the
developer experience is awkward — an unclear error, a missing type, a docs gap — write it down
in `docs/realtime-notes.md` with a reproduction. That is the most valuable artefact this
project can produce for his job." Also feeds the Notion friction-log deliverable, alongside
`docs/supabase-notes.md`.

## Realtime Authorization's join-time check is a dry-run rollback, not a real row read

**Found:** Spike 4 (Broadcast from Database on a private channel).

Per Supabase's own Realtime Authorization docs, the join-time check "performs a query on the
`realtime.messages` table and then rolls it back" — no pre-existing row is required, and
`realtime.topic()` is set to the topic being joined only for the duration of that check. This
means a pgTAP test can validate the *policy expression* in isolation but cannot validate the
live dry-run mechanism itself — that needs an actual client against a running Realtime server
(`apps/web/scripts/spike4-probe.mjs`, a real Playwright browser, was built for exactly this).
Worth surfacing to the team: the mechanism is not obvious from the policy alone, and a
docs callout at the point someone writes their first Realtime Authorization policy (a link to
"this check is a rollback, not a real read — you don't need seed data to test it, but a pgTAP
test alone won't tell you it actually works") would have saved a debugging pass here.

## A related, real design bug this spike caught (not itself Realtime friction, but found via it)

`port-plan.md` §10's own draft policy — `realtime.topic() like 'transfer:%' and exists (...)`
— never compares the row's own `topic` column to the `realtime.topic()` GUC, so it authorizes
"is this caller authorized for *some* topic they own," not the specific topic being joined.
Caught by a pgTAP test expecting a topic-scoped row count and instead getting every row across
every topic the owner had ever touched. Fixed by adding `topic = realtime.topic()` to the
`USING` clause. Not a product defect — the underlying `exists` shape is a common enough
pattern that it may be worth a callout in the Realtime Authorization docs' example policies,
since "the exists clause is satisfied by any topic you own, not just this one" is exactly the
kind of RLS mistake that "passes for months while leaking."
