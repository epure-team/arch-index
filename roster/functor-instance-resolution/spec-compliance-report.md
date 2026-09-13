# Spec-compliance review — functor-instance-resolution

Reviewer: independent spec-compliance review (embedded mode). Scope reviewed:
`main...HEAD`, the full modified catalogue product and test files, the validated
specification, and the reviewer/implementation briefs. This is an audit of the
bounded syntactic catalogue only; it makes no target-resolution or precision claim.

## Verdict

**GO — no spec-compliance findings.** All checks named in the specification were
executed independently; their actual outcomes are recorded in
`spec-compliance-execution.md`. `PASS` below means implementation evidence plus a
named, executed test/check; it is not inferred from a green aggregate.

## Functional requirements

| Requirement | Status | Implementation evidence | Executed test evidence |
|---|---|---|---|
| FR-001 | PASS | `lib/arch_index/arch_index_functors.ml:56-123` | `check-functor-catalogue.js inventory`; `tezt/fixtures/functor_catalogue/typedtree_probe.ml:88-129` |
| FR-002 | PASS | `lib/arch_index/arch_index_functors.ml:118-123` | `check-functor-catalogue.js inventory` external/shadowed census |
| FR-003 | PASS | `lib/arch_index/arch_index_functors.ml:73-85,118-123` | `check-functor-catalogue.js inventory` |
| FR-004 | PASS | `lib/arch_index/arch_index_functors.ml:62-91` | `check-functor-catalogue.js inventory` |
| FR-005 | PASS | `lib/arch_index/arch_index_functors.ml:3`; `lib/arch_index/arch_index.ml:304-310` | `check-functor-catalogue.js lifecycle`; `tezt/fixtures/functor_catalogue/selection_probe.ml:5-14` |
| FR-006 | PASS | `lib/arch_index/arch_index_functors.ml:3`; `lib/arch_tools/arch_functor_catalogue.ml:168-244` | `check-functor-catalogue.js lifecycle`, `compatibility` |
| FR-007 | PASS | `lib/arch_index/arch_index_functors.ml:56-101` | `check-functor-catalogue.js inventory` |
| FR-008 | PASS | `lib/arch_index/arch_index_functors.ml:62-101`; `lib/arch_tools/arch_functor_catalogue.ml:16-39` | `check-functor-catalogue.js inventory`, `query` |
| FR-009 | PASS | `lib/arch_index/arch_index_functors.ml:18-32,92` | `check-functor-catalogue.js inventory` Papply premise |
| FR-010 | PASS | `lib/arch_index/arch_index_functors.ml:34-54`; `lib/arch_tools/arch_functor_catalogue.ml:61-80` | `check-functor-catalogue.js inventory`, `query` |
| FR-011 | PASS | `lib/arch_index/arch_index_functors.ml:34-54,102-115` | `check-functor-catalogue.js inventory` |
| FR-012 | PASS | `lib/arch_index/arch_index_functors.ml:102-115`; `lib/arch_tools/arch_functor_catalogue.ml:203-224` | `check-functor-catalogue.js inventory`, `query` |
| FR-013 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:1-2,245-249`; `docs/functor-catalogue.md:1-34` | `check-functor-catalogue.js inventory`, `query` |
| FR-014 | PASS | `lib/arch_index/arch_index_cmt.ml:2751-2854`; `lib/arch_index/arch_index.ml:619-685` | `check-functor-catalogue.js lifecycle` |
| FR-015 | PASS | `lib/arch_index/arch_index_functors.ml:132-153` | `check-functor-catalogue.js lifecycle`; `tezt/fixtures/functor_catalogue/storage_probe.ml:31-95` |
| FR-016 | PASS | `lib/arch_index/arch_index.ml:390-400`; `lib/arch_index/arch_index_support.ml:32-61` | `check-functor-catalogue.js lifecycle` |
| FR-017 | PASS | `lib/arch_index/arch_index.ml:691-696`; `lib/arch_index/arch_index_functors.ml:164-178` | `check-functor-catalogue.js lifecycle` |
| FR-018 | PASS | `architecture-schema.sql:61-88`; `lib/arch_tools/arch_functor_catalogue.ml:226-249` | `check-functor-catalogue.js lifecycle`, `compatibility` |
| FR-019 | PASS | `lib/arch_index/arch_index.ml:659-681`; `lib/arch_index/arch_index_cmt.ml:2847-2855` | `check-functor-catalogue.js compatibility` |
| FR-020 | PASS | `lib/arch_index/arch_index_support.ml:57-61`; `lib/arch_tools/arch_functor_catalogue.ml:189-249` | `check-functor-catalogue.js lifecycle`, `compatibility` |
| FR-021 | PASS | `bin/arch_query/arch_query.ml:140-156` | `check-functor-catalogue.js query` |
| FR-022 | PASS | `bin/arch_query/arch_query.ml:140-156,258-266` | `check-functor-catalogue.js query` |
| FR-023 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:117-152` | `check-functor-catalogue.js query` |
| FR-024 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:117-244` | `check-functor-catalogue.js query` |
| FR-025 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:232-249` | `check-functor-catalogue.js query` |
| FR-026 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:1-2,245-249` | `check-functor-catalogue.js query` |
| FR-027 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:226-229` | `check-functor-catalogue.js query` |
| FR-028 | PASS | `bin/arch_query/arch_query.ml:258-266`; `lib/arch_tools/arch_functor_catalogue.ml:245-249` | `check-functor-catalogue.js query` |
| FR-029 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:117-245` | `check-functor-catalogue.js query` |
| FR-030 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:96-117` | `check-functor-catalogue.js query`, `compatibility` |

