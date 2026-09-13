# R2 independent spec-compliance report

Date: 2026-09-13
Specialist: spec-compliance
Spec: `specs/guard-division-analysis.md`
Reviewed tip: `c586a931903992392bda5026b5a1f694b922a4c2`
Verdict: PASS — 47/47 FR, 19/19 AC, 6/6 CHECK and the pending context regression pass. No DIVERGE, MISSING, UNTESTED, or unspecified public feature.

The supported boundary is CLI-only: `bin/arch_guard/dune:1-4` installs `arch_guard`; `lib/arch_guard/dune:1-3` has no `public_name`; `docs/arch-guard.md:13-17` describes the implementation library as private. This resolves the R1 architectural observation without promising in-process compiler-global restoration.

## Functional-requirement matrix

| Claim | Status | Implementation evidence | Test evidence |
|---|---|---|---|
| FR-001 | PASS | `lib/arch_guard/arch_guard.ml:11-23,35-60` inventories immediate primitive heads | `scripts/check-arch-guard.js:210-279` inventory mode |
| FR-002 | PASS | `lib/arch_guard/arch_guard.ml:43-55` counts only primitive-headed expression | `scripts/check-arch-guard.js:241-243` later saturation |
| FR-003 | PASS | `lib/arch_guard/guard_interpreter.ml:83-92` accumulates eligibility reasons | `scripts/check-arch-guard.js:241-252` malformed shapes/combined ancestry |
| FR-004 | PASS | `lib/arch_guard/arch_guard.ml:50-52` reads original argument index 1 | `scripts/check-arch-guard.js:241-250,266-278` slot controls |
| FR-005 | PASS | `lib/arch_guard/arch_guard.ml:17-23` requires `Val_prim` | `scripts/check-arch-guard.js:210-225`; `tezt/fixtures/arch_guard/inventory.ml:1-15` |
| FR-006 | PASS | `lib/arch_guard/guard_interpreter.ml:20-31,89-91,166-181` compiler-expanded native-int checks | `scripts/check-arch-guard.js:173-185,253-257` unresolved/non-native operands and guards |
| FR-007 | PASS | `lib/arch_guard/arch_guard.ml:69-86` rejects symlinks, realpaths, sorts/dedups | `scripts/check-arch-guard.js:225-233,367-376` |
| FR-008 | PASS | `lib/arch_guard/arch_guard.ml:159-162` rejects duplicate module/source identity | `scripts/check-arch-guard.js:226-227,375-376` copy/hardlink |
| FR-009 | PASS | `lib/arch_guard/guard_input.ml:3-7`; `arch_guard.ml:61-67,89-101` before/after SHA-256 | `scripts/check-arch-guard.js:362-366` changed-read seam |
| FR-010 | PASS | `bin/arch_guard/arch_guard.ml:3-10,19-21` buffers result then exit 2 on error | `scripts/check-arch-guard.js:202-208,344-406` atomic rejection controls |
| FR-011 | PASS | `lib/arch_guard/arch_guard.ml:88-109` reader/annotation cases | `scripts/check-arch-guard.js:367-394` four annotation classes and malformed/incompatible inputs |
| FR-012 | PASS | `lib/arch_guard/arch_guard.ml:190,224` empty outcome/exact sentence | `scripts/check-arch-guard.js:285-289`; context regression |
| FR-013 | PASS | `lib/arch_guard/arch_guard.ml:38-49,137-144` per-artifact ordinal/path/digest | `scripts/check-arch-guard.js:210-224,263-265` |
| FR-014 | PASS | `lib/arch_guard/arch_guard.ml:174-185` frozen sort with null-first option order | `scripts/check-arch-guard.js:263-265,320-331` duplicate/invalid/ghost ranges |
| FR-015 | PASS | `lib/arch_guard/guard_interpreter.ml:94-103` exact precedence | `scripts/check-arch-guard.js:161-198` exact numeric matrices |
| FR-016 | PASS | `lib/arch_guard/guard_interpreter.ml:95-103,113-119` reasons precede reachability | `scripts/check-arch-guard.js:186-195,250-252` unsupported ancestry/effects |
| FR-017 | PASS | `lib/arch_guard/guard_interpreter.ml:121-139` constants and binding-time aliases | `checker_numeric_cases.js:1-44`; `r1_cases.ml:1-19` |
| FR-018 | PASS | `lib/arch_guard/guard_interpreter.ml:165-183` four equality primitives/both orders/bools | `checker_numeric_cases.js:1-44`; guard type mutations `check-arch-guard.js:173-185` |
| FR-019 | PASS | `lib/arch_guard/guard_interpreter.ml:78-81,122-124` `Ident.same`, unknown Top | `r1_cases.ml:21-56`; exact 36-site oracle `check-arch-guard.js:173-188` |
| FR-020 | PASS | `lib/arch_guard/guard_interpreter.ml:128-135` simultaneous RHS pre-env/value-copy/shadow | `r1_cases.ml:1-30`; exact oracle `checker_numeric_cases.js` |
| FR-021 | PASS | `lib/arch_guard/guard_interpreter.ml:138-146` branch restrictions and join | numeric mode exit 0, 26 base + 36 R1 sites |
| FR-022 | PASS | `lib/arch_guard/guard_domain.ml:17-45` conservative bounded arithmetic | domain mode: 640734 responses/23219242 independent oracle assertions |
| FR-023 | PASS | `lib/arch_guard/guard_interpreter.ml:157-164` div/mod return Top and never execute divisor | domain/numeric modes exit 0 |
| FR-024 | PASS | `lib/arch_guard/guard_domain.ml:1-45` distinct Bottom/Top, join/restrict/contains | domain widths 3-8 exhaustive and 31/63 sampled |
| FR-025 | PASS | `lib/arch_guard/guard_interpreter.ml:125-127` every supported function evaluates `[] true []` | `r1_cases.ml:32-65`; numeric exact 36-site oracle |
| FR-026 | PASS | `lib/arch_guard/guard_interpreter.ml:113-119,125-127` inherited exclusion uses iterator while supported entry resets | `r1_cases.ml:67-76`; combined ancestry cases |
| FR-027 | PASS | `lib/arch_guard/guard_interpreter.ml:38-76` closed excluded constructor list | `r1_cases.ml:58-93`; effect seams `check-arch-guard.js:189-196` |
| FR-028 | PASS | `lib/arch_guard/guard_interpreter.ml:62-76,113-119` loops are lexical exclusions; no iterative engine | `r1_cases.ml:78-93`; numeric exact reasons |
| FR-029 | PASS | `lib/arch_guard/guard_interpreter.ml:147-164` visits head and each arg in same env; unknown returns Top | `r1_cases.ml:95-104`; numeric exact oracle |
| FR-030 | PASS | `lib/arch_guard/guard_interpreter.ml:147-164` all args visited before target emission/closed transfer | inventory malformed shapes; method/effect cases `r1_cases.ml:105-115` |
| FR-031 | PASS | `lib/arch_guard/guard_interpreter.ml:94-103`; CLI exit independent of status | status-aware oracle `checker_report_oracle.js:27-39`; report negative controls |
| FR-032 | PASS | component isolated under `lib/arch_guard`/`bin/arch_guard` | forced full suite 256/256 Tezt + 64 Alcotest; self golden 23/828/5223; rules unchanged |
| FR-033 | PASS | `lib/arch_guard/arch_guard.ml:207-241` text projects one JSON result and JSON-quotes paths | report mode all-five-status oracle; newline/space/delimiter paths `check-arch-guard.js:290-315` |
| FR-034 | PASS | `bin/arch_guard/arch_guard.ml:3-21` Cmdliner CLI | `scripts/check-arch-guard.js:462-465`; input bad-arg controls |
| FR-035 | PASS | `arch-guard:1-9` only execs existing binary | `scripts/check-arch-guard.js:466-472` isolated missing-binary test |
| FR-036 | PASS | `lib/arch_guard/arch_guard.ml:150-155,213-223` shared compiler/context/limitations | `scripts/check-guard-report-context.js:20-88` actual empty/classified JSON+text |
| FR-037 | PASS | `lib/arch_guard/arch_guard.ml:150-155,187-190` exact tool/analysis/top shape | `checker_report_oracle.js:13-25`; report mode |
| FR-038 | PASS | `lib/arch_guard/arch_guard.ml:137-148,187-194` closed input/site shapes | `checker_report_oracle.js:13-47`; report mode |
| FR-039 | PASS | `lib/arch_guard/arch_guard.ml:25-33,134-135` complete <=256-byte spelling or omission | `scripts/check-arch-guard.js:258-262,266-278` 256/257 UTF-8 controls |
| FR-040 | PASS | `lib/arch_guard/arch_guard.ml:111-136` validated coordinates/ranges/ghost | `scripts/check-arch-guard.js:320-331` invalid/ghost/cross/backwards/max-column |
| FR-041 | PASS | `lib/arch_guard/arch_guard.ml:146-148`; interpreter reasons are fixed constructor names | `checker_report_oracle.js:27-39`; numeric/report negative controls |
| FR-042 | PASS | `lib/arch_guard/arch_guard.ml:185-194` census equations | oracle census checks and every checker report |
| FR-043 | PASS | `lib/arch_guard/arch_guard.ml:207-241` shared-result text projection, quoted paths | `checker_report_oracle.js:49-56`; actual newline-path report mode |
| FR-044 | PASS | `lib/arch_guard/arch_guard.ml:74-86,40-46,196-204` exact inclusive bounds | inputs/report: 128/129,32MiB/+1,256MiB/+1,100000/+1,10000/+1,512/513,16MiB/+1 |
| FR-045 | PASS | `lib/arch_guard/arch_guard.ml:35-60,163-168` complete preflight before interpretation | inputs traversal exact/one-over mode exit 0 |
| FR-046 | PASS | docs `docs/arch-guard.md:18-20,74-101`; checker child wrapper caps | all six modes and context checker exit 0 |
| FR-047 | PASS | owned mode targets only `_build/default/lib/arch_index/.arch_index.objs/byte` | owned: 23 artifacts, 0 sites/statuses, no corpus expansion |

