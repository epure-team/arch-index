# Architecture fitness functions (`arch-rules`)

Automated checks that an architectural property still holds — the category ArchUnit (Java),
deptrac (PHP), import-linter (Python) and go-arch-lint (Go) established.

```sh
./arch-rules /tmp/repo.db arch-rules.txt
./arch-rules /tmp/repo.db arch-rules.txt --format md      # for a PR comment
./arch-rules /tmp/repo.db arch-rules.txt --on-unknown fail
```

## What is different here

**Every tool in that category checks declared imports.** That is a syntactic over-approximation:
it answers *does module A mention module B*, not *can a call in A reach B*. A layering violation
routed through a callback, an interface, or a function value is invisible to it — and so is a
`import` that is present but never actually used to cross the boundary.

`arch-rules` answers the semantic question over the sound call graph, and reports **four**
verdicts where other tools report two:

| verdict | meaning | exit |
|---|---|---|
| `VIOLATION` | a **MUST** path exists — this happens at runtime on that path | fail |
| `POSSIBLE` | reachable over MUST ∪ MAY_ENUMERATED — a dynamic dispatch could land there | fail (`--on-possible warn` to soften) |
| `UNKNOWN` | nothing found, but the cone escapes through a ⊤ edge — **nothing is proved** | warn (`--on-unknown fail` to harden) |
| `PASS` | proved unreachable in a closed universe | pass |
| `VACUOUS` | the selector matched no code | fail (`--on-vacuous warn` to soften) |
| `NOT_COMPUTED` | the index lacks the data this rule needs, so the rule was never evaluated | fail (`--on-not-computed warn` to soften) |

The interesting one is `UNKNOWN`. A rule that can answer it is strictly more honest than one
that silently returns "no violation" because the edge went through a callback it could not
resolve. ⊤-marking is what makes that verdict expressible at all.

`UNKNOWN` is **fail-open by default**, deliberately: a rule that blocks every PR whose cone
happens to touch a callback teaches people to delete the rule, which leaves them worse off than
a loud warning. `--on-unknown fail` is there for teams who have driven their ⊤ frontier down far
enough to want it.

`NOT_COMPUTED` goes the other way and fails by default, because it is not an analysis result at
all: the index carries no `function_effects` or `module_deps`, so the rule was not checked. A
rule that reads `n/a` on every run looks exactly like a rule that passes on every run, and it is
the one case the author can always resolve — populate the data, or delete the rule.

All four `--on-*` flags take exactly `fail` or `warn` and **abort on anything else**. Reading an
unrecognised value as "not fail" would mean a typo (`--on-possible fial`) silently removes the
check it names.

### PASS is a proof, and is refused when it would not be one

`PASS` means: no path over MUST ∪ MAY_ENUMERATED, **and** no ⊤ edge anywhere in the source cone,
**and** the index is ⊤-marked. On an index without the edge-kind contract the verdict degrades to
`UNKNOWN_NO_CONTRACT` — because in a graph that silently drops dynamic edges, "no path found" is
not evidence of anything. This is the same refusal `arch-query unreachable` makes.

### A vacuous rule is a failure

A rule whose selector matches nothing cannot fail, so it turns green forever the moment someone
renames a directory. That is worse than having no rule, because it looks like coverage. Vacuous
rules fail by default and are counted separately in the summary.

## Rule syntax

Line-oriented, `#` comments. One statement per rule.

```
rule "ui must not reach persistence"
  forbid reach from file:src/ui/** to file:lib/db/**

rule "only the api layer is exported"
  forbid exported outside file:lib/api/**

rule "the validate phase must not mutate global state"
  forbid effect from file:src/validate/** kind:GlobalVar

rule "core must not declare a dependency on the web framework"
  forbid dep from module:lib/core/** to module:Web.**
```

A malformed rule file **aborts** (exit 2). A rule that silently fails to parse is a gate that
silently stops gating.

### Selectors

