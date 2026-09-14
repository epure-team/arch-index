# Independent compiler UID endpoint evidence

The measured run witnesses the endpoints and multiplicity of all 831 changed module-parameter rows (800 ordinary rows and 31 `value_alias` rows), plus all 34 new computed-return TOP residuals. There are 810 caller/site buckets, retaining all 1,364 exact old/new display-group keys. No UID endpoint, source-anchor, occurrence-cardinality, or residual-cardinality gap remains in this run. This is evidence for review, not reviewer approval or a complete certificate of the product's structural eligibility policy.

Current evidence: ignored `improvement/2026-09-14-tezos-resolution/attempt1-uid-evidence-v2.json`, SHA-256 `8811a7e0b1d93c25eb5e40c2f680112add0d54e2a7f764f1a2aa1668e094c909`. The report records SHA-256 of its probe, runner, original changes/report/provenance files, and the fixed410 manifest. It reads63 manifest-selected CMTs covering every changed file, checking each selected CMT SHA-256 before and after reading. It does not rebuild or write Tezos. The original location-only report (SHA25654e5c5564fca7fa1a22ffb5ef55d27d54c8b4853845213830eff1500285738cd) is retained separately as historical evidence, not used for approval.

## What is mechanically established

- OCaml 5.3 compiler-libs parses the existing CMTs directly. The probe imports no arch-index code, does not reuse `local_module_targets`, and does not reconstruct local-module export resolution.
- A body witness is a real `Tpat_var` binding UID whose RHS is `Texp_function`. Its arity is the number of function parameters, plus the final parameter when the body is `Tfunction_cases`.
- Each source occurrence is located by its old typed path and native expression/application location. The path only selects a candidate occurrence. Endpoint proof uses actual native `Shape.Uid.Tbl` identity lookup against body UIDs, using either `val_uid` or the compiler's `cmt_ident_occurrences` entry with `Shape_reduce.Resolved`. The occurrence lookup uses the complete located Longident, not location alone: PPX identifiers may share coordinates. Competing native body endpoints fail before consulting DB targets. Approximate/unresolved/alias results are not accepted as resolved endpoints.
- All 831 occurrences have a compiler `Resolved` UID equal to a body UID. Direct `val_uid` alone reaches a body for 589; those all agree with the resolved UID. The remaining 242 require the compiler occurrence mapping. For example, `object_graph.ml:181` `Table.create` has value-description UID `Irmin__Object_graph.65`, but compiler resolution selects `Irmin__Object_graph.51`, the actual function at lines 81–83, matching DB target `Make.Table.create`.
- The selected target's DB file/start/end range must uniquely identify one native function-body binding. The caller range must identify one native binding, or one anonymous function when no binding matches. Identifier byte offsets must fall inside that caller. This checks the actual source anchor behind ordinal-qualified names; names or suffixes do not establish target identity.
- Exact row multisets are subtracted within each caller/site bucket. Each removed row is assigned once to a native occurrence and once to a new same-file target with preserved `edge_form`. Native-occurrence count must equal removed-row count, including duplicates. All target rows must be consumed. Every assignment carries its full before row, after target row, identifier column/offsets, UID/body locations, and any applied-head evidence.
- There are 782 applied-head assignments, 18 ordinary non-head identifier assignments, and 31 aliases. The 428 Irmin and 403 protocol changed rows are row counts, not distinct gained relations.
- Each of the 34 residual rows has one native application whose supplied nonempty argument slots exceed the matched function's syntactic arity. The arity/supplied distribution is 2/3: 5, 4/5: 1, 1/2: 13, 5/6: 7, 1/3: 8. For example, `tree.ml:1986` applies `Contents.of_key` with 3 arguments, and resolved UID `Irmin__Tree.268` identifies the two-parameter body at line 281.

## Source and location details

All 63 CMT source digests match their actual compiled inputs. The recorded build directory is `/workspace_root`; the runner explicitly maps that relocation to `/home/mathias/dev/tezos/tezos/_build/default`. For preprocessed files, the digest covers the `.pp.ml` marshalled AST, not the original `.ml` text. All original `.ml` files also match their `_build/default` copies byte-for-byte, and their SHA-256 values are recorded. This does not independently replay preprocessing or prove its historical derivation.

Ten rows initially failed a naive identifier-start-line check. Five were direct callback arguments, including two `Commit.pp_hash` occurrences within the logging application starting at `store.ml:671`; physical Typedtree argument-expression identity provides their application context. Five more are pipeline expressions in `validate.ml`: the compiler emits a direct application starting on line 4048 whose function identifier `Voting.wrap_proposals_conflict` occurs on line 4049. Its application/head locations establish the correct DB site without a line-window heuristic. All such concrete contexts are retained.

## Limits and review handoff

Native UIDs prove compiler-declared definition endpoints. They do not independently establish FR-002's prohibition on aliases, functor applications, unpacking, or unproven member hops; that requires the separate structural/native product checks. They also do not establish runtime functor-instance identity, which is outside this iteration's scope. CFG/channel correctness and no existing relation loss remain the comparator and product guards' responsibility.

The probe emits no approval. Root's separate `reviewed-witness.js` serializes the inspected exact v2 evidence only, checking every native endpoint for ambiguity and every occurrence's multiplicity, plus every residual's consumed head/arity. Its metadata identifies the root endpoint review, never a human or roster GO. Eight PPX occurrences in four proof.ml buckets have duplicate identical native records; each duplicate is consumed once, not discarded or counted as a separate relation. After Longident-key correction all831 occurrences have one resolved native body, with no direct-UID disagreement. The correction changed evidence precision, not any product target or measured gain.

## Replay

The following commands compile only the independent probe. Use a fresh owned temporary directory; replace `UID_TMP` below with that directory's exact path. The runner writes a new ignored evidence file and refuses overwrite. Pass an optional output path after the probe for a separate replay. Preserve the exact original evidence when replaying.

```sh
rtk proxy mktemp -d /tmp/arch-index-uid-witness-XXXXXX
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ocamlc -I +compiler-libs -c -o UID_TMP/probe.cmo roster/tezos-call-resolution/uid-witness.ml
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ocamlc -I +compiler-libs ocamlcommon.cma UID_TMP/probe.cmo -o UID_TMP/probe
rtk proxy node roster/tezos-call-resolution/uid-witness.js UID_TMP/probe
rtk proxy node roster/tezos-call-resolution/reviewed-witness.js improvement/2026-09-14-tezos-resolution/attempt1-uid-evidence-v2.json improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json root-compiler-endpoint-review
```

The executed directory was `/tmp/arch-index-uid-witness-kujR9a`. Installed interfaces consulted: `typedtree.mli` (`Tpat_var`, `Texp_ident`, `Texp_function`, `Texp_apply`), `types.mli` (`val_uid`), `cmt_format.mli` (digests, occurrence map, UID declarations), and `shape_reduce.mli` (`Resolved` versus approximate/unresolved variants), all under `_opam/lib/ocaml/compiler-libs`.
