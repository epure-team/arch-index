# Acceptance checkpoint — 2026-09-13

Implementation is complete: final320/320Tezt+64Alcotest passed, including all54
binding tests and all four independent families. Review/QA/PR remain pending.
This is execution evidence, not a replacement for the frozen spec.

## Executed evidence

- Build passes; the four independent Node families are now registered in Tezt.
- Full unchanged baseline before these additions:308Tezt+64Alcotest pass.
  Latest full rebuilt suite including checker wiring:318/318Tezt+64Alcotest PASS,
  exit0 (2026-09-13, completed18:10:58 local runner time).
- All four Node dispatcher commands pass on the current binaries. Set
  `ARCH_FUNCTOR_OPAM_SWITCH=/home/mathias/dev/arch-index` for this local worktree.
  The script has no hardcoded machine switch; by default compiler commands inherit
  the selected PATH from parent opam/Dune/CI. The explicit override remains supported.
  Root also checked query-checker exit1 against `/bin/true` (empty output cannot
  pass a byte oracle) and exit2 against a missing query executable.
- Inventory:13 native occurrences,6 declarations,9 matched,4 native refusal
  reasons; the plain Node inventory now also runs a premise-checked synthetic
  compiler-libs probe for identity conflicts, alias-cycle, missing/persistent heads,
  kind mismatch, overapplication/head ordinals, inner-refusal precedence,
  Pident/Pdot/Papply/Pextra_ty/persistent roots and four named nullable combinations.
  A separate native census verifies11 exact declarations across typed contexts,
  ignored untyped payloads, unpack refusal and two artifact-local cross-CMT joins.
- Lifecycle: real second-result insertion failure after a trigger independently
  checks input1/declaration1/result1; targeted error-message assertion, rollback,
  preserved committed old facts, successful/rejected failed-row writes,
  RAISE(ROLLBACK) uncertainty, marker timing/zero-result/empty-selection/write-error.
  Standalone probe explicitly reports direct-API evidence. An additional real
  producer CLI fixture injects second-result and failed-row errors through owned
  schemas, checks exact old-fact parity, valid/failed/valid reindex marker behavior,
  and no fabricated rows for zero-application/unreadable catalogue inputs.
- Query: independently authored two-input/three-result cells,2 matched/1unresolved,
 18 nonempty and18 zero-result exact byte oracles across six renderers,
 57 independently seeded limit0 corruptions,10 schema and7 marker refusals,
  strict CLI and precedence, authored60-row default50 limit and unchanged DB bytes.
- Compatibility: prior versioned rich graph oracle on16 semantic surfaces,
 3 legacy queries,2 indexing passes, plus unchanged catalogue bytes/DB hash around
  the binding query.

## Genuine TDD defect closed

The reader snapshot's exception-pattern handler covered validation but not commit.
The new connection double includes a real read-only Caqti connection, injects a
commit `Arch_db.Broken`, and counts attempted rollback. Successful full validation
must reach that exact injected error. Before the product change:

    reader commit failure rollback count 0, expected 1

Direct Tezt exit1 (one actual selected test). After replacing the outer match with
`try` enclosing validation and commit, the same test passes inside48/48.
An earlier mistyped title selected no tests and exited3; it is not RED evidence.

## Corrections to test premises (not product regressions)

`Check` local-open overloaded comparisons made four callback expressions fail to
compile; ordinary predicates now live outside that local-open. `Option.exists`
is unavailable in this compiler environment; use `Option.fold` instead.

The native Alias application head is `Tmod_constraint(Tmod_ident Alias)`, observed
by a temporary structural diagnostic. An initial direct-head premise and root's
subsequent normalization-to-F guess both failed. The test now independently peels
the wrapper and verifies `Ident.same` against Alias before mutating its RHS to a
self-cycle. There is no claim that this source alias was normalized to F.

The lifecycle probe's first empty-selection setup inserted a SQL-disallowed zero
run header and exited2. It now uses a schema-valid empty catalogue and asks the
finalizer to reject selection0; the assertion itself was not relaxed.

## Remaining contract work before review

Independent closure audit identified three final gaps, now implemented:

1. A serialized, reread, premise-checked duplicate-Ident synthetic CMT now reaches
   the actual producer: catalogue1 preserved, binding collection_failed0/0, no
   partial rows or marker. Explicitly not source-valid evidence.
2. Begin/commit/rollback injection covers the real reader API; a separate genuine
   SQLite overflow in an accessed view proves actual CLI exit2/empty stdout after
   schema/marker premises. No production fault hooks or simulated CLI catch.
3. Exact binding output survives a demonstrably malformed unrelated exn_origins
   row. Three authored historical flat-query oracles pass before/after the new
   command's refusal; alias exclusion and unchanged bytes are checked.

54/54 focused tests passed before the final accessed-SQL addition; the subsequent
full320/320 suite includes that addition and passes. Build/scope/bundle/syntax/diff
gates pass. The completed implementation artifact is ready for round commit and
roster review/QA/ship. No failure is waived.

## Fresh bounded target observation

Replayed the exact digest-verified410-CMT Tezos/Irmin corpus with current binaries:
1275 applications,202 matched formal slots (protocol120/Irmin82),1073 unresolved,
410 collected inputs/no failed binding input. No numerical gain over the previous
observation and no new call targets. Tezos revision and47 dirty entries unchanged;
CMT digests rechecked after indexing. The exact temporary corpus/DB was removed.
