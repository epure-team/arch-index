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

`arch-rules` answers the semantic question over the sound call graph, and reports **seven**
verdicts where other tools report two:

| verdict | meaning | exit |
|---|---|---|
| `VIOLATION` | a **MUST** path exists — this happens at runtime on that path | fail |
| `POSSIBLE` | reachable over MUST ∪ MAY_ENUMERATED — a dynamic dispatch could land there | fail (`--on-possible warn` to soften) |
| `UNKNOWN` | nothing found, but the cone escapes through a ⊤ edge — **nothing is proved** | warn (`--on-unknown fail` to harden) |
| `UNKNOWN_NO_CONTRACT` | nothing found, on an index that was never ⊤-marked — so nothing could have been proved for *any* rule on it. A different cause from `UNKNOWN` with a different fix: rebuild with a contract-stamping backend | warn (shares `--on-unknown`) |
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

`--on-vacuous` covers **all four** rule forms, and what counts as "matching nothing" differs by
form, because each quantifies over a different population:

| form | VACUOUS when |
|---|---|
| `forbid reach` | either selector matches no function (`NO_SOURCE` / `NO_TARGET`) |
| `forbid effect` | the source selector matches no function, so the cone is empty |
| `forbid exported` | **no function in the index is exported at all** — the rule quantifies over the empty set. An empty *selector* with exports present is a `VIOLATION` (every export is an offender), never downgraded |
| `forbid dep` | the **source** selector matches no module in the index |

`forbid dep` deliberately has no target-side vacuity check, unlike `forbid reach`. A `reach`
target ranges over functions that exist; a `dep` target ranges over module paths *already depended
on*. So "nothing matches `Web.**`" is not evidence of a typo — it is the rule succeeding, and
`forbid dep from module:lib/core/** to module:Web.**` is a preventive rule whose whole purpose is
to hold while nothing depends on `Web`. Calling that VACUOUS would fail the build precisely when
the codebase is clean.

### The summary line is two lines

The text and `md` summaries print a **census** and a **gate**, in that order:

```
4 rule(s): 1 proved, 0 violation, 0 possible, 3 unknown, 0 unknown-no-contract, 0 vacuous, 0 not-computed
gate: 0 failing — violation=always possible=fail unknown=warn vacuous=fail not-computed=fail
```

The first line is what the analysis **found**. Its counts partition the rules, so they sum to the
total and the line can be read as a whole. Every state is printed even at zero: a state that
appears only when non-zero cannot be told from a state the tool does not have, and `0 proved` is
the single most important thing this summary can say.

The second line is what the **policy did** with those verdicts. `failing` overlaps six of the
seven census counts, so it lives on its own line and is never added to them, and the flag values
shown are the ones **actually in force** for that invocation — not the defaults.

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

rule "protocol entry points gain no new fatal origin"
  forbid origin from file:src/proto_alpha/**/main.ml form:assert,division allow-file:crash-allow.txt
