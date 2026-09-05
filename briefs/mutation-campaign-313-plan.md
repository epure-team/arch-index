# Plan — mutation-campaign-313

**Date:** 2026-09-05T14:20:00+02:00
**Status: DRAFT**
**Base:** `879fedb`. Re-verified after rebase in `/mnt/ssd-external-2to/arch-index-mutation-313`:
build clean, **188/188** tezt cases, 0 failures. Was 165 on `2ac80eb`; the SARIF-out merge added 23.

## Consensus Table

Voice 1 was a Claude architect sub-agent. Voice 2 was intended to be Codex, a genuinely different
model; it was killed twice by its time limit without producing output, so Voice 2 is the
documented fallback, a second adversarial Claude sub-agent. A Codex attempt is still running in the
background and will be folded in as a third voice if it returns. **This substitution is recorded
rather than glossed: the dual-voice guarantee here is weaker than "two models".**

| Point | Voice 1 | Voice 2 | Status |
|---|---|---|---|
| The suggested ordering is horizontal at step 1 (schema with no writer) | ✅ defect | ✅ implied | AGREE — reordered |
| Profiles cannot be the last slice: `granularity` is load-bearing inside CHECK-1/CHECK-2 | ✅ | ✅ (obj 7) | AGREE — a minimal granularity ships in slice 1 |
| The pilot is the only reality check and is scheduled last | — | ✅ (obj 7) | AGREE — slice 1 ends with a measured pilot run, not a stub-only demo |
| mutaml cannot scope tests per mutant → premise may be unimplementable | ⚠️ assumption | ✅ **"most likely to sink the schedule"** | **REFUTED by evidence** — see Decisions |
| `discover_profile` hardcodes `-errors.toml`; not suffix-parametrized | ✅ (`arch_index.ml:105`) | ✅ (obj 12) | AGREE — slice 5 owns it, and does not generalise the shared function |
| Diff→functions logic is binary-local in `arch_impact.ml`, not a library | ✅ (`:72`) | ✅ (obj 2) | AGREE — resolved by shelling out, not extracting |
| `mutant_kills` key is not actually pinned anywhere | — | ✅ (obj 5) | AGREE — pinned in Decisions |
| No CHECK owns US-4 (diff scoping) | ✅ | — | AGREE — CHECK-16 added |
| CHECK-9 has no supply path to an Octez-scale mutant population | — | ✅ (obj 8) | AGREE — the probe must state its population size and refuse to imply a pass |
| `~allow` for `run --tests` undecided | — | ✅ (obj 9) | AGREE — decided |
| alcotest `group` granularity may make the cost story backfire | — | ✅ (obj 3) | AGREE — measured in slice 1, never assumed |
| Schema-version constant is a live race | ✅ | ✅ (obj 4) | AGREE — already handled by FR-009; base moved twice during this session alone |
| Quint invariants will keep coming back vacuous | — | ✅ (obj 10) | AGREE — that is what CHECK-13 is for, and it has already caught one |

No USER-CHALLENGE arose: neither voice proposed changing the brief's goal, only its ordering and
its unstated details.

## Sequential steps

**Slice 0 is deliberately absent.** An earlier draft of this plan opened with a feasibility spike
against a real mutaml, because Voice 2 rated that risk highest. Reading the engine's source
removed the need: the mechanism is established, so a spike would only re-establish it. What
remains is a runtime confirmation, which is CHECK-8 inside slice 1.

1. **Slice 1 — drive and persist one campaign, and measure the pilot.** Schema DDL for the four
   tables lands *in the same commit as the driver that writes them* — no DDL without a writer.
   Includes engine resolution and the exit-2 abort, per-mutant invocation through the
   `MUTAML_MUTANT` wrapper, intended and executed sets both recorded, a minimal granularity
   concept sufficient for a `group` profile, singleton-only attribution, append-only re-run
   semantics, resolved binary paths, and self-uncertification.
   **Exit criterion is a measured pilot run on `~/dev/miaou`, not a stub demo**, reporting wall
   clock for the naive path and for the selected path, with corpus, commit, build state and the
   count of mutants the engine could actually build. If selection is not cheaper, that is a
   finding to report, not a failure to hide.
   Lands FR-001..FR-010, FR-012, FR-027..FR-030. AC-1..AC-6, AC-19, AC-21..AC-24.
   CHECK-1, CHECK-2, CHECK-3, CHECK-8, CHECK-9, CHECK-14, CHECK-15.

2. **Slice 2 — the published verdict is sound.** The derivation from engine status plus selection
   provenance, PENDING from the absence of a row, and the grep-style guard that no emitter writes a
   status without its provenance. Reuses the predicate already at `arch_mutants.ml:122` rather than
   recomputing it. Adds a second grep-style guard that no output path emits a ratio.
   Lands FR-011, FR-013, FR-014, FR-015. AC-7..AC-11. CHECK-4, CHECK-5, CHECK-7.

