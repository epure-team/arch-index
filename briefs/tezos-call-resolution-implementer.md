# Implementer — tezos-call-resolution

**Status: VALIDATED**

Goal: first of five bounded attempts improves actual indexed local structured-module call targets on fixed410 Tezos. Comparator setup is prerequisite, not a product gain. Read the validated plan and specs/tezos-call-resolution.md completely before edits; preserve all refusal/metadata requirements.

## Files and scope

Modify lib/arch_index/arch_index_cmt.ml/.mli (iter_structure_items, build_binding_names, collect_calls_from_expr), lib/arch_index/call_graph_extractor.ml (both optional context and exact same-file target attribution), optionally a new private local-module helper and lib/arch_index/dune only for its registration. Add tezt/tests/local_module_targets.ml and only its registration/dependencies in tezt/tests/main.ml/dune. Add checker/snapshot/runner files under roster/tezos-call-resolution/. Supporting changes: .gitignore improvement/, ignored improvement/, briefs/tezos-call-resolution-* and active manifest control, specs/tezos-call-resolution.md, docs/edge-kind-contract.md, skills-meta/friction.jsonl and /home/mathias/notes/2026-09-01-arch-index-roadmap.md.

No arch_index.ml, schema, public CLI, dependency, Tezos/build/corpus, unrelated file, old worktree or PR93 changes. If existing representation cannot satisfy this, report the concrete scope issue before widening.

## Sequence and completion

Scope amendment approved by the user on 2026-09-14 ("ok ok continue en autonomie !"), in direct response to the six-path extension request: add roster/functor-instance-resolution/compatibility-rich-baseline.json, roster/functor-instance-resolution/compatibility-baseline.md, scripts/check-functor-catalogue.js, test/fixtures/origin-consumer/self.allow, test/fixtures/origin-consumer/reference.json and checks/origin-recurring-consumer.js. Recalibrate only reviewed precision/reference changes described in roster/tezos-call-resolution/guard-diagnosis.md. Keep full checks, historical QA evidence and all prior refusal cases; no blanket allowlist or comparator weakening. This resolves the prior scope blocker, not the failing gates themselves.

1. Capture base/dirty scope manifest before further build gates. Implement comparison checks test-first, then canonical comparison and fixed410 runner; validate mutation tests, baseline self/replay, provenance and full baseline guard. Add ignore before logs and record iteration0.
2. Add real compiled local-module native fixture; demonstrate a failing assertion, not a missing command/import. Then implement one integrated ownership-to-target slice using per-CMT binder roots and existing stored names. Both collectors get equivalent optional input; no bare global lookup for a newly proven same-file target. Default absence preserves previous behavior.
3. Cover spec's ownership/shadow/include/constraint/refusal/arity/callback/point-free/storage/fallback cases. Run native/full guards and fixed410 comparison. Inspect every changed group and target source witness; no count-only keep.
4. Document limits/results, commit only owned files, write implementation evidence and hand off to independent roster review/QA. Exactly-head green CI and rebase merge are downstream gates.

All exact commands, report names, baseline/manifest hashes and keep/discard criteria are in the plan's Operational decisions and Quality gates and are binding. Checker commands do not exist yet. Main orchestration owns plan/ledger/friction/roadmap; delegated implementers write only their explicitly assigned subset. No extra worktree/build and no external writes from implementation agents.

Highest risks: identity versus name, source-order export masking, flat cross-file capture, arity residual loss, false MUST, same-line ambiguity and circular comparator confidence. No numerical coverage claim without a configured measurement. Setup-first overrides the generic mixed-scope OCaml-first ordering because the approved intake prohibits product edits before executable baseline verification.
