# Ship gate — report-verdict-absence

Mode: Fast. Branch: `fix/report-verdict-absence`. Target: `main`.

Issue #84: unavailable rule-verdict totals must not look like measured zeroes.
JSON keeps the eight numeric keys for compatibility and adds NOT_COMPUTED/reason
metadata; HTML displays unavailable totals; SARIF carries report-wide metadata.
No verdict evaluation or persistence is added. Findings remain independently usable.

Implementation: `c82ab916d776b4b508c97e83cbc38a182bcb6b4b`.
Review GO: `4ddad7c31816b273f0b73aa20fc8868866870243`.
QA GO: `b29e1d5dc2a241ebeac2bd75f828e322bc55896c`.
Root independently reran the review static and QA convergence gates: both exit 0.
Build, full 227-test suite, 5 report CLI tests, self-index golden and architecture
gate passed locally and in the independent Sol/OpenCode QA. Architecture outcomes
remain 1 proved and 3 UNKNOWN warnings, not four proofs. Existing package metadata
lint debt is documented and is not a CI gate.

Authorization: Mathias explicitly approved autonomous PR creation, fixing CI and
merging each green roster-reviewed/QA'd slice before the next. No repeated human
push/merge quiz is required under that instruction; no quality gate is waived.

Remote main was fetched and remains `5ee982e89afc94d03f7b80c580163109887040ea`.
Required remote check: `build`, with strict up-to-date branch protection.
Publish only this task's branch; merge by rebase only after exact-head CI success.

Status: MERGED. PR https://github.com/epure-team/arch-index/pull/97 merged by rebase
at 2026-09-12T13:51:15Z as `9309107d293ed0530892d2f810daf0401b56a79a`.
Issue #84 is closed. The exact PR head checked was
`244a5be9c9e187332596656c35e53763f553ed6e`; merge state was CLEAN.

CI run `34696889124`, attempt 2: required build succeeded (12m31s), including
full tests, self-index smoke, recalibration, architecture rules and impact briefing.
Attempt 1 failed in opam repository initialization before compilation, matching
upstream https://github.com/ocaml/opam/issues/7031. Rerunning the failed job passed
without changing code, checks or sandbox configuration. MCP and tag-only release
jobs were skipped by their existing conditions.

Post-merge bookkeeping is retained as a local commit before the worktree is
removed/reused; the next roadmap slice can carry this record onto main.
No KB or harness counter exists here. Cost snapshot omitted: the first ledger
entry has only a date, not the full timestamp required by the bounded join helper.
Friction schema validation uses the available compiled checker in
`/home/mathias/dev/agent-roster/dist/scripts/check-friction-shape.js`.