| form | matches against |
|---|---|
| `file:<glob>` | the function's file path |
| `fn:<glob>` | the function's name |
| `module:<glob>` | file path, except in `forbid dep` where it is the declared module path |

Globs: `*` stops at `/`, `**` crosses it, and `**/` matches **whole directory components** — so
`**/parser.ml` matches `lib/parser.ml` and `parser.ml`, but never `lib/my_parser.ml`. That
boundary is not cosmetic: a rule aimed at one file silently covering a differently-named sibling
produces false verdicts in both directions.

## Which rules work on which backend

The rule language, the evaluator and the reporter are pure consumers — agnostic. The **facts**
they quantify over are not uniformly available:

| rule form | reads | Go backend | OCaml CMT | notes |
|---|---|---|---|---|
| `forbid reach` | `calls` + edge kinds | ✅ | ✅ | the sound core, and the one that beats declared-import checking |
| `forbid exported outside` | `functions.exported` | ✅ | ✅ | needs no reachability, so it is **exact** on any backend that records exports |
| `forbid effect` | `function_effects` | ❌ | ✅ | reports `NOT_COMPUTED` elsewhere, never a false clean |
| `forbid dep` | `module_deps` | ❌ | ✅ | this is the *declared-import* check — the syntactic one every other tool does |

The split is worth noticing: the two forms that work everywhere today are the two that carry the
differentiator, because both hinge on the ⊤ frontier. `forbid dep` — the one that needs a
per-language producer — is the one every competing tool already covers, and it says so in its own
output rather than pretending to be the semantic check.

Path-glob layering (`file:src/ui/**` → `file:lib/db/**`) needs nothing but `file_path`, works on
every backend, and recovers most of what module-level layering buys.

## Rules for arch-index itself

[`arch-rules.txt`](../arch-rules.txt) at the repo root, checked in CI against the self-index.

## Machine output contract (`--format json`)

`--format json` prints **exactly one JSON object** on stdout — no preamble, no log line; every
diagnostic goes to stderr. Every value in the tree is `null`/`bool`/`string`/int/array/object — no
floats. Absence of data is stated, never implied.

| field | type | meaning |
|---|---|---|
| `computed` | bool | the rule set was evaluated (always `true` when this object is printed) |
| `contract_ok` | bool | is this index ⊤-marked (the same fact that degrades `PASS` to `UNKNOWN_NO_CONTRACT` per rule) |
| `verdict` | `"pass"` \| `"fail"` | the same decision the exit code encodes — restated for a stdout-only consumer |
| `failing` | int | `= len(failed)` — how many rules count as failing under the current `--on-*` policy |
| `unknown` | int | rules verdicted `UNKNOWN` or `UNKNOWN_NO_CONTRACT` |
| `vacuous` | int | rules verdicted `NO_SOURCE` or `NO_TARGET` (a selector matched nothing) |
| `not_computed` | int | rules verdicted `NOT_COMPUTED` (the index lacks the data the rule form needs) |
| `results[].verdict` | string | the per-rule verdict, unchanged (`VIOLATION`/`POSSIBLE`/`UNKNOWN`/`UNKNOWN_NO_CONTRACT`/`PASS`/`NO_SOURCE`/`NO_TARGET`/`NOT_COMPUTED`) |
| `failed` | array of string | rule names counted failing — `failing` is its length, kept as a separate int field so a gate does not need to count an array |

**`verdict` is only ever `"pass"` or `"fail"`, never `"refused"`.** Unlike `arch-impact`,
`arch-rules` has no process-level sound-refusal path (no exit 3): an un-⊤-marked or data-less
index does not abort the whole run — it degrades the *individual rules that need that data* to
`UNKNOWN_NO_CONTRACT` / `NOT_COMPUTED`, and the existing `--on-unknown`/`--on-not-computed`
policies decide whether that counts as failing. A workflow gate consuming `arch-rules` output
should treat `failing == 0` as the pass condition and never expect a third verdict value from this
tool.
