# Task — port-fork-robustness-fixes

**Mode:** full (escalated from fast — see below)
**Branch:** `port-fork-robustness-fixes` off `main` (2ccfe8f), build+test green, zero files changed
**Date opened:** 2026-08-25

## Goal

Carry four robustness fixes out of a stale fork before that fork is deleted.

`épure/src/arch_index/` (at /home/mathias/dev/epure/src/arch_index/) is an ANCESTOR of this
repo's `lib/arch_index/`. Lineage: arch-index was born in octez-manager, copied into épure where
both evolved in parallel, then épure's copy was extracted into this repo, which became the most
evolved. The épure fork is being deleted; four fixes made in it on 2026-08-24 (épure PR #265,
CI-verified there) exist only there.

An identifier-level inventory was done first — 19 épure-only identifiers, only these four cross:

1. **Absolute `file://` URIs.** `collect_file_uris` builds `"file://" ^ Filename.concat
   project_dir row.file_path`; the scanners build `"file://" ^ path`. With `project_dir = "."`
   (the CLI default) this yields `file://./src/foo.ml` — a malformed file URI, so the server never
   opens the document and every `documentSymbol` comes back empty. The same defect makes
   `relative_path ~project_dir` never match, storing absolute machine-specific paths in the DB.
2. **Per-file failure isolation.** In `extract_symbols`, one document the server rejects raises
   and takes the whole extraction down. Measured in épure: ocamllsp answered `unsupported file
   extension` on a single `.ts` fixture and the entire index came out empty.
3. **Honest partial results on timeout.** `Runner.run`'s timeout handler returns `([], [])` while
   printing "returning partial results". Measured in épure: a run that had already extracted
   35845 symbols threw all of them away and wrote an empty database.
4. **Unknown-language fallback must not scan TypeScript.** `scan_source_files ~language` ends
   with `| _ -> scan_ts_files`, handing `.ts` files to whatever server is running.

Alongside 1–3: the silent-failure diagnostics — `workspace/symbol` and `documentSymbol` errors
are swallowed as `[]` with no message, so an empty index never names its own cause.

## Explicitly NOT to port (settled by the inventory, do not revisit)

- `source_extensions` — this repo already has the capability as `scan_source_files ~language`
  dispatching to per-language scanners.
- The 7 `line_counter` locals — this repo rewrote that module better (immutable state, 89 lines
  vs the fork's 114).
- `is_notification`, `lookup_name` — the fork's versions are INFERIOR: this repo answers
  server→client requests, and the sound qualified-name fix lives on branch
  `20-sound-qualified-name-resolution` (pushed, separate — do not touch).
- `candidates` — a coverage-reducing bound on the call graph. A decision, not a port. Out of scope.

## Why Full mode

A Fast-mode attempt stopped before touching any code, on a measured blocker:

- `Lsp_client.t` is abstract (`lsp_client.mli:10`) with no constructor but `start`, which spawns a
  real server process. `Lsp_extractor.extract_symbols` takes a `Lsp_client.t`.
- `Lsp_extractor` is NOT re-exported in `lib/arch_index/arch_index.mli`, so even the pure helpers
  are unreachable from `test/`.
- `grep -rln 'ocamllsp\|run_lsp\|OCAMLLSP' test/ tezt/` returns nothing — no LSP integration
  harness exists here.
- Net: items 1 and 4 have pure/filesystem cores that could be tested after a surface addition;
  items 2 and 3 are control flow around an un-stubbable dependency and cannot be proven
  red-then-green at all.

The fact that makes this a design question rather than a scoping annoyance: **the CMT half of
this library has 69 tests, the LSP half has zero.** The untestability is not local to two fixes.

The human chose Full mode over (a) porting all four with 2 of 4 unproven and (b) splitting the
task — so the test seam is designed work, and all four fixes are then proven.

## Constraint to carry forward

The four fixes are already written and CI-verified in épure, so the port itself is known-good
code. What is being designed is only the seam that lets it be proven here.

## Rigour bar set by the human

- Every claim in a phase artifact carries the command and its exit code. Not "verified" — the
  command.
- Each of the four fixes needs a test that FAILS before it and passes after. Then each guard is
  MUTATED and shown to die, **through `dune test`** — never by invoking a binary by hand. A kill
  obtained by running an executable directly does not count; that shortcut already invalidated a
  mutation table once this week.
