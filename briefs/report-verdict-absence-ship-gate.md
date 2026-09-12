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

Status: ready to open PR; remote CI and merge pending.