## Acceptance-criterion matrix

| Claim | Status | Evidence |
|---|---|---|
| AC-1 | PASS | CHECK-1 exit 0; eight identities, slot metadata, partial/shadow/reversal at `scripts/check-arch-guard.js:210-279` |
| AC-2 | PASS | CHECK-2/3 exit 0; exact base/R1 matrices; full suite and self golden unchanged |
| AC-3 | PASS | CHECK-5/6 and context regression exit 0; private library/public CLI installation asserted |
| AC-4 | PASS | CHECK-1 seam cases later saturation/labels/overapplication/missing/ancestry exact reasons |
| AC-5 | PASS | CHECK-1/2 primitive identity and unresolved/non-native type mutations |
| AC-6 | PASS | CHECK-1/4 canonical repeat, reversal, copy/hardlink collision |
| AC-7 | PASS | CHECK-4/5 exact and one-over boundary matrix, atomic failures |
| AC-8 | PASS | CHECK-5/6/context empty-inventory exact scope and zero census |
| AC-9 | PASS | CHECK-3 independent BigInt oracle, widths 3-8 and 31/63 |
| AC-10 | PASS | CHECK-2/5/context exact conditional reasons and global limitations |
| AC-11 | PASS | CHECK-2 R1 aliases/alpha/shadow/simultaneous exact matrix |
| AC-12 | PASS | CHECK-2 R1 nested/curried/immediate/structure entry and sticky ancestry matrix |
| AC-13 | PASS | CHECK-2/5 multiple exclusions, modeled bottom precedence, later sibling |
| AC-14 | PASS | CHECK-1/2 ordinary/unlisted/indirect/malformed/short-circuit/method/four effect seams |
| AC-15 | PASS | CHECK-2 status precedence matrix and status-aware oracle |
| AC-16 | PASS | CHECK-2 recursive/while condition/bounds/body exclusions; no iterative analysis |
| AC-17 | PASS | CHECK-3 domain laws/containment plus CHECK-5 census equations |
| AC-18 | PASS | CHECK-4 annotation/read/compatibility atomicity; context assumptions |
| AC-19 | PASS | CHECK-1/5 invalid/ghost/range/UTF-8/reasons/duplicate-coordinate/text projection cases |

