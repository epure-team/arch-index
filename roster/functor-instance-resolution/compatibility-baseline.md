# Independent pre-feature fixture baseline

Root compiled this owned fixture directly with the existing OCaml 5.3 compiler
(`ocamlc -bin-annot -c fixture.ml -o _build/default/fixture.cmo`), without Dune or
the new collector, in `/tmp/functor-compatibility.P8afAu`:

```ocaml
module type S = sig val run : int -> int end
module A = struct let run n = n + 1 end
module F (X : S) = struct let run n = X.run n end
module M = F (A)
module Anonymous = F (struct let run n = n - 1 end)
exception Bad of int
let check n = if n < 0 then raise (Bad n) else A.run n
let execute n = try M.run (check n) with Bad _ -> 0
```

The preserved baseline producer (SHA256 in implementation-baseline.md), using
the unchanged main-checkout schema copy, indexed one CMT successfully: 4 functions,
7 calls (1 resolved), 0 module dependencies, 8 type usages. Direct SQLite reads
captured `compatibility-baseline.json`; `created_at`, `last_analyzed` and
`producer_run_id` are excluded as run metadata. Fixed-fixture surrogate IDs remain
to preserve exact graph relationships. Future comparisons must sort rows
canonically, not rely on SQLite's unspecified default row order.

The fixture has real exception-origin and handler-scope rows as well as
module-parameter TOPs. It does not establish nonempty dependency, conditional,
dead-code or every error-channel coverage: additional fixture/probe premises
are still required. Existing rule/query verdict comparisons are also pending.
No current-product compatibility pass is claimed from this baseline alone.

Baseline query commands in `ARCH_QUERY_FORMAT=json` each exited 0:

- `raises execute`: `execute: UNBOUNDED (⊤): {}` with reasons
  `may_top_edge fixture.ml:7` and `may_top_edge fixture.ml:8`.
- `unreachable execute check`: `REACHABLE (may-reach): execute -> check`.
- `may-fail check --channel exception`: direct `Fixture.Bad` row (`via=-`),
  then `check: UNBOUNDED (⊤): {Fixture.Bad}` and reason
  `may_top_edge fixture.ml:7`.

These are observed existing outputs, not desired new precision. The catalogue
must preserve them for the same artifacts. An attempted `DB --help` query
returned existing usage error2; it was not counted as a successful query.

The shipped checker must embed/reuse the fixed source and semantic expected
facts without requiring these temporary paths or old binaries. Root owns cleanup
of this scratch directory after comparisons and evidence capture.

## Richer two-module baseline

The separate `rich/` subdirectory uses `helper.ml`:

```ocaml
let identity n = n
exception Failure of int
```

and `fixture.ml`:

```ocaml
open Helper
module type S = sig val run : int -> int end
module A = struct let run n = identity n + 1 end
module F (X : S) = struct let run n = X.run n end
module M = F (A)
module Anonymous = F (struct let run n = n - 1 end)
let check n = if n < 0 then raise (Failure n) else A.run n
let execute n = try M.run (check n) with Failure _ -> 0
let dead n = if false then A.run n else identity n
let division d = 10 / d
```

Compile helper before fixture, with `-I _build/default` for fixture. The same
baseline producer successfully indexes2modules/7functions/11calls(3resolved),
1resolvedmoduledependency and12typeusages. `compatibility-rich-baseline.json`
captures all selected semantic table rows, excluding the same run metadata.
Its dependency and raise/division origin premises are nonempty. The constant
false branch does **not** produce conditions/dead_code_sites rows with the old
producer; do not misreport it as a positive stored dead-site premise. It still
provides a fixed source branch whose call classification can be compared.

## First in-progress old/new comparison

Sol indexed the unchanged simple fixture with the current producer into
`/tmp/functor-compatibility.P8afAu/current.db`. Root independently compared all15
recorded semantic table/marker snapshots after removing run metadata and sorting
object keys/rows canonically: exact equality, exit0. This includes identities,
call classifications and anchors, exception handler/origin relationships and
all three existing contract values; not merely aggregate equality.

Root reran the three recorded query commands with the current query executable;
all exited0 and their exact visible outputs match the baseline above. These are
intermediate integration results, not final-head evidence or the completed
compatibility CHECK-4. Repeat after the final code and independent checker land.

## Local structured-module resolution recalibration (2026-09-14)

The reviewed local-module capability changes only the two calls through the
fixture's concrete `module A = struct ... end`: `A.run` at lines 7 and 9 now
targets the existing `A.run` body (function ID 1) as `MAY_ENUMERATED`, with null
TOP fields. The functor parameter call `X.run` at line 4 and application-result
call `M.run` at line 8 remain `MAY_TOP` with `module_param`; every other selected
table row and contract is unchanged.

Consequently, `raises execute` retains only the line-8 TOP reason, and
`may-fail check --channel exception` becomes bounded while retaining its direct
`Helper.Failure` origin. This is an explicit capability-specific successor
oracle. It does not rewrite the historical pre-feature observations above or
weaken the checker's exact-table and exact-query comparisons.
