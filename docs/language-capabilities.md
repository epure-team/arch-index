# Languages and capabilities

arch-index has one query/report layer and several ways to produce an index.
Choose the producer first; its contract determines what a result can establish.
Do not infer capability from a file extension, an empty table, or a successful
process exit. When the coverage-matrix pass has been run, its
`analysis_coverage` records state what it observed; their absence is not proof
that an analysis ran or did not run. See [schema](schema.md).

## Choose an input path

| Project or input | Start with | Index shape and limit |
|---|---|---|
| Go, Rust, TypeScript, Python or OCaml source | `arch-index REPO DB LANGUAGE` | LSP symbol/index path. Useful discovery; its call graph is heuristic and does not itself ⊤-mark unknown calls. |
| OCaml built with Dune | `arch-callgraph-ocaml --build-dir … --db-path DB --schema-path architecture-schema.sql` | Native CMT producer. It records unresolved calls as TOP; use the CMT/functor material below. |
| Go module needing call-graph edges | `arch-callgraph-go … \| arch-load DB` | Native Go SSA/CHA producer through NDJSON. The producer, build and run must be available; inspect its declared coverage/provenance. |
| Rust Cargo workspace | `arch-callgraph-rust WORKSPACE \| arch-load DB` | Native MIR producer plus whole-workspace merge. It requires the pinned nightly and is not a lightweight default CI dependency. |
| Another language or an existing analyzer | `PRODUCER \| arch-load --producer=… DB` | Bring structured NDJSON, including explicit edge kinds and provenance. The loader cannot manufacture missing analysis. |

The query, impact, rules and reporting commands are shared once a compatible
database exists. Some visual/UI tools intentionally support only the flat
LSP/NDJSON schema; for example `arch-serve` declines the CMT main schema and
points to `arch-query` instead.

## LSP: quick, broad discovery

The LSP wrapper accepts `auto`, `ocaml`, `typescript`, `rust`, `go` and
`python`. Install the corresponding server and run from the project root:

```sh
./arch-index /path/to/project /tmp/project.db go
./arch-query /tmp/project.db stats
```

`auto` detects language roots in a polyglot repository. LSP startup, timeout,
partial-result and unexpected-server diagnostics go to stderr, but the wrapper
retains a best-effort contract and can write an empty or partial database with
exit 0. Treat that as discovery data, not as evidence that an absent path is
unreachable. [Installation](install.md) lists the servers and language-specific
root requirements.

## OCaml: CMT, error channels and functors

For an OCaml project, the CMT producer is the deeper native path. Build first,
then index the relevant CMT directory:

```sh
opam exec -- dune build
./arch-callgraph-ocaml --build-dir _build/default/lib \
  --db-path /tmp/project.db --schema-path architecture-schema.sql
./arch-query /tmp/project.db reaches SOURCE SINK
```

Its TOP-marked contract preserves unresolvable calls instead of silently
dropping them. It can additionally collect OCaml error channels, syntactic
functor applications, and a deliberately narrow set of authenticated
formal-member targets. That target evidence is additive `MAY_ENUMERATED`, not
defunctorization, runtime instance counting, a complete resolution or a MUST
edge. Read [functor catalogue](functor-catalogue.md), [functor targets](functor-targets.md)
and [error channels](error-channels.md) before relying on those additions.

## Go: native producer or LSP

For broad navigation, use the LSP route at the directory containing `go.mod`.
For call-graph production, build the Go driver from this checkout, then load
its NDJSON output:

```sh
(cd callgraph-go && go build -o ../bin/arch-callgraph-go .)
./arch-callgraph-go /path/to/go-module | ./arch-load \
  --producer=arch-callgraph-go --producer-version=LOCAL /tmp/project.db
```

The placeholder version above is not a release identity: replace it with an
actual producer version when one is available. `arch-load` defaults to a
heuristic soundness class; a producer may declare `sound_with_top` only when it
meets that contract. The loader rejects malformed records rather than guessing
what an omitted call means. [Change impact](change-impact.md) documents the
resulting line-span behavior.

## Rust: native workspace analysis is deliberate infrastructure

The Rust native path uses a `rustc_private` MIR driver and a whole-program merge
pass to retain unresolved `dyn`, generic, function-pointer, FFI and intrinsic
calls as TOP. It is more involved than the LSP path:

```sh
(cd callgraph-rust && cargo build --release)
opam exec -- dune build bin/arch_callgraph_rust_merge
./arch-callgraph-rust /path/to/workspace | ./arch-load \
  --producer=arch-callgraph-rust --producer-version=LOCAL /tmp/project.db
```

The driver is pinned to its Rust nightly/toolchain and the wrapper performs a
fresh workspace compilation. The current merge can narrow some trait dispatch
to bounded MAY candidates, but keeps conservative TOP fallbacks where its proof
conditions are absent. It should be introduced as a reviewed CI dependency, not
silently added to a fast default job. Its detailed contract and accepted limits
live in [the Rust producer README](../callgraph-rust/README.md).

## NDJSON: integrate a producer without pretending it is native

`arch-load` accepts `function` and `call` records from another analyzer. At a
minimum, provide stable names, paths and explicit `MUST`, `MAY_ENUMERATED` or
`MAY_TOP` edge kinds. `MAY_TOP` needs a reason/anchor; an unresolved call must
not be omitted merely to make a negative query appear clean.

```sh
my-analyzer --emit-ndjson . | ./arch-load \
  --producer=my-analyzer --producer-version=1.2.3 \
  --soundness-class=heuristic /tmp/project.db
```

Declare the producer accurately. `--soundness-class=sound_with_top` is a claim
about its handling of every unresolved call, not a way to request stronger
queries. Use `analysis_coverage` and the producer metadata to make unavailable
analyses visible to reporting/rule consumers.

## After indexing

Use the [CI and agent guide](ci-agent-guide.md) for a review/gate integration,
[change impact](change-impact.md) for a PR briefing, and
[fitness functions](fitness-functions.md) for explicit rules. Their results
remain conditional on the selected producer and its recorded scope; an index is
not a whole-project security, correctness or completeness certificate.
