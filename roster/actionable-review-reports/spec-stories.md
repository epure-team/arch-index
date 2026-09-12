# Story input for independent specification challenge

Provisional story material, not a validated spec. Sources: validated intake, fresh Terra
spec-research, eight-item Sol clarification (zero OPEN, zero questions to the user).

## Clarifications

| Q | A |
|---|---|
| Report failure or rule-gate failure? | Successfully written reports exit 0 for every rule verdict; arch-rules retains its policy-driven exits. |
| No rules vs invalid rules? | No option retains NOT_COMPUTED placeholders; empty/malformed/unreadable file rejects with exit 2 before writes. |
| Which ordering? | Artifact alert order is VIOLATION, POSSIBLE, uncertainty, vacuity, then declaration ordinal within each tier; not viewer-order/confidence promises. |
| Shared evaluation? | One extracted parser/evaluator, invoked once using the same read-only DB handle; exit policy stays at CLI boundary. |
| Origin identity and caps? | Existing site identity/count/allow matching and 200-site cap unchanged; contexts are separate supporting data with explicit omitted totals. |
| Syntax or value? | CMT typed-AST slot 2, literal kind/identifier/other/missing; no source reread, folding, range or nonzero inference. |
| Which producers? | Native division/remainder exception origins only; older/flat indexes and unsupported forms/channels explicitly unavailable. |
| Entity naming? | RuleReportEntry and DivisorOperandContext; no redefinition of raise-set verdict. |

## User Stories

### US-1: Follow evaluated architecture rules in one report (Priority: P0)

As a repository maintainer, I want a unified report with the same evaluated rules and witnesses
as arch-rules, so I can inspect violations and uncertainty without manually combining outputs.
**Why this priority:** the existing witness computation is shipped but absent from report artifacts.
**Scope:** does not change reachability semantics, rule gate policy, imported-finding rigor,
concurrent DB-writer support or source freshness guarantees.
**Independent Test:** run real arch-report and arch-rules CLIs against a bounded fixture DB/rules
and compare verdicts/evidence plus three report renderings, without operand producer changes.
**Acceptance Scenarios:**
1. **Given** a quiescent fixture index with MUST path entry → middle → sink and one forbidden
   reach rule, **When** the maintainer runs `arch-report fixture.db --out report --rules rules.txt`,
   **Then** exit is 0, the VIOLATION census is 1, and JSON/HTML/SARIF retain the same ordered
   three-step witness as arch-rules; the report is not a policy gate.
2. **Given** that same DB, **When** the option is omitted, **Then** all eight compatibility counts
   remain explicitly NOT_COMPUTED placeholders; **When** an empty, malformed or unreadable rules
   file is supplied, **Then** exit 2 and a diagnostic occur before writes, not no-rules success.
3. **Given** rules deliberately declared vacuous, UNKNOWN, VIOLATION, POSSIBLE and PASS in that
   order, with a second UNKNOWN after the first, **When** reports are rendered, **Then** alert
   entries use the documented tier order, both UNKNOWN entries retain declaration order, PASS
   is counted but not an alert, and all individual rule results remain inspectable in JSON.
4. **Given** one escaping MAY_TOP witness and a separate no-contract index, **When** corresponding
   reports are produced, **Then** UNKNOWN versus UNKNOWN_NO_CONTRACT and their explanations
   remain distinct, and no frontier witness is presented as a path to the target.
5. **Given** an evaluated origin/effect rule whose source table is absent, **When** the report
   completes, **Then** census availability is COMPUTED but that rule remains NOT_COMPUTED;
   native coverage and imported producer metadata do not become proofs by association.
6. **Given** rule names and detail strings containing HTML metacharacters and duplicate rule
   display names, **When** rendered, **Then** output is escaped, entries remain individually
   identifiable by declaration ordinal, and repeated runs produce the same artifact order.

### US-2: Inspect divisor syntax without changing the origin gate (Priority: P1)

As a maintainer reviewing `forbid origin`, I want bounded divisor context beside a reported
division/remainder site, so I can read the relevant operand while retaining the current gate.
**Why this priority:** this removes source-navigation work and provides data for the separately
planned value-analysis experiment without pretending that experiment already exists.
**Scope:** integer primitive division/remainder exception origins only; not arrays, general
expressions, value channels, semantic symbol identities or value analysis.
**Independent Test:** compile a tiny owned OCaml fixture, index it, inspect origin metadata and
run the existing arch-rules CLI; this story is useful without the optional unified report path.
**Acceptance Scenarios:**
1. **Given** typed fixture bodies `x / 0`, `x / 2`, `x / y`, `x / (y + 1)` and typed int32/int64/
   nativeint remainders, **When** indexed, **Then** second-slot syntax categories, primitive and
   integer kinds are recorded without evaluating expressions; every preexisting division origin
   and its escape state remains, including the nonzero literal case.
2. **Given** two division sites on one source line with different divisors and an allow count of
   one for their aggregate identity, **When** arch-rules runs, **Then** it still reports the same
   increased-count offender; operand context remains supporting data, not a new identity/exemption.
3. **Given** an old index with no operand metadata, a missing second argument slot, and an
   unsupported origin form/value channel, **When** queried/reported, **Then** metadata absence,
   missing operand and unsupported context are explicit; no later present argument is substituted.
4. **Given** a fixture whose source file was changed or removed after CMT generation, **When**
   the existing CMT is indexed, **Then** operand context still comes from that typed AST; it is
   not represented as exact text from the current source tree.
5. **Given** more origin contexts than the displayed evidence budget and an oversized identifier,
   **When** results are rendered, **Then** representation and context lists are bounded, omitted
   counts/reasons are visible, existing aggregate counts remain exact, and HTML is escaped.
6. **Given** a unified report of a division-origin rule after US-1 is available, **When** generated,
   **Then** the same structured operand context and unavailability states reach all three
   artifacts without changing the rule verdict or suppressing an origin.

## Proposed runnable check boundary (for challenge)

Use a self-contained `node checks/actionable-review-reports.js <case>` over authentic built
CLIs and bounded self-created fixture indexes, with cases `rules`, `ordering`, `operands`,
`compatibility`. Explicit 0 pass / 1 assertion / >=2 fixture-build/spawn/parse/environment error.
Wire it through Tezt's normal suite, reusing available binary-path conventions. Missing tools
cannot pass or be misreported as a failed feature assertion. No new test runtime dependency.
Do not copy the legacy wrapper that maps every nonzero Tezt exit into assertion failure.
