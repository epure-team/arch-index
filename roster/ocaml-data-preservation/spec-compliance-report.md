---
auditor: spec-compliance-auditor
date: 2026-09-15
head: 126a0086d1a7016139ac26fa466d676ad889e292
status: 1 critical, 3 warnings, 1 info
coverage: 18/24 FR/AC claims PASS (75%); 3 DIVERGE; 3 UNTESTED
---

# Spec compliance — OCaml data preservation

## Gate evidence

| Gate | Exit | Evidence |
|---|---:|---|
| `opam exec -- dune build` | 0 | `improvement/2026-09-15-ocaml-cfa/spec-compliance-build.{log,json}` |
| `opam exec -- dune runtest --force` | 0 | 344/344; `spec-compliance-runtest.{log,json}` |
| CHECK-1 effects | 0 | `spec-compliance-check1.{log,json}` |
| CHECK-2 CMT copies | 0 | `spec-compliance-check2.{log,json}` |
| CHECK-3 pinned 410 | 0 | 45,052 rows; digest `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`; Irmin 4,849 / protocol 12,171; 360 emitted, 139 distinct stored, 63 bound; `spec-compliance-check3.{log,json}` |
| Review bundle | 0 | 22 files SHA-matched, bundle 1.6.0; `spec-compliance-bundle.{log,json}` |
| `git diff --check` | 0 | `spec-compliance-diff-check.{log,json}` |

These green gates do not cover the independently reproduced nullable-path homonym below.

## Compliance matrix

| Claim | Status | Implementation | Test/evidence | Notes |
|---|---|---|---|---|
| FR-001 | DIVERGE | `lib/arch_effects/effects_db.ml:68-80` | CHECK-1 | A supplied exact path aborts if an unrelated same-name candidate has NULL `file_path`, instead of ignoring that nonmatch and selecting the exact non-NULL row. |
| FR-002 | PASS | `effects_db.ml:75-85,94-116` | unit effects + CHECK-1 | NULL retention, unique pathless association, ambiguity clearing, flat schema and diagnostics covered. |
| FR-003 | UNTESTED | `lib/arch_effects/ocaml_effects_extractor.ml:92-118` | partial CHECK-1 | Relative and contained-absolute paths are covered; no runnable assertion found for missing metadata, absolute outside-root metadata, or literal underscores. |
| FR-004 | PASS | `ocaml_effects_extractor.ml:163-239` | unit effects + CHECK-1/2 | Typedtree list order, top-level boundary and nonidentical-CMT refusal are implemented. |
| FR-005 | PASS | `effects_db.ml:101-113`; migration index | unit effects + CHECK-1 | Complete payload distinguishes soundness and NULL/empty while exact reload is idempotent. |
| FR-006 | PASS | `effects_db.ml:27-34,87-116`; migration SQL | CHECK-1 | Existing IDs/payloads survive repair; incompatible duplicates refuse transactionally. |
| FR-007 | PASS | `effects_db.ml:101-114` | unit effects + CHECK-1 | Association repairs retain row ID and count as written; unchanged reload counts duplicate. |
| FR-008 | UNTESTED | `effects_db.ml:3-14,94-116`; `effects_load.ml` | partial unit effects + CHECK-1 | Preparation, step/trigger, repair, malformed-input and input-I/O failures are covered; no bind- or commit-failure injection was found. Code checks both paths explicitly. |
| FR-009 | PASS | `lib/arch_index/arch_index_cmt.ml:3102-3156,3174-3219,4075-4081` | inline tests + CHECK-2 | Run-local source/unit key, full bytes, stable representative and failed extraction controls covered. |
| FR-010 | PASS | `arch_index.ml:623-668`; `arch_index_cmt.ml:3106-3129` | CHECK-2 | Fresh run state and exact selected path spellings, including symlink, are preserved. |
| FR-011 | PASS | `arch_index_cmt.ml:3205-3214`; `arch_index.ml:668-684` | CHECK-2 | Catalogue and binding collection run separately for every selected artifact. |
| FR-012 | PASS | `arch_index_cmt.ml:3174,3217-3219,4075-4081`; per-artifact callbacks | CHECK-2 | Matches frozen C11 criterion: extraction returns without new statement failures; callback failures independently withhold their markers. |
| AC-1 | DIVERGE | `effects_db.ml:68-80` | CHECK-1 misses nullable candidate | Exact-path homonym association fails for a valid nullable alternative-schema row. Other producer/NULL behavior passes. |
| AC-2 | PASS | `effects_db.ml:101-113` | unit effects + CHECK-1 | Duplicate and complete-payload distinctions pass. |
| AC-3 | PASS | CMT reuse and callbacks above | CHECK-2 | Exact copies yield one graph and separate nonempty artifact provenance. |
| AC-4 | DIVERGE | `effects_db.ml:68-80` | independent reproduction | Alternative schema uses the prescribed field, but a NULL field on an unrelated homonym aborts rather than remaining a nonmatch. |
| AC-5 | PASS | `effects_db.ml:75-85,101-110` | unit effects + CHECK-1 | Newly ambiguous pathless reload clears the obsolete ID and diagnoses ambiguity. |
| AC-6 | UNTESTED | `ocaml_effects_extractor.ml:219-239` | partial unit effects + CHECK-1 | Ordinary repeated top-level bindings prove `f#1`/`f`; no equal-location typedtree fixture was found. |
| AC-7 | PASS | byte gate and insertion refusal | CHECK-2 | Independently compiled same-source CMT remains rejected/dropped. |
| AC-8 | PASS | transactional migration/write | CHECK-1 | Duplicate legacy rows and injected write/repair failures retain prior data. |
| AC-9 | PASS | effects loader/writer | CHECK-1 | Batch SQL, malformed input, input I/O, allow-skip and no-success-summary behavior covered. |
| AC-10 | PASS | per-run cache construction | CHECK-2 | Reindex/fresh run does not retain stale reuse state. |
| AC-11 | PASS | exact artifact payload callbacks | CHECK-2 | Copy/symlink spellings remain distinct; only graph extraction is shared. |
| AC-12 | PASS | failure latch/outcomes/markers | CHECK-2 | Failed representative and either per-artifact callback failure do not borrow completion markers. |

