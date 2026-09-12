# Stories — origin-recurring-consumer

Derived only after the fresh eight-item clarification ledger was resolved.

### US-1: Review the production library's origin drift (Priority: P0)
As an arch-index maintainer, I want each required CI run to execute the existing origin policy
over the bounded built library and refuse silent coverage changes, so new visible fatal-origin
sites and degraded measurements cannot pass unnoticed.
**Why this priority:** establishes the missing real recurring consumer, using already shipped tools.
**Scope:** no value inference, third-party corpus, automatic exemptions, new evaluator or completeness proof.
**Independent Test:** invoke the local runner with the reviewed reference on owned built library;
inspect exit, gate JSON and coverage status without requiring a CI artifact download or HTML review.
**Acceptance Scenarios:**
1. **Given** reference d711296, 23 module paths, counters 23/828/5223 and 491 raw origins,
   the one reviewed assertion allowance and the trusted local build, **When** the maintainer runs
   the dedicated consumer, **Then** exit0, policy held with UNKNOWN remains explicitly unproved,
   and no observed coverage drift is asserted.
2. **Given** an owned native CMT control with an additional escaping division absent from its
   allow-list, **When** the same consumer evaluation path runs, **Then** exit1 and policy-failed
   identify that division; changing reference counts cannot exempt it.
3. **Given** an owned native fixture with two division occurrences at the same counted identity
   but x1 allowed, **When** evaluated, **Then** exit1 and the increased count is observable.
4. **Given** a valid built subject whose module inventory matches but one observed raw count
   differs, **When** evaluated without a policy violation, **Then** coverage-drift/exit1,
   actual/reference/delta retained; no automatic reference update or code-regression attribution.
5. **Given** a missing/extra module, empty origin pass, wrong contract, unavailable tool or
   invalid result JSON, **When** the consumer runs, **Then** it never exits0 and distinguishes
   measured drift from execution/incomplete-analysis error. Existing CI gates remain unchanged.
6. **Given** a developer needs to review a legitimate scope or allowance change, **When**
   following the documented procedure, **Then** reference metadata and any allowance must be
   deliberately edited/reviewed separately; there is no --regenerate/autoaccept path.

### US-2: Inspect a complete and attributable review package (Priority: P1)
As a code reviewer, I want a locally reproducible compact report package with its exact input
identities and uncertainty, so I can understand the origin gate without re-reading the whole
codebase or assuming a successful report means a successful policy.
**Why this priority:** makes the recurring consumer useful and auditable in actual review.
**Scope:** no stable structured parsing of evaluator prose, no source freshness certificate,
  no database/build uploads, no fabricated reviewer-time savings.
**Independent Test:** run the shared runner on an owned native fixture outside production CI
  and without the production reference deployment; validate publication, report consistency
  and failure artifacts. Shared execution infrastructure does not require US-1's CI rollout.
**Acceptance Scenarios:**
1. **Given** a fresh output destination and valid observed policy outcome, **When** the runner
   finishes, **Then** gate.json, report.json, report.sarif, report.html and run.json are present
   and mutually consistent; diagnostics are retained, and the final record distinguishes
   policy outcome, coverage comparability and measurement completeness.
2. **Given** a genuine division policy failure, **When** the runner completes analysis,
   **Then** nonzero policy exit does not suppress the complete reviewer package; its rule
   details/contexts match actual evaluator output and no PASS is fabricated.
3. **Given** an existing output directory or symlink, **When** requested as --out,
   **Then** exit2 before overwrite; previous bytes remain unchanged.
4. **Given** a report subprocess failure or a write failure, **When** publication stops,
   **Then** exit2, no complete-success marker, partial report set excluded from publication;
   useful diagnostics/run error record survive when writable. A record write failure is
   itself failure, never silently accepted.
5. **Given** the same production paths under a different compiler/build path or changed source
   revision, **When** evidence is generated, **Then** it records actual inventories/digests and
   revision/dirty state, labels trusted-build assumptions, and never promotes hash equality or
   unchanged counts into a complete/freshness proof.
6. **Given** CI starts the consumer and receives held, policy-failed, coverage-drift or error,
   **When** retention runs, **Then** known compact report/diagnostic artifacts survive for 14 days;
   no transient DB/build tree is uploaded, no failed gate is converted to success, and absent
   expected artifacts are not silently represented as an upload success.

Authentic-control obligation applies to both stories: direct standalone checks must distinguish
check assertion1 from execution>=2, use actual built OCaml fixtures/CLIs for success/new/count
cases, and test wrong/empty/incomplete inputs separately. No real corpus is downloaded.