## Acceptance criteria

| Criterion | Status | Implementation evidence | Executed test evidence |
|---|---|---|---|
| AC-1 | PASS | `lib/arch_index/arch_index_functors.ml:56-123` | `check-functor-catalogue.js inventory`, `compatibility` |
| AC-2 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:245-249` | `check-functor-catalogue.js query` |
| AC-3 | PASS | `lib/arch_index/arch_index_functors.ml:118-123` | `check-functor-catalogue.js inventory` |
| AC-4 | PASS | `lib/arch_index/arch_index_functors.ml:73-85,118-123` | `check-functor-catalogue.js inventory` |
| AC-5 | PASS | `lib/arch_index/arch_index_cmt.ml:2818-2846` | `check-functor-catalogue.js lifecycle` |
| AC-6 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:226-249` | `check-functor-catalogue.js lifecycle`, `compatibility` |
| AC-7 | PASS | `lib/arch_index/arch_index_cmt.ml:2751-2854`; `lib/arch_index/arch_index_functors.ml:132-153` | `check-functor-catalogue.js lifecycle` |
| AC-8 | PASS | `lib/arch_index/arch_index_functors.ml:102-115` | `check-functor-catalogue.js inventory` |
| AC-9 | PASS | `lib/arch_index/arch_index.ml:659-681` | `check-functor-catalogue.js compatibility` |
| AC-10 | PASS | `lib/arch_index/arch_index.ml:390-400,691-697` | `check-functor-catalogue.js lifecycle` |
| AC-11 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:117-244` | `check-functor-catalogue.js query` |
| AC-12 | PASS | `bin/arch_query/arch_query.ml:140-156`; `lib/arch_tools/arch_functor_catalogue.ml:117-140` | `check-functor-catalogue.js query` |
| AC-13 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:245-249` | `check-functor-catalogue.js query` |
| AC-14 | PASS | `lib/arch_index/arch_index_functors.ml:56-101` | `check-functor-catalogue.js inventory` |
| AC-15 | PASS | `lib/arch_index/arch_index_functors.ml:18-32,92` | `check-functor-catalogue.js inventory` |
| AC-16 | PASS | `lib/arch_tools/arch_functor_catalogue.ml:1-2,245-249`; `docs/functor-catalogue.md:1-34` | `check-functor-catalogue.js query` |

The potentially confusing local name `ghost` in the read validator is a type
check (`Some (\`Bool _)`), not a read of the Boolean value. Consequently valid
`ghost:false` locations are accepted; no divergence is present.
