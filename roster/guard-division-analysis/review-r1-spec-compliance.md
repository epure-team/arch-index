---
auditor: spec-compliance-auditor
date: 2026-09-13
head: 2b8b7bf
status: 1 critical, 3 warnings
spec: specs/guard-division-analysis.md
---

# Independent spec-compliance review, round 1 cycle 1

Frozen contract: 47 FRs, 19 ACs, six CHECK interfaces. The full spec, intake, plan, reviewer/implementation briefs, complete new product code, checker, native fixture/probes, docs and relevant integration diff were read. Scope gate exit0 was supplied by root. No source/spec changes were made. Required report path is adapted to the frozen roster directory because no KB exists.

PASS means implementation matches and a relevant executable test exists; UNTESTED means an explicit part of the claim lacks test evidence, even when adjacent happy paths pass. DIVERGE means a concrete contract mismatch. Partial tests are named instead of inflating them into complete acceptance. FR totals: {"PASS":23,"UNTESTED":23,"DIVERGE":1}. AC rows retain their own compound coverage status; a narrow PASS does not override a broader missing acceptance scenario.

## Functional requirement matrix

| Claim | Status | Implementation | Test evidence | Assessment |
|---|---|---|---|---|
| FR-001 | PASS | lib/arch_guard/arch_guard.ml:34 | scripts/check-arch-guard.js:206 | Eight resolved primitive identities, partial and shadowed calls. |
| FR-002 | UNTESTED | lib/arch_guard/arch_guard.ml:45 | scripts/check-arch-guard.js:206 | No later-saturation fixture. |
| FR-003 | UNTESTED | lib/arch_guard/guard_interpreter.ml:90 | scripts/check-arch-guard.js:206 | No labels/over-application/combined eligibility defects. |
| FR-004 | UNTESTED | lib/arch_guard/arch_guard.ml:52 | scripts/check-arch-guard.js:222 | Absent slot tested; explicit None with later arguments not tested. |
| FR-005 | PASS | lib/arch_guard/arch_guard.ml:18 | scripts/check-arch-guard.js:206 | Identity exclusively Val_prim; shadow and indirect excluded. |
| FR-006 | UNTESTED | lib/arch_guard/guard_interpreter.ml:18 | scripts/check-arch-guard.js:179 | Resolved local alias covered; unresolved/non-native native-operation and guard cases absent. |
| FR-007 | UNTESTED | lib/arch_guard/arch_guard.ml:68 | scripts/check-arch-guard.js:225 | Canonical repeats tested; reversed distinct accepted paths not compared byte-for-byte. |
| FR-008 | PASS | lib/arch_guard/arch_guard.ml:160 | scripts/check-arch-guard.js:228; scripts/check-arch-guard.js:349 | Copies/hard links rejected as distinct conflicting candidates. |
| FR-009 | PASS | lib/arch_guard/arch_guard.ml:87 | tezt/fixtures/arch_guard/changed_read_probe.ml:13; scripts/check-arch-guard.js:338 | Actual digest/reader sequencing via private shared-reader seam; no filesystem race claim. |
| FR-010 | PASS | bin/arch_guard/arch_guard.ml:3 | scripts/check-arch-guard.js:200; scripts/check-arch-guard.js:321 | Atomic rejected-input and size failures assert exit2, stderr and empty stdout. |
| FR-011 | PASS | lib/arch_guard/arch_guard.ml:87 | scripts/check-arch-guard.js:352 | Linked Cmt_format.read exposes only magic mismatch as Cmi_format.Error; other corrupt/read failures use malformed/read branch. |
| FR-012 | PASS | lib/arch_guard/arch_guard.ml:191; lib/arch_guard/arch_guard.ml:215 | scripts/check-arch-guard.js:282 | Explicit empty outcome, inputs and zero census; exact text sentence. |
| FR-013 | PASS | lib/arch_guard/arch_guard.ml:49 | scripts/check-arch-guard.js:220 | Ordinal generated per artifact, directly asserted; docs/arch-guard.md:53 scopes stability. |
| FR-014 | UNTESTED | lib/arch_guard/arch_guard.ml:177 | scripts/check-arch-guard.js:267 | Comparator checked only on ordinary/single-site metadata fixtures; duplicate/null ordering not challenged. |
| FR-015 | PASS | lib/arch_guard/guard_interpreter.ml:99 | scripts/check-arch-guard.js:152 | Five statuses and mixed 0/2 join in authentic fixture. |
| FR-016 | UNTESTED | lib/arch_guard/guard_interpreter.ml:126 | scripts/check-arch-guard.js:161 | Single unsupported-under-false case; accumulated ancestry/eligibility combinations absent. |
| FR-017 | PASS | lib/arch_guard/guard_interpreter.ml:135 | scripts/check-arch-guard.js:152; tezt/fixtures/arch_guard/inventory.ml:1 | Literals, local aliases, zero and parameters asserted. |
| FR-018 | PASS | lib/arch_guard/guard_interpreter.ml:172 | scripts/check-arch-guard.js:156 | Both operand orders, equality identities, literal false, unrecognized ordering. |
| FR-019 | UNTESTED | lib/arch_guard/guard_interpreter.ml:86 | scripts/check-arch-guard.js:154 | Identity-based shadowing covered; explicit alpha-renaming acceptance case absent. |
| FR-020 | UNTESTED | lib/arch_guard/guard_interpreter.ml:140 | scripts/check-arch-guard.js:153 | Alias copy/shadow/and-group covered; alias-before/inside refinement absent. |
| FR-021 | PASS | lib/arch_guard/guard_interpreter.ml:147 | tezt/fixtures/arch_guard/inventory.ml:12; scripts/check-arch-guard.js:187 | 0/2 join and contradictory guard fixture statuses asserted. |
| FR-022 | PASS | lib/arch_guard/guard_domain.ml:19 | scripts/check-arch-guard.js:49 | Independent BigInt modular oracle, small-width represented sets and native extrema. |
| FR-023 | PASS | lib/arch_guard/guard_interpreter.ml:154 | scripts/check-arch-guard.js:187 | Literal-zero site tested without evaluation; div/mod result falls through Top. |
| FR-024 | PASS | lib/arch_guard/guard_domain.ml:7 | scripts/check-arch-guard.js:102 | Plan concretization; probe transfer tables, restriction, join and monotonicity laws. |
| FR-025 | UNTESTED | lib/arch_guard/guard_interpreter.ml:138 | scripts/check-arch-guard.js:162 | Fresh captures/dead outer branch tested; immediate/curried/full required entry combinations absent. |
| FR-026 | UNTESTED | lib/arch_guard/guard_interpreter.ml:128 | scripts/check-arch-guard.js:152 | Sticky unsupported across nested function resets not tested. |
| FR-027 | UNTESTED | lib/arch_guard/guard_interpreter.ml:50 | scripts/check-arch-guard.js:172 | Some exclusions tested; defaults with sites, multiple causes and unaffected later siblings absent. |
| FR-028 | UNTESTED | lib/arch_guard/guard_interpreter.ml:68 | tezt/fixtures/arch_guard/inventory.ml:3; scripts/check-arch-guard.js:173 | Loop body/recursive function tested; loop condition/bounds/all region positions absent. |
| FR-029 | UNTESTED | lib/arch_guard/guard_interpreter.ml:154 | scripts/check-arch-guard.js:164 | Ordinary call/result covered; complete unlisted/indirect nested-argument dispatch not covered. |
| FR-030 | UNTESTED | lib/arch_guard/guard_interpreter.ml:154 | scripts/check-arch-guard.js:206 | Normal arithmetic/partial inventory covered; malformed-known nested operands/method cases absent. |
| FR-031 | UNTESTED | lib/arch_guard/guard_interpreter.ml:99 | scripts/check-arch-guard.js:182 | Statuses and success checked, but exact corresponding conditional reason not asserted. |
| FR-032 | PASS | tezt/tests/must_null_ceiling.ml:299 | tezt/tests/must_null_ceiling.ml:309; .github/workflows/ci.yml:141 | No extraction/rule/reference diff; authorized source-only pin amendment. Independent gates recorded below. |
| FR-033 | UNTESTED | lib/arch_guard/arch_guard.ml:205 | scripts/check-arch-guard.js:304 | No full per-site artifact/id/status/primitive/reasons equality assertion. |
| FR-034 | UNTESTED | bin/arch_guard/arch_guard.ml:11 | scripts/check-arch-guard.js:341 | Required/bad args covered; help/version lack regression controls. |
| FR-035 | UNTESTED | arch-guard:4 | scripts/check-arch-guard.js:9 | Checker directly invokes binary; root wrapper is never tested. |
| FR-036 | DIVERGE | lib/arch_guard/arch_guard.ml:213 | scripts/check-arch-guard.js:304 | Default text omits compiler version and mandatory assumptions/heap/interprocedural limitations. |
| FR-037 | PASS | lib/arch_guard/arch_guard.ml:189 | scripts/check-arch-guard.js:233 | Closed top/tool/analysis keys and values asserted. |
| FR-038 | PASS | lib/arch_guard/arch_guard.ml:140 | scripts/check-arch-guard.js:251 | Closed input/site and nested key/type validation. |
| FR-039 | UNTESTED | lib/arch_guard/arch_guard.ml:23 | scripts/check-arch-guard.js:301 | ASCII overlong spelling tested, not inclusive 256-byte or multi-byte boundary. |
| FR-040 | PASS | lib/arch_guard/arch_guard.ml:114 | scripts/check-arch-guard.js:288 | Invalid, ghost, cross-file, backwards, maximal column tested. |
| FR-041 | UNTESTED | lib/arch_guard/guard_interpreter.ml:99; lib/arch_guard/arch_guard.ml:144 | scripts/check-arch-guard.js:263 | Vocabulary regex and sorted uniqueness checked on limited report sample; full reason classes/accumulation absent. |
| FR-042 | PASS | lib/arch_guard/arch_guard.ml:186 | scripts/check-arch-guard.js:143 | All census identities cross-count actual statuses. |
| FR-043 | UNTESTED | lib/arch_guard/arch_guard.ml:205 | scripts/check-arch-guard.js:304 | Shared result projection; test checks census and one status/location, not each site's semantics. |
| FR-044 | PASS | lib/arch_guard/arch_guard.ml:68; lib/arch_guard/arch_guard.ml:197 | scripts/check-arch-guard.js:315; scripts/check-arch-guard.js:335; scripts/check-arch-guard.js:389 | Input/traversal/JSON exact+one-over tested. Current text is a smaller semantic projection; no independent dominant text-bound fixture demanded. |
| FR-045 | UNTESTED | lib/arch_guard/arch_guard.ml:165 | scripts/check-arch-guard.js:389 | Preflight/order evident; default and unsupported expression counting not challenged independently. |
| FR-046 | PASS | scripts/check-arch-guard.js:15 | docs/arch-guard.md:67; scripts/check-arch-guard.js:15 | Trusted-input/no-OS-sandbox disclosure and enforced 120s/combined16MiB subprocess caps. |
| FR-047 | PASS | scripts/check-arch-guard.js:425 | scripts/check-arch-guard.js:425 | Explicit owned arch_index artifacts and real census only; execution recorded below. |

