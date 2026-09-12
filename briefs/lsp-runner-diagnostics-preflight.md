# Preflight — lsp-runner-diagnostics

Mode: Fast. Issue: https://github.com/epure-team/arch-index/issues/23.
Verdict: READY.

Scope: make the four existing runner failure/partial-result diagnostics unconditional
on stderr. Keep progress narration behind verbose. Preserve exit-code, partial-data
and database-writing behavior; structured run outcomes are not introduced here.

Base: main at `9309107d293ed0530892d2f810daf0401b56a79a` (PR #97 merged).
The documentation-only prior shipment record is carried in commit `acd68e8`.
Worktree: `/home/mathias/dev/arch-index-worktrees/lsp-runner-diagnostics`.
Only this task has an active worktree created by this run; the report worktree/build
was removed after its evidence was preserved. Main's six pre-existing untracked
entries are untouched.

Deterministic routing checks: no trust-boundary or critical keyword hit; no adjacent
formal spec or crypto import; no prior task ledger. No project hooks, KB, claims
reconciler or code-intel gate pack is installed. OCaml specialist definition is read
from `/home/mathias/dev/agent-roster/agents/specialist/ocaml-dune-specialist.md`.

- Review bundle: 22 files sha-matched, version 1.6.0; manifest tracked.
- Build: `opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`, exit 0.
- Collection: `opam exec --switch=/home/mathias/dev/arch-index -- dune exec --root . tezt/tests/main.exe -- --list`, exit 0.
- Toolchain: opam, Node, SQLite and Python present; project switch supplies Dune and
  ocamllsp (ocamllsp is not on the unactivated shell PATH); gopls is installed.
- Format: no configured ocamlformat; use existing style and `git diff --check`.
- Supplemental opam metadata lint debt remains documented from #84; do not call it
  green or silently change package metadata as part of this issue.
- Collection warned about nine historical `/tmp/tezt-*` entries; no blanket removal.

Implementation must run its full baseline before edits, then demonstrate actual-CLI
RED/GREEN coverage for quiet-mode failure diagnostics and preserved verbose progress.
All Dune commands must use the explicit project switch AND `--root .`; never run Dune
commands concurrently. Retain useful audit logs while cleaning regenerable builds/DBs.
