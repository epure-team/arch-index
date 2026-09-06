# Mutation testing, targeted by the call graph (`arch-mutants`)

The dominant defect class found across four corpora in the decision-lint work was **tests that
cannot fail** — 25 of ~34 verified findings. They are covered, they pass, and they assert
nothing. No coverage metric can see them. `decision-lint` catches only the *syntactically*
vacuous ones; the general case is a test that runs the code and asserts something that would hold
anyway, and the established way to detect that is mutation testing.

## arch-index contains no mutation engine, on purpose

The category is mature and per-language:

| language | engine |
|---|---|
| OCaml | [Mutaml](https://github.com/jmid/mutaml) |
| Rust | `cargo-mutants` |
| Go | `go-mutesting`, `ooze` |
| Python | `mutmut`, `cosmic-ray` |
| JS/TS/C# | Stryker |
| Java | PIT |

Each mutates its own AST and drives its own test runner. Writing a seventh would be the least
useful thing this project could do.

What arch-index contributes is **targeting** — the reason mutation testing has a reputation for
being too slow to use. It mutates everything and reruns everything; the sound graph cuts both.

## `plan` — what is worth mutating

```sh
./arch-mutants plan /tmp/repo.db --tests 'file:test/**'
./arch-mutants plan /tmp/repo.db --tests 'file:test/**' --format lines > allowlist.txt
```

Every indexed function lands in **exactly one** bucket, and the report reconciles the total. A
plan that silently loses functions still looks complete, which is worse than one that admits a
gap:

- **targets** — test-reachable, with a source span, each carrying the tests that must rerun for
  it. That list is the rerun-selection input.
- **unreached** — no test reaches it. This needs a *dead-code* report, not a mutant: a survivor
  there tells you nothing you did not already know.
- **no source location** — reachable, but the index has no file (stdlib and dependency callees
  that appear only as edge targets). Nothing to mutate; counted so the numbers add up.
- **test roots** themselves.

Lines inside a target that already carry a dead-logic finding are flagged: the cheap tier settled
them, so they need no mutant. Escalating from `useless-branches` is the point of having a cheap
tier.

### When the plan is a proof, and when it is a heuristic

`unreached` is a **proof** only when the test cone is closed — no function reachable from a test
holds a ⊤ edge — and the index is ⊤-marked. Otherwise a ⊤ edge means "may call anything", so the
suite might in fact execute code listed as unreached, and the report says so:

```
• N function(s) no test is KNOWN to reach — a candidate list, not a proof
• the test cone escapes through M function(s) holding a ⊤ edge, so the suite may in fact
  execute code listed as unreached above. Targeting is a heuristic here, not a restriction
  you can trust
```

A ⊤ edge **outside** the test cone does not weaken anything — dynamic dispatch in code no test
touches cannot make an untested function secretly tested.

### Test roots

`--tests` takes an `arch-rules` selector (`file:test/**`, `fn:test_*`). Without it a name/path
heuristic runs and **announces itself**: a wrong test-root set silently changes every number
below it, so it must not pass for a decision. A selector matching nothing aborts rather than
reporting every function as unreached.

## `report` — attributing a survivor

```sh
./arch-mutants report /tmp/repo.db mutaml-report.json --from mutaml --tests 'file:test/**'
./arch-mutants report /tmp/repo.db mutants.ndjson --tests 'file:test/**'
```

For each surviving mutant: which function it is in (the **innermost** enclosing span — blaming an
enclosing function makes the developer hunt), and which tests reach that function and failed to
kill it. That is an actionable message:

```
• SURVIVED lib/x.ml:15  (a && b -> a || b)
    in check_bounds
    3 test(s) reach it and none killed it: test_lower, test_upper, test_roundtrip
```

versus, when nothing reaches it at all:

```
    NO test reaches it — this is not a weak test, it is untested code
```

A survivor that maps to no indexed function is **reported**, never dropped: a dropped survivor is
a defect that silently disappears.

### There is no mutation score

A mutation score is exactly as gameable as a coverage percentage, and every measurement in this
line of work argued against gating on either. This tool reports surviving mutants together with
the tests that should have killed them, and will never print a ratio. `--fail-on-survivors` is a
defect list being non-empty — not a threshold to tune.

The published verdicts make this sharper rather than looser: two of the six — `UNKNOWN` and
`UNKNOWN_NO_CONTRACT` — say *we do not know*. Any fraction built over them silently decides what
an unknown counts as, and whichever way it decides it is wrong for half its readers.
`scripts/check-no-score.sh` enforces the absence.

## `verdict` — what is actually published

```
arch-mutants verdict <db> [--campaign N] [--format text|json] [--max-list N]
```

`run` stores what the **engine** said. `verdict` publishes what the **tool** is willing to claim,
and the two are not the same value. The published verdict is **derived on every read and stored
nowhere**:

| stored `engine_status` | stored `selection_provenance` | published verdict |
|---|---|---|
| `KILLED` or `TIMEOUT` | any of the three | `KILLED` |
| `ERROR` | any of the three | `ERROR` |
| `SURVIVED` | `proved_superset` | `SURVIVED` |
| `SURVIVED` | `top_bounded` | `UNKNOWN` |
| `SURVIVED` | `no_contract` | `UNKNOWN_NO_CONTRACT` |
| *(no run row, in a campaign whose `completed_at` is NULL)* | *(none exists)* | `PENDING` |

The asymmetry is the whole point. A **kill is a proof**: the mutant died, and a wider selection
could only have killed it too, so no amount of shortfall in the selection weakens it. Only the
negative claim — "no test caught this" — depends on having run every test that could have, which
is exactly what `top_bounded` says you did not.

`PENDING` has no column and must never get one. It is the **absence** of a `mutant_runs` row
inside an open campaign, and storing it would widen a vocabulary closed to four values that this
tool's own bucketing depends on. A mutant that was never attempted reported as `SURVIVED` would
be a false accusation against a test that was never given the chance.

Two consequences worth stating because they are easy to get backwards:

- Every published verdict carries the provenance **of the run row that produced it**, joined by
  identity. Where no run row exists — a `PENDING` finding — both the status and the provenance are
  an explicit `null`, never the first value available elsewhere in the campaign.
- An index no campaign has ever run against **refuses**, exit 3, rather than publishing an empty
  verdict list. "Nothing ran" and "ran and found nothing" are different facts.

### An all-green mutation run proves nothing on its own (issue #77)

**A mutation run containing at least one RED self-certifies its greens.** A stale or wrong
binary cannot go red — it just answers plausibly. So if any mutant killed an assertion, that run
really did execute *that* binary, and the assertions that stayed green **in the same run** are
green under the mutant, not under a phantom. The corollary inverts the usual reading: **an
all-green mutation run proves nothing at all, whatever md5 you checked** — the first suspicion
should be "the experiment did not happen," not "the tests are weak." This matters most for
assertions that are *expected* to stay green for a structural reason unrelated to the mutant —
a stale binary imitates that result perfectly, and only a red in the same run dates it.

The md5 that matters is the CLI under test, e.g. `bin/arch_mutants/arch_mutants.exe` — a
CLI-only change never moves `tezt/tests/main.exe`'s own hash, so checking the wrong artefact's
hash gives false confidence.

**Build hazard, closed in `tezt/lib/dune`.** `tezt/tests/dune`'s `(test main)` stanza lists
every CLI under test in `(deps …)`, but on a `(test)` stanza `deps` attaches to the `runtest`
**alias**, not to building `main.exe` as a file target — that is dune's own semantics, not a bug
in this file. Measured (2026-09-06, base 6930d3c, agent worktree, dune 3.24.2, `(lang dune 3.15)`): after
`dune clean`, `dune build --root . tezt/tests/main.exe` produced `main.exe` and left
`_build/default/bin` with **0** `.exe` files.

An earlier version of this passage, and of the comment in `tezt/tests/dune`, said there was no
stanza-level way to make a scoped executable target pull in extra link-irrelevant deps. Issue
\#77's second comment refuted that with a prototype, reproduced here on the same procedure: a
`(rule)`'s `deps` are ordinary build-graph edges with no alias/target split. `tezt/lib/dune`
now carries such a rule — it generates `cli_paths.ml`, lists the 19 executables the suite drives
as its `deps`, and `tezt/lib/arch_tezt.ml` references the generated module. Same
clean-then-scoped-build procedure after that rule: **19** of 19 present.

`git grep "dune exec tezt/tests/main.exe"` and `git grep "does NOT rebuild a test"` over all
tracked files (2026-09-06) find the premise at **five** further live sites across four files,
listed below; each now carries a superseding note pointing here. Four are fully superseded; the
fifth only **partly**, because for `test/<t>.exe` nothing changed. The same search returns 8
lines in 7 files under `briefs/`, left alone as history:

| site | what it says |
|---|---|
| `specs/point-free-aliases.md:349` | "never `dune exec tezt/tests/main.exe`" |
| `specs/qualified-unit-resolution.md:314` | same, and cites `tezt/tests/dune:35-36` — a coordinate this branch invalidates |
| `specs/qualified-unit-resolution.md:377` | table row, marked superseded in place |
| `specs/reexport-resolution.md:535` | "never `dune exec` … demonstrated" |
| `scripts/mutate-check.sh:9-11` | states it as the script's *design rationale*, so it justifies the tool this document is about. **Partly** superseded only: for `test/<t>.exe` nothing changed |

Their in-session demonstrations were accurate for the trees they ran on: the premise changed,
not the observations. Separately, this branch's `+7` insertion in `arch_tezt.ml` invalidated
line citations into it: `git grep -E "arch_tezt\.ml:[0-9]+|tezt/tests/dune:[0-9]+"` counts 10
in `roster/` and 5 in `briefs/`, none of them corrected here — chasing them is unbounded and
neither area is live guidance. The 4 in `specs/` are.

### Scoping a run to one test

A mutation run must execute the test under study. `dune runtest` cannot be scoped to one file:
`dune runtest -- --file X` is refused (`"--file" does not match any known test`) and
`dune build @runtest -- --file X` is refused (`Don't know how to build --file`). Scoping is done
by running the test binary yourself. **This is the form to use.** `git grep "tezt/tests/main.exe"
-- scripts/ lib/ bin/ checks/` returns one non-doc hit, and it runs it this way too:
`checks/mid-caller-shadow-attribution.js:26` spawns `_build/default/tezt/tests/main.exe`
directly, scoping with `--title`. That search finds callers of the *binary*: a script driving the
suite through `dune runtest` need contain no `main.exe` at all and would not appear in it. That
is how `scripts/mutate-check.sh` (below) was missed — it contained no `main.exe` before this
commit added a note to it that mentions one, so the same command run today returns three hits in
two files, two of them inside that note.

```sh
dune build --root=.                                          # full, not scoped
./_build/default/tezt/tests/main.exe --file <file>.ml --keep-going
```

`scripts/mutate-check.sh` is the wrapper for a single mutant ("replaces a four-step manual
ritual with one command", `:2`; `0 = KILLED / 1 = SURVIVED / 2 = setup refused`, `:60-62`). Its
fifth argument is the test command, and **its default is the unscoped whole suite** —
`DEFAULT_TEST_CMD="dune runtest --root <repo>"` at `:76`. Pass the scoped form explicitly to
attribute the red to the test under study:

```sh
scripts/mutate-check.sh <file> <expected-count> <anchor> <replacement> \
  './_build/default/tezt/tests/main.exe --file <f>.ml --keep-going'
```

Its green-baseline check (`:104-107`) rules out a *pre-existing* red. It does not attribute a new
red to the right test: on the default command any red anywhere in the 227 returns KILLED.

Measured: `--file tezt/tests/helpers.ml --keep-going` ran `(1/2)`, `(2/2)`, exit 0. This form
reads no dune stanza, so no stanza edit can change it.

`--keep-going` is explicit here. The `(action)` field that supplies it to `dune runtest` belongs
to the `runtest` alias and is not consulted on this route.

#### On `dune exec` and scoped builds

`tezt/tests/dune` used to say "NEVER `dune exec tezt/tests/main.exe` or a scoped
`dune build tezt/tests/main.exe`", and gave its reason: a scoped build leaves the CLIs unbuilt,
so the suite runs against stale or absent binaries. **The `cli_paths.ml` rule removes that
premise** — the executables are dependencies of *compiling* `arch_tezt`, so they exist before
`main.exe` can be linked, let alone run.

Measured as a pair, and neither number means much without the other: after `dune clean`, a
scoped `dune build --root . tezt/tests/main.exe` left **19** `.exe` under
`_build/default/bin` and `_build/default/poc` (0 at merge-base); `dune exec --root=. tezt/tests/main.exe -- --keep-going` on that tree then
gave exit 0, `(227/227)`. The green is only evidence because the 19 says the binaries under it
were freshly built — a green on a tree carrying stale binaries is the failure mode this whole
section is about.

The recommendation is unchanged all the same: use the direct-binary form above for a scoped run
and `dune runtest` for the suite. `dune exec` is recorded as safe here rather than recommended,
and one difference on it is measured: `_build/default/tezt/tests/servers.version` is not
produced by a scoped build and did not exist during that run. No `.ml` under `tezt/` reads it;
it is a `deps` entry of the stanza.

`dune build --root=.` (full) followed by `dune runtest`, or `dune runtest` alone, remain the
right invocations for a whole-suite run. "`dune runtest` alone" was itself false at merge-base;
the rule above is what makes it true.

### What the rule does not close

- **It costs a compile, not a link.** `arch_tezt.ml` references the generated module, so
  `cli_paths.ml` is needed to **compile** the library. Measured, clean tree each side:
  `dune build --root . @tezt/lib/check` leaves **0** `.exe` under `_build/default/bin` and
  `_build/default/poc` at merge-base and **19** with the rule. Opening
  `tezt/lib` in an editor now builds every listed CLI. Accepted rather than fixed; moving the
  rule to a leaf library that only `main.exe` depends on would keep the edges and drop the cost,
  and is a direction, not a verified fix.
- **The generated module holds a `bool`, not paths.** `%{exe:…}` does not produce absolute
  paths — it expands to a **build-context-relative** one (`../../bin/arch_query/arch_query.exe`,
  measured with a throwaway rule). Three forms were available:
  - the relative expansion as-is. Byte-identical in every checkout of one commit, so it carries
    no cache hazard, and it would resolve from the suite's cwd. **Not taken, and no measurement
    argues against it**: it would bypass the runtime `locate` that reports a missing binary as a
    build error naming the search (issue #77 / PR #78), and one resolution path was preferred to
    two.
  - absolute paths — the stronger form issue #77 names. Producing them takes a `realpath`/`pwd`
    inside the action, and *that* is what makes the output checkout-dependent while the cache
    key — action text plus dep digests — stays checkout-independent; this machine carries a
    10 GB `~/.cache/dune`. Rejected on that reasoning, **not** on a measurement: no
    cross-checkout cache hit was demonstrated, and the runs above had `DUNE_CACHE=disabled`.
  - a constant. Chosen; the rule is wanted for its `deps`.
- **Two binaries the suite reaches are still outside dune's graph**:
  `callgraph-rust/target/release/arch-callgraph-rust` (cargo) and `bin/arch-callgraph-go` (go).
  `tezt/tests/coverage_matrix.ml` fabricates a `#!/bin/sh\nexit 0` stub for the first when it is
  absent, so that assertion exercises a real binary or a stub depending on prior build state.
  `bin/arch_callgraph_rust_merge/arch_callgraph_rust_merge.exe` was in the same position and
  **is** a dune target; it is now in the rule's `deps`, which is why the count above is 19.
- **Five paths resolve out of the source tree, load-bearingly.** Measured absent from
  `_build/default` after a clean scoped build and present in the source tree:
  `effects-schema-migration.sql`, the `arch-impact` wrapper, `scripts/pcc/pcc-index`,
  `callgraph-go/main.go`, `docs/curation-workflow.md`. `locate` finds them by climbing out of
  `_build/default`, which holds no `dune-project`. `architecture-schema.sql` is present in
  `_build/default` after the same build and does not rely on that climb.
- A worktree whose CLIs were rebuilt piecemeal can still have other CLIs missing or stale — the
  rule covers builds that go through `arch_tezt`, not every path by which a binary can end up on
  disk. See `tezt/lib/arch_tezt.ml`'s `find_upwards`/`locate` for how a missing binary is
  reported as a build error naming the search, rather than resolved by silently walking up into
  a sibling worktree or the parent checkout.

**A red run reports a lower bound unless the suite is told to keep going.** `tezt/tests/dune`'s
`(test main)` stanza carries `(action (run %{test} --keep-going))`. A/B on one tree
(2026-09-06, base 6930d3c) with two deliberately failing cases registered ahead of the other 227,
that field being the only difference: without it the run reported `(1/229, 1 failed)` and one
`FAILURE` line; with it, `(229/229, 2 failed)` and two. Both exited 1. The played count appears only in
each line's `(N/M)` prefix.

What this does and does not change for a mutation run. `scripts/mutate-check.sh` computes no
survivor list: it runs `$TEST_CMD`, branches on `$?` (`:119-123` SURVIVED, `:125` KILLED), and a red
suite exits 1 whether it truncated at case 1 or played all 229. So the flag moves no
KILLED/SURVIVED bit that wrapper produces. What it changes is what a human reads from a red run,
and any workflow that reads the failure set rather than the exit status: without it that set is a
lower bound, with no count saying how many cases never played.

## `run --diff <range>` — scoping a campaign to a change

Without `--diff` the selection is the **whole index**, and the report says so. There is no
implicit default range: a guessed range scopes a campaign the operator never asked for, and its
output is indistinguishable from a correct one.

With `--diff`, the selected mutant set is the **union** of three rules, each a different kind of
claim:

1. **Touched functions.** Mutants whose site falls inside a function the range touched. The
   diff → function mapping is not computed here — `arch-mutants` shells out to
   `arch-impact --format json` and reads its `touched` array, so the two tools cannot come to
   disagree about the same diff.
2. **Modified or added tests.** Mutants of every function reached by a test the range changed.
   Test **helpers** are included: a touched test-side function is walked *backward* to the cases
   that traverse it and only then forward, so a change to a shared helper selects everything
   those cases reach. Walking forward from the helper alone would select nothing at all when the
   helper is a leaf, which is what an assertion helper usually is.
3. **Deleted tests.** For a test a prior campaign attributed a kill to and which the current
   index no longer carries, every mutant that campaign attributed to it **alone** — exactly one
   `mutant_kills` row in that mutant's latest campaign, naming that test.

**Selection is by FUNCTION, never by file and never by line.** A comment-only change inside a
production function still selects that function's mutants. That over-selection is deliberate: the
alternative is parsing intent, and a selection that is too small turns a mutant an excluded test
would have killed into a survivor — a false accusation against a real test. The report states the
over-selection rather than presenting the selection as precise.

**The un-recheckable list is the honest half of rule 3.** A mutant killed in its latest campaign
with **no** kill row had an executed set larger than one and no engine naming the killer, so
nothing can say whether the deleted test was the only one catching it. Those mutants are reported
by name — never silently skipped, and never quietly re-run as if the question had been answered.

Mutants selected through a bounded test reach carry the **same** `selection_provenance` rules as
any other mutant. There is no separate accounting for them: a bound of a bound is still a bound,
and it is already labelled.

### Exit 3 from `arch-impact` means REFUSED, not failed

If the scoping subprocess exits 3 it declined to answer. `arch-mutants` propagates 3 and writes
**no campaign row**. It does not fall back to an empty touched-function set: an empty set selects
nothing and reads as *"nothing to test"*, which is the single worst way to lose the distinction
between "did not really run" and "ran and found nothing". Any other non-zero exit is a **failure**
and produces exit 2 — a different code for a different fact.

### What the scope does NOT constrain

The scope narrows the **driver's** accounting and the selection file the wrapper reads; it does
not narrow the **engine's** own loop, because `run` does not drive mutant generation. An engine
handed its full catalogue will still call the wrapper for an out-of-scope mutant, and the wrapper
refuses it (exit 2) rather than running the whole suite. No `mutant_runs` row is written for such
a mutant — the driver only records outcomes for mutants it selected — but the *engine's own*
report file will record its refusal in whatever terms that engine uses for a non-zero exit. Pass
the scoped allowlist (`arch-mutants plan --format lines`) to the engine's generation phase when
that matters.

## Input formats

**Generic** (NDJSON, one object per line) — the contract any engine adapter targets:

```json
{"file":"lib/x.ml","line":42,"status":"SURVIVED","id":"7","mutation":"a && b -> a || b"}
```

`status` ∈ `SURVIVED` | `KILLED` | `TIMEOUT` | `ERROR`. TIMEOUT counts as killed (the suite
noticed); ERROR counts neither way and is reported separately.

**Mutaml** (`--from mutaml`) reads `mutaml-report.json` — a bare JSON array of
`test_result = {status; mutant}` where `mutant = {number; repl; loc}` and `loc` is an OCaml
`Location.t`. One caveat, handled rather than assumed: mutaml's own sources disagree on `status`.
The type declares `int` (a raw exit code) while the runner maps exit codes to strings first. Both
encodings are accepted; **anything else aborts**, because guessing wrong here inverts every
verdict — a survived mutant read as killed is a defect silently deleted from the report.

## Adding an engine

~150 lines: map the engine's report to the generic record, and (optionally) accept the
`--format lines` allowlist on the way in. Nothing about the targeting logic is language-specific
— it is set operations over `calls`, `functions` and reachability. The one asymmetry is that
targeting is only *sound* where reachability is sound, so it lands on the Go and OCaml backends
and degrades to a heuristic on LSP-only languages, where the report will say `not a proof`.