## Acceptance criterion matrix

| Claim | Status | FR trace | Evidence | Assessment |
|---|---|---|---|---|
| AC-1 | UNTESTED | FR-001/004/005/007/009 | scripts/check-arch-guard.js:206 | No reversed distinct-input byte equality. |
| AC-2 | PASS | FR-015/017/018/021/032 | scripts/check-arch-guard.js:152; tezt/tests/guard_division_analysis.ml:8 | Native statuses/domain and unchanged self gates (execution below). |
| AC-3 | DIVERGE | FR-033/034/035/037/038/043/047 | lib/arch_guard/arch_guard.ml:213 | Mandatory context absent from text; equality controls incomplete. |
| AC-4 | UNTESTED | FR-001/002/003 | scripts/check-arch-guard.js:206 | Later saturation and malformed application combinations missing. |
| AC-5 | UNTESTED | FR-005/006 | scripts/check-arch-guard.js:179 | Unresolved/non-native operand/guard type cases missing. |
| AC-6 | PASS | FR-007/008/009 | scripts/check-arch-guard.js:225; scripts/check-arch-guard.js:349 | Canonical repeats, copies and hard links. |
| AC-7 | PASS | FR-010/044/045/046 | scripts/check-arch-guard.js:315; scripts/check-arch-guard.js:335; scripts/check-arch-guard.js:389 | All reachable inclusive bounds and one-over; changed read is declared shared-reader seam. |
| AC-8 | DIVERGE | FR-012/036/047 | lib/arch_guard/arch_guard.ml:213; scripts/check-arch-guard.js:282 | Empty inventory honest; mandatory report context incomplete. |
| AC-9 | PASS | FR-022/023 | scripts/check-arch-guard.js:49 | Independent BigInt oracle and literal-zero report. |
| AC-10 | DIVERGE | FR-031/036 | lib/arch_guard/arch_guard.ml:213; scripts/check-arch-guard.js:182 | Text context missing; exact semantic reasons untested. |
| AC-11 | UNTESTED | FR-019/020 | scripts/check-arch-guard.js:152 | Alpha-renaming and before/inside guard aliases missing. |
| AC-12 | UNTESTED | FR-025/026 | scripts/check-arch-guard.js:162 | Required full fresh-entry/sticky-ancestry combinations absent. |
| AC-13 | UNTESTED | FR-016/027/041 | scripts/check-arch-guard.js:161 | Single cause under false covered; accumulated causes/sibling control absent. |
| AC-14 | UNTESTED | FR-029/030 | scripts/check-arch-guard.js:164 | Opaque cases covered; full closed dispatch table not challenged. |
| AC-15 | UNTESTED | FR-015/016 | scripts/check-arch-guard.js:152 | Five statuses covered but full exclusion/ancestry precedence combinations absent. |
| AC-16 | UNTESTED | FR-028 | tezt/fixtures/arch_guard/inventory.ml:3 | Loop body/recursion covered; other loop expression positions absent. |
| AC-17 | PASS | FR-022/024/042 | scripts/check-arch-guard.js:49; scripts/check-arch-guard.js:143 | Represented-set containment and join/restriction laws, census. |
| AC-18 | DIVERGE | FR-010/011/036 | lib/arch_guard/arch_guard.ml:213 | Mandatory text compiler/trusted-build context missing. |
| AC-19 | UNTESTED | FR-013/014/033/039/040/041 | scripts/check-arch-guard.js:280 | Some metadata tested; duplicates, UTF-8 boundary, all reasons and full text equivalence absent. |

