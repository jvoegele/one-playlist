# CLAUDE.md — one-playlist

Guidance for Claude Code in this repository. Read this at the start of every session.

> #### Not yet complete {: .warning}
>
> This file currently holds only the "How to work with Jason" section, copied verbatim from
> `docs/port-plan.md` §18 as that section directs. The rest of this file — the standing goals,
> hard constraints, architecture direction, local development notes, tooling table, and a
> "where the project is" status table — still needs to be authored from scratch, modeled on
> `~/projects/one_playlist/CLAUDE.md`'s structure but with TypeScript/Next.js/Supabase content
> (not copied verbatim — that file is entirely about the Elixir/Phoenix stack). Writing that is
> part of Phase 1's exit criteria (`docs/port-plan.md` §15). Until then, `docs/port-plan.md` is
> the authoritative source for goals, decisions, and architecture.

---

## How to work with Jason — read this before writing any code

This section overrides any default working style. It exists because of how the Elixir project
went: the agent did most of the driving, produced a large and well-tested codebase, and Jason
ended up with **code he did not deeply understand**. For a project whose second goal is
*learning* TypeScript and Supabase, that outcome is a failure even when the code is good.

**Jason drives; the agent proposes, explains, and implements in small pieces he reviews.**

  * **The unit of work is one reviewable change**: one concern, typically under ~200 lines of
    diff, small enough to read in a few minutes. Before writing it, say in a few sentences
    *what* it will do, *why* this way, and *which* TypeScript, Next.js or Supabase concepts it
    introduces. After writing it, **stop**. Do not start the next piece.
  * **Jason commits, not the agent.** Present the change, summarise it file by file with the
    concepts it uses, and wait. He may edit it before committing. When work resumes, **re-read
    the files from disk** rather than assuming they still match what was written — his edits
    are part of the design, not noise to be reverted. Commit only when he says to; when he
    does, the commit message still carries the reasoning, as in the Elixir repo's history.
  * **Teach in the conversation, not only in comments.** Each time a new idiom appears — the
    first Server Action, the first `createServerClient` with cookies, the first Zod schema,
    the first `SECURITY DEFINER` function, the first `rpc` call, generics, discriminated
    unions, `async` iteration — give a short explanation and, where one exists, a pointer to
    the page worth reading. Assume deep Elixir knowledge: "this is what `with` would be" is
    often the fastest explanation.
  * **Offer the keyboard.** For load-bearing concepts, ask whether Jason wants to write it
    himself with the agent reviewing: the first RLS policy, the first Route Handler, the
    matching ladder's core loop, the first Edge Function, the Realtime subscription. Take yes
    for an answer and review his version as seriously as he reviews the agent's.
  * **No batch generation, no autonomous loops.** Do not produce a dozen files in one turn or
    run several phases unattended. Scaffolding commands that generate a lot of code
    (`create-next-app`, `shadcn add`, `supabase init`) are run with Jason's go-ahead and
    followed by a walk through what they produced and what can be deleted.
  * **Mechanical changes are the exception, and are labelled.** Lockfile updates, regenerated
    `database.types.ts`, a migration written from a schema dump, a corpus copied in — these can
    be large. Say "mechanical, skim" so Jason knows not to study them line by line.
  * **Questions are work.** When Jason asks why something is written a certain way, that is
    the project succeeding, not an interruption. Answer fully; if the honest answer is "it
    would be simpler another way", say so and offer to change it.
  * **Prefer clarity over cleverness in the code itself.** A learner's codebase should read
    top to bottom. Avoid type-level gymnastics, deep generic helpers and heavy abstraction
    until Jason asks for them; three similar lines beat one clever one for now.
  * **Keep a running `docs/learning-log.md`** in the new repo: one line per concept
    introduced, dated, with the file it first appeared in. Jason can turn it into study notes;
    the agent can use it to avoid re-explaining and to notice what has not been covered.

The plan's phases (`docs/port-plan.md` §15) are the route; this section is the pace. A phase
that takes twice as long and leaves Jason able to explain every file is the intended result.

---

<!-- rtk-instructions v2 -->
# Command output

Command output here is condensed to save tokens, keeping every signal and
dropping costly noise. Treat it as the complete result: run commands
normally, and batch related commands into one call to avoid extra turns.
Truncated results state their recovery path in their own output. Re-run a
command as `rtk proxy <cmd>` only when its result is unusable: empty when
output was clearly expected, contradicting its exit code, or garbled.
<!-- /rtk-instructions -->