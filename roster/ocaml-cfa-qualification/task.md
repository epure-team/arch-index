# Stage 5 — OCaml CFA qualification

Standing authority: complete autonomous Roster pipeline, then PR, exact-head
green CI and guarded rebase merge before the next stage. Preserve unrelated
files and remove only worktrees/artifacts owned by this task.

## Objective

Make the bounded CFA/functor precision already delivered observable and useful
without claiming it is MUST or complete: expose query-level limits and evidence,
define a repeatable useful-query benchmark, and measure Tezos Irmin/protocol
precision and resource costs on the pinned corpus.

## Initial constraints

- Existing `MAY_ENUMERATED` remains possible, never definite. `MAY_TOP` stays
  visible and independently counted.
- A gain in known edges is not a risk reduction claim.
- Measurements must use stable semantic identities, pinned inputs, zero-loss and
  no-new-MUST controls; resource data is observational unless a bound is
  separately specified.
- This intake must reuse the Stage 4 target-v2 proof rather than inventing CFA
  provenance unavailable in current rows.
- The later user-facing analyses roadmap (explained queries, profiles, recurring
  diffs) remains staged after this qualification and must not be silently folded
  into it.

## Required intake outputs

1. Current query/graph semantics and every wording that conflates MUST with MAY.
2. A small, real Tezos/Irmin query suite with success criteria meaningful to an
   operator, including unresolved frontier reporting.
3. Reproducible pinned-corpus precision/resource protocol and failure taxonomy.
4. A bounded implementation plan, spec, independent checks and documentation
   updates, before product edits.