## Runnable-check contract matrix

| Claim | Status | Implementation/test | Assessment |
|---|---|---|---|
| CHECK-1 | UNTESTED | scripts/check-arch-guard.js:206; tezt/tests/guard_division_analysis.ml:71 | Mode exists with authentic fixtures; required unusual shapes and distinct-input byte ordering remain untested. |
| CHECK-2 | UNTESTED | scripts/check-arch-guard.js:152; tezt/tests/guard_division_analysis.ml:71 | Authentic five-status checks exist; exact closed reasons and explicit scope/entry combinations omitted. |
| CHECK-3 | PASS | scripts/check-arch-guard.js:49; tezt/fixtures/arch_guard/domain_probe.ml:1 | Independent JS BigInt oracle checks actual OCaml probe transfers; no expected status supplied by probe. |
| CHECK-4 | PASS | scripts/check-arch-guard.js:335; tezt/fixtures/arch_guard/changed_read_probe.ml:21 | Real CLI input/traversal boundaries; changed-read seam candidly separate; reader diagnostic interpretation checked against the actual linked reader source. |
| CHECK-5 | UNTESTED | scripts/check-arch-guard.js:280; tezt/tests/guard_division_analysis.ml:71 | Exact schema/metadata/census/JSON bound checks; complete semantic text projection and required limitations not asserted. |
| CHECK-6 | PASS | scripts/check-arch-guard.js:425; tezt/tests/guard_division_analysis.ml:71 | Explicit owned arch_index CMT directory only; actual census returned, no expanded external corpus. |

