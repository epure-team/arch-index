# Research — tezos-residual-targets

_Generated: 2026-09-14_
_Mode: fast_
_Online research: enabled_

Research-process notes: the claims reconciler was not installed, so its required
`manifest-neutral` validation could not run. The acknowledged research-orientation
resolver was also unavailable (`scripts/code-intel-resolve.js` did not yield a
resolvable pack); direct live-source reads were used. These are tooling skips,
not source findings.

## Question 1: How do arch_index_cmt.ml and call_graph_extractor.ml currently derive, represent, and classify module and value identities from CMT Typedtree, Path, Ident, and Uid data?

**Finding:** The CMT fallback reads only implementation annotations, obtains a
source path from the CMT metadata, and constructs per-structure tables before
walking each top-level value binding. A pending call preserves caller module/name,
a `call_head`, source line, and CFG-derived execution facts. `Head_local` is a
same-module function-body target, `Head_qualified` is a persistent-root qualified
target, `Head_enumerated` is a bounded local/lambda/owned-module target, and
`Head_unknown` retains a display name plus a reason.

Top-level function identities are keyed by `Ident.unique_name`; the index names
colliding bindings by source order, keeping the final binding's unsuffixed name.
The local-function table maps that identity to the registered definition path and
syntactic arity. The local-module table is keyed by `Ident` and maps syntactically
owned structure exports to optional `(definition name, arity)` values. A qualified
path is rendered structurally from `Pident`/`Pdot`; `Papply` and `Pextra_ty` have
no structural module/name decomposition in that helper. `Uid` is not used by these
two extraction paths for call-head classification.

**References:**

- `lib/arch_index/call_graph_extractor.ml:233-280` — reads CMT implementations and builds the local function/module tables.
- `lib/arch_index/call_graph_extractor.ml:289-360` — threads alias/module tables into the shared collector and emits flat call rows.
- `lib/arch_index/arch_index_cmt.ml:601-670` — defines `call_head`, `pending_call`, and the display projection.
- `lib/arch_index/arch_index_cmt.ml:900-959` — gives source-order collision naming and `Ident.unique_name` mapping.
- `lib/arch_index/arch_index_cmt.ml:961-997` — records eligible top-level function bodies by `Ident.unique_name`, definition path, and arity.
- `lib/arch_index/arch_index_cmt.ml:1000-1114` — represents locally owned module exports keyed by `Ident` and resolves member paths through that map.
- `lib/arch_index/arch_index_cmt.ml:721-756` — extracts/prints module paths and explicitly handles `Pident`, `Pdot`, `Papply`, and `Pextra_ty`.

---

## Question 2: Which existing code paths handle qualified persistent modules, module aliases, functor applications, and functor parameters, and where do they deliberately refuse or leave call targets unresolved?

**Finding:** A qualified path whose root `Ident` is persistent is represented as
`Head_qualified`; a non-persistent root is classified as dynamic and becomes
`Head_unknown (..., Module_param)` unless a local structured-module export or a
per-CMT module-alias rewrite supplies a target. Module aliases are keyed by the
binder's `Ident.unique_name` and are recorded only when their target root is
persistent; application, unpack, literal-structure, unit-local, and
functor-parameter aliases are not recorded by that table. Alias rewrites require
ordinary dot segments and attach `edge_form = "module_alias"`.

The local structured-module resolver recognizes bodies represented by
`Tmod_structure` (and constrained equivalents); it descends into a functor body
to discover inner concrete binders, but does not assign an owner to the functor,
`Tmod_apply`, `Tmod_apply_unit`, `Tmod_ident`, or `Tmod_unpack`. Path lookup also
returns no local owner for `Papply`/`Pextra_ty`. Unqualified identifiers absent
from the local function-body table become `Head_unknown (..., Callback_param)`;
computed heads use `*TOP*`. The shared collector carries these classifications
into the fallback flat schema as display names and optional files.

**References:**