## Critical

### C1 — Nullable alternative-schema homonym prevents exact-path association

- **Spec claims:** FR-001, AC-1, AC-4.
- **Actual behavior:** with functions `(1,'f',NULL)` and `(2,'f','a.ml')`, loading effect `f/a.ml` exits nonzero with `non-text function path`; it must associate ID 2. A nullable stored source is valid data, not malformed schema.
- **Location:** `lib/arch_effects/effects_db.ml:68-80`.
- **Evidence:** `ids_at_normalized_path` converts every candidate path to TEXT before testing equality, so the unrelated NULL row aborts traversal. Existing CHECK-1 has no nullable-path homonym and passes.
- **Recommendation:** treat a NULL candidate path as a nonmatch while retaining exact normalized path matching for non-NULL candidates; add the reproduced regression.

## Warnings

### W1 — Producer path distinctions are only partially tested

FR-003 code matches the contract on inspection, but missing `cmt_sourcefile`, absolute outside-root metadata, and literal underscores lack runnable assertions. Add focused producer fixtures without expanding relocation semantics.

### W2 — SQL error-path coverage omits bind and commit failures

FR-008 explicitly checks preparation/bind/step/commit errors in code, while tests exercise preparation/index refusal, step/trigger, repair and input failures. Bind and commit behavior remains UNTESTED.

### W3 — Equal-location shadow ordering is untested

AC-6 requires declaration order even for equal locations. The implementation iterates Typedtree lists, but current fixtures use ordinary distinct source locations.

## Info

### I1 — FR-012 wording is broader than its frozen C11 resolution

FR-012 says “successfully stored representative graph,” while the intake, C11 and the `ExactCmtGraphReuse` entity define eligibility as graph extraction returning without new statement failures. Deferred call/dependency/type-usage persistence occurs later. The current implementation matches the explicit C11 boundary; catalogue and binding markers remain independent per-artifact contracts and are not graph-completeness markers. This is an ambiguity to clarify in a future human-approved spec amendment, not a present divergence.

## Unspecified implementation scan

No unauthorized public API or user-facing behavior was found in the scoped diff. The CMT reuse type is abstract/private to the ingestion API, independently compiled variants remain stage 4, and issue #68 remains partial. Approved source-only golden changes are limited to ceiling 554 and references 1013/6425/583 with the assertion allowlist unchanged.

## Final corrected-source addendum — HEAD `10d75e2`

The matrix and Critical section above preserve the review's pre-fix observation at HEAD `126a008`. The same-round correction at `10d75e2` adds non-NULL candidate filtering to both main- and alternative-schema supplied-path queries. The expanded CHECK-1 proves that a NULL-path homonym cannot hide an exact match and cannot authorize name-only fallback after that match disappears. FR-001, AC-1 and AC-4 therefore move from **DIVERGE** to **PASS (resolved in round 1)**. No specification relaxation was used.

Final personal validation on `10d75e2`:

| Gate | Exit | Final evidence |
|---|---:|---|
| `opam exec -- dune build` | 0 | `improvement/2026-09-15-ocaml-cfa/spec-compliance-final-build.{log,json}` |
| `opam exec -- dune runtest --force` | 0 | 344/344; `spec-compliance-final-runtest.{log,json}` |
| CHECK-1 | 0 | Includes main/alternative nullable-path exact-match and no-fallback regression; `spec-compliance-final-check1.{log,json}` |
| CHECK-2 | 0 | `spec-compliance-final-check2.{log,json}` |
| CHECK-3 | 0 | 45,052 rows; digest `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`; 4,849/12,171 relations; 360 emitted, 139 stored, 63 bound; `spec-compliance-final-check3.{log,json}` |
| Review bundle | 0 | 22 files SHA-matched, bundle 1.6.0; `spec-compliance-final-bundle.{log,json}` |
| `git diff --check` | 0 | `spec-compliance-final-diff-check.{log,json}` |

**Current status:** 0 critical, 3 warnings, 1 info. **Current claim coverage:** 21/24 FR/AC claims PASS (87.5%); 0 DIVERGE; 3 UNTESTED. The prior CRITICAL remains in the historical report and findings ledger as `RESOLVED`; W1–W3 remain `OPEN`.
