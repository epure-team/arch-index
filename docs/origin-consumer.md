# Recurring origin checks on arch-index itself

The repository runs the existing `forbid origin` evaluator over its own built OCaml library.
This is a regression check for escaping assertion and integer division/remainder origins,
with an explicit reviewed allowance. It is not a new analyzer or a proof that the library
cannot fail. The original four reachability rules in `arch-rules.txt` remain separate.

## Run locally

From the repository root, with the project's opam switch selected and its dependencies,
Node, Git and `sqlite3` available:

```sh
opam exec -- dune build --root . @install
origin_review_parent="$(mktemp -d)"
node scripts/origin-consumer.js --out "$origin_review_parent/report"
node scripts/origin-consumer-artifacts.js "$origin_review_parent/report"
```

Keep the consumer's exit status: the second command checks artifact integrity, not whether
the policy held. A valid package describing a violation can pass artifact validation.
In a shell using `set -e`, capture the consumer's failure explicitly if you want to inspect
the package afterward; do not turn that captured status into a successful policy check.

The runner accepts only `--out`. It indexes the fixed `_build/default/lib/arch_index` input
afresh, using the built indexer, `arch-rules` and `arch-report`. It does not accept a supplied
database, build the project, download a corpus, regenerate exemptions, or mutate sources.
Rebuild after editing source; a fresh database does not establish that its CMT inputs are fresh.

The output leaf must not exist, even as a dangling symlink. Its parent must already exist;
parent symlinks are resolved to a physical directory. Use a dedicated local/CI parent without
concurrent writers. Existing outputs are never overwritten. The runner removes its temporary
database and report staging; retain or remove your report directory deliberately after review.

## Interpret the outcome

| Consumer status | Exit | Meaning |
|---|---:|---|
| `held` | 0 | Valid contracted policy held and the observed population matches the reviewed reference. |
| `policy-failed` | 1 | Existing evaluator reported a policy failure; the complete evidence remains available. |
| `coverage-drift` | 1 | Policy did not fail, but module inventory or raw reference counters changed. Review the drift. |
| `error` | 2 | Input, analysis, contract, execution or publication was unusable/incomplete. Never read as clean. |

An execution/validation error takes precedence over policy failure; policy failure takes
precedence over coverage drift. The run record keeps independently validated policy and
coverage evidence so a higher-priority outcome does not hide a measured lower-priority one.

`UNKNOWN` is eligible for a held policy, just as in the existing evaluator policy. It still
means that an escaping/unknown part prevents proof. `NO_SOURCE`, `NO_TARGET`, `NOT_COMPUTED`
and `UNKNOWN_NO_CONTRACT` are not successful `UNKNOWN`: this consumer rejects them. An empty
origin pass, missing rule, malformed result or inconsistent process exit cannot hold the gate.

## What is pinned

The versioned inputs live in [`test/fixtures/origin-consumer`](../test/fixtures/origin-consumer/):

- `self.rules`: one rule, `self escaping assertion and division origins`, selecting
  `file:lib/arch_index/**`, forms `assert,division`, channel `exception`.
- `self.allow`: one explicitly reviewed counted assertion identity, not a generated baseline.
- `reference.json`: revision, module paths, raw totals and grouped origin observations.

Initial reference: `d7112964df679fb44bc033e878059537208f58da`, with 23 modules, 828 functions,
5,223 calls and 491 raw origin rows across all channels. There is one escaping assertion
and no division origin in this production reference. Native test fixtures separately demonstrate
that a new division and a same-site count increase are detected; zero production divisions
alone would not demonstrate that.

The sole initial allowance is:

```text
collect_calls_from_expr.<fun:1374:21>.<fun:1385:36> | lib/arch_index/arch_index_cmt.ml:1388 | assert | Assert_failure | x1
```

The source review rationale is local: `split_last` is called with a nonempty segment list;
its recursive multi-item branch reaches a singleton before the empty-list assertion branch.
This is a reviewed justification for exactly one occurrence, not a machine-checked invariant,
value-analysis result, or reason to exempt other assertions.

The reference is an observation, not the code being scanned: each invocation analyzes the
current checkout's built library. Raw origin groups are keyed by channel, form and escapes.
Comparison uses the union of current/reference keys, with absent counts treated as zero.
Redistributing rows between groups is drift even when the total remains unchanged. Missing or
extra source/indexed modules also block; an unusable or empty measurement is an error instead.