```

A malformed rule file **aborts** (exit 2). A rule that silently fails to parse is a gate that
silently stops gating.

### Selectors

| form | matches against |
|---|---|
| `file:<glob>` | the function's file path |
| `fn:<glob>` | the function's name |
| `module:<glob>` | file path, except in `forbid dep` where it is the declared module path |
| `ext:<glob>` | the name of an external leaf (a callee with no body in the index) — valid only as the **target** of `forbid reach` |
| `exported:<glob>` | the name of a function **on the API surface** — `fn:` restricted to nodes flagged exported. Valid only as the **source** of `forbid reach` |

`forbid origin` accepts `file:` and `fn:` only; `module:` and `ext:` abort (exit 2).
`forbid dep` accepts `module:` only, on both sides — including against `exported:`.

**Why `exported:` and not `entry:`.** The concept is already named three times in this
repository — `Arch_graph.node.exported`, `arch-query --roots exported`, and the
`forbid exported outside` rule form. A fourth spelling for one set is how two names for the same
thing come to disagree in the one place it matters. The rule verb and the selector kind are
different namespaces and cannot be confused by the parser.

The flag is normalised across the two schemas before any selector sees it: the MAIN schema's
column is `functions.exposed`, the FLAT schema's is `functions.exported`, and `Arch_graph` reads
both into `node.exported`. `exported:` selects through the node, never through SQL, which is what
keeps that normalisation in one place.

**`exported:` is granted per position, never inherited.** It is absent from `Arch_sel.structural`
— the list `arch-coverage` and `arch-mutants` pass — and lives in `Arch_sel.cone_source`, which
only `forbid reach`'s source uses. The hazard is the mirror of `ext:`'s, and `ext:` documents it
against itself: a selector answerable in one position only, accepted in another, matches a
population that position never ranges over, and the empty result is then reported as a **proof
rather than as vacuity** — a green nobody earned. A kind must be granted at each call site.

Globs: `*` stops at `/`, `**` crosses it, and `**/` matches **whole directory components** — so
`**/parser.ml` matches `lib/parser.ml` and `parser.ml`, but never `lib/my_parser.ml`. That
boundary is not cosmetic: a rule aimed at one file silently covering a differently-named sibling
produces false verdicts in both directions.

**`forbid dep` only accepts `module:` on either side — `file:` and `fn:` abort (exit 2).**
`forbid dep` never consults the call graph: both operands are globbed straight against strings
read out of `module_deps`, a table of declared module-to-module dependencies. `module:` is the
only selector kind whose reading of a `dep` operand matches what the syntax promises; `file:` and
`fn:` would be silently reinterpreted as module-path globs against a population they were never
written to describe, so they are refused rather than accepted and misapplied.

### `forbid origin` — a regression gate, and why it is an allow-list

`forbid origin from <sel> form:<f1,f2,...> [channel:<name>] allow-file:<path>` walks the forward
cone of `<sel>` and reports every escaping `exn_origins` site of the named forms, **on one error
channel**, that the allow-file does not cover.

**`channel:` defaults to `exception`, and the default is load-bearing.** `exn_origins` holds every
error channel, not just exceptions — on the `option` channel, "raising" means *returning `None`*.
Measured — on proto_alpha (`lib_protocol`, 500 `.cmt` indexed from `origin/main` `0982a42` with
`--errors-profile=tezos`) `form:raise` from `file:**/main.ml` sees **1** origin on `exception`,
**128** on `option` and **247** on `tzresult` — so the unscoped rule quantified over **376**
origins while appearing to police crashes. An independent reviewer measured 1 / 75 / 161 on their
own build of the same tree; both are internally consistent and the gap is corpus COVERAGE, not
disagreement — which is why a number here names its build state and not just its tree.

An unscoped rule reported an option-typed return as a crash site.

**And the `option` count was mostly not even that — until 3.14 removed the cause.**
The walker used to record a `None` origin for every **omitted optional argument** —
the `None` the type-checker synthesises, not one anyone wrote — so 51 % of the
functions carrying `option` origins had no real-position origin at all. Roadmap
3.14 stopped writing that class, so the counts above (**128** on `option`, **247**
on `tzresult`, **376** together) describe an index built **before** it; on a
current index the `option` figure is smaller, and the difference is the phantoms
rather than any change in the code being measured. The numbers are kept in their
pre-3.14 form because they are what the paragraph's argument was made from, and
re-deriving them would date the prose without dating the claim.

The default keeps that class out of the gate entirely. It was chosen because
`exception` is what a crash-surface rule means; that it also excluded a producer
artefact nobody had diagnosed yet is luck, and worth saying so rather than
claiming foresight — and it is why removing the artefact changes no verdict this
document reports.

Forms are `exn_origins.form`'s own vocabulary — and it is read from **the database's own `CHECK`
constraint**, not from a list in the tool. That matters because a column added to a table crashes
loudly while a **value added to an existing column's vocabulary is dropped in silence**: `form`
gained `inferred_bind` at schema 1.8 and `top_reason` gained `ambiguous_unit` at 1.9, and a tool
holding a list from before either would refuse a legal member while insisting it is not one — with
neither `has_col` nor a capability probe able to see it, since the column is present and the value
is the thing they never look at. So: a version is what a database *claims*, a column is what it
*has*, and a vocabulary is what the schema *declares*. An unknown form **aborts**: it would select nothing, and the rule would report a PASS while policing
an empty population. **So does an unknown `channel:`**, for the identical reason — measured before
it was fixed, `channel:banana` and `channel:result` produced byte-identical `[UNKNOWN] 0 origin(s)`
verdicts at exit 0, so a misspelling was indistinguishable from a genuinely clean channel. Unlike
`form:`, the vocabulary is not a schema `CHECK`: `exn_origins.channel` is free text whose members
come from the errors profile the **index** was built with, so the accepted set is the set of
channels that database contains, and the refusal lists them.

Selector kinds: **`file:` and `fn:` only.** An origin belongs to a function in a file; a module is
not a root a cone starts from, and an external leaf has no body to hold one.

**It is an allow-list, not a baseline, and there is deliberately no `--regenerate` flag.** A site
list can grow for three different reasons — a real regression, *widened coverage*, or a proof that
strengthened `MAY → MUST` — and a line-diff conflates all three. Only a person can tell them apart,
so the gate's job is to force the person, not to automate an excuse. An allow-list that a command
can regenerate is a baseline with extra ceremony: people run it blindly and the review property
evaporates. Extending the list must cost a deliberate edit.

Because the human always adjudicates, the failure message reports a **coverage figure** alongside
the sites — cone size, origins found, sites, and how many allow-entries matched nothing. Without it
a widened-coverage failure reads as a regression, and the third time that happens someone disables
the rule.

#### Allow-file format

```
fn | file:line | form | exn | ×N
```

Full-line `#` comments only — a trailing-comment rule is what truncates a path at its first `#`,
and that failure is *by deletion*: the line still parses, just shorter. `×N` may also be written
`xN`.

