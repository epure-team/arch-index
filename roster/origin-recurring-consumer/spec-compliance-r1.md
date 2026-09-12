---
auditor: spec-compliance-auditor
date: 2026-09-12
status: 0 critical, 5 warnings, 0 info
coverage: 26/45 claims verified (57.8%)
spec: specs/origin-recurring-consumer.md
head: 189f805
---

# Spec compliance — recurring owned origin consumer

The implementation matches every located requirement. No `DIVERGE`, `MISSING`, or unspecified
user-facing feature was found. The warnings below are intentionally conservative: implemented
branches without a specific test remain `UNTESTED`, even where a neighboring branch is exercised.

Context-reuse disclosure: this specialist thread previously formalized the feature requirements;
it is therefore not a fresh independent voice. Compliance conclusions were re-grounded in the
final corrected spec, implementation diff, changed product files, and independently executed gates.

The skill's default `kb/reports/` destination was redirected to this task-owned roster path because
the manifest forbids creating `kb/`; this is reporting friction, not a product finding.

## Compliance matrix

| Claim | Status | Implementation | Specific test/evidence | Notes |
|---|---|---|---|---|
| FR-001 | PASS | `scripts/origin-consumer.js:282`; `.github/workflows/ci.yml:298` | `checks/origin-recurring-consumer.js:50`; full suite | Fixed production CLI and required build-job step. |
| FR-002 | UNTESTED | `scripts/origin-consumer.js:63` | production reference exercised at `checks/origin-recurring-consumer.js:50` | Negative reference-shape/group validation branches lack specific tests. |
| FR-003 | PASS | `scripts/origin-consumer.js:89` | `checks/origin-recurring-consumer.js:127-137` | Directional total, module, and group redistribution checks. |
| FR-004 | PASS | `scripts/origin-consumer.js:12,186-187,218` | production authentic check; diff confirms `arch-rules.txt` unchanged | Exact declaration and four gate flags. |
| FR-005 | PASS | `test/fixtures/origin-consumer/self.allow:1` | `checks/origin-recurring-consumer.js:57-58,74-90` | Literal allowance and counted division controls. |
| FR-006 | PASS | `scripts/origin-consumer.js:167-170,200-206,236-241` | `checks/origin-recurring-consumer.js:183-200` | Config-presence and scoped source mutation are rejected. |
| FR-007 | UNTESTED | `scripts/origin-consumer.js:123-144,228-231` | malformed `{}` only at `checks/origin-recurring-consumer.js:139-144` | Missing/extra/census/exit variants are not each specifically tested. |
| FR-008 | UNTESTED | `scripts/origin-consumer.js:126-138,230-234` | authentic PASS/UNKNOWN and VIOLATION paths | POSSIBLE and each ineligible verdict lack consumer-specific tests. |
| FR-009 | PASS | `scripts/origin-consumer.js:230-245,260-263` | `checks/origin-recurring-consumer.js:74-90,215-226` | Policy-over-drift and error-over-held evidence retained. |
| FR-010 | UNTESTED | `scripts/origin-consumer.js:25-60,67-69,195-205` | physical escape and CMT symlink tests | Duplicate canonical CMT and generated-CMT recording lack specific tests. |
| FR-011 | PASS | `scripts/origin-consumer.js:101-107,197-217` | `checks/origin-recurring-consumer.js:131-133,156-160` | Valid module mismatch drifts; unusable empty measurement errors. |
| FR-012 | PASS | `checks/origin-recurring-consumer.js:19-91` | CHECK-1 and registered Tezt controls | Native CMTs traverse actual tools and full runner. |
| FR-013 | PASS | `scripts/origin-consumer.js:282-285`; `docs/origin-consumer.md:132` | matched-reference policy controls; CLI shape | No regeneration/autoaccept or count exemption. |
| FR-014 | PASS | `scripts/origin-consumer.js:220-243`; `docs/origin-consumer.md:116-129` | fresh production package inspection | Opaque evidence preserved; limitations documented. |
| FR-015 | PASS | `scripts/origin-consumer.js:235-243,265-268` | `checks/origin-recurring-consumer.js:61-70,238-247` | Closed six-file package; run record written last. |
| FR-016 | PASS | `scripts/origin-consumer.js:148-153` | `checks/origin-recurring-consumer.js:96-109` | Existing leaves preserved; physical parent resolved. |
| FR-017 | UNTESTED | `scripts/origin-consumer.js:18-24` | timeout and overflow at `checks/origin-recurring-consumer.js:203-213` | Signal and abnormal nonzero subprocess branches lack specific tests. |
| FR-018 | UNTESTED | `scripts/origin-consumer.js:123-144` | report-JSON tamper and missing HTML tests | SARIF-specific/census parity corruption lacks a consumer-specific test. |
| FR-019 | PASS | `scripts/origin-consumer.js:171,217,232-243` | package/authentic checks plus fresh package | Separate status fields and final artifact digests present. |
| FR-020 | PASS | `scripts/origin-consumer.js:228-243` | `checks/origin-recurring-consumer.js:74-90` | Failure package validates and retains evaluator detail. |
| FR-021 | UNTESTED | `scripts/origin-consumer.js:244-277` | staging cleanup and final-record fault tests | Promotion/write-permission and diagnostics-write failures lack specific tests. |
| FR-022 | UNTESTED | `scripts/origin-consumer.js:189-206` | detached/outside-Git/physical escape tests | Dirty and untracked-input recording lack specific tests. |
| FR-023 | PASS | `scripts/origin-consumer.js:224-243`; `docs/origin-consumer.md:126-129` | authentic UNKNOWN package passes parity | Reporter SARIF is copied unchanged; outcomes remain in run record. |
| FR-024 | UNTESTED | `.github/workflows/ci.yml:302-319`; `scripts/origin-consumer-artifacts.js:7-25` | static workflow assertions and local validator tests | Remote retention/upload and early-no-output behavior are not executed locally. |
| FR-025 | PASS | exported seam at `scripts/origin-consumer.js:147`; fixture builder | CHECK-1/CHECK-3 outside production rollout | Independent native fixture package demonstrated. |
| AC-1 | PASS | production path/reference/rule | `checks/origin-recurring-consumer.js:50-58`; fresh production run | Held0, exact totals, zero drift, UNKNOWN package. |
| AC-2 | PASS | policy classification and reference separation | `checks/origin-recurring-consumer.js:72-90` | Fresh line-2 division remains failure after count update. |
| AC-3 | PASS | counted allow evaluator path | `checks/origin-recurring-consumer.js:71-90` | Same-line `x2` fails against `x1`. |
| AC-4 | PASS | coverage comparison/status | `checks/origin-recurring-consumer.js:127-137` | Total and redistribution deltas observed. |
| AC-5 | UNTESTED | gate/evidence validation | malformed gate test only | Full malformed/renamed/noncomputed/census matrix is not specifically tested. |
| AC-6 | UNTESTED | inventory/reference validation | empty, module mismatch, escape, symlink tests | Invalid reference-path and generated-CMT outcomes lack tests. |
| AC-7 | UNTESTED | mutation/provenance | scoped mutation and config-presence tests | Unrelated dirty-state behavior lacks a specific test. |
| AC-8 | PASS | checker exit mapping and native orchestration | registered three modes plus assertion1/execution2 | Full suite executed all five Tezt registrations. |
| AC-9 | PASS | fixed CLI/artifacts/docs | literal allowance assertion and matched-reference control | Manual-only update boundary is observable. |
| AC-10 | PASS | precedence/retention | policy+drift and cleanup-failure controls | Both mixed outcomes exercised. |
| AC-11 | PASS | complete fixture package | authentic/package modes and fresh validator | Six consistent files, independent fixture, digests. |
| AC-12 | PASS | policy-failed publication | new/count policy cases call validator | Complete faithful exit1 package. |
| AC-13 | PASS | exclusive output ownership | file/directory/dangling symlink and parent-alias controls | Prior bytes preserved. |
| AC-14 | UNTESTED | subprocess/error rollback | timeout and overflow controls | Signal and abnormal exit are implemented but not specifically tested. |
| AC-15 | UNTESTED | evidence parity validator | JSON tamper and absent HTML controls | SARIF-specific divergence and HTML wrong-value branches lack tests. |
| AC-16 | UNTESTED | rollback/finalization | stage cleanup, DB cleanup, final record faults | Promotion/write-permission and report-cleanup-failure paths lack tests. |
| AC-17 | UNTESTED | provenance and limits | detached, outside-Git, physical escape controls | Dirty/untracked and changed compiler/path cases lack specific tests. |
| AC-18 | UNTESTED | workflow validator/upload | static CI assertions only | Actual status-dependent GitHub retention is not executed locally. |
| AC-19 | UNTESTED | validator failure behavior | disappeared HTML tested | Early no-file retention and CI-level independent failure are not executed. |
| AC-20 | PASS | unchanged SARIF plus run separation | authentic UNKNOWN passes `validateEvidence`; fresh package validates | Expected UNKNOWN alert and no fabricated consumer SARIF fields. |