All modes use the shared 120-second/combined16MiB process wrapper at scripts/check-arch-guard.js:15. Assertion/execution controls are registered independently in tezt/tests/guard_division_analysis.ml:81. The exact JSON output bound is exercised in JSON and text modes. The current text renderer is a smaller field projection; no unreachable independently dominant text-size case is demanded.

## Critical and warning findings

### C1: Text reports omit mandatory compiler and trusted-build assumptions

- Severity: CRITICAL; confidence 5/5.
- Contract: FR-036, FR-033, AC-3, AC-8, AC-10, AC-18.
- Location: lib/arch_guard/arch_guard.ml:213.
- Evidence: FR-036 requires every successful report to record linked compiler version, trusted same-compiler/target and no-source-freshness assumptions, and interprocedural/heap limitations. render_text prints only input count/int_bits, sites, census and a shorter global warning (lines 213-228); these required fields remain only in analysis_json/tool JSON. C-5 also requires an explicit indirect-operations/omitted-artifacts limitation in both formats; neither renderer includes it.
- Recommendation: Project compiler metadata and all required assumptions/limitations from the shared result into text; include the explicit C-5 exclusions in shared limitations and assert them in both renderers.

### W1: Immediate-application shape and operand-type obligations are only partially tested

- Severity: MEDIUM; confidence 5/5.
- Contract: FR-002, FR-003, FR-004, FR-006, FR-030, AC-4, AC-5, AC-14.
- Location: scripts/check-arch-guard.js:206.
- Evidence: Inventory tests cover a partial primitive with absent slot 2, native fixtures, aliases and shadow spelling. They do not exercise a later-saturated immediate application, explicit None second slot with further arguments, labelled/over-applied known primitives, accumulated eligibility defects, or unresolved/non-native operands of native primitives/zero guards. The fixture probe rewrites only annotation/location/spelling, not these shapes. These are explicit AC-4/AC-5 obligations, not inferred extra precision.
- Recommendation: Extend the private trusted fixture seam for inaccessible application/type shapes and invoke the actual CLI, asserting exact inventory, original slot, eligibility reasons and conservative guard behavior.