The line is split from the **right**: the last four fields are taken as `file:line`, `form`, `exn`
and the count, and the function name absorbs everything before them. OCaml operator names
legitimately contain `|` (`( |+| )` exists in this repository), and a left split requiring exactly
five fields made such a site permanently un-exemptable — worse, since a malformed allow-file
aborts, one such line copied from the tool's own output took every other rule in the file down
with it.

A **duplicate identity is refused**, naming both counts. It was previously accepted in silence with
first-wins, so the order of lines decided the verdict — and in an append-only workflow, which is
the one this design imposes, a corrected allowance appended at the end was silently ignored.

**The count is load-bearing, and a measurement put it there — a different one from the one this
document first claimed.**

The four fields were specified as a site identity and then tested rather than assumed. Re-derived
2026-09-05 with `GROUP BY … HAVING count(*) > 1`, on a table that carries **no** `UNIQUE`
constraint over these columns — so the probe could legitimately have returned zero, and did not:

| corpus (and build state) | origins | distinct identities | rows in colliding groups | worst group |
|---|---|---|---|---|
| proto_alpha, **all rows** | 30 526 | 5 305 | 26 901 (88 %) | 139 |
| proto_alpha, **rows with a real position** | 3 344 | 3 147 | **281 (8.4 %)** | **9** |
| octez-manager, all rows | 18 758 | 6 367 | 15 569 (83 %) | 118 |
| octez-manager, real position | 3 100 | 2 962 | **218 (7.0 %)** | **7** |
| whole `src`, all rows | 265 217 | 116 684 | 169 525 (64 %) | 139 |
| whole `src`, real position | 86 198 | 83 665 | **4 196 (4.9 %)** | **9** |

