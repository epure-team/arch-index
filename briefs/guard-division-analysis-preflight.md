# Preflight — guard-division-analysis

**Status:** READY

Base0a0fa36 (postship docs over merged main77c7691). Sole owned active delivery worktree.
Tool presence verified under explicit opam switch /home/mathias/dev/arch-index: dune,
ocamlc,node,sqlite3,go,ocamllsp. Bundle22files SHA match,1.6.0,exit0.
`opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . @install`: session9204exit0.
Initial direct Tezt --list failed127 because @install does not build test executable.
`opam exec --switch=/home/mathias/dev/arch-index -- dune build --root . tezt/tests/main.exe`:
session34005terminal0; subsequent direct executable --list exit0, non-executing collection.
All commands prefixed rtk proxy. Collection output truncated in UI; no exact collection count
claimed from truncated output. Preexisting /tmp/tezt warnings noted, those unrelated paths untouched.
No separate configured formatter/full linter. No code-intel packs, no claims authority/hooks/KB.
No source changes or global installations. Full suite remains required in implementation/QA.
