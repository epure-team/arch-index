# Reviewer R1 — origin-recurring-consumer

## Verdict

**Changes required** for one low-severity contract mismatch. The implementation is otherwise
coherent and fail-closed in the exercised trusted-local/nonhostile-writer scope. No policy bypass,
unsafe overwrite, incomplete-success marker, or regression was reproduced.

## Finding

### LOW — malformed reference module paths are accepted as drift inputs

- Location: `scripts/origin-consumer.js:68`
- Category: correctness
- Confidence: 5/5
- Fingerprint: `origin-reference-path-canonical-validation`

`validateReference` explicitly rejects absolute paths, literal `..` slash-components, and
duplicates, but it accepts empty, dot, and noncanonical identities. A direct HEAD probe reported
`ACCEPTED` for `""`, `"."`, `"lib//x.ml"`, and `"lib/./x.ml"`. These are ambiguous reference
module identities. In a normal run they subsequently mismatch the measured module population,
yielding coverage-drift1 and a complete package. The gate is therefore still
nonzero/fail-closed, but invalid-looking configuration is described as measured drift rather
than an input error.

Clarify the intended reference-path grammar. If empty, dot, or noncanonical spellings are not
valid module identities, reject them during reference validation and add failures-mode cases that
assert error2 plus the error artifact shape; otherwise document their drift classification.

## Executed verification

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`
  — chunk `d5be72`, terminal exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`
  — session `68019`, terminal exit 0; 245/245 Tezt tests succeeded. The run also completed the
  repository's Alcotest suites (64 tests across the emitted suites).
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js authentic`
  — chunk `14ef19`, exit 0.
- Same command with `failures` — chunk `fb8ff6`, exit 0. Expected injected staging-cleanup and
  final-record diagnostics were visible.
- Same command with `package` — chunk `047850`, exit 0.
- `rtk proxy git diff --check main...HEAD` — terminal exit 0 (no session allocated).
- Fresh production run under an owned `mktemp -d` parent, followed by
  `origin-consumer-artifacts.js` on the same leaf — consumer exit 0 and validator exit 0.
  Retained compact evidence: `/tmp/origin-review-r1.u0YHne/output`. Measured status `held`, policy
  `UNKNOWN`, complete `true`, totals 23 modules / 828 functions / 5,223 calls / 491 origins,
  zero deltas, 46 source inputs, 48 CMT-family inputs, detached `false`, and exactly the six known
  package files. No consumer DB, report staging directory, or native checker fixture remained.
- Direct malformed-reference probe through exported `validateReference` — terminal exit 0;
demonstrated the finding above by printing `ACCEPTED` for the ambiguous samples.

## Review coverage and limitations

Reviewed the full `main...HEAD` diff, both role briefs, the complete feature specification, and
all modified product files. Dimensions covered: runner correctness and precedence, exclusive
output ownership, cleanup/rollback, artifact integrity, input/provenance mutation checks, CI
failure/retention ordering, native controls, regression risk, and the documented trusted-local
security boundary. Fixture inspection was read-only and used no third-party target.

The executable matrix covers authentic clean/new/count paths, drift, malformed/empty evidence,
ownership, timeout/overflow, parity, mutation, publication, cleanup, and checker exit mapping.
It does not provide a coverage percentage. As already disclosed by the implementation handoff,
individual malformed verdict/census variants, signal/abnormal-exit subtypes, WAL/SHM/journal and
report-unlink failures do not each have a distinct injected case; shared handling is implemented
and related controls passed. Hosted artifact delivery itself remains unexecuted locally. Those
are test limitations, not observed contradictions.

## Open questions

Should empty, dot, and noncanonical reference identities be rejected as input errors or be
accepted and documented as coverage-drift inputs?
