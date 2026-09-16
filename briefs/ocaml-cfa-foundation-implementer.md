# Implementer — ocaml-cfa-foundation

**Date:** 2026-09-16
**Status: VALIDATED**

## Goal and boundary

Implement stage2 finite function-value domain/constraints/worklist connected to
actual OCaml5.3 CMT calls, main persistence and flat output. Same-CMT nonrecursive
plain-variable alias chains, top-level aliases visible inside functions,
collector-promoted literals and if/match/sequence result flow are required.
Known candidates plus independent unknown reasons coexist. New targets are MAY,
never MUST. Preserve existing direct paths and alias predecessor facts.

Not stage3: no argument/formal/return/capture/recursive transfer or partial
closure propagation. No heap, general pattern transfer, functor substitution,
cross-compiled variants, numeric guard changes, generic shared library, public
API or proof graph. Existing supported direct recursion/literal behavior remains.
Read specs/ocaml-cfa-foundation.md as the normative contract before code.

## Files to modify/create

```text
lib/arch_index/arch_index_cfa.ml
lib/arch_index/arch_index_cfa.mli
lib/arch_index/arch_index_cfa_cmt.ml
lib/arch_index/arch_index_cfa_cmt.mli
lib/arch_index/arch_index_cmt.ml
lib/arch_index/arch_index_cmt.mli
lib/arch_index/call_graph_extractor.ml
lib/arch_index/dune
tezt/tests/ocaml_cfa_foundation.ml
tezt/tests/local_value_targets.ml
tezt/tests/point_free_aliases.ml
tezt/tests/callgraph_soundness.ml
tezt/tests/dune
tezt/tests/main.ml
tezt/fixtures/ocaml_cfa/
test/test_cfa.ml
test/dune
test/fixtures/self-index-stats.txt
test/fixtures/origin-consumer/reference.json
checks/origin-recurring-consumer.js
test/fixtures/origin-consumer/self.allow
docs/edge-kind-contract.md
roster/ocaml-cfa-foundation/
```

Relevant interface snippets from intake: pending_call, lambda_node,
collect_calls_from_expr, process_cmt in arch_index_cmt; full structure batch
in call_graph_extractor; SQL edge_form only NULL/value_alias/module_alias.
New ordinary CFA applications use NULL; no schema change. New private CFA/CMT
modules are optional separation, never a duplicate naming pass.

## Sequential work

User explicitly approved the four reference/allowlist files above on 2026-09-16
("oui!" answering the exact scope question). Apply only the measured 2x2
source-growth references and the unique unchanged assertion's new coordinate;
do not change policy rules or introduce exemptions. Evidence:
roster/ocaml-cfa-foundation/self-reference-evidence.md.

User approved the exact-file point-free scope extension on resume2026-09-16
("ok continue" answering the explicit approval question). Only migrate the
newly supported invocation expectations; preserve alias exclusions and no-MUST.

1. Write an authentic failing alias-chain fixture before production edits.
   Add minimal finite kernel and per-CMT session, binder/physical-expression
   identity and deferred-head reconciliation to both main and flat. Observe
   real target identity and existing query behavior, not just counts.
2. Test then add literal/branch/sequence flow, mixed unknowns, source-position
   collisions, shadowing and owner boundaries. Actual collector names alone
   authenticate promoted literals. Unobserved/rejected/ambiguous targets stay
   unknown; no bounded missing leaf.
3. Test occurrence metadata, per-target arity, independent residuals and
   same-line calls. Keep channel/exception links and all existing non-CFA
   behavior. Update only explicitly newly-supported historical TOP expectations.
4. Add standalone check-domain.js independent finite closure oracle,
   check-cmt.js authentic main/flat checks, and check-tezos.js frozen-corpus
   comparison. Register native coverage in CI. Update edge-kind docs.
5. Full gates, independent review/QA, then ship via root. Do not create/merge PR
   yourself or claim stage2 complete until all in-scope requirements pass.

## Quality gates and evidence

```sh
rtk proxy opam exec -- dune build
rtk proxy opam exec -- dune runtest --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
rtk proxy node roster/ocaml-cfa-foundation/check-domain.js
rtk proxy node roster/ocaml-cfa-foundation/check-cmt.js
rtk proxy node roster/ocaml-cfa-foundation/check-tezos.js
```

TDD: compileable authentic fixture must assert-fail on old source before production
change. New absent-module compile error is NOT a demonstrated behavioral RED.
Full suite on each GREEN slice; targeted checks aid iteration but do not replace
full gates. Single build token; ask root before any build/test while another
agent has token. Exact pre/post source/binary identities for final evidence.
No installed coverage/formatter gate: report unavailable, not fabricated percent.
Use apply_patch for all manual edits, rtk prefix for commands, opam exec for5.3.

## Risks and constraints

One whole-CMT session (not independent per-function solving); callable ownership
must keep captures unknown. Dedup facts within an occurrence only. Never compare
expressions using source positions. Flat may not represent an identity and has
no proof-bearing kind/reason schema: preserve explicit unknown, no homonym binding.
Preserve source/run/actual target provenance; no transitive proof-chain claim.

Historical pinned410 baseline remains fixed (45052 rows, Irmin4849/protocol12171);
measure and explain deltas separately. No unreviewed golden refresh or allowlist
weakening. Source-growth reference changes outside listed files need authority.
Preserve seven foreign untracked paths listed in manifest; no cleanups by glob.
No new worktrees. Missing specialist projection is handled by a scoped native
OCaml agent, not installed silently. Claims reconciler/hooks/KB absent; local
input digest manifest must stay current. Root manages ACTIVE_TASK and ledger.
