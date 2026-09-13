# Checker design — functor application catalogue

Implementation-independent design for `scripts/check-functor-catalogue.js`.  The
checker owns fixture source, expected syntax census, crafted SQLite rows and
mutation expectations; it does not ask the collector/query to calculate its
oracle.  It uses Node `assert/strict`, temp directories, `spawnSync`, and the
project's OCaml 5.3 compiler.  A missing executable/probe/compiler, failed
compile, unreadable fixture, or SQLite setup/read failure is **exit 2**;
assertion failures are **exit 1**; each successful named group is **exit 0**.

`run()` must preserve stdout/stderr/status.  Assertions for product refusals
require the specified status and empty stdout.  Every successful query captures
database bytes before and after.  Native fixtures first prove the premise from
an independently parsed/probed CMT (node count/category or explicit probe
evidence), then inspect catalogue tables; they never treat an unavailable
compiler shape as a skip.

## Groups and AC coverage

| group | ACs | independent oracle / principal assertions |
|---|---|---|
| `inventory` | AC-1, 3, 4, 8, 14, 15 | native fixture CMTs, direct SQLite catalogue reads, fixed preorder/descriptor oracle; graph snapshot before/after catalogue run |
| `lifecycle` | AC-5, 6, 7, 10 | discovered-path inputs plus controlled invalid/probe artifacts; direct lifecycle-table/marker inspection across runs |
| `query` | AC-2, 11, 12, 13, 16 | hand-authored valid v1 and one-fault-at-a-time SQLite DBs; CLI output parsed independently in every renderer |
| `compatibility` | AC-1, 2, 6, 9 | pre-existing fixture snapshots (function/call/dependency/error/marker/query verdict bytes), repeated-index public facts, read-only DB hashes |

This maps every AC exactly to at least one group.  `compatibility` repeats only
cross-cutting claims; it is not a substitute for direct table inspection.

## Inventory fixture and oracle

Compile an owned `catalogue.ml` with `-bin-annot` and use known source text to
derive the expected immediate application tree, not names inferred from report
rows.  Split only when OCaml 5.3 typing requires it:

```ocaml
module type S = sig val n : int end
module A = struct let n = 1 end
module B = struct let n = 2 end
module F (X : S) = struct let n = X.n end
module G (X : S) (Y : S) = struct let n = X.n + Y.n end
module U () = struct let u = 0 end
module H (X : S) = X
module N = F(A)
module C = F(struct let n = 3 end)
module Chain = G(A)(B)
module Nest = H(F(A))
module Unit = U()
module Constrained = (F(A) : S)
module In_functor (X : S) = struct module L = F(X) end
let local () = let module L = F(A) in L.n
let anonymous () = let module _ = F(A) in 0
let unpacked (module X : S) = let module L = F(X) in L.n
```

Add a separate well-typed functor-head case (an inline functor applied to `A`)
to require `opaque_functor_head`, and a combined inline-functor/structure case
to require sorted `anonymous_argument;opaque_functor_head`.  The fixture oracle
lists, per source application, `apply`/`apply_unit`, ordinal, head/argument
descriptor, and diagnostic set.  Assert exactly one row per listed immediate
node; contiguous `1..n`; parent before descendants; head subtree before argument
subtree; and every application descriptor points to a greater ordinal in the
same artifact.  Assert exact descriptor keys/types and reject serialized body,
type, coercion, Shape/UID, target/exactness fields.  Exercise named and unit
functor descriptors where they are operands, structure, unpack, constraint and
unit-only-as-`apply_unit`-argument.  Confirm source provenance survives invalid
locations and that valid ghost locations retain coordinates.

For AC-3, place at least one application in each available 5.3 reachable
context: expression/local module, nested structure, functor body, anonymous
argument, unpack, module-type-of, class/object method/initializer.  A tiny
test-only CMT inspector/probe must enumerate the immediate `Tmod_apply` and
`Tmod_apply_unit` nodes from the accepted Implementation tree and return their
context labels/count; checker compares that fixed census to direct DB rows.
It must also establish that referenced external module/signature paths are not
expanded.  If a proposed source construct does not yield the promised Typedtree
category, probe failure is exit 2 and the fixture must be revised.

### Native artifact seams (explicitly non-source output)

Ordinary OCaml source cannot reliably produce all metadata shapes.  A test-only
native probe should call the typedtree/path API directly (rather than expose a
production CLI fault-injection switch), read a seed CMT, rewrite it, and emit
`{ok:true, changed:true,premise:<name>, before_count, after_count}`.  The checker
requires that evidence before indexing.

- `papply`: rewrite a `Tmod_ident` operand path to a genuine `Papply` using
  existing typedtree/path constructors, retaining compiler/source renderable
  strings.  Probe then re-reads output and proves `Papply` is present.  Expect
  exactly its enclosing occurrence, a `path` descriptor with
  `contains_apply:true`, and no new ordinal/target claim.
- `ghost-valid`: set an application location ghost flag while retaining valid,
  equal nonempty endpoints.  Expect normal coordinates and no
  `unusable_location` solely from ghostness.
- `invalid-location`: create unequal/empty endpoint filename or unordered
  coordinates and preserve ghost state.  Expect all five location data fields
  null except `ghost`, source retained, and `unusable_location` joined with any
  independently triggered codes.
- `same-position`: give two distinct application nodes the same valid span.
  Expect distinct ordinals/rows, never location-based deduplication.
