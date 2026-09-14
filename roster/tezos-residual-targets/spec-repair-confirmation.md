# Independent bounded repair confirmation

Date: 2026-09-14. Specialist: spec-compliance. Working-tree repair on HEAD `975c73b49def2813517b00c296006417d062d8b2`; not a final committed-head review or delivery verdict.

The independently reproduced flat-attribution divergence is corrected in the inspected working tree. Actual native check exited **0**, session19859, completion chunk9829af. The original OPEN finding and preliminary report remain historical and unchanged. Final full build, suite and CHECK-1..5 on the committed repaired head remain pending.

The control uses `git show 975c73b:roster/tezos-residual-targets/check-flat.js` as its fixed harness, extends its temporary OCaml fixture with the original three legacy forms, and compiles both `fb9c8f3` and current working-tree extractor sources against the same current collector. It performs the same native comparison that previously exited1, with additional supported-qualified and point-free assertions. No root build, corpus producer, worktree or product edit was performed.

Actual assertions:

- Six observed direct/parameter/bare-callback rows (three forms in each of a.ml and b.ml) are exactly equal between old and repaired extractors. Their callee_file remains a.ml and edge_form remains NULL.
- Four supported qualified invocation rows retain the body display: a.ml gets its actual same-file symbol; b.ml, whose same-file symbol is absent, gets NULL instead of the foreign homonym.
- Two existing point-free rows remain exactly equal.

The repair's `pending_call.local_module_invocation` is default-false and set at the qualified application, qualified callback and invoked letop lookup success sites. Flat attribution now uses that occurrence-level fact to select invocation ownership. Bare callbacks remain Head_enumerated without this flag, so the earlier ambiguity is not merely moved to a head-constructor check. Point-free and return-residual emissions leave the flag false.

The executable control was evaluated in memory from the fixed harness; only its owned temporary native fixtures/compiler outputs were created and automatically removed. The exact command is retained in the specialist tool transcript. This artifact was written before the next source-state-hashed corpus gate.
