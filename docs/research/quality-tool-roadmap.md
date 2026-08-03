# What arch-index should become: five additions, ranked by impact

**Date:** 2026-08-02. **Status:** all five shipped. **Question:** what turns
arch-index from a call-graph query tool into a code-quality **control and
assistance** tool?

| § | tool | docs | selftest |
|---|---|---|---|
| 3 | `arch-impact` | [change-impact.md](../change-impact.md) | `selftest-impact.sh` |
| 2 | `arch-rules` | [fitness-functions.md](../fitness-functions.md) | `selftest-rules.sh` |
| 1 | `arch-mutants` | [mutation-testing.md](../mutation-testing.md) | `selftest-mutants.sh` |
| 4 | `arch-coverage` | [coverage.md](../coverage.md) | `selftest-coverage.sh` |
| 5 | `arch_mcp` | [mcp-server.md](../mcp-server.md) | `selftest-mcp.sh` |

Three things changed against the plan below, each because building it exposed
something the proposal had assumed:

- **§2 was not "fully agnostic" as first written.** The Go backend emits
  `function` and `call` records only, so `module_deps` and `function_effects`
  rules are OCaml-only today. The correction is already folded into the §2
  section; the two rule families that *do* work on both backends turned out to
  be the two carrying the differentiator.
- **§1's ⊤ accounting was wrong twice** — once losing 8378 functions silently,
  once counting ⊤ edges outside the test cone. Both are recorded in
  `docs/mutation-testing.md`.
- **§5 needed a fix in `arch-query`, not in the server**: it defaulted to
  `sqlite3 -box`, so a one-line verdict reached the agent inside ~400
  box-drawing characters. `ARCH_QUERY_FORMAT` now exists for machine consumers.

Ranked by measured or reasoned impact. Cost is noted but was explicitly a
secondary criterion.

---

## The evidence this ranking rests on

Everything below is anchored in what the decision-lint work actually measured
across four corpora (arch-index, octez-manager, sarek, Octez):

- **The most productive defect class by far was tests that cannot fail** — 25 of
  ~34 verified findings. They are *covered*, they *pass*, and they assert
  nothing. No coverage metric can see them.
- **Long-lived review does not remove this class.** Octez's oldest survivor is
  from 2019, in one of the most reviewed OCaml codebases in existence.
- **The yield is in the one-time sweep, not the per-PR gate** — 1 PR in 25
  introduced a finding.
- **Adding a corpus was the highest-return test of the tool**, twice exposing a
  false-positive class that inspection had not.

What arch-index already owns that nothing else does: a **sound** call graph with
an explicit ⊤, three-verdict reachability (REACHABLE / UNREACHABLE / UNKNOWN),
per-function CFG post-dominance, and an effects/capability layer.

## The rule every proposal below is graded against

arch-index is not language-agnostic — **its contract is** (§8.1 of
`mcdc-coverage-feasibility.md`). Three layers, and only the first is per-language:

- **producers** — `callgraph-go/main.go` (`go/ssa`), `arch-callgraph-ocaml`
  (Typedtree/CMT), the LSP path (ocaml, typescript, rust, go, python);
- **a wire format** — NDJSON record types, now with the per-record-type `FIELDS`
  contract shipped in lot 3;
- **agnostic consumers** — the SQLite schema, `arch-query`, and everything built
  on top of them.

So each proposal is graded twice: what fraction of it is consumer-side (agnostic
the day it is written) and what per-language producer work it needs. Two facts
constrain the answers, both verified rather than assumed:

- The Go backend emits **`function` and `call` records only** — `exported`, and
  edge kinds. It does *not* populate `module_deps`, `function_effects` or
  `capabilities`; those come from the OCaml `.cmt` indexer
  (`lib/arch_index/arch_index.ml:205`).
- The "sound backend" class and the "decision-capable" class coincide (§8.2):
  Go SSA, OCaml CMT, and a future Rust MIR producer can carry this work;
  LSP-only languages (TypeScript, Python) cannot, and already cannot tag edge
  kinds.

A proposal that only needs reachability works on Go **today**. One that needs
module or effect facts needs a producer per language first — that is a real cost,
and it is priced in below rather than waved at.

---

## 1. Test-effectiveness analysis — mutation testing, targeted by the call graph

**Impact: highest.** The dominant defect class found in this whole line of work
is vacuous tests. `decision-lint` catches only the *syntactically* vacuous ones —
`result = 0 || result <> 0`, `assert (jit <> direct)`. The general case is a test
that executes the code and asserts something that would hold anyway. The
established way to detect that is **mutation testing**: change the program, rerun
the suite, and see whether any test notices.

