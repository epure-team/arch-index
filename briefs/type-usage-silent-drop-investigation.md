# Investigation — type-usage-silent-drop

**Date:** 2026-08-26
**Symptom:** `Arch_index.run` reports more rows than it stores. On épure's tree:
`r.n_type_usages = 34833`, `SELECT COUNT(*) FROM type_usage = 34488` — 345 rows
written and then lost, with no error output.
**Status:** ROOT CAUSE IDENTIFIED

## Root Cause

**The CMT extractor records `let _ = ...` bindings as functions named `"_"`.**
A module containing several of them produces several inserts of the *same*
`(module_id, "_")` pair, and `INSERT OR REPLACE INTO functions` turns each
repeat into a DELETE-then-INSERT whose DELETE fires `ON DELETE CASCADE`,
destroying every row already attached to the previous `functions` row.

**Evidence:**

- `lib/arch_index/arch_index.ml:166` — `"INSERT OR REPLACE INTO functions (module_id, name, ...)"`
- `architecture-schema.sql` — `functions` carries an implicit UNIQUE (visible as
  `sqlite_autoindex_functions_1` in `sqlite_master`), so `OR REPLACE` can fire.
- Instrumented run of `arch_callgraph_ocaml` over `épure/_build/default/src`:
  **96 re-inserts across exactly 4 distinct `(module_id, name)` pairs**, and
  every one of the four is `<module>|_`:

  | occurrences | module |
  |---|---|
  | 63 | `src/web_routes/web_api_payloads.ml` |
  | 21 | `src/web_server/json_codec.ml` |
  | 11 | `src/tui/main_page_debug.ml` |
  | 1  | `src/types_base.ml` |

- ~~`grep -c "Statement error"` over a full run: **0** … the rows were written,
  then cascaded away.~~ **WRONG — corrected 2026-08-26 after review.** That
  measurement was taken on the wrong binaries: `arch_index_cli` takes the LSP
  path, and `test_indexer_accuracy.exe` does not relay the indexer's stderr.
  Run against the CMT binary directly — `arch_callgraph_ocaml --build-dir=…` on
  épure's `src/`, `2>` a file — main `631bba3` emits **238**
  `Statement error (CONSTRAINT): FOREIGN KEY constraint failed` lines on
  **stderr** (0 on stdout), reports 25151 type usages, stores 24913. The loss
  equals the error count exactly.

  So the rows were **never written**: they were rejected, loudly, and the exit
  code was 0 anyway. `pending_type_usages` is a deferred batch flushed at the
  end of the run; by then `INSERT OR REPLACE` has replaced the `"_"` row and
  the held `function_id`s are stale, so the deferred inserts violate the
  foreign key. Nothing was cascaded away.

  This makes H4 below CONFIRMED, not refuted — the first diagnosis was right
  about the failure mode and was discarded on a bad measurement.

**Introduced:** undetermined — `INSERT OR REPLACE` and the `_` recording both
predate the history root available here. The defect is invisible without a
reported-vs-stored comparison, and nothing in this repository makes one.

## Reproduction — three lines of OCaml

```ocaml
(* src/shadow.ml *)
let f (x : string) : int = String.length x
let f (x : int list) : bool = List.length x > 0
let g (y : float) : string = string_of_float y
```

`arch_callgraph_ocaml --build-dir=_build/default/src` reports **7 type usages**;
`SELECT COUNT(*) FROM type_usage` gives **5**. `functions` holds one `f`, not
two. No error printed.

Note this fixture reproduces the *mechanism* (repeated `(module, name)` →
`OR REPLACE` → cascade) via top-level shadowing of a real name. On épure the
trigger is different and narrower: the repeated name is always `_`. Both paths
end in the same cascade.

## Tested hypotheses

