# Preflight — origin-recurring-consumer

**Date:** 2026-09-12
**Verdict:** READY
**Mode:** Full (new recurring-consumer design decisions; standard route, no formal backend selected).

Base main `d7112964df679fb44bc033e878059537208f58da`, carried PR99 post-ship record `5125768`.
Sole owned worktree; prior PR99 worktree/build removed without force. RTK instructions read;
no project AGENTS.md/CLAUDE.md or harness/hooks found. README read before questions.

`rtk proxy node scripts/review-bundle-verify.js`: exit 0, 22 SHA-matched files, bundle 1.6.0.
`rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`:
terminal exit 0. Same prefix with `dune exec --root . tezt/tests/main.exe -- --list-tsv`:
terminal exit 0, 240 tests collected, not executed. Dune is absent from bare PATH but present
at `/home/mathias/dev/arch-index/_opam/bin/dune` under the explicitly selected switch.
opam/node/sqlite3/git/gh present. No separately configured OCaml formatter/linter; existing
package metadata lint debt retained, not green. No environment install/change.

Claims authority absent. Neutral manifest closed keys, technical IDs and canonical questions
SHA-256 checked locally; this is not a claims-authority validation. Graph orientation resolver
reports `DEGRADED: no installed research-orientation packs`; ordinary blind research applies.
Existing temporary Tezt directory warnings retained because ownership is not established.
Disk snapshot: /home 29G available, external SSD 67G; reflects concurrent activity, not solely
our cleanup. Main post-merge CI 34709378209 still running; PR99 pre-merge CI already green.
