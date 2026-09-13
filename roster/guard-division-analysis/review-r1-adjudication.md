# Review round 1 adjudication

All three independent specialists built and ran the full suite and local guard/self/origin
gates. All report255Tezt+64Alcotest passed. Their fresh recalibration attempts exit2 because
the root's review trace and reports make HEAD non-clean. This is not a successful calibration.
Implementation's committed fae9243 calibration passed; source code has not changed since.
Because this review is NO-GO on a real specification failure, successful recalibration is
required on the corrected committed head before any later GO, not waived. The earlier proposal
to rerun three pristine matrices on this already-NO-GO head is superseded by that sequencing.

Retain all seven normalized findings (one CRITICAL, six MEDIUM). Two reviewer checker findings
overlap the spec specialist's broader coverage gaps but retain independent sensitivity evidence;
do not inflate them into seven unrelated product defects. CRITICAL here is the roster spec
divergence severity, not a security vulnerability severity. No arithmetic unsoundness demonstrated.

The exported-library compiler-global mutation is corroborated but remains MEDIUM, not promoted
by speculation. Its remedy needs an explicit composability boundary in the correction plan;
restoring only path names or using Local_store alone does not restore every compiler global.
No finding is accepted or waived and no product/source auto-fix was made during this review.

The initially suspected malformed-input diagnostic defect was withdrawn after tracing the actual
CMT reader and corroborating its correct malformed/read failure behavior. An unreachable separate
text-size fixture demand was also withdrawn. Preserve these corrections in specialist evidence.

OpenCode was actually invoked once via the mandatory helper, round1/cycle1, timeout120.
It exited0 but returned prose instead of finding JSON. Helper classification is degraded,
reason non-conforming-output, digest opencode:fd1dbeaa7d0c6431; output is discarded, never GO.
The helper's journal retains the bounded diagnostic excerpt. No re-probe this cycle without a
qualifying configuration change or explicit retry. No finding is derived from its prose.

Normalizer2.0.0 actually ran twice (second run retained its output); zero rejections/warnings.
Raw specialist confidence/category conventions were corrected before intake; no substantive
finding was silently dropped. Scope gate passed; KB/code-quality, TUI and claims hooks absent.
No remote CI/QA/ship or Tezos scan yet. Full convergence gate still required before verdict.

Owned reviewer/spec/architect database scratch, marker clients and build artifacts removed
after compact evidence retention. Active delivery worktree remains needed; unrelated worktrees
and local cost telemetry untouched.