### W2: Scope, fresh-entry and accumulated unsupported-reason criteria lack required cases

- Severity: MEDIUM; confidence 5/5.
- Contract: FR-016, FR-019, FR-020, FR-025, FR-026, FR-027, FR-028, FR-029, FR-031, FR-041, AC-10, AC-11, AC-12, AC-13, AC-14, AC-15, AC-16.
- Location: scripts/check-arch-guard.js:152.
- Evidence: The 26 numeric cases and twelve-site fixture do not exercise alpha-renaming or aliases before/inside a refined guard; sticky unsupported ancestry through nested/curried/immediately applied functions; defaults containing target sites; multiple unsupported causes; later supported siblings; targets in loop conditions/bounds; or the full application dispatch categories. numeric() asserts statuses and census but never exact semantic/unsupported reason arrays. AC-11 through AC-16 explicitly require these cases.
- Recommendation: Add bounded owned native fixtures for binding-time alias values, function entry/reset and lexical ancestry, all loop expression positions, effect/method/unlisted dispatch, and assert exact closed reasons with precedence and unaffected siblings.

### W3: Report and boundary checks omit explicit acceptance obligations

- Severity: MEDIUM; confidence 5/5.
- Contract: FR-007, FR-013, FR-014, FR-033, FR-034, FR-035, FR-039, FR-040, FR-043, AC-1, AC-3, AC-19.
- Location: scripts/check-arch-guard.js:280.
- Evidence: reportMode checks census substrings and a single MAY_ZERO primitive/location, not every site's artifact/id/status/primitive/reasons against text. It lacks duplicate coordinates and 256-byte/257-byte UTF-8 spelling cases; inventory compares parsed objects for a repeat of one path, not reversed distinct accepted input bytes. Help/version and root wrapper behavior have no regression test. AC-1/AC-3/AC-7/AC-19 require these behaviors.
- Recommendation: Add byte-level reversed multi-input checks, full same-fixture semantic text/JSON comparisons, duplicate-coordinate and UTF-8 boundary fixtures, CLI/wrapper contract controls.

