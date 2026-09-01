---
name: roster-spec
type: spec
status: draft
feature: arch-lsp — architectural facts in the editor, while the code is being written
date: 2026-09-01
version: 0.1.0
---

# Spec — arch-lsp

An LSP server that surfaces arch-index's facts in the editor: blast radius, ⊤ frontier,
architecture-rule violations, and dead code — at the moment the code is written, not at CI.

## The central tension, and the rule that resolves it

arch-index is a **batch** tool over **compiled artifacts**. The OCaml producer reads `.cmt` files
that exist only after `dune build`; the Go producer needs `go/ssa`; the index is a snapshot of a
tree state. An LSP server is asked about a buffer that may be unsaved, uncompiled, and three edits
past anything the index has seen.

For a soundness tool that is not a performance problem, it is a **correctness** problem. A stale
`UNREACHABLE` shown against a function the developer just wired up is a confident lie — precisely
the failure class this project exists to refuse, delivered faster and with more authority because
it appears inline in the editor.

**Resolving rule: staleness is the temporal ⊤ — but scoped as narrowly as the evidence allows.**

The naive resolution is to withhold every negative fact whenever anything is dirty. That is sound
and nearly useless. Merlin points at better, and the comparison is instructive: `ocamllsp` has the
same dependency on compiled artifacts, and ships anyway, because it splits the problem. It
**type-checks the current buffer from source, in memory**, and reads `.cmi`/`.cmt` from `_build`
only for *dependencies*. Fresh-local, stale-global — and its familiar failure mode ("types from
another module are wrong until you `dune build`") is precisely the stale-global half.

Why Merlin can live with that and arch-index cannot, naively: Merlin's claims are **positive and
local** ("this expression has type X"), so a wrong one is contradicted by the compiler within
seconds. `UNREACHABLE` is **negative and whole-program**; nothing in the editing loop contradicts
it. The distinguishing axis is not "needs compiled code" — both do — but **whether a wrong answer
is self-correcting.**

So adopt Merlin's architecture rather than its tolerance:

- **Fresh local.** Link `merlin-lib` (5.6-503, already present in the project switch) to type the
  dirty buffer and extract its call sites precisely. Typed extraction matters: it resolves
  `Foo.Bar.baz` to a target, where a syntactic parse would only yield a name.
- **Indexed global.** Everything outside the buffer comes from the index.
- **Splice.** The buffer's edges replace that file's edges in the indexed graph. Edges the buffer
  adds are known; edges it deletes are known, because the index records what that file used to
  have.

When the **current buffer is the only dirty file**, that splice is exact and reachability can be
recomputed soundly — negative facts are served, not withheld. Only when *another* file has moved
past the index does the graph have unknown holes, and only then do negatives degrade.

| State | Positive facts (callers, reached-by) | Negative facts (`UNREACHABLE`, `PASS`, dead code) |
|---|---|---|
| Tree matches index | served | served |
| Only the current buffer is dirty | served, fresh via splice | **served** — recomputed over the spliced graph |
| Another file is dirty | served, marked `STALE` | **withheld** — `UNKNOWN (stale)` |
| File absent from index | withheld | `NOT_INDEXED` |
| Language has no producer | withheld | `NOT_ANALYSED` |

One honest caveat: Merlin types the buffer against **stale `.cmi`** for its dependencies, so a
resolved callee can be wrong if a dependency's interface changed. That is the same trust level
Merlin itself offers the developer all day, and it is marked — but it means the splice is exact
with respect to *this file's* text, not with respect to the whole program's types.

That asymmetry — exact where evidence is fresh, withheld where it is not — is the whole design.

## Buffer freshness is a per-language property

The splice above is described in OCaml terms, but the mechanism differs per language and so does
the soundness it preserves. **Splice tier is a property of the (language, producer) pair and is
recorded in the coverage matrix** (`specs/reporting-and-integration.md` FR-002) alongside analysis
coverage — a consumer must be able to see which languages serve negatives while dirty and which
do not.

| Tier | Meaning | Languages |
|---|---|---|
| **A — overlay-native** | The producer's own engine accepts unsaved buffers. Splice is exact, soundness class unchanged, negatives served. | **Go**, **TypeScript** |
| **B — parallel engine, comparable fidelity** | A different engine types the buffer, but it is the same typechecker lineage as the producer. Splice is exact w.r.t. the buffer's text; marked. | **OCaml** |
| **C — parallel engine, lower fidelity** | The available buffer engine produces a strictly weaker fact than the producer. Splicing would blend soundness classes, which ADR 002 forbids. Positives only, marked `heuristic`; negatives withheld while dirty. | **Rust**, **Python** |

**Go (A).** `packages.Config` — the exact struct `callgraph-go` already builds at `main.go:417` —
carries `Overlay map[string][]byte`, documented for "unsaved files". Unsaved buffers flow through
the same `go/ssa` + CHA pipeline that produces the committed graph. Nothing new is trusted, so
negatives are served for any set of dirty files the overlay covers, not just one.

**TypeScript (A).** The producer already drives `typescript-language-server`, and the TS language
service is built around unsaved buffers. Same engine both ways.

**OCaml (B).** Merlin is the compiler frontend, so its typing is comparable to the `.cmt` the
producer reads — but it is a different binary reading possibly-stale `.cmi` for dependencies, so
the splice is exact for this file's text and not for the whole program's types.

**Rust (C).** The producer is `rustc_private` MIR **after monomorphization** — its precision comes
from the mono collector enumerating reachable instances and from `Instance::try_resolve`.
`rust-analyzer` does not run the monomorphization collector; its call information is a
strictly weaker, un-monomorphized fact. Splicing it onto a MIR-derived graph would silently mix a
`heuristic` fact into a `sound_with_top` one. Until a buffer engine of matching fidelity exists,
Rust serves positives only while dirty.

**Python (C).** Resolution is `heuristic` by ADR 002 regardless of freshness, so it can never
license a `PASS` and the splice buys nothing for negatives.

**Consequence for the roadmap.** Go and TypeScript are the cheapest first targets for `arch-lsp` —
overlay support already exists in libraries the producers use. OCaml needs a `merlin-lib`
integration. Rust needs no work, because the honest answer there is "positives only", and shipping
that is better than pretending otherwise.

- **FR-015** Every response records the splice tier applied for that file's language, and a Tier C
  language MUST NOT serve a negative fact derived from a dirty buffer.

## FR — protocol surface

- **FR-001** stdio JSON-RPC LSP server, `arch-lsp <db-path>`. Reuse `lib/jsonrpc_client`'s
  `stdio_transport`, which already exists for the client direction.
- **FR-002** `textDocument/hover` — blast radius for the symbol under the cursor: callers, tests
  that reach it, exported API affected, whether its cone escapes through a ⊤ edge. Every hover
  ends with the index generation and staleness state.
- **FR-003** `textDocument/publishDiagnostics` — architecture-rule violations from
  `arch-rules` (Warning for `POSSIBLE`, Error for `VIOLATION`, nothing for `UNKNOWN`), plus
  `unsafe_params` newtype candidates as Hints, plus raw-machine-arithmetic call sites as Hints
  where a discipline rule declares them forbidden for that path.
- **FR-004** `textDocument/codeLens` — per-function reachability counts and coverage/mutation
  status, computed from the existing read model.
- **FR-005** `textDocument/definition` and `references` are **not** implemented. The language's own
  LSP already does them better, and arch-index would be answering from a stale snapshot. Declare
  the capabilities absent so editors do not route those requests here.
- **FR-006** Every diagnostic and hover carries `source: "arch-index"` and the generation stamp.
  A `STALE` response says so in text a human reads, not only in a properties bag.

## FR — freshness

- **FR-010** The server watches the database file. A reindex is picked up without restart.
- **FR-011** `workspace/didChangeWatchedFiles` and `didSave` mark affected files stale immediately;
  the server does not wait for a reindex to start withholding negative facts.
- **FR-012** The server MUST NOT invoke a build. It reports staleness and offers a command
  (`arch-index.reindex`) the user or editor may run. A tool that silently triggers `dune build` on
  keystroke is a denial-of-service on the developer's machine.
- **FR-013** Buffer splicing (above) is what makes the server useful before incremental capture
  lands: the single-dirty-buffer case is the common one and is served exactly. Incremental capture
  (`modules.content_hash`, per-unit reindex) remains required for the multi-dirty-file case, which
  otherwise degrades to withholding negatives until the next build.
- **FR-014** The buffer splice MUST be marked in every response derived from it, and MUST record
  that dependency types came from possibly-stale `.cmi`.

## Non-goals

Type errors, completion, formatting, rename — the language's own server owns those. `arch-lsp` is
additive and expects to run alongside `ocamllsp`/`gopls`/`rust-analyzer`, not instead of them.
Note the symmetry: arch-index consumes those servers as a client today (`lsp_client.ml`), and
would now also be one.

## Consolidation

This is the third server surface after `arch-serve` (HTTP/SPA) and `arch-mcp` (stdio MCP). All
three MUST answer from the one read model in `lib/arch_tools` — the module that exists precisely so
no two consumers can disagree about how the graph is keyed or which edges are in a closure. A
fact shown in the editor, returned to an agent, and rendered in the report must be the same fact.

## Verification

- **CHECK-1a** Edit only the current buffer; assert negative verdicts are still served and are
  computed over the spliced graph — add a call in the buffer that makes a previously-dead function
  reachable, and assert the dead-code diagnostic disappears without a rebuild.
- **CHECK-1b** Dirty a second file; assert negative verdicts for the current buffer degrade to
  `UNKNOWN (stale)` while positive facts remain, marked stale.
- **CHECK-2** Open a file in a language with no producer; assert `NOT_ANALYSED`, not silence.
- **CHECK-3** Assert `definition`/`references` capabilities are advertised as absent.
- **CHECK-4** Reindex while the server runs; assert the generation stamp advances with no restart.
- **CHECK-5** Assert no code path in `arch-lsp` spawns a build.
- **CHECK-6** Same query via `arch-lsp`, `arch-mcp` and `arch-query` returns the same verdict.

## Open questions

1. Does the OCaml producer's `.cmt` dependency make per-save incremental reindex viable at Octez
   scale, or is the realistic cadence per-build? That determines whether FR-013 is a week or a
   quarter.
2. Should diagnostics be opt-in per rule? A repository with many `POSSIBLE` verdicts would flood
   the editor, and a flooded panel gets switched off — after which the tool is worse than absent.