3. **Slice 3 — diff-scoped selection.** `--diff <range>`, the union of touched functions and of
   what a modified or added test reaches, plus the deleted-test rule.
   Lands FR-016..FR-018. AC-12, AC-13. CHECK-16 (new).

4. **Slice 4 — the per-added-test defect verdict.** The three-bucket split, and the non-bare-zero
   report. Lands FR-019..FR-022. AC-14..AC-16. CHECK-6.

5. **Slice 5 — test-invocation profiles.** A loader for `<name>-tests.toml` with its own
   discovery, the alcotest adapter, granularity validation, the additive-only dynamic reach source,
   and `not_analysed` without touching `analysis_coverage`.
   Lands FR-023..FR-026. AC-17, AC-18. CHECK-10.

**Standing gates, owned by no slice, run from day one:** CHECK-11, CHECK-12, CHECK-13 (Quint,
already green and red-verified), and CHECK-15 (binary provenance, already implemented and
red-verified on both branches).

## Dependencies

Slice 2 needs slice 1's rows to derive anything. Slice 3 needs slice 1's `mutant_kills` for the
deleted-test rule and slice 2's provenance rules, which it inherits unchanged. Slice 4 needs
slice 2's verdict to distinguish a defect from an unproven test, and slice 3 to know which tests
are "added" at all. Slice 5 generalises the granularity concept slice 1 introduces, so it must
follow it — but slice 1 cannot wait for it, which is why slice 1 carries a minimal in-memory
profile rather than a file loader.

## Identified risks

| Risk | Probability | Impact | Mitigation |
|---|---|---|---|
| alcotest `group` granularity makes selection cost more than the naive path on the pilot | Medium | High — it would invert the brief's headline value | Measured as slice 1's exit criterion, with numbers, before four slices are built on the assumption |
| `mutant_kills` rows written early in this branch do not match the final shape | Medium | Medium | The key is pinned in Decisions before slice 1 writes a row; a shape change after that is a migration, not a silent drift |
| CHECK-9 can only run on a small population until an engine runs at Octez scale | High | Medium | The probe prints its population size and states that a small population does not satisfy AC-19 — it never implies a pass it did not earn |
| The base moves again mid-slice | High — it moved twice today | Low | Rebase and re-verify; both rebases so far were clean and the test count moved 163 → 165 → 188 |
| Three sessions active; shared files outside the three frozen ones | Medium | Medium | Slice 3 shells out instead of extracting; slice 5 writes its own loader instead of generalising `discover_profile` |
| Quint invariants come back vacuous as new ones are added | High | Low | CHECK-13 is the standing answer and has already caught one |
| PR #78 changes `find_upwards` under the campaign | Medium | Low | My guard covers the environment-variable path that #78 does not; the two overlap without conflicting |

## Decisions made

| Point | Decision | Reason |
|---|---|---|
| mutaml per-mutant test scoping | **Achievable with no change to mutaml.** The driver passes a wrapper as the single test command; the wrapper reads `MUTAML_MUTANT` and resolves that mutant to its reaching tests | Established by reading `src/runner/runner.ml:123-130` and `src/ppx/mutaml_ppx.ml:40`, not by trusting a README. This refutes the objection rated most likely to sink the schedule |
| `mutant_kills` key | `UNIQUE(campaign_id, mutant_id, test_name)`. "Attributed to that test alone" means: in the latest campaign for that mutant, exactly one kill row exists and its `test_name` is the deleted test | Voice 2 correctly found this was never pinned. Without it the deleted-test rule silently answers a different question |
| `~allow` for `run --tests` | The same structural kinds `plan` accepts — `file:`, `fn:`, `module:` — and `ext:` refused exactly as `plan` refuses it | Declaring explicitly is mandatory since `Arch_sel.parse` takes `~allow`; inheriting a default by omission is how `Dep` was silently reinterpreting its arguments |
| Diff→functions mapping for slice 3 | **Shell out to `arch-impact --format json`**, do not extract the logic into a library | The mapping is binary-local at `arch_impact.ml:72`. Extracting it is shared-library surgery while three sessions are active. The cost is one process boundary; the alternative risks a collision on code this campaign does not own |
| Profile discovery for slice 5 | A separate loader for `<name>-tests.toml`, not a generalisation of `discover_profile` | `arch_index.ml:105` hardcodes both the suffix and its environment variable, and a live precedence test is tied to the errors-channel feature another session may still be working on |
| Slice 1's exit criterion | A measured pilot run, not a stub demo | Voice 2's objection 7: four slices could go green on fixtures before the only reality check runs |

## Assumptions

- `~/dev/miaou` can be read for the pilot measurement. It is on a working branch with four modified
  files, so the pilot takes a worktree rather than that checkout.
- The wrapper mechanism works at runtime as the source says it does. CHECK-8 confirms it; until it
  runs against a real mutaml, the integration is unverified and reported as such.
- `arch-impact --format json` is stable enough to parse. Not verified; slice 3 confirms it before
  depending on it.
