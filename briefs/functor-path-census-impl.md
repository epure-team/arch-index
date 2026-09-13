# Implementation Brief — functor-path-census

**Date:** 2026-09-13
**Mode:** full
**Status:** COMPLETED

## Modified files

Only roster/functor-path-census/ measurement code, native fixture, checks,
report and documentation, plus this task's briefs and friction bookkeeping.
No production files, schemas, APIs, installed CLI or CI changes.
The external roadmap note is updated separately.

## Decisions made

Real catalogue/binding collectors, exact ordinal bijection, two-pass binder
inventory and artifact-local compiler equality. Full outcomes retained;
unsupported paths enriched without attempting resolution. Exact staging,
manifest and before/after input digests, copied-source/binary/archive provenance.
Atomic exclusive report publication via same-filesystem hard link of completed
temporary output. All temporary builds and replay output removed.

TDD process violation was caught and recovered, not erased: first attempted RED
was an unrelated stub and premature implementation existed. Actual native
fixture/probe RED followed by unchanged-oracle GREEN is documented in
roster/functor-path-census/implementation-evidence.md. Root publication check
separately observed RED then GREEN. No discarded draft hashes are available.

## Quality Gates

- Build: `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` exit 0.
- Full tests: same prefix, `dune test --root . --force`, exit 0:
  320/320 Tezt and 64 Alcotest. Full log retained under roster/functor-path-census/.
- Native fixture, replay, manifest negatives, failure/no-overwrite publication:
  same prefix, `node roster/functor-path-census/check.js`, exit 0.
- Fixed410 `run.js` twice: exit 0 both; strict deep equality of totals,
  unit_inventory and every artifact/application PASS. Report retained.
- `node scripts/review-bundle-verify.js`: exit 0, 22/22 bundle1.6.0.
- `bash scripts/check-scope-diff.sh briefs/functor-path-census-manifest.txt`: exit 0.
- `git diff --check`: exit 0. No formatter/coverage instrumentation configured;
  no formatter or coverage-percentage claim.

## Points of attention for review

Report interpretation independently checked by Terra. Persistent-unit roots
dominate (846/1050); named inventory presence is not owner/target evidence.
202 matched outcomes unchanged. Replay excludes provenance only; report retains
all provenance. Extra-type branches encoded but not naturally exercised by
native module-head syntax. Before/after hashing is not an atomic snapshot.
Safety review concerns only this local measurement tool, not target auditing.

## Identified out-of-scope

Persistent-qualified and result-member resolution need a separate product
design/intake; no0CFA, normalization by name, CMI lookup or target gain added.
