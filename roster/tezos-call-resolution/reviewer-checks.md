# Independent reviewer checks — round 1, cycle 1

Reviewed HEAD `12ab1fcbd7f4e0cea6b54ea7452b7d9f83338a97` against `main`. Recommendation: **changes required**. One reproduced MEDIUM correctness/precision finding is in `reviewer-findings.json`. Successful corpus comparison does not authorize retention while this finding remains open.

Read RTK instructions, reviewer role/brief, implementation brief, plan/spec, complete changed production source and interfaces, native tests and registration, all changed JavaScript checkers, witness and runner code, and the full changed-file diff in batches. Scope findings are delegated to the independently executed scope gate as instructed. The six compatibility/origin evidence changes retain exact comparisons and prior X.run/M.run refusals; the moved split_last assertion is still guarded by a nonempty segment list. No broad allowlist was introduced.

## Commands personally executed

All shell invocations used the RTK prefix. Commands ran in `/home/mathias/dev/arch-index` unless indicated.

| Command | Exit | Evidence |
| --- | --- | --- |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` | 0 | Build completed |
| `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune runtest --root . --force` | 0 | Session 61088, Tezt 324/324 plus other Dune suites; expected failure-injection diagnostics are not aggregate failures |
| `rtk proxy node roster/tezos-call-resolution/check-comparison.js` | 0 | 28 assertions |
| `rtk proxy node roster/tezos-call-resolution/check-native.js --self-test` | 0 | 5 classification assertions |
| `rtk proxy node roster/tezos-call-resolution/check-native.js` | 0 | Session 12949, 4/4 native cases |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | Bundle 1.6.0, 22 files hash matched |
| `rtk proxy git diff --check` | 0 | No whitespace errors |
| `rtk proxy node roster/tezos-call-resolution/reviewed-witness.js improvement/2026-09-14-tezos-resolution/attempt1-uid-evidence-v2.json /tmp/arch-index-reviewer-label-qt01kV/reviewed-witness.json root-compiler-endpoint-review` | 0 | All 831 transition endpoints and 34 residual assertions; temporary regeneration, no new roster approval |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --witness improvement/2026-09-14-tezos-resolution/attempt1-reviewed-witness.json` | 0 | Session 56243, exact fixed410 candidate PASS |
| `rtk proxy node roster/tezos-call-resolution/verify.js --baseline /tmp/arch-index-resolution-baseline-OmhcEs/baseline.db --self` | 0 | Self-comparison PASS, 45,018 unchanged rows |

Candidate report: `improvement/2026-09-14-tezos-resolution/2026-09-14T06-00-00-477Z-candidate-2411716/report.json`. Candidate digest `90e76d6b40b2d7f108fcc25523f85de1cb533a98565a8a7d6d284c1654939d4b`; 45,052 rows; 831 removed/865 added; 795 distinct relations gained (400 Irmin, 395 protocol), zero existing relation losses. Self report: `improvement/2026-09-14-tezos-resolution/2026-09-14T06-00-25-682Z-self-2412398/report.json`. Both reports explicitly keep `retention_authorized=false`.

Also personally executed a Node assertion over every original/regenerated exact witness, excluding only review metadata, and checked all 1,364 changed display-group keys across 810 source/site buckets: 831 transitions, 34 residuals, 31 aliases; exit 0. Source/target endpoint evidence is checked programmatically in full, not represented as manual reading of every line of the large JSON evidence. No endpoint ambiguity or incomplete bucket remains. Comparator preserves row multiplicity, exact positioned witnesses, no existing-target losses and no newly added MUST. UID evidence establishes endpoints, while the separate owner policy/native tests establish permitted structure classes.

## Reproduced uncovered arity case

The root explicitly authorized the temporary native fixture after the potential defect was reported. All reproducer artifacts are retained in `/tmp/arch-index-reviewer-label-qt01kV`.

```ocaml
module M = struct
  let f ~a ~b = if b > 0 then (fun c -> a + b + c) else (fun c -> c)
end
let partial () = M.f ~b:1 2
let full () = M.f ~a:3 ~b:1 2
```

