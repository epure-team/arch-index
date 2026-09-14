# Intake Brief — tezos-call-resolution

**Date:** 2026-09-14
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** no

Validation basis: the user's explicit standing delegation of roster execution and five bounded improvement iterations. No interactive quiz answer or additional approval is claimed. Classification concerns call-target resolution, not changing financial/protocol behavior. Keyword checks on the task description returned no trust/critical hit; this is the standard Full route.

## Goal

For the first iteration of the five-attempt loop, connect calls through same-compilation-unit structured modules to their actual indexed function definitions using compiler binder identity. Initial real-corpus witnesses include protocol Helpers.add_name and Irmin Inode.update/Infix operators; their display-name matches only prioritize examination and do not authorize resolution.

The same delivery includes a repeatable fixed410 before/after comparison harness. Instrumentation does not count as a product gain. Retain the iteration only when distinct caller/file:line/internal-target relations increase, native semantic/refusal tests pass, and comparison finds no unexplained loss or certainty promotion. Separate Irmin/protocol outcomes. Review, QA and exact-head green PR CI precede rebase merge; subsequent retained iterations start after merge. The remaining four attempts are chosen from measured residuals, not preclaimed as successful features.

## Scope Boundary

Writable product scope: lib/arch_index/arch_index_cmt.ml and .mli, lib/arch_index/call_graph_extractor.ml, a private local-module target helper .ml/.mli if justified, lib/arch_index/dune only for that private helper, tezt/tests/local_module_targets.ml, tezt/tests/main.ml, tezt/tests/dune only for the new checks. Supporting scope: roster/tezos-call-resolution/**, briefs/tezos-call-resolution-*, specs/tezos-call-resolution.md, docs/edge-kind-contract.md for accurate capability limits, .gitignore for improvement/, ignored improvement/**, skills-meta/friction.jsonl, and the named external roadmap note.

Out of scope for this first iteration:

- Tezos source/build edits, dependency installation, corpus widening or changing the fixed manifest.
- Cross-unit member ownership, functor argument substitution/instance expansion, general 0CFA, protocol validation or vulnerability research.
- Resolving parameters, applications, unpacked modules or module aliases merely because their names match a structure. Existing persistent-alias behavior remains unchanged.
- SQL schema changes, new public CLI/query commands or rewriting current qualified facade heuristics.
- Broad changes to error-channel configuration matching, CFG semantics, function naming or flat-LSP nested-definition coverage.
- Unrelated dirty files, held PR93, old worktrees not owned by this loop.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| lib/arch_index/arch_index_cmt.ml | Typed traversal, definition identities, head emission | iter_structure_items; build_binding_names; collect_calls_from_expr |
| lib/arch_index/arch_index_cmt.mli | Private shared collector API | optional per-CMT stamp tables |
| lib/arch_index/call_graph_extractor.ml | Existing CMT fallback caller | collect_calls_from_expr with per-CMT tables |
| lib/arch_index/dune | Library private-module boundary | private_modules |
| tezt/tests/main.ml | Native regression registration | Module_alias_heads.register () |
| tezt/tests/dune | Full suite and CLI dependencies | run %{test} --keep-going |
| tezt/tests/module_alias_heads.ml | Read-only adjacent refusal oracle | aliases to parameters retain MAY_TOP |
| architecture-schema.sql | Read-only storage contract | calls.callee_id, call_site, edge_form |
| roster/tezos-call-resolution/baseline-preparation.md | Measured provenance, SQL, owned DB | 4,372 Irmin / 11,220 protocol distinct relations |

## Architecture Notes

Binder identities are per-CMT; same spelling does not establish ownership. Resolve member ownership through the actual declared structured module and its exported members, with shadowing honored and the value's existing binding_name used for the database target. Only function-body members are eligible in this slice; function-valued expressions and value aliases remain refusals. New edges remain MAY_ENUMERATED, never gain MUST solely from naming. Existing pending-edge metadata and refusal paths must be preserved. The internal resolver's absence/default preserves old API behavior; both existing caller paths must be considered and tested without changing flat-schema identity policy.

Qualification inside nested structures and functor bodies is already indexed. A parameter-supplied nested member is not thereby an owned structure. Signature constraints do not create a function body. Includes and recursive module shapes require explicit conservative handling; no implicit last-writer name guess is allowed. The spec must settle these cases before implementation.

The current DB has file:line call sites, not unique expression IDs. Primary metric is a set of caller/source-line/target relations; preservation guards additionally compare multisets and metadata. A real target gain requires a semantically justified native fixture and exact before/after witness, not model consensus or a global edge count. No managed claims tooling or KB is installed.

## Quality Gates

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force
rtk proxy node scripts/review-bundle-verify.js
rtk proxy git diff --check
```

No configured formatter/coverage command is documented for this scope. Baseline build, full runtest --force and bundle check already passed at ea8e5b4. Planned feature checks must distinguish assertion failure (1) from setup failure (>=2); the comparator will have a self-comparison mode and deliberately altered-input tests before it is used as an improvement-loop Verify command. The fresh fixed410 baseline is retained at /tmp/arch-index-resolution-baseline-OmhcEs. The executable comparator does not yet exist; product implementation must wait for its validated setup, baseline replay and guard pass.

## Open Questions

None requiring a user choice. Compiler-specific shadowing/include/constraint cases are requirements-design work to resolve against existing code and the native tests in roster-spec, not grounds to assume additional scope.