Indexes built by `origin/main` `0982a42`: proto_alpha (500 `.cmt`) and the whole
tree from `tezos/_build/default` with `--errors-profile=tezos`, octez-manager from
its own `_build/default`. Build state belongs beside the corpus name because how
many origins EXIST depends on which units were compiled.

**Read the second row of each pair, and here is why the first is misleading.** An
investigation into the `option` channel (roadmap 3.14) established that every
`line = 0` origin is a **phantom**: the walker records a `None` origin for each
*omitted optional argument*, the `None` that `Typecore.option_none` synthesises
during type-checking. Those are not `None` returns anyone wrote. Attribution was
measured at **100 %, zero residue, on two corpora** — proto_alpha 2 402 / 2 402.

> **A number withdrawn, 2026-09-05.** This sentence also read *"arch-index
> 394 / 394"*, and 394 reproduces on nothing. Re-derived with the `0982a42`
> producer over this repository's own `_build/default`, `line = 0` `option`
> origins are **245** for `_build/default/lib/arch_index` and **1 205** for the
> whole `_build/default`. A reviewer measuring the same two scopes on their own
> checkout got 253 and 1 310 — neither of us is wrong, and the gap is which units
> happened to be compiled, which is the point this page makes two paragraphs
> above and which the withdrawn figure did not carry. It is replaced rather than
> corrected because there is no build state under which it was right, so there is
> nothing to re-label. The attribution claim itself is unaffected: it was verified
> independently on proto_alpha, and the `arch-index` figure was only ever a second
> witness.

Within one function every such row collapses to `<fn> | <file>:0 | None`, so
2 158 functions yield **exactly 2 158 identities** — verified here, not assumed.
The 139-row worst group is one function's phantoms: `receipt_repr.ml`'s
`balance_and_update_encoding` is a **value**, not a function (`let … =` with no
parameter at `receipt_repr.ml:235`), so it cannot return `None` at all. Its 139
rows are the `?title`/`?description` omitted from the `Data_encoding`
combinators that build it.

**The decision this table supports is unchanged and the argument for it is now
narrower.** On rows that describe real code, the identity still collides 5–8 % of
the time with a worst group of **9** — nine origins sharing function, file, line,
form and exception. A count is still what stops an entry from being a *set*
exemption. But the 88 % figure argued the point from a producer artefact, and
would have become false the day 3.14's fix lands (a measured 2 322 → 402 rows,
−82.7 %).

**And the column does not rescue it**: 26 901 → 26 786 on proto_alpha, 169 525 → 166 584 on the
whole tree. Under half a percent. A worst group of 139 origins shares one function, file, line,
form and exception.

So no positional identity is unique, by a wide margin. Without a count an entry is a *set*
exemption whose membership can grow after review: a 140th origin on an already-exempted line would
inherit the decision taken about the first 139.

**An earlier revision of this document cited "25 479 origins, 1 150 collisions (4.5 %), 139
remaining with the column".** Those figures could not be reproduced on any corpus available here,
and the "139 remaining" appears to have fused two different quantities — 139 is the worst *group
size*, not a residual count. The correction runs in the safe direction: the real collision rate is
an order of magnitude worse and the column is nearly useless, so the decision to require a count is
more strongly supported than the numbers that were used to argue for it. That does not make citing
them acceptable, and they are corrected rather than quietly dropped.

Filtering to the population this gate actually polices tells the other half of the story: the
**37 crash-surface sites** reachable from proto_alpha's `main.ml` with forms `assert,division,index`
are **all ×1**, verified with this tool. A format that is a key on the population you demo and not
on the table it reads is exactly the shape that survives review.

The count is brittle to reformatting — but so is the line number it accompanies, and both fail
loud. Line-based identity is a known and accepted property of this class of gate.

#### Reading the output