Executed `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ocamlc -bin-annot -c label.ml` in that directory, exit 0. Executed the absolute current `arch_callgraph_ocaml.exe` with `--build-dir /tmp/arch-index-reviewer-label-qt01kV --db-path /tmp/arch-index-reviewer-label-qt01kV/candidate.db --schema-path /home/mathias/dev/arch-index/architecture-schema.sql`, cwd the fixture directory, exit 0. SQLite query exit 0 shows both partial/full callers have `M.f/MAY_ENUMERATED` plus `*TOP*/MAY_TOP/callback_param`.

Compiled the independent compiler UID probe with `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ocamlc -I +compiler-libs ocamlcommon.cma /home/mathias/dev/arch-index/roster/tezos-call-resolution/uid-witness.ml -o /tmp/arch-index-reviewer-label-qt01kV/probe`, exit 0. This first invocation generated `.cmi/.cmo` next to its source; those two newly generated outputs were moved into the owned temporary directory immediately, restoring repository state. Probe confirms partial: arity 2/supplied 2/slots 3, full: arity 2/supplied 3/slots 3.

`collector.ml` links the existing compiled library and invokes its optional local-module context disabled/enabled on the identical CMT. First link attempt with `digestif` exited 2 (missing concrete implementation); corrected package `digestif.c` linked exit 0. Final link command, cwd the fixture directory:

```sh
rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ocamlfind ocamlopt -linkpkg -package compiler-libs.common,sqlite3,ppxlib,eio,eio.unix,yojson,otoml,digestif.c,ppx_inline_test.runtime-lib,ppx_assert.runtime-lib -I /home/mathias/dev/arch-index/_build/default/lib/arch_index/.arch_index.objs/byte -I /home/mathias/dev/arch-index/_build/default/lib/arch_io/.arch_io.objs/byte -I /home/mathias/dev/arch-index/_build/default/lib/jsonrpc_client/.jsonrpc_client.objs/byte /home/mathias/dev/arch-index/_build/default/lib/arch_io/arch_io.cmxa /home/mathias/dev/arch-index/_build/default/lib/jsonrpc_client/jsonrpc_client.cmxa /home/mathias/dev/arch-index/_build/default/lib/arch_index/arch_index.cmxa collector.ml -o collector
rtk proxy /tmp/arch-index-reviewer-label-qt01kV/collector /tmp/arch-index-reviewer-label-qt01kV/label.cmt
```

Collector execution exit 0:

```text
context=false caller=partial callee=M.f head=module_param partial=true
context=true caller=partial callee=M.f head=enumerated partial=true
context=true caller=partial callee=*TOP* head=callback_param partial=false
context=false caller=full callee=M.f head=module_param partial=false
context=true caller=full callee=M.f head=enumerated partial=false
context=true caller=full callee=*TOP* head=callback_param partial=false
```

A separately executed Node assertion checks the partial head/control and requires zero residual rows for the omitted-label case. It exits 1 with `ASSERTION FAILED: omitted label is not a supplied argument beyond body arity`, `1 !== 0`. This is an authentic semantic assertion failure, not a compiler/link/setup failure. No historical baseline binary was executed: the disabled optional-context path and reviewed pre-change branch provide the before comparison.

## Coverage and limits

Reviewed compiler binder identity, concrete intermediate owners, source-order masks for values/modules/includes, final stored names, alias/parameter/application/unpack refusal, callbacks/letops/point-free forms, dropped-node handling, flat same-file attribution and unchanged caller coverage. No additional demonstrated wrong-target or metadata regression was found. Flat attribution still consults a display-name set; the possible unknown-head homonym interaction was considered, but no new regression was established and none is claimed.

The arity finding is conservative extra TOP/precision loss, not a claim of unsound target certainty. It is an existing slot-count assumption newly exercised by the changed known-qualified-body branch. Existing tests lack this labeled argument case; their green results do not invalidate the reproduced failure.

Requested `.claude/patterns/ocaml.md` and `.claude/patterns/javascript.md` do not exist (read command exit 1). No configured formatter or coverage tool was claimed. Mandatory external runtime review belongs to root; root reports timeout/degraded, not approval. This reviewer does not claim QA, hosted CI, keep, PR or merge approval. Full Dune output was observed through the tool session; no untruncated standalone raw-log artifact is claimed.

Waited until root's cross-runtime journal was stable, completed both fixed410 runs, then wrote only these owned review reports. No product changes, commit, PR, new worktree, or Tezos edits. Existing unrelated dirt remains preserved.