- `mid-input-failure`: use a real, narrow lifecycle seam after at least one
  occurrence has been accumulated but before input publish; evidence must name
  the targeted artifact.  This is lifecycle evidence, not a source fixture.

The design presumes a narrowly scoped test-only native probe executable.  It is
currently an implementation prerequisite, not evidence that source compilation
alone can make Papply or synthetic locations.

## Lifecycle checks

The CLI discovers from directories, so cover normal directory discovery with two
distinct copy/symlink path strings to equivalent bytes and two artifacts which
collide under the established module/source insertion identity.  A native
selection probe, calling the producer's discovery/selection API directly with
an exact repeated path string, owns the duplicate-string oracle: it must return
the exact-string sorted/deduplicated selection without realpath/inode collapse.
The integration run then asserts that copy/symlink paths remain separate selected
inputs and the collision input is `dropped_module`, has zero rows, and cannot
inherit the earlier input's success.

Create one selected input for each ordered outcome: unreadable/no CMT info,
non-Implementation annotation, unresolved source, duplicate insertion,
collection/provenance failure through a direct native test probe, and collected
(including a collected zero-application fixture).  Direct SQL assertions: exactly one outcome/input;
failure precedence; selected count equals input rows; expected row count equals
actual only for collected inputs; non-collected inputs have zero occurrence rows;
non-null module/source/compiler-unit provenance for collected inputs; producer
linkage present but absent from public output.

Run success twice with identical selected strings/source mapping and compare
ordered public catalogue facts byte-for-byte (not surrogate/run/timestamp/stamp
columns); assert no old rows/tables survive.  Then test reindex interruption at
(1) after eligibility clear/before final marker and (2) before schema replacement
through a real narrow lifecycle seam (a test-only callback at those exact
boundaries that terminates the producer, not a generic production CLI option):
the old marker is absent/non-authoritative, old catalogue tables are replaced on
the subsequent run, and only committed complete nonempty selection with all
collected inputs earns exact `functor_catalogue_contract=v1`.  A failed or
markerless partial run must never be queried as complete.

## Query crafted-DB matrix

Use Node SQLite setup to create the exact expected v1 schema/marker and a valid
two-artifact, three-row baseline plus a valid one-input zero-row baseline.  Keep
the schema construction in the checker, with JSON cells built from the closed
contract.  Validate CLI results in table and every supported `ARCH_QUERY_FORMAT`:
summary headers/order and exact values; application headers/order/no extras;
artifact+ordinal sort; `limit=2` gives total 3/returned 2/truncated 1;
`limit=0` gives no application rows, and JSON exactly `summary-array + "\\n" + []`.
Descriptor cells remain strings which themselves parse as closed JSON, never
nested renderer objects.  Assert fixed scope and limitations text and absence of
target/runtime/closure/freshness/physical-uniqueness/defunctorization claims.

For each successful invocation (default 50, 2, 0; table and JSON), compare raw
database bytes before/after.  Invalid command cases `-1`, `+1`, ` 1`, `0x10`,
overflow decimal, non-ASCII digit, and extra positional argument must be exit 2
with no catalogue stdout, even against a nonexistent DB (proves validation first).
An open/operational DB failure is also exit 2.

One-fault-at-a-time mutations of an otherwise marked, full-schema DB must be
exit 3, empty stdout, named `INCONSISTENT_CATALOGUE`, including with limit 0:
missing/duplicate header or bad producer link; zero/mismatched selected/input
counts; non-collected or incomplete outcome; missing/bad module/source/unit
provenance; expected-count mismatch; duplicate artifact; gap/zero/negative
ordinal; orphan occurrence/input/header; malformed/extra-key/invalid-type
location, descriptor, or diagnostics JSON; invalid diagnostic ordering/duplicate
or wrong derived code; bad kind/unit placement; dangling/backward/cross-input
application reference.  The exact valid baseline must pass first.

Separately assert refusal precedence: missing main tables/columns and flat DB =>
`UNSUPPORTED_SCHEMA`; full schema with absent/unknown marker, including
markerless partial rows, => `NOT_COLLECTED` (diagnostic includes observable
failed-outcome counts); only then malformed marked data =>
`INCONSISTENT_CATALOGUE`.  All three are exit 3 with empty stdout.

## Compatibility oracle

Before adding catalogue selection, index fixed existing graph/effect fixtures
and serialize canonical ordered snapshots of functions (identity/name/exposure/
span), calls (caller/callee/display/site/kind/TOP reason-anchor/conditional-dead/
scope-edge form), dependencies, exceptions/errors, existing markers, and existing
query verdict tokens.  Reindex the same accepted inputs with collection enabled
and require equality of those snapshots and the established three-list/head
taxonomy probe result.  A catalogue failure fixture additionally proves prior
graph facts remain and no edge is promoted.  This group deliberately compares
identity-bearing fields rather than only aggregate counts.

## Boundaries / untestable premises

The checker can prove selected-artifact behavior and disclosure, not runtime
instance multiplicity, closed-world completeness, source freshness, physical
program uniqueness, target resolution, alias identity, Shape/UID behavior, or
parameter-substitution sufficiency; these are explicitly prohibited claims, not
positive properties.  It cannot establish traversal of an OCaml 5.3 child kind
unless the native premise probe both creates and confirms that kind.  Likewise
interruption and collector failure tests require explicit narrowly-scoped test
seams; without them, claiming AC-7/10 coverage would be vacuous and the group
must fail setup (2), not pass or skip.
