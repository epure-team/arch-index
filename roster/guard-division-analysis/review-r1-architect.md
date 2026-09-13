# Architect review — round 1, cycle 1

Overall architecture risk: **medium**.

## Findings

### MEDIUM — Public analysis mutates compiler-global lookup state

- Location: `lib/arch_guard/guard_interpreter.ml:111`
- Boundary: the installed `arch-index.guard` library's `Arch_guard.render_json` / `render_text` entry points
- Risk: `analyze` calls `Load_path.init`, whose compiler-libs contract resets the process-global load path, and then clears the process-global `Envaux` cache. It neither snapshots nor restores the caller's visible/hidden paths. A compiler-libs host that initializes project include paths, calls the public render API, and then performs another environment reconstruction will unexpectedly search only `Config.standard_library`. This is a concrete composability regression even though the bundled CLI exits immediately afterward.
- Corroboration: a compiler-only owned client initialized `Load_path` with a fresh marker directory plus the standard library, invoked `Arch_guard.render_json` on the already-built owned `arch_index.cmt`, then inspected `Load_path.get_paths ()`. Compile exited 0; execution exited 0 and printed `before_marker=true after_marker=false`.
- Fix direction: the narrowest safe remedy is to keep the stateful analyzer process-isolated behind the CLI and stop presenting render functions as a composable library API. If in-process use is required, first define that contract explicitly, then encapsulate all affected compiler-global state and serialize access. Restoring `Load_path.get_paths ()` in `Fun.protect` plus resetting `Envaux` caches addresses registered paths but is not by itself a complete restoration: compiler-libs' auto-include callback is a separate ordinary reference and `Envaux` owns an ordinary cache table. A regression client should establish a non-stdlib path/callback behavior, invoke both success and exception paths, and verify subsequent compiler lookup behavior.

## Independent verification

- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune build --root .` — exit 0.
- `rtk proxy opam exec --switch=/home/mathias/dev/arch-index -- dune test --root . --force` — exit 0; 255 Tezt and 64 Alcotest cases reported.
- `rtk proxy git diff --check` — exit 0.
- `inventory`, `numeric`, `domain`, `inputs`, `report`, and `owned` modes of `scripts/check-arch-guard.js`, run under the project switch — each exit 0. Domain evidence reported 640,734 responses and 23,219,242 law assertions. Owned census was 23 artifacts and 0 sites.
- `checks/origin-recurring-consumer.js` modes `authentic`, `failures`, and `package` — each exit 0. A fresh owned producer leaf and its artifact validator both exited 0.
- Fresh self index and golden comparison — exit 0, with 23 modules, 828 functions, and 5,223 calls. Self architecture rules and `arch-impact --diff main..HEAD` both exited 0; impact explicitly reported the 66 changed files outside the index as UNKNOWN.
- `env DUNE_CACHE=enabled DUNE_CACHE_STORAGE_MODE=copy opam exec --switch=/home/mathias/dev/arch-index -- ./scripts/recalibrate.sh --check` — exit 2 before measurement because the coordinated review's untracked trace/review artifacts made the worktree non-clean. Per the review coordinator, a successful rerun is deferred until review artifacts are committed. An initial attempt outside the opam environment also exited 2 (`dune not found`) and is not counted as calibration evidence.
- Compiler-only load-path client — compile exit 0; run exit 0, reproducing marker-path loss (`before_marker=true after_marker=false`). No Dune command was used for this corroboration.
- Remote exact-head CI — not run by this specialist; external/remote gate.
- No Tezos or external corpus scan was performed.

The component otherwise preserves the bounded separation: new implementation is confined to `lib/arch_guard` / `bin/arch_guard`, the CLI buffers output before publication, inventory and interpretation reconcile explicitly, unsupported ancestry remains represented, and the existing indexed libraries/rules/schema/reference surface is unchanged apart from the authorized ratchet pin.