- `lib/arch_index/arch_index_cmt.ml:1023-1039` — local-module ownership accepts structures/constraints, scans functor bodies, and declines apply/ident/unpack forms.
- `lib/arch_index/arch_index_cmt.ml:1090-1102` — local member lookup declines `Papply` and `Pextra_ty`.
- `lib/arch_index/arch_index_cmt.ml:1163-1232` — module-alias table uses binder identity and admits only persistent-root targets.
- `lib/arch_index/arch_index_cmt.ml:1454-1514` — identifies non-persistent path roots as dynamic and constrains alias rewrites to dot-segment paths.
- `lib/arch_index/arch_index_cmt.ml:1516-1560` — classifies function-valued arguments, including owned modules, rewritten aliases, dynamic module parameters, and unknown heads.
- `lib/arch_index/arch_index_cmt.ml:1564-1595` — classifies resolved `Path.t` calls as local, owned/enumerated, alias-rewritten, dynamic-module, or qualified.
- `lib/arch_index/arch_index_cmt.ml:1603-1631` — the configuration-head classifier deliberately does not perform module-alias rewriting.
- `tezt/tests/local_module_targets.ml:134-198` — asserts enumerated same-file module targets and module-parameter/opaque/apply/alias boundary cases.
- `tezt/tests/top_anchor_taxonomy.ml:83-119` — checks a functor argument member as `MAY_TOP`/`module_param` and a direct local call as `MUST` without a top reason.

---

## Question 3: How do the Tezt tests, retained corpus artifacts, and verifier harness under roster/tezos-call-resolution and roster/functor-instance-resolution currently measure resolution outcomes and preserve existing graph relations?

**Finding:** Tezt fixtures exercise call-kind and target-row outcomes in SQLite.
The soundness corpus defines unconditional, deferred, conditional, callback,
first-class-module, alias, partial-application, and functor shapes; its comments
and test assertions describe MUST as every execution and retain demoted calls.
The local-module suite checks `MAY_ENUMERATED` rows with matching caller/callee
module IDs, retains `MAY_TOP` for specified boundary fixtures, and checks the
flat CMT path separately. The top-anchor suite checks the pairing of `MAY_TOP`
with a top reason/anchor and verifies a resolved MUST row has neither.

The retained 410-CMT functor catalogue is a bounded syntactic-artifact corpus:
its reproduction script validates each manifest digest, symlinks the selected
artifacts into a temporary build tree, runs the existing producer, then queries
catalogue and aggregate output. Its report records 410 selected inputs, 1,275
syntax applications, and states that the run does not claim target resolution or
a before/after precision result.

The Tezos comparison verifier pins manifest, producer, Tezos revision, checkout,
baseline row count/digest, source-state hashes, and artifact hashes. It snapshots
baseline/candidate rows, requires an exact-positioned witness for approved
transitions or residuals, compares them, and writes provenance, changes, and a
report. Its isolated checker constructs controlled databases and refuses missing,
altered, incomplete, duplicate, or wrongly attributed corpus/provenance inputs.

**References:**

- `tezt/tests/callgraph_soundness.ml:8-25` — defines the enforced dominance-based MUST corpus and retention of demoted calls.
- `tezt/tests/callgraph_soundness.ml:63-100` — contains callback, first-class-module, cross-module, and module-alias fixture shapes.
- `tezt/tests/callgraph_soundness.ml:102-151` — contains conditional/deferred functor and partial-application shapes.
- `tezt/tests/local_module_targets.ml:134-198` — SQL assertions for enumerated/local and `MAY_TOP` boundary outcomes.
- `tezt/tests/local_module_targets.ml:223-246` — tests both indexed and flat-CMT results for local module targets.
- `tezt/tests/top_anchor_taxonomy.ml:83-156` — checks module-parameter and resolved-edge top-reason/anchor relations.
- `roster/functor-instance-resolution/tezos-irmin-candidate/reproduce.sh:16-44` — creates a temporary symlink corpus, verifies manifest digests, runs the producer, and queries results.
- `roster/functor-instance-resolution/tezos-irmin-candidate/report.md:27-64` — records the 410-input/1,275-application corpus outcome and one-run graph totals.
- `roster/functor-instance-resolution/tezos-irmin-candidate/report.md:82-89` — states the catalogue limitations and that a matching baseline is required for a delta.
- `roster/tezos-call-resolution/verify.js:36-69` — validates pinned provenance, manifest entries, and source state.
- `roster/tezos-call-resolution/verify.js:88-121` — binds witnesses/residuals to exact snapshots and source positions.
- `roster/tezos-call-resolution/verify.js:123-183` — creates a candidate from symlinked inputs, compares snapshots, preserves input/source state, and writes durable verification outputs.
- `roster/tezos-call-resolution/check-comparison.js:28-63` — exercises neutral replay, duplicate deletion, target/kind mutation, exact approved transition, and cross-file refusal cases.
- `roster/tezos-call-resolution/check-verifier-inputs.js:60-119` — tests manifest digest/count/duplicate checks and corpus/provenance/database completeness checks.

