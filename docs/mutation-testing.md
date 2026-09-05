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

**Build hazard, not (fully) fixable in the dune stanza.** `tezt/tests/dune`'s `(test main)`
stanza lists every CLI under test in `(deps …)`, but on a `(test)` stanza `deps` attaches to the
`runtest` **alias**, not to building `main.exe` as a file target — that is dune's own semantics,
not a bug in this file, and there is no stanza-level way to make a scoped executable target pull
in extra link-irrelevant deps. Confirmed: after `dune clean`, `dune build tezt/tests/main.exe`
builds `main.exe` alone and leaves every CLI in `(deps …)` (e.g. `arch_mutants.exe`) unbuilt,
while a full `dune build --root=.` builds them all (each directory's own `@default` alias
builds its own executables, independent of the test stanza's deps). Consequences:

- **Never** `dune exec tezt/tests/main.exe` or `dune build tezt/tests/main.exe` (or any other
  scoped target under `tezt/tests/`) to run or check this suite — it silently tests whatever CLI
  binaries happened to be built by something else, possibly stale ones.
- Use `dune build --root=.` (full workspace build) followed by `dune runtest`, or `dune runtest`
  alone (which builds its own deps correctly through the `runtest` alias).
- A worktree whose CLIs were rebuilt piecemeal (e.g. only `main.exe` and `arch_rules.exe`) can
  have other CLIs (e.g. `arch_mutants.exe`) still missing or stale from a previous build. See
  `tezt/lib/arch_tezt.ml`'s `find_upwards`/`locate` for how a missing binary is now reported as a
  build error naming the search, rather than resolved by silently walking up into a sibling
  worktree or the parent checkout.

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
