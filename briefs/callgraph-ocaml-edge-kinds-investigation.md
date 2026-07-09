# Investigation — callgraph-ocaml-edge-kinds

**Date:** 2026-07-09
**Symptom:** `./selftest-callgraph-ocaml.sh` fails on clean `main` (RC=1): after the name-pattern
issue, all edge-kind soundness assertions fail — `reaches`/`unreachable`/`escapes` produce no/only
REFUSED output, and "DB has 9 edges with missing/invalid kind". Pre-existing; reproduced on `main`.
**Status:** ROOT CAUSE IDENTIFIED

## Root Cause (two independent layers)

### Layer 1 — producer emits no edge kinds and no contract flag
`arch-callgraph-ocaml` (→ `Arch_index.run`, main arch-index schema) never populates `calls.kind`
and never writes `comment_db_meta('callgraph_contract','v1')`.
- `lib/arch_index/arch_index_cmt.ml:255-261` — `pending_call` record has **no `kind` field**.
- `lib/arch_index/arch_index_cmt.ml:337-370` — `collect_calls_from_expr` records callees with **no
  MUST/MAY classification**, and ignores non-`Texp_ident` application heads (`| _ -> ()` at :363),
  so applying a computed/parameter function emits **no edge at all**.
- `lib/arch_index/arch_index_db.ml:152-159` — `insert_call` binds only caller_id, callee_id,
  callee_name, call_site → schema column 5 `kind` left **NULL** (`architecture-schema.sql:85`).
- `Arch_index.run` writes `comment_db_meta.schema_version` but not the contract flag (only
  `lib/arch_db/arch_load.ml:115` writes `callgraph_contract`).
- The local-vs-external resolution needed for MUST/MAY_TOP EXISTS but is discarded: `fn_lookup`
  hashtable keyed `(module_path, fn_name)` in `arch_index.ml:257-296` decides "resolved to known
  function" (`Some id`) vs not (`None`) — currently used only for the report counter, not `kind`.

### Layer 2 — arch-query reaches/unreachable/escapes are flat-schema-only
`arch-query:100-132` — `reaches`, `unreachable`, `escapes` query `c.caller_name`/`c.callee_name`
TEXT columns directly. The **main schema has no `caller_name`** (it uses `caller_id` FK →
`functions`). So even once the producer emits kinds, these three subcommands error on a main-schema
DB. Contrast `dead-code` (:159-208) and `pure-fns` (:269-302), which already branch flat-vs-main via
`pragma_table_info('calls') WHERE name='caller_name'`. `require_contract` (:74-94) also REFUSES on
missing flag OR any NULL/invalid kind.

## Tested hypotheses

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | Only the name-pattern `%.add` assertion is wrong | REFUTED | fixing it exposes 7 edge-kind failures |
| H2 | Producer omits kind + contract flag | CONFIRMED | arch_index_cmt.ml:255-370, arch_index_db.ml:152-159 |
| H3 | Consumers can't read main-schema for these verbs | CONFIRMED | arch-query:100-132 reference caller_name (absent in main schema) |

## Fix plan (full roster task — feature/api-change: changes producer output contract)

1. **Producer kinds** (`arch_index_cmt.ml` + `arch_index.ml`): thread a `kind` through `pending_call`.
   Classify at resolution time using `fn_lookup`:
   - Unqualified `Pident` name resolving to a same-module top-level function → **MUST**.
   - Unqualified `Pident` NOT in the module's top-level set (function parameter / let-bound closure)
     → **MAY_TOP** (emit synthetic `*TOP*` edge, mirroring the Go producer at `callgraph-go/main.go:333-375`).
   - Qualified `Pdot` external call → MUST if resolved to a known function, else MAY_TOP.
   Also match non-`Texp_ident` application heads so computed-function calls emit a MAY_TOP edge.
2. **Contract flag**: write `comment_db_meta('callgraph_contract','v1')` from the OCaml producer path
   once every emitted edge has a valid kind.
3. **`insert_call`**: bind column 5 `kind`.
4. **arch-query main-schema branches** for `reaches`/`unreachable`/`escapes` (mirror dead-code/pure-fns
   flat-vs-main detection): resolve caller via `caller_id` FK → `functions.name`.
5. Add `selftest-callgraph-ocaml.sh` to CI once green (ratchet) + revert the local name-pattern
   assertion to accept unqualified (`name='add' OR name LIKE '%.add'`).

## Fix risks

- Edge-kind classification must be **sound**: when in doubt, emit MAY_TOP (never a false MUST) — a
  false MUST corrupts `reaches` ground-truth and `unreachable` soundness.
- Emitting synthetic `*TOP*` edges must not break existing consumers that count/join real edges.
- arch-query main-schema CTEs must match the existing recursion semantics exactly (MUST-only for
  reaches; MUST∪MAY_ENUMERATED for unreachable closure).

## Tests to add

- `selftest-callgraph-ocaml.sh` green end-to-end (reaches MUST path; island UNREACHABLE from
  clean_entry; island UNKNOWN from dirty_entry via apply_fn MAY_TOP; escapes lists apply_fn).
- Edge-kind integrity: 0 NULL/invalid kinds; contract flag present.
- Unit: a fixture asserting a function-parameter call yields a MAY_TOP edge and a direct top-level
  call yields MUST.

## Impact scope

All CMT-built OCaml indexes gain sound `unreachable`/`escapes`/`reaches` support (currently REFUSED
or erroring). No effect on Go/flat paths (already contract-compliant via arch-load).
