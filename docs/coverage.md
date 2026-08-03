# Reachability-weighted coverage (`arch-coverage`)

The `coverage` table in `architecture-schema.sql` was a stub nothing wrote to, and it was
line-granular — the wrong shape. Line coverage answers *was this executed*, which the whole MC/DC
study argued is the wrong question.

```sh
bisect-ppx-report lcov > coverage.lcov          # OCaml
go test -coverprofile=c.out ./... && gcov2lcov -infile c.out -outfile coverage.lcov
coverage lcov -o coverage.lcov                  # Python
cargo llvm-cov --lcov --output-path coverage.lcov

./arch-coverage /tmp/repo.db coverage.lcov --repo .
./arch-coverage /tmp/repo.db coverage.lcov --mutants mutants.json   # the pairing
./arch-coverage /tmp/repo.db coverage.lcov --write                  # fill the coverage table
```

## Why LCOV

One parser for every language. bisect_ppx, gcov/lcov, `go test -coverprofile` (via `gcov2lcov`),
`coverage.py`, `cargo-llvm-cov` and every JS tool via nyc all emit it. LCOV `DA:` records are
`(line, hit-count)`, which join to `functions.file_path` plus line spans on **every** backend with
no per-language code at all.

Ingesting bisect_ppx's native `.coverage` binary format would be marginally more precise and
OCaml-only. That trade is not worth one parser per ecosystem.

`FN`/`FNDA` records are deliberately ignored. What a producer calls a "function" varies wildly —
bisect_ppx emits none, gcov emits one per mangled symbol — while `DA` means the same thing
everywhere. The call graph already knows where functions begin and end, and using it keeps a
single definition of "function" across the whole toolchain.

## What it reports

**Reachable from the API, never exercised.** Of the functions in the closure of the exported API
(or of `--roots <selector>`), which have instrumentation data showing zero hits. API-relative,
because a global percentage mixes in code nobody can call.

**Covered, but only ⊤-reachable.** The coverage tool saw the line execute; the graph can only
reach that function through an unresolvable edge. The line ran — but *what called it* is unknown,
so "exercised by the API" is not supported by this data.

**Covered, but outside the API cone.** Executed by the tests, and reachable from the API neither
directly nor through a ⊤ edge. This bucket exists so that every covered function lands somewhere:
without it a function in none of the other categories was simply absent, and the report looked
complete while dropping it. A non-empty list here means either the roots are wrong or the tests
exercise code the product cannot reach.

**Covered, but the tests check nothing.** With `--mutants` (an `arch-mutants report --format
json` document): functions that are covered *and* have surviving mutants. Executed by tests that
would not notice them changing. **This pairing is the honest replacement for a coverage
percentage**, and the tool never prints a single headline number to be gamed.

## The distinction the whole tool rests on

> **"No instrumentation data" is not "0% covered."**

A function with no `DA` record inside its span — an inlined definition, a type-only binding, a
ppx-generated body, a file the coverage run never touched — is reported as *no data*. Recording
it as 0% would fabricate a gap and send someone to write a test for code that cannot be
instrumented. The same rule applies file-wide: indexed files absent from the tracefile are listed
as not instrumented, never as uncovered.

Consistently with that, an LCOV file with **no `SF:` records at all aborts**. An empty tracefile
and a coverage run that never happened are indistinguishable from the data, and reporting 0% for
the second is how a green pipeline hides a broken one.

Duplicate `SF:` records **sum** their hit counts. Merged and sharded runs emit the same file
twice; overwriting would silently discard a shard's results.

The `--mutants` join is by function name, the only key an `arch-mutants` report carries. On the
main schema a name is unique only within its module, so names shared by several indexed functions
are **excluded from the pairing and reported** rather than mis-attributed — an unexplained
absence is recoverable, a wrong attribution sends someone to rewrite the wrong test. The
duplicate count is taken over every indexed function, not only the instrumented ones: if two
functions share a name and only one has coverage data, counting within the instrumented set sees
one, stays silent, and blames the survivor on whichever copy happens to be instrumented.

`--roots` **aborts when it selects nothing**, including the default `--roots exported` on an
index whose producer never marked exports. Every finding is relative to the API cone, so an empty
cone empties every list — and an empty report reads as a clean one.

## `--write`

Populates the `coverage` table (main schema, keyed by `function_id`) or `coverage_by_name` (flat
schema, which has no function ids — inventing them would produce rows that join to nothing).
Replaces rather than accumulates, so rerunning does not grow the table.
