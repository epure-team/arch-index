# Implementation evidence — final handoff

Source: Sol product owner `/root/origin_implement`, not independent review or root QA.
Initial integrated suite session7896 reached terminal exit0,245/245Tezt plus64Alcotest.
Root requested finalization/provenance corrections before accepting phase completion.

## Executed behavior reported before the final corrections

- AC1: production held UNKNOWN,23/828/5223/491,zero drift, exact single allowance.
- AC2/3/8: real independently built native clean/new/count cases traverse the full runner;
  fresh line2×1 and allowed line1×2 produce actual policy-failed1. Checker expected failure
  remains pass0; deliberate checker assertion1 and execution2 verified.
- AC4/6: total, module and union-of-origin-group directional drift; empty index and CMT
  symlink refusal. Invalid reference paths initially inspected only, not injected.
- AC5: malformed gate JSON and census/structural validation. Not every invalid verdict variant
  separately injected; absence of a variant test must not be represented as executed evidence.
- AC7: scoped source mutation and arch-errors.toml absence-to-presence mutation refused;
  dirty fixture state did not independently fail the consumer.
- AC9: literal allowance pinned; regeneration absent from CLI. Review rationale is a manual
  process/documentation obligation, not something automated tests prove.
- AC10: policy violation plus coverage drift retained with policy-failed precedence.
- AC11/12: native six-file packages and final artifact digests, including actual violations.
- AC13: occupied directory/file/dangling symlink preserved; symlinked parent physically resolved.
- AC14: timeout and16MiB capture overflow refused. Distinct signal/abnormal-exit injection
  initially untested.
- AC15/20: live gate/JSON/SARIF parity, explicit report tamper and missing HTML; distinct
  UNKNOWN alert-removal injection initially untested.
- AC17: source/CMT/interface/config/tool identities and outside-Git refusal. Detached/root/output
  record fields found missing by root; corrected in the subsequent batch below.
- AC18/19: CI known six filenames,v7,14-day retention and no consumer continue-on-error
  inspected/static checked; missing artifact validator checked. Remote upload has not run.

## Subsequent correction batch

Owner reports actual cleanup behavioral red1 (`cleanup failure must outrank a validated held
policy`, observed0), then failures mode green0 after finalization correction. This is an actual
test-first correction, unlike the earlier setup-only red disclosed in implementation-baseline.md.
The batch adds cleanup/final-record controls; preserves policy before report copies; records
Git root, detached state, physical output and trusted-build limitation; checks detached inputs
and physical source containment; reruns new/count with matching updated reference and unchanged
allowance (policy-failed1,zero drift); cleans native fixture construction failures.

Root's follow-up read still found cleanup errors sent only to diagnostics rather than stderr;
the explicit AC16/EC13 stderr requirement was returned to the owner before final handoff.
Final post-correction session60629 terminal0 (245/245Tezt plus64Alcotest, build0);
last Tezt success19:07:58.378Z. Prior session82217 terminal0 preceded the stderr correction.
Latest retained package `/tmp/origin-consumer-evidence-final.NHLnhy/output` passes consumer0
and validator0 with held UNKNOWN,23/828/5223/491,zero drift,46sources/48CMT-family inputs,
Git root/output/detached=false/trusted-build fields and schema1.13+producer metadata.

## Ownership and next gates

One shared delivery worktree; owner has exclusive product/build execution. Root owns docs,
pipeline evidence and roadmap. No new worktree. Final impl brief is emitted at handoff.
Independent reviewer, architect, spec-compliance, cross-runtime review, QA and exact-head
remote CI remain required; this record does not stand in for any of those gates.