## Warnings

### W1 — Reference and gate validation variants are not specifically tested

- **Claims:** FR-002, FR-007, FR-008, AC-5
- **Evidence:** validation exists in `scripts/origin-consumer.js:63-80,123-144`, but the adverse
  suite supplies only a malformed empty gate object; it does not independently exercise duplicate
  reference groups, unsafe totals, extra results, inconsistent census/exit, POSSIBLE, or each
  rejected verdict.
- **Recommendation:** add table-driven consumer tests for the unresolved validation branches.

### W2 — Inventory and provenance edge branches have incomplete direct coverage

- **Claims:** FR-010, FR-022, AC-6, AC-7, AC-17
- **Evidence:** escape, symlink, detach, outside-Git, and source mutation are covered, but duplicate
  canonical CMTs, generated CMT recording, dirty/untracked inputs, and compiler/build-path variation
  are not specifically asserted.
- **Recommendation:** add focused fixture cases without expanding production discovery scope.

### W3 — Subprocess and publication failure families are only partially exercised

- **Claims:** FR-017, FR-021, AC-14, AC-16
- **Evidence:** timeout, overflow, staging cleanup, DB cleanup, and final-record faults are covered;
  signal, abnormal nonzero exit, promotion/write-permission failure, diagnostics-write failure, and
  report-cleanup failure are not individually tested.