## Runnable-check matrix

| Check | Status | Fresh result |
|---|---|---|
| CHECK-1 inventory | PASS | exit 0; base 9 sites and 12 seam cases |
| CHECK-2 numeric | PASS | exit 0; 26 cases; R1 36 sites (19 covered/17 unsupported); four effect primitives |
| CHECK-3 domain | PASS | exit 0; 640734 probe responses, 23219242 oracle/law assertions |
| CHECK-4 inputs | PASS | exit 0; all input/traversal exact and one-over bounds |
| CHECK-5 report | PASS | exit 0; six metadata cases; 16777216 accepted/16777217 rejected |
| CHECK-6 owned | PASS | exit 0; 23 owned artifacts, zero sites; CLI public/library private |
| Pending context regression | PASS | `node scripts/check-guard-report-context.js`: empty/classified actual CLI JSON/text PASS |

## Independent execution record

All commands ran under `rtk proxy`; compiler-backed commands used `opam exec --switch=/home/mathias/dev/arch-index --`. Build exit 0. Forced suite exit 0: 256/256 Tezt and 64 Alcotest. `git diff --check`, bundle preflight, and exact manifest scope gate exit 0. Three origin modes (`authentic`, `failures`, `package`) exit 0; failure-mode diagnostics were expected controls. Fresh self DB `/tmp/guard-r2-spec-self-AMmd4w/self.db`: 23 modules, 828 functions, 5223 calls; exact-byte golden comparison and `arch-rules --on-vacuous fail` exit 0 (1 proved, 3 UNKNOWN, 0 failing/vacuous). `arch-impact --diff origin/main..HEAD` exit 0: 0 touched indexed functions and 102 outside-index files UNKNOWN; effects/decision not computed. Fresh origin package `/tmp/guard-r2-spec-self-AMmd4w/origin` and validator both exit 0.

Pristine `DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check` exit 0 at exact tip: golden A/B/C/D = 23/828/5223; ceiling A=B=396, C=D=437; pin 430 is within unchanged headroom 25 and source-attributed. No reference, pin, extractor, code, spec, ledger, or KB files were edited. Final repository status is clean at the reviewed tip.

The known opam-lint missing metadata and absent odoc remain pre-existing non-gating debt. No third-party or Tezos scan, vulnerability claim, formal proof, or production precision-gain claim was made.
