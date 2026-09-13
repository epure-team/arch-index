# QA Brief — guard-division-analysis

**Date:** 2026-09-13T08:32:09Z
**Status:** GO ✅
**Round:** 1 (qualifying 0/5)

## Round state

Fresh cycle1, round1; causes empty. Actual lifecycle witness and QA convergence
gate0, no warnings/violations. Reviewed clean commit75c30ac9fe478bcada8cae4c3ff65a130ec76c80.
No code changes during QA. Evidence writes followed pristine calibration.

## Quality Gates

Exact resolved commands, raw output, terminal exits and durations are retained in
[qa-execution.json](../roster/guard-division-analysis/qa-execution.json).
All commands used rtk proxy; compiler-backed commands used the configured opam switch.

| Gate | Exit | Duration |
|---|---|---|
| build | 0 | 0.465s |
| suite | 0 | 154.321s |
| whitespace | 0 | 0.162s |
| guard-inventory | 0 | 0.410s |
| guard-numeric | 0 | 0.653s |
| guard-domain | 0 | 6.796s |
| guard-inputs | 0 | 9.899s |
| guard-report | 0 | 1.245s |
| guard-owned | 0 | 0.343s |
| context | 0 | 0.312s |
| origin-authentic | 0 | 2.811s |
| origin-failures | 0 | 4.721s |
| origin-package | 0 | 0.419s |
| self | 0 | 0.321s |
| golden | 0 | 0.194s |
| rules | 0 | 0.202s |
| impact | 0 | 0.196s |
| origin-produce | 0 | 0.472s |
| origin-validate | 0 | 0.188s |
| recalibration | 0 | 4.397s |
| scope | 0 | 0.185s |

Build preceded the full forced suite; whitespace gate preceded standalone checks.
No separately configured formatter/full linter. Existing opam lint metadata debt
is explicitly non-gating; no metadata/dependency changes or hidden lint PASS.

## Tests: detail

256/256 Tezt successes and64 Alcotest cases (3+8+17+10+7+5+14), no failures.
Eleven guard Tezt registrations include six checker modes, shared context and
assertion/execution controls. Complete40,301-byte suite output was captured without
truncation; qa-full-suite.log only normalizes ANSI/trailing whitespace.

CHECK-1 through CHECK-7 each PASS independently, including promoted AC-20.
All47FR, original19AC and new context AC20 retain the independent R2 matrix.
Inventory tests8primitive identities, application/type seams, exact original
operand slots, reversal/dedup, shadowing and metadata boundaries. Numeric tests
all5statuses,26base cases and36nativeR1sites, exact reasons, binder/entry/exclusion
semantics and four disclosed effect seams. Domain640734probe responses and
23219242 independent BigInt laws, exhaustive3–8/sample31/63: executable evidence,
not formal proof. Input/report exact and one-over limits, actual CLI atomicity,
semantic text/JSON equality, unusual escaped paths, wrong-reason/field sensitivity
controls, install privacy/public CLI and copied-wrapper behavior PASS.
Owned corpus23artifacts, genuinely0sites. No percentage coverage invented.

Fresh self golden byte-equal23modules/828functions/5223calls. Rules1proved,
3UNKNOWN,0failing/vacuous. Impact111outside-index changed files UNKNOWN; effects
and decision analysis not computed. Origin producer+validator0, held result.
Pristine four-cell calibration0: golden unchanged; A=B396,C=D437, pin430 within
unchanged25headroom. No reference/pin/extractor changes.

## Code-intel gate

Skipped: no kb/properties.md/code-intel block or installed consumer resolver.
Claims authority/reconciler and context freshness mechanism absent; legacy draft
claims remain disclosed. Hooks absent. No stale managed-claims PASS asserted.

## TUI

Skipped: no TUI surface or scenarios; CLI behavior is covered above.

## Cross-runtime QA

Actual shared-breaker availability check (including after all deterministic gates)
returned skipped-degraded, source review-go, unchanged runtime version,
config_digest opencode:76f897c73342fdbf. No second-runtime PASS or provider attempt.
The briefs-not-ignored warning is disclosed; journals are scoped task evidence.

## Verdict

GO — ready for roster-ship under standing explicit autonomous approval.
No Tezos scan/measured gain, whole-program guarantee, host-global restoration,
source freshness, interprocedural model or functor specialization claimed.
