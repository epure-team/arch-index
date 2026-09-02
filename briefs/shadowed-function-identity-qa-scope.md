# QA Scope — shadowed-function-identity

**Date:** 2026-09-02

## Quality Gates (exact commands)

```bash
eval "$(opam env --switch=/home/mathias/dev/arch-index --set-switch)"
dune build
dune test --force
dune fmt
```

Roadmap soundness gate for this item class (also required):

```bash
# arch-rules over a self-index, must fail on any vacuous rule
arch-rules --on-vacuous fail <self-index-db>

# Self-index-scale MUST/MAY_TOP measurement, before and after the fix, comparing counts
```

Octez re-measurement (9629 `type_usage` FK rejections attributed to this collision class,
per roadmap notes) is a documented follow-up, not a blocking gate for this PR.

## Behaviors to validate

1. **Same-module shadow fixture**: a compilation unit with two top-level bindings of the same
   name produces exactly two `functions` rows after indexing, not one.
2. **Edge attribution**: each of the two rows' outbound call edges match that specific binding's
   own body — verify by querying `calls` for each row's id and confirming the callee sets differ
   and are each individually correct (not merged, not duplicated onto one row).
3. **Naming direction**: the last-bound (source-order-final) definition's row has the bare name;
   the earlier, shadowed definition's row has a `#N` suffix. Query `functions.name` directly for
   both rows and confirm which one is bare.
4. **Cross-module resolution**: a second module calling the shadowed function's module by
   qualified name (`A.f`) resolves its call edge to the *live* (last-bound) definition's row, not
   the shadowed one. This is the fixture that most directly tests the ordinal-direction Decision
   — treat a failure here as a correctness blocker, not a test-flakiness issue.
5. **No-collision regression check**: a compilation unit with no shadowing produces
   byte-identical `functions`/`calls` rows to pre-fix behavior (name, no suffix, same edges).
6. **Adjacent-but-distinct cases unaffected**: `ocaml_shapes.ml`'s toplevel-vs-nested-module
   homonym test and `callgraph_soundness.ml`'s stamp-level (parameter-shadows-outer-let) test both
   remain green — these are different collision axes and must not be perturbed by this fix.
7. **`exposed`/doc-comment attribution**: confirm the live (bare-named) row is the one marked
   `exposed` and carrying any doc comment, not the shadowed row.

## Out of scope for this QA pass

- The cross-module homonym hazard in `bin/arch_query/arch_query.ml` (already-accepted, unrelated
  axis — do not test or gate on it here).
- Full Octez-scale re-measurement (deferred follow-up).
- Any change to `INSERT OR REPLACE` semantics on `functions` (not part of this fix).

## Verdict criteria

GO requires: all quality gates pass, all six behaviors above hold, and the cross-module fixture
specifically demonstrates the corrected (last-bound-keeps-bare-name) direction rather than merely
"two rows exist." A test suite that passes only the same-module case is NOT sufficient evidence
for GO, per the plan's explicit risk note that this is the axis most likely to hide a regression.