| # | Hypothesis | Result | Evidence |
|---|---|---|---|
| H1 | `find_cmt_files` returns both `.cmt` and `.cmti` for one source, so each module is extracted twice | **REFUTED** | `arch_index.ml:83-88` filters `cmt_files` (`.cmt` only) for extraction; `cmti_files` feeds `collect_exposed` for exposed names and doc comments alone |
| H2 | One CMT yields the same function name twice (shadowing, `let rec` groups, functors) | **CONFIRMED as a mechanism, REFUTED as the trigger here** | the 3-line fixture above shows the delta; but all 4 real pairs are `_`, not shadowed named functions |
| H3 | Two modules collapse to one `module_id` | **NOT REACHED** | the 4 pairs span 4 distinct `module_id`s mapping to 4 distinct paths |
| H4 | the held `function_id` is stale by the time the deferred batch flushes, so the inserts are FK-rejected | **CONFIRMED** (was wrongly marked REFUTED) | 238 `Statement error (CONSTRAINT): FOREIGN KEY constraint failed` on stderr, main `631bba3`; loss (238) equals error count exactly |

An earlier diagnosis (issue #29, original body) claimed FK rejection at insert
time. Refuted by the same zero-`Statement error` measurement and corrected in a
comment on the issue.

## Impact scope — wider than the symptom

Eight tables reference `functions(id)` with `ON DELETE CASCADE`, including
`calls` on both `caller_id` and `callee_id` (`:107-108`), so a cascade *could*
delete call-graph edges. **It does not here, and the earlier claim that it did
was unsupported.** Measured: `calls` is 45377 reported and 45377 stored on both
main and the fix. Not one edge was lost. The loss is confined to `type_usage`
and equals the statement-failure count exactly.

Two further consequences:

- **The index contains `functions` rows whose name is `"_"`.** They are not
  callable and cannot be a call-graph target, so every metric computed over
  `functions` counts non-functions. Relevant to the metric-population work
  tracked as épure issue #267.
- **CMT path only.** épure's `docs/architecture.db`, produced by the LSP
  indexer, contains **0** functions named `_`. The LSP extractor does not record
  wildcard bindings.

## Fix plan (not executed — investigation only)

1. **`lib/arch_index/arch_index_cmt.ml` — do not record wildcard bindings.**
   At the binding-extraction site (around `:1544`, where `insert_function` is
   called), skip patterns that bind no name. `let _ = e` has no name, is not
   callable, and its "function" row is meaningless. This removes the trigger.
2. **Decide `INSERT OR REPLACE`'s fate independently.** Even with `_` gone, the
   combination of `OR REPLACE` on `functions` and `ON DELETE CASCADE` on eight
   dependent tables is unsafe for any repeated `(module_id, name)` — top-level
   shadowing is legal OCaml and the fixture above exercises it. Either the
   second insert must not happen (dedupe upstream), or it must not be a
   replace (`INSERT OR IGNORE`, or an explicit update that preserves children).
3. **Make the counters honest.** `n_type_usages` is incremented unconditionally
   after the insert (`arch_index.ml:~522-530`); `n_type_usages_resolved`
   increments on a *type* lookup hit, which is a different question from
   whether the row landed. Both can overstate. Counting after a verified write
   is the minimum.

**Fix risks.** Skipping `_` changes `total_functions` for every consumer — a
baseline shift, not a regression, but épure's arch-metrics comparison will see
it. Changing `OR REPLACE` semantics could reintroduce duplicate rows where the
replace was silently deduplicating something legitimate; step 2 needs the
"why is it inserted twice" answer for named functions, which this
investigation did not need to reach.

## Tests to add

- **The invariant that caught this, upstream:** after `run`, assert
  `r.n_type_usages = SELECT COUNT(*) FROM type_usage`, and the same for calls,
  deps and types. Nothing in `test/` (7 modules) or `tezt/tests/` (25 modules)
  asserts any reported-vs-stored equality today; a consumer's test found it.
- **A fixture with two `let _ = ...` in one module**, asserting no `functions`
  row is named `_` and no dependent row is lost.
- **A fixture with a shadowed top-level name** (the 3-liner above), asserting
  the reported/stored equality holds — this pins step 2 independently of `_`.

## Instrumentation

A throwaway `dup_probe` Hashtbl in `lib/arch_index/arch_index_db.ml` logged
`DUPINSERT <module_id>|<name>` on every repeated pair. Reverted; the branch
`throwaway/measure-dup-inserts` exists only to hold it and can be deleted.