Offender lines lead with their marker (`[new]`, `[was ×N]`) and end with the identity, so the
line a reviewer copies into the allow-file is the tail. That order is a safety property: a sloppy
paste that keeps the marker corrupts the *function name*, which simply fails to match and stays an
offender. Had the marker trailed, a sloppy paste would corrupt the **count** — the one field that
decides how much a line exempts.

#### What a PASS does and does not claim

On a real index the cone almost always escapes through a ⊤ edge, so this rule normally reports
`UNKNOWN`, not `PASS`, and says how many ⊤ edges it escaped through. That is the honest verdict:
the gate proves *no new site among those it can see*, never *no fatal origin exists*. `VIOLATION`
fails the gate regardless of ⊤, which is what makes it useful as a regression gate even when
completeness is out of reach.

An `exn_origins` table that is present but **empty** reports `NOT_COMPUTED` with its own message,
distinct from the absent-table case: an empty table is what a producer killed before the exception
pass looks like, and it must not read the same as a codebase with genuinely no origins.

## Which rules work on which backend

The rule language, the evaluator and the reporter are pure consumers — agnostic. The **facts**
they quantify over are not uniformly available:

| rule form | reads | Go backend | OCaml CMT | notes |
|---|---|---|---|---|
| `forbid reach` | `calls` + edge kinds | ✅ | ✅ | the sound core, and the one that beats declared-import checking |
| `forbid exported outside` | `functions.exported` | ✅ | ✅ | needs no reachability, so it is **exact** on any backend that records exports |
| `forbid effect` | `function_effects` | ❌ | ✅ | reports `NOT_COMPUTED` elsewhere, never a false clean |
| `forbid dep` | `module_deps` | ❌ | ✅ | this is the *declared-import* check — the syntactic one every other tool does |
| `forbid origin` | `exn_origins` | ❌ | ✅ | the crash-surface regression gate; `NOT_COMPUTED` elsewhere |

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
| `contract_ok` | bool | is this index ⊤-marked (the same fact that degrades `PASS` to `UNKNOWN_NO_CONTRACT` per rule). Computed by the same `Arch_db.contract_ok` helper `arch-impact` uses for its own `contract_ok` — the same index gets the same answer from both tools, never `t.contract <> None` alone (a flag set on an index with a NULL-kind edge is worse than no flag; see `Arch_db.require_contract`'s doc comment) |
| `verdict` | `"pass"` \| `"fail"` | the same decision the exit code encodes — restated for a stdout-only consumer |
| `failing` | int | **the gate, not a verdict.** `= len(failed)` — how many rules count as failing under the current `--on-*` policy. It is a policy-driven aggregate that OVERLAPS every census field below except `proved`, so it must never be added to them |
| `proved` | int | rules verdicted `PASS` |
| `violations` | int | rules verdicted `VIOLATION` |
| `possible` | int | rules verdicted `POSSIBLE` |
| `unknown` | int | rules verdicted `UNKNOWN` **or** `UNKNOWN_NO_CONTRACT` — the union, kept with its original meaning because gates read it. It is `unknown_escaping + unknown_no_contract` |
| `unknown_escaping` | int | rules verdicted `UNKNOWN`: the source cone reaches a ⊤ edge |
| `unknown_no_contract` | int | rules verdicted `UNKNOWN_NO_CONTRACT`: the index was never ⊤-marked, so nothing could have been proved for *any* rule on it. A different cause with a different fix — hence a separate number |
| `vacuous` | int | rules verdicted `NO_SOURCE` or `NO_TARGET` (a selector matched nothing) |
| `not_computed` | int | rules verdicted `NOT_COMPUTED` (the index lacks the data the rule form needs) |
| `results[].verdict` | string | the per-rule verdict, unchanged (`VIOLATION`/`POSSIBLE`/`UNKNOWN`/`UNKNOWN_NO_CONTRACT`/`PASS`/`NO_SOURCE`/`NO_TARGET`/`NOT_COMPUTED`) |
| `results[].detail` | array of string | the offending call paths / functions / dependencies, capped at 20 |
| `results[].detail_total` | int | the untruncated count `detail` was capped from — equal to `len(detail)` when nothing was cut, so a consumer never has to guess whether "20 shown" means "20 total" or "20 of 200" |
| `results[].witness` | array of string | for a `reach` rule verdicted `VIOLATION`/`POSSIBLE`/`UNKNOWN`, the concrete call path (source-to-target order) that produced the verdict — `VIOLATION` walks the same MUST-only edges its own proof used, `POSSIBLE` the wider MUST ∪ MAY_ENUMERATED cone, `UNKNOWN` the path to the nearest ⊤-holding caller (the same function `detail`'s first entry names). `[]` on every other verdict and every non-`reach` rule form, since none of those carry a reachability claim a path could illustrate |
| `results[].top_reasons` | array of string | for a `reach` rule verdicted `UNKNOWN`, the distinct `top_reason` values (roadmap 1.4's ⊤-anchor taxonomy) recorded on the `MAY_TOP` edge(s) the escaping cone hit. `[]` when no reason was recorded (or the verdict is anything else, including `UNKNOWN_NO_CONTRACT` — no specific edge is at fault there, the whole index was never ⊤-marked) |
| `failed` | array of string | rule names counted failing — `failing` is its length, kept as a separate int field so a gate does not need to count an array |

`proved`, `violations`, `possible`, `unknown_escaping`, `unknown_no_contract`, `vacuous` and
`not_computed` **partition** the rule set: every rule has exactly one verdict, so those seven sum
to `len(results)`. `unknown` is the one redundant field, retained for compatibility.

**`verdict` is only ever `"pass"` or `"fail"`, never `"refused"`.** Unlike `arch-impact`,
`arch-rules` has no process-level sound-refusal path (no exit 3): an un-⊤-marked or data-less
index does not abort the whole run — it degrades the *individual rules that need that data* to
`UNKNOWN_NO_CONTRACT` / `NOT_COMPUTED`, and the existing `--on-unknown`/`--on-not-computed`
policies decide whether that counts as failing. A workflow gate consuming `arch-rules` output
should treat `failing == 0` as the pass condition and never expect a third verdict value from this
tool.

## SARIF output (`--format sarif`)

`--format sarif` emits a single-run [SARIF 2.1.0](https://sarifweb.azurewebsites.net/) document —
the same information as `--format json`, in the shape GitHub code scanning (and any other SARIF
consumer) expects. This is roadmap item 2.1; the writer itself lives in
`lib/arch_tools/arch_sarif.ml` so item 2.2's `arch-report` reuses it rather than reimplementing
SARIF emission.

- **One `result` per rule verdict that is not `PASS`.** A `PASS` is a proof, not a finding, and
  putting proofs in the same list as violations is what CodeQL-style tools do that this project's
  design explicitly rejects.
- `ruleId` is the `arch-rules` rule name — TODAY this doubles as its human title, because the
  `.rules` DSL has no stable-id syntax of its own; renaming a rule's prose therefore closes its
  GitHub alerts and opens new ones (see `lib/arch_tools/arch_sarif.ml`'s doc comment on
  `rule_id`). `level`: `VIOLATION` → `error`, `POSSIBLE` → `warning`,
  every other verdict (`UNKNOWN`, `UNKNOWN_NO_CONTRACT`, `NOT_COMPUTED`, `NO_SOURCE`, `NO_TARGET`)
  → `note` — none of these is a proof of anything, but FR-024's "never silence" discipline applies
  to a single rule's own verdict too, not just to a whole language's coverage.
- Every result carries `properties.verdict` (the exact verdict string, e.g.
  `"UNKNOWN_NO_CONTRACT"` — `level` alone collapses five distinct "nothing proved" verdicts onto
  `note`) and `properties.detail_total` — the untruncated count `results[].locations` (see below)
  was capped from, the same `detail_total` fitness function as `--format json`'s (row above),
  reintroduced here so a SARIF consumer never has to guess whether 20 locations means 20 total or
  20 of 200.
- `results[].locations` carries the offending call paths/functions as SARIF
  `logicalLocations`/`physicalLocation` entries — but ONLY for `reach` and `exported` rules, whose
  `detail` rows are real display labels (`name` or `name  (file)`, from `Arch_graph.label`). A
  `dep` or `effect` rule's `detail` rows are free-form prose ("A --kind--> B  (line N)", "name
  KIND VALUE") — not locations — so `locations` is `[]` for those two rule forms; the same
  evidence is still readable in `message.text`, which always includes it. Absolute paths are
  emitted with no `uriBaseId`, so GitHub resolves them relative to the repository root rather than
  to a declared base — correct only when the index's own paths already are repo-relative (true of
  every producer in this repo today); a future producer that indexes with absolute filesystem
  paths would need a `uriBaseId` added here.
- An `UNKNOWN` result carries `properties.soundness = "unknown_top"` and, when known,
  `properties.top_reason` — the ⊤-anchor taxonomy values (see `results[].top_reasons` above) for
  the edge the cone actually hit.
- A rule's witness path (roadmap 1.5) becomes a `codeFlows` entry — one thread flow, one location
  per step — rather than a flat string, so a SARIF viewer renders it as a clickable path.
- `driver.name`/`driver.version` come from this index's own provenance
  (`producer_runs` on the main schema, `comment_db_meta` on the flat one — see `docs/schema.md`'s
  Provenance section), falling back to `"arch-index"` on a pre-1.2 index that recorded neither.
  `driver.rules` lists every distinct `ruleId` seen, `{id}` only — no `name`/`shortDescription`,
  so a consumer like GitHub shows the bare id rather than a richer catalogue entry.
- **The ⊤ frontier is a count, in `run.properties.top_frontier` — never a member of `results`.**
  A real corpus's ⊤ frontier is orders of magnitude past GitHub's 25 000-result cap (Octez alone
  carries 286k+ such edges); putting it in `results` would either get silently truncated or make
  every upload fail.
- `run.properties.category` and `automationDetails.id` are both stamped
  `"arch-index/rules"` — GitHub stopped merging SARIF runs that share `tool.driver.name` +
  category in one upload as of July 2025, so a caller emitting several analyses from one producer
  (2.2's `arch-report`, which calls the same `Arch_sarif` writer once per analysis) must give each
  a distinct category, or a second upload overwrites the first rather than merging with it.
- `run.properties.contract_ok`/`computed`/`proved` mirror `--format json`'s own top-level fields
  of the same name (see the table above) — without these, an all-`PASS` run and a run that
  evaluated nothing both produce a document with an empty `results` and no way to tell them apart.
- The `analysis_coverage` matrix (roadmap 1.3), when present, becomes `run.properties.coverage`;
  a `status = "not_analysed"` row becomes a `toolExecutionNotifications` entry on the run, never
  an absent section (spec FR-024). Its `descriptor.id` is `"not_analysed/<analysis>"`.
- `properties.soundness_class` is the ADR-002 class of the INDEX a result was computed against
  (`heuristic` / `sound_with_top` / `asserted`), read once per run and shared by every finding in
  it — not a per-finding ingestion fact. `arch-rules` always sets it on any index that carries the
  value (every plain `arch-load` output does, defaulting to `"heuristic"` with no
  `--soundness-class` flag): it is `None` only for a pre-1.2 MAIN index with neither
  `producer_runs.soundness_class` nor `comment_db_meta`'s key populated. A consumer filters on it
  per FR-022 to drop heuristic-derived findings.

Validated in CI against the vendored schema at `vendor/sarif/sarif-schema-2.1.0.json` (JSON
Schema draft-04) using python3's `jsonschema` library — see `tezt/tests/sarif_out.ml`'s header
comment for why that validator was chosen over the opam package of the same name.
