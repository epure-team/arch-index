# Stage 1 preflight and diagnostic evidence

Date: 2026-09-15. Branch: `fix/ocaml-data-preservation`, base local `c10d1a4`, fetched upstream `a8114dc307ef2288aa6faabc375938ee19546ff3`.

## Environment

- `rtk proxy opam exec -- dune build`: exit 0.
- `rtk proxy node scripts/review-bundle-verify.js`: PASS, 22 files, bundle 1.6.0.
- `rtk proxy opam exec -- dune exec tezt/tests/main.exe -- --list`: exit 0, 342 tests registered.
- `rtk proxy opam exec -- dune runtest --force`: exit 0, 279392 ms, exact before/after porcelain status unchanged. Generated receipts: `improvement/2026-09-15-ocaml-cfa/stage1-baseline-guard.{json,log}` (ignored runtime evidence).
- No new worktree. Existing unrelated files and temporary directories preserved.

## Confirmed effect misattribution

Owned diagnostic directory: `/tmp/arch-data-preflight-0lS4GH`.
SQLite fixture `identity.db` contains functions `(1, f, a.ml)` and `(2, f, b.ml)`.
The actual built `arch_effects_load` executable consumed two effect JSON lines for `f`, one from each path. It exited 0 and printed `2 effects written, 0 skipped`.
Both stored effects received `function_id = 1`, including the effect from `b.ml`.

This demonstrates incorrect identity association, **not** the historical issue #26 claim of 54% row loss. The current effect unique index does not use function_id; that old proposed root cause is not established on this revision.

## Confirmed identical-artifact rejection

Compiled `let touch a = a.(0) <- 1` with `ocamlc -bin-annot -c` into `build/a/source.cmt`; copied its exact bytes into `build/b/source.cmt`.
Both SHA256 values: `965e84f9d0063482673d027279ce94d043f608c095130b32378c44d8c652d980`.
The actual callgraph CLI selected both artifacts and exited 1, with one module, one function, one call and three type usages stored. It reported `UNIQUE constraint failed: modules.path`, a dropped Source compilation unit, and one rejected modules statement.

This demonstrates rejection of byte-identical duplicates. It does **not** establish that arbitrary same-source or per-executable artifacts are equivalent.

## Remaining qualification

Record the pinned Tezos baseline, independently compiled per-executable cases and negative non-equivalence controls before claiming issue #68 resolved. No product code or test changes have been made at this point.

## Fresh pinned Tezos baseline

Actual replay at 2026-09-15T16:53:15Z: 410 input CMTs, 45052 canonical call rows, 4849 distinct resolved Irmin relations and 12171 protocol relations. Canonical SHA256 `1799c07fd3eb87d4bca433b15b7daeb47f466f90cb098541372e1dd9dd7bac7a`, equal to the previous delivered result. Producer SHA256 `1cb7943cefa15a56f0df39fd2c2e741832d1acefaeedb92d189eb643075e9593`; schema SHA256 `1dd2d909e1feb2582e8a13f717ef165b7be9b73b908f73f47983920bded580d0`. All manifest artifact digests and both checkout status snapshots were unchanged. Runtime including snapshot extraction: 5330 ms; this is not a pure producer CPU benchmark.

Generated package: `improvement/2026-09-15-ocaml-cfa/stage1-baseline/` contains copied producer/schema, selected symlinks, database, snapshot, log and provenance. No Tezos source or CMT edits, no build in Tezos.

## Independently compiled duplicate control

Recompiled the same diagnostic `source.ml` with the same compiler and flags, changing only output from `build/a/source.cmo` to `build/c/source.cmo`. Compiler exited 0. New CMT SHA256 `22700bf5c96d244cac27ca8271dee109a03fdbea4547b86e2e1f46bedb49c372` differs from the first artifact. Therefore exact-byte deduplication alone does not handle even every independently compiled copy of the same source. Different bytes do not prove different semantics; this control establishes only the insufficiency of a byte-only acceptance policy for the complete issue #68 request.

Independent design consultation: ephemeral read-only Sol session `01a0a5f9-aa74-7312-874a-489ad475d954`, completed. It recommends separating artifact accounting from graph admission, exact-byte reuse as a conservative first slice, and explicit conflicts otherwise. Its system compiler inspection used OCaml 5.5 rather than the project's 5.3; use the root research's installed 5.3 interface as authoritative. Its broad claims about existing completion markers were recommendations, not verified facts or accepted contract changes.