## Withdrawn diagnostic hypothesis

An initial hypothesis inferred that catching all Cmi_format.Error values conflated Corrupted_interface with version mismatch. Inspection of the actual linked OCaml 5.3 reader disproved reachability: _opam/.opam-switch/sources/ocaml-compiler.5.3.0/file_formats/cmt_format.ml:389 calls Cmi_format.input_cmi directly and raises only Not_an_interface on initial magic mismatch. Corrupted_interface belongs to the separate read_cmi wrapper, which this path does not call. Raw payload errors reach the existing malformed/read branch. This is withdrawn, not a finding; dynamic corroboration follows with the execution evidence.

## Unspecified public behavior

No separate unspecified product feature found. Public render_json/render_text and Guard_domain are the plan-selected separate library surface; domain serialization supports the private test probe and does not add a public CLI probe command. The extra output-boundary checker mode and environment-selected checker executables are test tooling, not a new user analysis feature. Stdlib-only CMT environment reconstruction is an engineering restriction documented in docs/arch-guard.md:41 and consistent with unresolved types remaining unsupported. Existing origin ship-gate bookkeeping is not a new product behavior.

## Independent execution evidence

All commands below ran in /home/mathias/dev/arch-index-worktrees/guard-division-analysis at HEAD 2b8b7bfa1ebdc4dae767916e48b6c4a845fc12ef, with shell prefix `rtk proxy`. Compiler-backed commands used `opam exec --switch=/home/mathias/dev/arch-index --`. Only one Dune invocation ran at a time; standalone native checkers used their isolated temporary directories.

