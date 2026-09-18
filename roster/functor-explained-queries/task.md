# Roster intake — functor explained queries

## Objective

Expose the already-persisted `functor_target_contract=v2` evidence as strict,
human- and machine-readable `arch-query` answers, and expose the reachable
`MAY_TOP` frontier without treating an unavailable analysis as an empty result.

## Scope

1. Add `analysis-status`, reporting the availability and contract markers of
   supported optional analyses.
2. Add `functor-targets`, a validated reader of target v2 candidates and their
   witnesses, preserving physical occurrences and the coexisting top frontier.
3. Add `unknown-frontier` as an explained, structured alias of the existing
   sound `escapes` semantics.
4. Retain existing command output contracts and distinguish `NOT_COMPUTED`,
   `UNSUPPORTED_SCHEMA`, `INCONSISTENT`, and an empty computed result.

## Non-goals

- No producer, SQLite schema, graph-edge, MUST, reachability, or CFA change.
- No inference of which MAY edges originated in 0-CFA.
- No silent change to the existing streaming JSON interfaces.

## Acceptance evidence

- Authentic CMT fixture emits target/candidate/witness evidence and remains
  distinguishable from a `MAY_TOP(module_param)` frontier.
- Missing, flat, partial, corrupt, and markerless databases refuse explicitly.
- Query ordering and limits are deterministic; `limit=0` is computed, not a
  refusal.
- Full native Tezt and the stage-specific checker pass before merge.

## Rollback

Remove only the new reader/commands and their Roster files. They are read-only
and do not change indexed data or legacy command semantics.
