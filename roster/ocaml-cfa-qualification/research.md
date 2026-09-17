# Research — Stage 5 OCaml CFA qualification

Research is read-only. It establishes the current contracts and gaps before
selecting a product slice.

## What is already delivered

The graph keeps three distinct edge classes. `MUST` is a definite invocation;
`MAY_ENUMERATED` is a bounded possible target set; `MAY_TOP` is an open target
frontier. The normative contract is `docs/edge-kind-contract.md` and the graph
representation (`lib/arch_tools/arch_graph.ml`) explicitly holds a resolved
forward closure over `MUST ∪ MAY_ENUMERATED` and separately retains TOP nodes.

`arch-query reaches` is deliberately MUST-only. `unreachable` is the sound dual
only on a TOP-marked index, and returns `REACHABLE`, `UNREACHABLE` or `UNKNOWN`.
`escapes` already exposes the reachable TOP frontier. `arch-rules` calls the
wider closure `POSSIBLE`, not definite. These are usable foundations; a second
CFA solver is neither needed nor in scope.

Stage 4 adds target-v2 witnesses for functor-derived `MAY_ENUMERATED` calls.
The existing durable records are artifact-local occurrences, candidates and
witnesses. They prove a bounded functor relation but do **not** tag every
`MAY_ENUMERATED` edge as "0-CFA". Any report must preserve that distinction.

## Current user-facing gaps

1. `arch-query` exposes `functor-applications` and `functor-bindings`, but not
   target-v2 candidates/witnesses or a capability/status summary. The evidence
   exists but cannot yet be inspected through the public CLI.
2. `docs/change-impact.md` says the `MUST ∪ MAY_ENUMERATED` closure is
   "DEFINITELY reach" / ground truth. This contradicts the edge contract and
   `arch_rule_eval`'s `POSSIBLE` verdict. It must become a MUST-only definite
   section plus a possible bounded section, with TOP scope separately named.
3. Existing fixed-410 checkers measure relation deltas and resource observations
   (`producer_wall_ms`, best-effort RSS) but they do not answer a stable set of
   operator questions. Aggregate edge gain alone is insufficient qualification.
4. Existing reports (`arch-report`, `origin-consumer`) already have JSON/HTML/
   SARIF concordance and deterministic artifact patterns. Qualification should
   reuse those pieces rather than introduce a parallel report format.

## Candidate useful-query benchmark

The smallest meaningful corpus suite should exercise both the delivered gain
and its limitation:

| Question | Existing primitive | Required qualified assertion |
|---|---|---|
| Can this known source definitely reach a target? | `arch-query reaches` | MUST-only answer and exact witness / no wider claim. |
| Can it possibly reach a bounded functor/CFA target? | graph closure / rules | MUST versus MAY path classification, with the candidate proof when it is target-v2. |
| Why is an answer still incomplete? | `arch-query escapes` | deterministic TOP reason/site/path; no empty result masquerading as a closed cone. |
| Did the pinned corpus retain prior resolved relations? | Stage 4 CHECK-3 comparison | semantic relation multiset, no loss/new MUST, separate Irmin/protocol slices. |
| What did this cost? | Stage 4 CHECK-3 measurement | wall clock and best-effort RSS labelled observation, with corpus/tool/source hashes. |

The first three questions can be made executable using a small authentic CMT
fixture plus a fixed set of named roots; the fourth/fifth remain the pinned 410
replay. A successful benchmark must refuse an old/flat/markerless database,
an absent root and a partial corpus rather than report an empty success.

## Boundaries proposed for the specification

- Do not add a generic benchmark CLI in this stage. A task-local checker can
  prove the contract; later stages 6–8 own durable user-facing query/report/
  recurring-run interfaces.
- Do correct public semantic wording and any existing report wording it proves
  inconsistent. This is a correctness/documentation requirement, not scope
  creep.
- Do not claim recall, whole-program completeness, a resource upper bound or
  a vulnerability finding from the benchmark.
- Preserve all target-v2 provenance and MAY_TOP residuals; measured improvement
  remains additive only.

## Sources inspected

- `bin/arch_query/arch_query.ml` (command contract and available subcommands)
- `lib/arch_tools/arch_graph.ml`, `lib/arch_tools/arch_rule_eval.ml`
- `docs/edge-kind-contract.md`, `docs/change-impact.md`
- `roster/ocaml-functor-targets/check-tezos.js` and
  `roster/ocaml-cfa-foundation/check-tezos.js`
- `architecture-schema.sql`, `specs/ocaml-functor-targets.md`
- `lib/arch_tools/arch_report.ml`, `scripts/origin-consumer.js`
