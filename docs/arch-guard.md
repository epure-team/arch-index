# arch-guard (experimental)

`arch-guard` is a separate, report-only OCaml analysis component. It inventories
immediate compiler-resolved integer division/remainder primitive applications in
explicitly supplied, trusted implementation CMT artifacts. It does not alter
arch-index's graph, database, rules, or existing soundness labels.

Build with the project's configured OCaml switch:

```sh
dune build --root . @install
./arch-guard --cmt path/to/module.cmt --format json
```

The wrapper only runs an existing binary; it does not build or install anything.
CMT files must match the compiler and target used to build the tool. Never supply
untrusted marshalled compiler artifacts. This is not a process-level sandbox.

## Interpretation

The `constant-zero-v1` domain tracks bottom, exact constants, nonzero, and unknown.
Within the supported acyclic native-`int` fragment it handles scalar local aliases,
addition/subtraction/multiplication/negation, joins, and direct comparisons with
zero. Possible arithmetic overflow may lose precision to unknown. Each function
starts with fresh unknown parameters and captures; ordinary calls return unknown.
There is no interprocedural specialization, heap model, loop fixpoint, or
défonctorisation.

Statuses describe conditional facts about the divisor:

- `NONZERO`: excludes zero within the model, if reached.
- `ZERO`: exactly zero within the model, if reached; not a confirmed failure.
- `MAY_ZERO`: the model cannot exclude zero.
- `UNREACHABLE`: a supported branch condition contradicts the modeled state.
- `UNSUPPORTED`: excluded syntax, argument shape, type, or integer family.

Unsupported lexical ancestry takes precedence over other classifications.
Loops, recursion, handlers, effects, compound/alias patterns, optional arguments,
function cases, arrays, objects, and short-circuit boolean subtrees are excluded.
In OCaml 5.3 an explicitly annotated parameter can become an alias pattern and
therefore be excluded. Local type aliases are expanded using compiler environment
summaries and the linked compiler's standard library only; arbitrary artifact
include paths are not loaded. Unresolved types remain unsupported.

The inventory includes all eight immediate `int`, `int32`, `int64`, and
`nativeint` div/mod primitives, but numeric interpretation currently covers only
native `int`. Indirect aliases of primitive functions are not reconstructed.
An empty inventory means zero matching immediate applications in the supplied
artifacts, not absence of failures in a program.

## Reports and limits

Text is the default. JSON schema version 1 includes artifact SHA-256 attribution,
source locations, original operand-slot-2 syntax, statuses, reasons, assumptions,
limitations, and census. IDs are deterministic per-artifact inventory ordinals,
not cross-build fingerprints. Locations describe artifacts, not certified fresh
source files. `precision_gain_sites` counts NONZERO plus UNREACHABLE sites; it is
not a production defect rate or a measured improvement on Tezos.

Successful reports, including ZERO and UNSUPPORTED, exit 0. Input, usage, and
internal errors exit 2 with a stderr diagnostic and no partial stdout. Output is
buffered; JSON is emitted without an additional newline beyond its checked byte
bound. Canonical repeated paths deduplicate; distinct artifacts with the same
module/source identity, leaf symlinks, and non-implementation annotations fail.

Inclusive limits: 128 unique inputs, 32 MiB per artifact, 256 MiB combined,
100,000 expression nodes, 10,000 sites, expression depth 512, and 16 MiB serialized
JSON and selected rendered output. Breaches fail rather than truncate. These
checks are not an OS memory/time limit. The before/after digest check is not an
atomic filesystem snapshot or a freshness certificate.

## Verification status

Run checkers under the same compiler environment as the build:

```sh
node scripts/check-arch-guard.js inventory
node scripts/check-arch-guard.js numeric
node scripts/check-arch-guard.js domain
node scripts/check-arch-guard.js inputs
node scripts/check-arch-guard.js report
node scripts/check-arch-guard.js owned
```

`ARCH_GUARD_OCAMLC` may name the matching compiler executable. The checker never
installs a toolchain. Its private domain probe is checked against independent
JavaScript BigInt signed modular arithmetic: exhaustive small widths 3–8 and
selected 31/63-bit extrema. This is executable evidence, not machine-checked
proof. Every child process is limited to 120 seconds and 16 MiB captured output.
Checker exit 1 means an assertion failure; exit 2 means setup, execution, or
internal failure. Changed-read rejection is exercised by a deterministic private
shared-reader seam, not a timed filesystem race. Installed CLI error atomicity is
checked separately on invalid inputs. Exact limits use real CLI invocations;
test-only CMT metadata mutation and an independent Typedtree counter provide
otherwise inaccessible boundary fixtures.