| Command (after rtk proxy) | Exit | Fresh observed result |
|---|---:|---|
| opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . | 0 | Full repository build. |
| opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force | 0 | 255/255 Tezt and 64 Alcotest tests; deliberate assertion/execution diagnostics are expected controls. |
| git diff --check | 0 | No whitespace errors. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js inventory | 0 | 9 sites:2NONZERO,7UNSUPPORTED. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js numeric | 0 | 26 additional cases; twelve-site fixture:3NONZERO,1ZERO,2MAY_ZERO,1UNREACHABLE,5UNSUPPORTED. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js domain | 0 | 640734 actual probe responses;23219242 law assertions; exhaustive widths3–8, sampled31/63. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js inputs | 0 | Input128/129,file33554432/33554433,aggregate268435456 and one extra byte; nodes100000/100001,sites10000/10001,depth512/513; four annotation classes; declared changed-read seam. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js report | 0 | Six metadata cases; JSON16777216 bytes accepted,16777217 rejected; does not close identified contract gaps. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/check-arch-guard.js owned | 0 | 23 artifacts;total_sites0;numeric_covered0;nonzero0;zero0;may_zero0;unreachable0;unsupported0;precision_gain_sites0. |
| opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js authentic | 0 | Existing native origin controls pass. |
| opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js failures | 0 | Expected injected staging-cleanup/final-record diagnostics; controls pass. |
| opam exec --switch=/home/mathias/dev/arch-index -- node checks/origin-recurring-consumer.js package | 0 | Evidence-package controls pass. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer.js --out /tmp/arch-guard-spec-r1-pwfXav/origin-consumer | 0 | held. Fresh leaf under mktemp-owned parent. |
| opam exec --switch=/home/mathias/dev/arch-index -- node scripts/origin-consumer-artifacts.js /tmp/arch-guard-spec-r1-pwfXav/origin-consumer | 0 | Fresh retained package validates. |
| opam exec --switch=/home/mathias/dev/arch-index -- ./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe --build-dir=_build/default/lib/arch_index --db-path=/tmp/arch-guard-spec-r1-pwfXav/self.db --schema-path=architecture-schema.sql | 0 | 23modules,828functions,5223calls. |
| sqlite3 same fresh self.db with the three CI count queries, Node exact-byte comparison to test/fixtures/self-index-stats.txt | 0 | Golden bytes unchanged. Initial operator query used double quotes and failed1; corrected SQL string quoting passed, no DB/source change. |
| opam exec --switch=/home/mathias/dev/arch-index -- ./arch-rules /tmp/arch-guard-spec-r1-pwfXav/self.db arch-rules.txt --on-vacuous fail | 0 | 1proved,3UNKNOWN,0failing,0vacuous. No precision gain claimed. |
| opam exec --switch=/home/mathias/dev/arch-index -- ./arch-impact /tmp/arch-guard-spec-r1-pwfXav/self.db --diff 0a0fa361fa7d850b858bb54f9e671e9854cdc167..HEAD --repo . | 0 | Actual merge-base(main,HEAD) selected;0touched indexed functions,66changed files outside index UNKNOWN; effects/decision not computed. |
| opam exec --switch=/home/mathias/dev/arch-index -- env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy ./scripts/recalibrate.sh --check | 2 | Refused because review artifacts are uncommitted, before measurement. Root instructed stop here and schedule clean-tree rerun after committing review evidence. No pin/reference changes. |

The recalibration refusal is a genuine remaining execution gate, not a product DIVERGE or a measured pin mismatch. No clean recalibration, remote CI or merge GO is claimed by this report.

### Targeted report-context reproduction

Owned source /tmp/arch-guard-spec-r1-pwfXav/context_fixture.ml contains `let divisor d = 10 / d`. Compiled with `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- ocamlc -bin-annot -c context_fixture.ml` in that temporary directory: exit0. Invoked the actual root wrapper twice using `--cmt /tmp/arch-guard-spec-r1-pwfXav/context_fixture.cmt`, default text then `--format json`, through the same opam prefix: both exit0.

JSON records compiler_version5.3.0, int_bits63, trusted same-compiler/target, no-source-freshness and no-interprocedural/heap statements. Text contains int_bits63, one MAY_ZERO site with divisor_may_be_zero, all census counts and its short warning; compiler version and those assumptions/limitations are absent. This dynamically corroborates C1. Artifact digest127f5e1ffac751978e550aa63500d623dccee28f5f26fa0c36ecd80d365a2fbc is the CMT digest reported in JSON, not a source-freshness certificate.

### Targeted ordinary read-error corroboration

A local test file /tmp/arch-guard-spec-r1-pwfXav/corrupt_fixture.cmt contains the correct linked CMI magic `Caml1999I035` followed by an ordinary invalid payload. A bounded invocation of the actual root wrapper returns exit2 and exactly zero stdout bytes; stderr is `arch-guard: ...: malformed/read failure: Failure("input_value: bad object")`. A Node assertion of these three observations exits0. No broad malformed-artifact search or external target was performed. This agrees with the linked reader source and corroborates withdrawal of the initial diagnosis hypothesis.

Temporary owned parent /tmp/arch-guard-spec-r1-pwfXav retains the scalar fixture, ordinary corrupt test payload, fresh self.db and six-file origin package for root's later cleanup. This specialist removed nothing.
