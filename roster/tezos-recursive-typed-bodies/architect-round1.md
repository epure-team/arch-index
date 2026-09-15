# Architect round 1 — tezos-recursive-typed-bodies

**Review target:** `d954303f7059f0a60b6bee3e463060508dd20eee`
**Findings:** none (`architect-round1.json` is the empty standard-finding array).
**Architecture risk:** low for the reviewed change; this is not a pipeline GO, CI, formal-verification, or human-approval claim.

## Architecture assessment

The only product seam changes the singleton recursive descriptor construction in
`lib/arch_index/arch_index_cmt.ml`.  The direct-function alternative is retained;
the added alternative admits only one `Texp_open` with `Tmod_ident` and an
immediate `Texp_function`.  Its `recursive_expected_body` and arity are taken
from the matched original inner expression object, not the wrapper or a copy.

The surrounding `Ident.same`-based recursive scope, unique physical observation,
collision-qualified allocation, and successful-storage gate are unchanged.  The
change does not add to ordinary binding tables, public flat collection, schema,
or native/SQL identity responsibilities.  The native witness reconstructs
identity, shape, caller, range, ordinal, and arity from CMT input; candidate SQL
is checked separately for storage correspondence.  Counted rich/pending and
duplicate-sensitive flat preservation, parent/continuation/non-head controls,
and single-use head/residual capacities are exercised by the task checks.

Frozen evidence replayed as the sealed PR108 v2 baseline: 45,052 rows, digest
`082bdce92c6cab7b654f87a90db59ca9979d7004f45a42997a33718f6cd7c67a`, and
Irmin 4,849 / protocol 12,157 relations.  The comparison reports 14 witnessed
relation gains with zero loss; that result does not authorize retention.

No architecture duplication defect was identified: the narrow AST admission
reuses the existing recursive target and storage machinery rather than creating
a parallel resolver.  Scope findings are deferred to the already-passed scope
gate, as directed.

## Personally executed serial gates

| Command | Exit | Duration | Result |
|---|---:|---:|---|
| `rtk proxy opam exec -- dune build` | 0 | 0.236s | passed |
| `rtk proxy opam exec -- dune exec tezt/tests/main.exe -- --no-color --keep-going` | 0 | 273.2s | 342/342 SUCCESS; recursive-open tests included |
| `rtk proxy node scripts/review-bundle-verify.js` | 0 | <0.001s | 22 files, bundle 1.6.0 |
| `rtk proxy git diff --check` | 0 | <0.001s | passed |
| `rtk proxy node roster/tezos-recursive-typed-bodies/prepare-baseline.js --check` | 0 | 4.328s | sealed neutral replay passed |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-native.js` | 0 | 3.042s | authentic targets; rich/flat preservation passed |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-witness-inputs.js` | 0 | 3.747s | CMT identity and refusal/capacity controls passed |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-baseline.js` | 0 | 5.744s | immutable sealed baseline controls passed |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-comparison.js` | 0 | 29.734s | witnessed candidate comparison passed |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-compatibility.js` | 0 | 3.875s | public/schema/flat and old-checker preservation passed; CI remains unverified |
| `rtk proxy node roster/tezos-recursive-typed-bodies/check-residual-capacity.js` | 0 | 6.884s | supplied-slot/residual capacity controls passed |

## State custody

The actual HEAD before and after the gate sweep is
`d954303f7059f0a60b6bee3e463060508dd20eee`.  The actual producer is
`_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe`, SHA-256
`1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593`.
Correction by the orchestrator after checking the actual invocation log: the
initial aggregate state probe failed with `spawnSync git EPERM`. The two equal
`baseline.js state()` fingerprints
`c3efe3021ca8c657918cb69fa60c7c66603d405eb934cd031a961572b67047e1`
were captured consecutively **after** the gate sweep, not on either side of it.
That local `assertStateUnchanged` passed but does not prove the entire sweep's
aggregate stability. Individual checkers performed their own successful state
checks; the root independently captured the same digest during the full test run.
No failed probe is represented as PASS. The existing seven unrelated untracked user
files were preserved; no source, test, checker, old evidence, or git state was
written by this review.

## Residual risk

Risk is bounded to the intentionally narrow typedtree pattern and is mitigated
by native negative shapes, storage-rejection behavior, identity/capacity
refusals, and full counted preservation checks.  Exact-final-head CI and the
remaining pipeline/human controls are outside this review and unverified here.
