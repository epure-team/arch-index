# Tezos / Irmin functor-instance benchmark inventory

Date: 2026-09-13.  Preparation only: no build, install, analyzer run, database
creation, or security/exploit activity was performed.

## Located input and provenance

* Checkout: `/home/mathias/dev/tezos/tezos` (Octez, including vendored `irmin/`).
* Checked-out SHA: `1727d7e192f2374edda7ad7adceef6f4ec51f71a`.
* Working tree is **dirty** (46 porcelain entries at inventory time).  Do not
  call a later result reproducible from the SHA alone; retain the CMT paths and
  their input manifest/digests with every run.
* The active compiler in both the arch-index and this checkout's opam switches
  is OCaml `5.3.0`.  `ocamlobjinfo` from the arch-index switch successfully
  decoded representative protocol and Irmin CMTs (`…__Apply.cmt`,
  `…/irmin__Store.cmt`).  The CMTs are therefore compatible with arch-index's
  OCaml-5.3 reader.  The ambient (non-switch) `ocamlobjinfo` is 5.5 and rejects
  them as older-format artifacts; it is not the compatibility oracle.

## Bounded selected inputs

Use only CMTs below (not all 473 CMTs found anywhere beneath vendored `irmin`,
and not all of Octez).  Counts include byte-code object CMTs and were measured
with `rg --files --hidden -g '*.cmt'`.

| Slice | Exact artifact directory | CMTs | Why it is in the benchmark |
|---|---|---:|---|
| Irmin core | `/home/mathias/dev/tezos/tezos/_build/default/irmin/lib_irmin/.irmin.objs/byte` | 67 | Dense generic `Maker`/`Make` definitions and applications. |
| Irmin pack interfaces | `/home/mathias/dev/tezos/tezos/_build/default/irmin/lib_irmin_pack/.irmin_pack.objs/byte` | 18 | Core pack functors and signatures. |
| Irmin pack Unix implementation | `/home/mathias/dev/tezos/tezos/_build/default/irmin/lib_irmin_pack/unix/.irmin_pack_unix.objs/byte` | 53 | Concrete multi-argument `Make` applications. |
| Tezos Alpha protocol | `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol/.tezos_raw_protocol_alpha.objs/byte` | 276 | Independent protocol-side functor use, especially storage construction. |
| **Total** | four directories above | **414** | Fixed initial input set. |

Do not add the wrapper-library CMTs from the same protocol build directory:
they duplicate/forward raw units and would confound edge and outcome counts.
Do not add Irmin test CMTs in slice 0: they widen the corpus without testing a
new production application shape.

## Representative application shapes

These are source anchors for a small query roster, not claims that the current
implementation resolves them:

| Shape | Source anchor |
|---|---|
| Nested generic-store construction and exported `Make` | `irmin/lib_irmin/irmin.ml:49-180` (`Maker_generic_key`, `Maker`, `Maker.Make`, `KV_maker`) |
| Backend-parametric store | `irmin/lib_irmin/store.ml:32` (`Make (B : Backend.S)`) |
| Pack Unix store composed from several concrete functors | `irmin/lib_irmin_pack/unix/store.ml:35-130` |
| Pack Unix façade instantiation | `irmin/lib_irmin_pack/unix/irmin_pack_unix.ml:28-32` |
| Protocol storage functors instantiated into the Alpha context | `src/proto_alpha/lib_protocol/storage_functors.ml:45-260` and `storage.ml:494-498,1946,1968` |

The source inventory also visibly contains nested applications such as
`Backend.Contents_store.Make (S.Hash) (S.Contents)` and
`File_manager.Make (Io) (Index) (Errs)`.  This establishes syntactic presence
of the target shape only.  It does **not** establish a callee identity, an edge,
or a precision gain.

## Feasible bounded A/B benchmark

Run the baseline and candidate against the same ordered, manifest-recorded
414-CMT set using separate output databases outside this worktree.  Record the
arch-index commit, compiler version, Tezos SHA, dirty flag, exact path list,
and a digest per input.  Never compare a fresh candidate database to one of the
historical whole-Octez databases.

For each run, report both populations below:

| Measure | Definition | Interpretation |
|---|---|---|
| Selected syntactic applications | Source/CMT occurrences classified as direct functor application, nested application, and result-module value call.  Preserve the enumerated occurrence IDs. | Coverage of the intended syntax, not precision. |
| Candidate graph outcomes | For those same IDs: resolved callee ID, unresolved/external leaf, or `MAY_TOP`, with reason. | Actual target-resolution result. |
| Resolution delta | `baseline MAY_TOP -> candidate resolved`, `baseline external -> candidate resolved`, reverse transitions, and retargets. | Precision can improve only in the first two classes; retargets require review. |
| Global guarded totals | Calls, resolved internal calls, `MAY_TOP` calls by reason, and functions whose reachable graph remains unbounded. | Detects collateral widening/regression; it is not evidence of per-shape success. |

Bound the inspection to the five anchor families above and at most 20 stable
occurrence IDs: 12 Irmin (at least one from each of the first four rows) and 8
protocol storage occurrences.  For each ID, issue a direct caller/callee graph
query and preserve baseline/candidate rows.  If function identity is not stable
across runs, key the roster by CMT-relative path, source location, and typed
head spelling; do not match merely by function name.

### Gates

1. Input-manifest equality is mandatory.  A changed CMT list/digest yields
   `NOT_COMPARABLE`, not a gain.
2. No candidate may turn a baseline resolved callee into an unresolved result;
   every retarget is manually classified before reporting a net improvement.
3. A syntactically detected application that remains `MAY_TOP` is counted as
   **covered-but-unresolved**, never as a resolved instance.
4. Claim a precision gain only with at least one same-occurrence
   `MAY_TOP`/external-to-resolved transition and no unreviewed reverse or
   retarget transition.  A lower aggregate `MAY_TOP` count alone is insufficient.
5. If the candidate emits syntactic facts but the outcome distribution and the
   bounded query roster have no qualifying transition, report **no
   target-resolution gain measured**.  This is the currently supported status
   for slice 0.

## Missing premises / limits

* The source checkout is dirty; a clean frozen checkout or an immutable CMT
  manifest is needed for a reproducible benchmark.
* This inventory proves artifact readability with OCaml 5.3, not that every
  artifact's dependency closure is present in the selected set.
* No analyzer baseline/candidate database was generated in this preparation, so
  there are no outcome counts, resolved edges, `MAY_TOP` deltas, or improvement
  claim yet.
* The protocol slice contains many ordinary `Map.Make`-style constructions;
  the roster must retain the listed storage anchors so a positive result is not
  diluted into generic syntactic coverage.
