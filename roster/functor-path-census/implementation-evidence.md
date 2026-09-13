# Functor path census implementation evidence

## Recovered TDD chronology

The first attempted RED was invalid: `check.js` invoked a shell stub it created
itself, and the initial fixture expectation said nine while that draft contained
eight applications and did not put every required case in the functor head.
Production drafts of `probe.ml` and `run.js` were also written prematurely.
Those results are discarded; this is a process violation, not claimed as strict
test-first work.

The harness was corrected before retaining a GREEN result. The checked-in
fixture now has ten authored applications: nine qualified unsupported heads and
one direct matched local functor. `check.js` compiles that fixture, copies and
compiles the checked-in `probe.ml` in its owned temporary directory, and invokes
that executable on the generated CMT.

Authoritative recovered RED command:

```text
rtk opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-path-census/check.js
exit 1
assertion: fixture must retain the independently authored ten application occurrences
0 !== 10
```

The compiled OCaml stub returned valid JSON with zero applications; compilation
and execution setup errors were separately classified as exit 2. Before the
real probe replaced the stub, the oracle was frozen at ordinals 1..10,
9 `unsupported_path`, 1 matched, root categories structure=4, alias=3,
persistent=1, parameter=1, seven artifact-local identity classes and six
distinct display paths.

## GREEN evidence

```text
rtk opam exec --switch=/home/mathias/dev/arch-index -- node roster/functor-path-census/check.js
exit 0
```

The same command also runs the wrapper twice and compares semantic payloads,
then proves digest mismatch and duplicate-artifact manifests are rejected.
There is no configured coverage instrumentation, so no coverage percentage is
claimed. `Pident`, `Pdot`, and naturally produced application heads are covered;
recursive `Papply`/`Pextra_ty` encoding is implemented, but native module-head
syntax does not exercise the two extra-type variants.

## Root independent verification and publication correction

Root reran the native check with `rtk proxy opam exec
--switch=/home/mathias/dev/arch-index -- node roster/functor-path-census/check.js`:
exit 0. The commands above are the implementer's reported spellings.
No hash of the discarded premature implementation was retained; its chronology
is documented, not retrospectively reconstructed as clean TDD.

Root added an atomic-publication test before the helper existed: exit 1,
`atomic publication helper required`, actual undefined versus function.
The unchanged test then passed after implementation: an injected partial write
leaves no public output, temporary publication files are cleaned, a success
round-trips, and an existing report remains byte-identical on EEXIST.
Publication uses a same-filesystem hard link of a completed temporary file.
Source provenance now hashes the copied source actually compiled.
The implementer subsequently expanded probe formatting without behavior changes.

The fixed410 corpus ran twice, both exit 0. Root compared totals,
unit_inventory and all artifact records using strict deep equality: PASS.
The resulting counts and their limitations are in measurement.md.