- **Recommendation:** add labeled deterministic fault cases for the remaining shared branches.

### W4 — Cross-artifact validation lacks SARIF-specific corruption coverage

- **Claims:** FR-018, AC-15
- **Evidence:** report JSON tampering and missing HTML fail closed, while SARIF rule census/alert
  divergence and wrong HTML identity/verdict are implemented but not directly corrupted by tests.
- **Recommendation:** add one SARIF census/alert tamper and one wrong-HTML-content case.

### W5 — CI retention is statically checked, not behaviorally executed

- **Claims:** FR-024, AC-18, AC-19
- **Evidence:** workflow text, local validator digest/missing-file behavior, and `always()` wiring are
  present; local checks cannot establish actual GitHub upload execution, early-no-output handling,
  or 14-day delivery.
- **Recommendation:** retain exact-head CI execution as the premerge evidence gate and archive its
  artifact/upload result.

## Verification performed

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`:
  exit 0, chunk `f94702`.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force`:
  session `75624`, terminal exit 0; 245/245 Tezt plus all displayed unit suites passed.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js authentic`:
  exit 0, chunk `d4b5a6`.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js failures`:
  session `89119`, terminal exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js package`:
  exit 0, chunk `254dde`.
- `rtk proxy git diff --check`: exit 0.
- `rtk proxy mktemp -d`: exit 0, created `/tmp/tmp.NBTjo66baF`.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer.js --out /tmp/tmp.NBTjo66baF/output`:
  exit 0 `held`.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer-artifacts.js /tmp/tmp.NBTjo66baF/output`:
  exit 0.

The temporary package was intentionally retained for root QA evidence; no corpus was downloaded.