Exact counters are deliberately conservative: normal source evolution may require a reviewed
reference update. Unchanged counters do not prove that no population was lost or substituted.
The existing self-index golden and attributed recalibration checks remain independent.

## Read the review package

Completed `held`, `policy-failed` and `coverage-drift` runs contain six files:

| File | Use |
|---|---|
| `run.json` | Consumer status, separate policy/coverage information, actual input provenance and report digests. |
| `gate.json` | Existing `arch-rules` results and gate census; the policy evidence. |
| `report.json` | Structured existing report, including evaluated rule details and operand contexts. |
| `report.sarif` | Existing reporter's SARIF findings and rule census, unchanged. |
| `report.html` | Self-contained human-readable report. |
| `diagnostics.txt` | Execution diagnostics; may be empty on success. |

Start with `run.json` and the policy's verdict, then use HTML or JSON to inspect the relevant
sites. Shared gate/report/SARIF evidence is checked before publication. The final completion
record is written last and records digests of the final gate/report files. The separate
artifact validator detects required-file absence, inconsistent completion and changed bytes.
It is an integrity check under trusted local execution, not a signature or adversarial attestation.

On error after output creation, `run.json` and diagnostics are retained when writable, with
an optional valid gate result but no partial report trio. If output or the final record cannot
be written, stderr and exit 2 are the evidence; there may be no readable run record. A filesystem
failure can also prevent cleanup and is reported, not hidden behind a successful completion.
There is no guarantee of atomic publication against concurrent readers or hostile writers.

## Provenance and limits

The run records actual source and CMT-family inventories/digests, revision and dirty state,
tool/schema/config/rule/allow/reference identities and observed database metadata. Interfaces
and `.cmti` inputs matter too. Generated Dune CMTs are recorded without pretending there is
exactly one compiled file per source module. Scoped changes during execution are refused;
unrelated working-tree dirtiness is recorded but does not itself fail the check.

This assumes a trusted local build. CMT bytes may vary across compilers or build paths; the
record does not certify source-to-CMT correspondence. Whole-tree Git state and context fields
can disclose local paths or source-derived text: review locally generated packages before sharing.

Raw corpus counters and the evaluator's exact coverage note are separate evidence. The note
is not parsed into a new structured coverage API. Neither a held gate nor stable counts prove
completeness. This is a full bounded scan, not a Git-differential finding baseline. SARIF does
not fabricate consumer `baselineState` or successful invocation status: consult `run.json`.

## Review a deliberate change

1. Rebuild and inspect the actual outcome and directional coverage deltas. First rule out a
   wrong/stale build, configuration drift or an incomplete measurement.
2. For legitimate population evolution, edit `reference.json` explicitly, recording the new
   reference revision, module inventory and observed totals/groups with a review rationale.
3. Review any newly uncovered origin separately. Prefer fixing the source; if an allowance
   is justified, edit its exact identity/count and document why. Moving a source line or changing
   its function identity can require this review even when the source behavior is unchanged.
4. Keep reference and allowance changes separately visible with separate rationales; they may
   share a PR. Updating counters never changes what the evaluator exempts. There is no automatic
   acceptance command or mechanical proof of reviewer intent.
5. Run all three standalone checks and the full suite before review:

```sh
opam exec -- node checks/origin-recurring-consumer.js authentic
opam exec -- node checks/origin-recurring-consumer.js failures
opam exec -- node checks/origin-recurring-consumer.js package
opam exec -- dune test --root . --force
```

Checker exit 0 means the expected behavior was verified, including expected consumer failures.
Checker exit 1 means an assertion failed; exit 2 or higher means execution/setup failed.
The standalone checker needs the configured compiler/Dune on PATH; `opam exec` supplies the
selected switch's tools. Pass your switch explicitly to opam when working outside its directory.
The native controls compile their own owned fixtures and run the real consumer path. Fault
injection controls are separate; they are not evidence of production adoption or value analysis.

## CI retention

The existing required build job runs the production consumer and separately validates its
package. Retention attempts run after the consumer has run, including after a policy failure
or artifact validation failure. The upload contains only the six known report/diagnostic
filenames, retained for 14 days; databases, build trees and staging directories are excluded.
Missing required evidence fails independently, and successful upload never erases the consumer's
failure. If the consumer never starts because an earlier step failed, there is no consumer
package to claim. Job cancellation or runner loss can prevent artifact delivery.