**There is no mutation engine to build, in any language.** The category is mature
and per-language: [Mutaml](https://github.com/jmid/mutaml) (OCaml, PPX-based,
OCaml Software Foundation support), `go-mutesting`/`ooze` (Go), `cargo-mutants`
(Rust), `mutmut`/`cosmic-ray` (Python), Stryker (JS/TS/C#), PIT (Java). Each
mutates its own AST and reruns its own test runner. That is precisely the layer
arch-index should not enter.

**What arch-index uniquely contributes is targeting.** Mutation testing's
reputation is "too slow to use", because it mutates everything and reruns
everything. arch-index can cut both:

- **Mutate only what is reachable** from a test root, over MUST ∪ MAY_ENUMERATED.
  Code no test can reach needs no mutant — it needs a *dead-code* report instead,
  which arch-index already produces.
- **Rerun only the tests that reach the mutant.** A surviving mutant is then
  attributable: "this mutant in `f` survived, and these 3 tests reach `f`" — an
  actionable message rather than a percentage.
- **Escalate from the cheap tier.** Run `useless-branches` first; a decision
  already proved vacuous needs no mutant.

**Across languages.** The three bullets above are the whole proposal, and none of
them mentions a language: they are set operations over `calls`, `functions` and
reachability. What is per-language is a thin **adapter** on each side of the
targeting — telling the engine *which* mutation sites to keep (a file:line
allowlist, which every engine above accepts in some form), and mapping its
surviving-mutant report back onto `function_id`. Call it ~150 lines per engine.

The honest asymmetry: targeting is only *sound* where reachability is sound, so
this lands on Go and OCaml and stops at the LSP-only languages — where you can
still run the mutation engine, you just cannot claim the untested sites were
unreachable rather than unindexed.

**Cost: M–L.** One engine adapter (Mutaml first, since the corpus that produced
all the evidence is OCaml), a runner, and the attribution join; then ~150 lines
per additional engine. The real risk is wall-clock: mutation testing is expensive
by nature, and the call-graph targeting is exactly what makes it affordable
rather than a nice-to-have. Budget a nightly job, not a PR gate.

---

## 2. Architectural fitness functions over the *sound* graph

**Impact: high — and this is the "control" half of the request.** It is what
turns a query tool into a gate.

Architecture-rule enforcement is a mature category:
[ArchUnit](https://loiane.com/2026/07/architecture-testing-java-archunit/) (Java),
deptrac (PHP), import-linter (Python), go-arch-lint (Go). The pattern is called
an [architecture fitness function](https://aipatternbook.com/architecture-fitness-function):
an automated check that an architectural property still holds. Q1 2026 saw
ArchUnit 1.3 and Spring Modulith 1.4, so the category is consolidating.

**Every one of those tools checks declared imports.** That is a syntactic
over-approximation: it answers "does module A mention module B", not "can a call
in A reach B". arch-index answers the second question **soundly, with an explicit
unknown**:

```
rule "ui must not reach persistence"
  forbid reach from module:src/ui/** to module:lib/db/**
  verdict: UNREACHABLE = pass | REACHABLE = fail | UNKNOWN = fail-open + report
```

A rule that can answer `UNKNOWN` is strictly more honest than one that silently
returns "no violation" because the edge went through a callback it could not
resolve — and ⊤-marking is exactly what makes that verdict expressible. Layer
rules, capability rules ("no `Validate`-phase function may reach a `mint`
effect"), and API-surface rules ("nothing outside `lib/api` may be `exposed`")
all fall out of tables that already exist.

**Across languages — and a correction.** The rule language, the evaluator and the
reporter are pure consumers: agnostic the day they are written. But the *facts*
rules quantify over are not uniformly available, and it would be wrong to imply
otherwise:

| rule family | reads | Go backend today | note |
|---|---|---|---|
| reachability (`forbid reach from … to …`) | `calls` + edge kinds | ✅ works now | the sound core, and the one that beats ArchUnit |
| API surface (`nothing outside X may be exported`) | `functions.exported` | ✅ works now | Go emits `exported` |
| layering by module | `module_deps` | ❌ | OCaml `.cmt` only |
| capability/effect | `function_effects`, `capabilities` | ❌ | OCaml `.cmt` only |

The two families that already work on both backends are also the two that carry
the differentiator, because both hinge on the ⊤ frontier. Layer rules stated over
*module* dependencies are the ones every competing tool already does — and they
are the ones that need a per-language producer. So the multi-language story here
is better than it looks: the rules worth having port first.

Path-glob layering (`src/ui/**` → `lib/db/**`) is a third option that needs
nothing but `file_path`, works on every backend, and recovers most of what
`module_deps` layering buys.

**Cost: S–M.** A rules file, an evaluator over existing queries, a CI reporter.
Mostly SQL and glue. The hard part is not the code, it is the vocabulary. Add M
per language for a `module_deps`/effects producer if effect rules are wanted
beyond OCaml.

---

## 3. Change-impact analysis for reviewers and agents

**Impact: high — this is the "assistance" half**, and it is the cheapest of the
five relative to what it delivers, because every piece already exists.

Given a diff, answer the questions a reviewer or an agent actually has:

- which **exported** functions does this change reach, and how many;
- what **blast radius** over MUST ∪ MAY_ENUMERATED — and where the ⊤ frontier
  starts, i.e. what the analysis cannot see;
- which **effects and capabilities** the changed path crosses (payment, auth,
  state mutation);
- which **new findings** the diff introduces (`useless-branches`, `dead-blocks`),
  which is the ratchet the R5 measurement recommended;
- which **tests** reach the changed code — the same query mutation testing needs
  in §1.

The measurement that motivates this: only 1 PR in 25 introduces a finding, so a
per-PR *gate* is thin. But a per-PR **briefing** is valuable on every PR, gate or
not. "This 3-line change reaches 47 exported functions and crosses the signing
path" is the sentence a reviewer wants and no diff can produce.

**Across languages.** The most portable of the five. A diff is
`(file, line-range)`; `functions` already carries `file_path` and line bounds for
every backend; the closure queries are agnostic. **Nothing here is per-language**
— no parsing, no AST, no engine adapter. The blast-radius and ⊤-frontier bullets
work on Go the day they are written; only the effects bullet degrades to "not
available on this backend", and it should say so explicitly rather than print an
empty list.

**Cost: S–M.** Diff → changed function set → existing closure queries → a report.
The only new machinery is the diff-to-function mapping, and
`scripts/callgraph-diff.sh` is already a first draft of it.

---

## 4. Reachability-weighted coverage

**Impact: medium-high.** The `coverage` table in the schema is a stub nothing
writes to, and it is line-granular — the wrong shape. Line coverage answers "was
this executed", which the whole MC/DC study argued is the wrong question.

Cross a coverage report with the sound graph instead:

- of the functions **reachable from the exported API**, which are never
  exercised — API-relative coverage, far more meaningful than a global
  percentage;
- of the functions **reachable only through a ⊤ edge**, which the coverage tool
  claims to cover — a place where confidence is unwarranted;
- and the cross-check with §1: a function that is *covered* but whose mutants all
  survive is covered by tests that check nothing. That pairing is the honest
  replacement for a coverage percentage.

**Across languages — ingest LCOV, not bisect_ppx.** The join is generic; only the
report format is not, and the ecosystem already converged on one. bisect_ppx
emits LCOV (`bisect-ppx-report lcov`); so do `gcov`/`lcov` natively,
`go test -coverprofile` via `gcov2lcov`, `coverage.py` via `coverage lcov`,
`cargo-llvm-cov` via `--lcov`, and every JS tool via nyc. LCOV records are
`(file, line, hit-count)` — which joins to `functions.file_path` + line bounds on
**every** backend with no per-language code at all.

Ingesting bisect_ppx's native `.coverage` binary format would be marginally more
precise and OCaml-only; ingesting LCOV is one parser for every language. Take the
second. If per-point precision is later needed for OCaml specifically, add the
native reader as an optional refinement, not as the primary path.

**Cost: M.** An LCOV parser (small, the format is line-oriented and stable), a
line→function join, and queries. No analysis to invent, and no per-language work
beyond "run your coverage tool with `--lcov`".

---

## 5. A sound-verdict MCP server

**Impact: medium — an adoption multiplier, not a capability.** Ranked last
deliberately, and the search is why.

The MCP code-intelligence space is **crowded**:
[codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp) (158
languages, sub-ms queries, semantic vector search),
[CodeIndexer](https://lobehub.com/mcp/zilliztech-codeindexer),
[Sourcegraph MCP](https://sourcegraph.com/mcp), Claude Context. arch-index cannot
compete on breadth — two sound backends against 158 heuristic ones — and should
not try.

**None of them offers a sound verdict.** They do tree-sitter/LSP structural
indexing: "who calls what", best-effort, with dropped dynamic edges and no way to
say *I don't know*. arch-index's differentiator is exactly the thing an agent
most needs and most lacks: **an answer it can trust, and an explicit admission
when there isn't one.** An agent asking "can this handler reach `os.Exit`?" and
getting `UNKNOWN: MAY_TOP frontier at …` is far better served than one getting a
confident wrong "no".

So: expose `reaches`, `unreachable`, `escapes`, `dead-blocks`,
`useless-branches`, `mutation-density` and the §3 change-impact briefing as MCP
tools, and frame the product as *the sound one*, not *another index*.

**Across languages.** Fully agnostic — it exposes `arch-query`, which is a
consumer. The one design rule that matters is that the server must report *which
backend indexed the answer*, so an agent can tell "UNREACHABLE, proved over Go
SSA" from "UNREACHABLE, and this index has no edge kinds at all". The
`callgraph_contract` / `decision_contract` stamps already carry that; the server
just has to surface them instead of swallowing them.

**Cost: S.** The database and the CLI exist; this is a thin server over them.

---

## What I would deliberately not do

- **Clone/duplication detection.** Well served by existing tools, and arch-index
  has no soundness angle on it.
- **A third language backend.** The R9 contract now makes one mechanical, and
  Rust/MIR is the obvious candidate — but it is execution, not strategy, and it
  should follow a decision about which of the five above to build. Note the
  grading table: three of the five need *no* new backend to be multi-language,
  so a backend is not on the critical path for any of them.
- **Deepening the SMT tier.** Measured yield was 5 findings on one corpus, all of
  one shape. The cheap tiers and the purity join carry the analysis.
- **Anything gated on a percentage.** Every measurement in this branch argued
  against it, and §1's mutation score is the most tempting one to misuse: a
  mutation *score* is as gameable as a coverage percentage. Report surviving
  mutants with the tests that should have killed them; never a number with a
  threshold.

---

## Language grading, side by side

| | works on **every** backend as written | needs per-language work | what that work is |
|---|---|---|---|
| §1 mutation testing | targeting logic, attribution join | ✅ yes | ~150-line adapter per engine (Mutaml, cargo-mutants, go-mutesting, mutmut, Stryker); sound only where reachability is sound |
| §2 fitness functions | reach rules, API-surface rules, path-glob layering, the whole evaluator | partially | `module_deps`/effects producers, only if module-layer or capability rules are wanted beyond OCaml |
| §3 change impact | **everything** | ❌ none | — (effects bullet degrades to "not available", explicitly) |
| §4 coverage join | **everything, via LCOV** | ❌ none | — (users run their own coverage tool with `--lcov`) |
| §5 MCP server | **everything** | ❌ none | — (must surface the contract stamps) |

Three of the five are multi-language the day they are written. The fourth (§2)
is multi-language for exactly the rule families that constitute its
differentiator, and OCaml-only for the families every competitor already covers.
Only §1 has irreducible per-language work — and it is per-*engine* glue, not per
language analysis, because the mutation engines already exist everywhere.

That is the same shape as the decision-lint result reported earlier: **the
contract is agnostic, the producers are not** — and the deliberate consequence is
that four of five proposals sit on the agnostic side of that line.

## Suggested order

**§3 → §2 → §1 → §4 → §5.**

Change-impact first because it is the cheapest per unit of value, it makes the
tool useful on every PR rather than on every sweep, and it is fully agnostic.
Fitness functions second because they are what "control" means and the data for
the rules that matter is already there on both backends. Mutation testing third
because it has the highest ceiling but the highest cost, needs §3's
diff-to-function mapping, and is the only one carrying per-language glue.
Coverage fourth. MCP last, once there is something distinctive to expose.

The ordering is unchanged by the multi-language grading — which is itself the
useful signal: the cheapest and most valuable items were already the portable
ones, so nothing has to be traded off against breadth.

## Sources

- [mutaml — an OCaml mutation tester](https://github.com/jmid/mutaml)
- [awesome-mutation-testing](https://github.com/theofidry/awesome-mutation-testing)
  — the per-language engine survey §1 rests on
- [LCOV tracefile format](https://github.com/linux-test-project/lcov) — the
  cross-language coverage interchange §4 targets
- [Architecture Fitness Function](https://aipatternbook.com/architecture-fitness-function)
- [Architecture testing for Java with ArchUnit](https://loiane.com/2026/07/architecture-testing-java-archunit/)
- [codebase-memory-mcp](https://github.com/DeusData/codebase-memory-mcp)
- [Sourcegraph MCP](https://sourcegraph.com/mcp)
- [CodeIndexer](https://lobehub.com/mcp/zilliztech-codeindexer)