---

## Question 4: [ecosystem] What identity, path, alias, and functor-application information do the supported OCaml compiler-libs APIs officially expose through CMT files, Typedtree, Path, Ident, and Uid?

**Finding:** The official OCaml 5.3 compiler-libs documentation describes CMT/CMTI
reading through `Cmt_format.read`; `cmt_infos` exposes the compilation-unit name,
typed annotations, source/build/load-path metadata, declaration dependencies
keyed by `Typedtree.Uid.t`, `uid_to_decl`, implementation shape, and identifier
occurrences. `cmt_annots` can contain an implementation `Typedtree.structure` or
interface `Typedtree.signature`. Typedtree is the post-typing AST, and the 5.3
API states that every `Longident.t` is accompanied by a resolved `Path.t`.
Typedtree bindings carry both `Ident.t` and `Uid.t` in relevant constructors.

`Shape.Uid.t` identifies declarations in signatures and implementations and is
stored in the CMT UID-to-declaration table; its public cases include compilation
unit, item (compilation unit, integer id, interface/implementation), internal,
and predefined identities. `Ident` exposes `name`, `unique_name`, `persistent`,
and equality by binding location; the documentation explicitly notes that equal
visible names can be shadowed by distinct identifiers. These identity APIs are
versioned compiler internals: the OCaml 5.3 manual says the exported front-end
interface follows compiler evolution and offers no backwards-compatibility
guarantee. This report distinguishes OCaml 5.3.0 API documentation from the
current “latest” Typedtree documentation, which is a later release line.

**References (official primary sources, accessed 2026-09-14):**

- [OCaml 5.3.0 `Cmt_format` API](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmt_format/index.html) — `read`, annotation variants, and CMT metadata including UIDs and shapes.
- [OCaml 5.3.0 `Typedtree` API](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Typedtree/index.html) — post-typing tree, resolved `Path.t` alongside long identifiers, and binding fields.
- [OCaml 5.3.0 `Shape.Uid` API](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Shape/Uid/index.html) — declaration identity and CMT UID-to-declaration storage.
- [OCaml 5.3.0 `Ident` API](https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Ident/index.html) — names, unique names, persistence, binding-location identity, and shadowing behavior.
- [OCaml 5.3 compiler-front-end manual](https://ocaml.org/manual/5.3/parsing.html) — compiler-libs status and no backwards-compatibility guarantee for the exported front-end API.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---:|---|
| Per-CMT stamp identity | `lib/arch_index/arch_index_cmt.ml` | 961-997 | Local function bodies map `Ident.unique_name` to registered path and arity. |
| Persistent-root qualification | `lib/arch_index/arch_index_cmt.ml` | 1454-1465 | Persistent roots remain qualified; non-persistent roots are dynamic. |
| Alias rewrite by binder identity | `lib/arch_index/arch_index_cmt.ml` | 1163-1232 | Only persistent-target aliases enter the per-CMT table. |
| Explicit functor/application boundary | `lib/arch_index/arch_index_cmt.ml` | 1023-1032 | Functor bodies are scanned for inner binders; functor/apply forms receive no concrete owner. |
| Pinned corpus comparison | `roster/tezos-call-resolution/verify.js` | 131-173 | Baseline/candidate comparison is bound to hashes, source state, and exact witnesses. |

## External prior art

| Tool / API | Source | Key finding |
|---|---|---|
| OCaml compiler-libs 5.3 `Cmt_format` | https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Cmt_format/index.html | CMT metadata includes typed annotations, declaration UIDs, shapes, and identifier occurrences. |
| OCaml compiler-libs 5.3 `Typedtree` and `Shape.Uid` | https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Typedtree/index.html ; https://ocaml.org/p/ocaml-compiler/5.3.0/compiler-libs.common/Shape/Uid/index.html | Typedtree carries resolved paths; UIDs identify declarations and can be stored in CMT data. |

## Coverage gaps

None. The source answers are static-behavior findings; the retained catalogue itself records that it is not a target-resolution comparison.
