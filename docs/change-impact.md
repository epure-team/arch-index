# Change impact (`arch-impact`)

A per-diff briefing: what a change touches, who is affected, how far it reaches, and — the part
no other tool prints — **what the analysis cannot see about it**.

```sh
./arch-impact /tmp/repo.db --diff main...HEAD --repo /path/to/repo
./arch-impact /tmp/repo.db --files src/auth.go,src/session.go   # no git needed
./arch-impact /tmp/repo.db --diff HEAD~1..HEAD --format md      # for a PR comment
./arch-impact /tmp/repo.db --diff HEAD~1..HEAD --format json    # for an agent
```

## What it answers

| section | question |
|---|---|
| Touched functions | which indexed functions does this diff modify? |
| Who is affected | which functions — and which **exported** ones — can reach them? |
| Blast radius | what can the changed code reach? |
| ⊤ frontier | where does the analysis lose track, so the radius stops being a bound? |
| Tests reaching | which tests exercise the changed code? |
| Effects crossed | which mutations/capabilities does the changed path cross? |
| Findings introduced | does the diff touch a line carrying a dead-logic or dead-block finding? |

## Approximation direction — read this before reading a number

Both closures are computed over **MUST ∪ MAY_ENUMERATED**, with `MAY_TOP` (⊤) edges dropped.
Dropping them is what makes the closure computable, and a ⊤ edge could land anywhere. So:

> **Every count is a LOWER bound, in both directions.** Never a bound.

Anyone who reads "12 functions reach this change" as *twelve* will under-review the change. The
tool therefore prints two sets, not one:

- **DEFINITELY reach** — a resolved path exists. This is ground truth, not an estimate.
- **MAY reach through a ⊤ edge** — every function holding an unresolvable edge, plus everything
  that reaches one. A ⊤ edge means "may call anything", which includes the changed code.

Backwards that second set is enumerable, so it is enumerated. Forwards it is not (⊤ means
*anything*), so only the frontier itself is reported — the functions in the forward cone that hold
an escaping edge, which are precisely the places where the radius stops being trustworthy.

When the forward cone contains **no** ⊤ edge, the tool says so explicitly: the cone is closed and
the radius really is a bound. That is the same closed-universe condition `arch-query unreachable`
requires, and it is worth reading as a positive result.

**On an index without the edge-kind contract**, the lower bounds survive — dropping edges only
lowers a lower bound — but the closed-cone claim does not. "No ⊤ in the cone, therefore this is a
real bound" is precisely the inference a silently-dropped dynamic edge invalidates, so that one
claim is withheld and said to be withheld. Everything else still prints.

## Granularity: line spans

Mapping a hunk to a function needs the function's source span. Availability by producer:

| producer | spans | granularity |
|---|---|---|
| `arch-callgraph-ocaml` (CMT) | ✅ `functions.line_start/line_end` | line |
| `arch-callgraph-go` (`go/ssa`) | ✅ emitted in the NDJSON `function` record | line |
| any NDJSON producer | optional `line_start` / `line_end` | line if present, else file |
| LSP path | depends on the server's symbol ranges | varies |

Without spans the tool falls back to **whole-file** attribution and says so, per file, in the
report — it never silently over-attributes. A *half* span (`line_start` with no `line_end`) is
refused by `arch-load` outright: it would mis-map every hunk in the file, which is worse than
having no span at all.

Synthetic functions with no syntax to point at (Go wrappers, thunks, package `init`) carry no
span by design. Inventing one would attribute a diff hunk to a function the developer never wrote.

## Not a gate

The measurement in
[`docs/research/mcdc-poc-report-r5-hit-rate.md`](research/mcdc-poc-report-r5-hit-rate.md) found
**1 PR in 25** introduces a decision finding. That is too thin to justify blocking every PR — but
a *briefing* is worth printing on every PR, gate or not. "This 3-line change is reached by 47
exported functions and crosses the signing path" is the sentence a reviewer wants, and no diff
can produce it.

`--fail-on-new-findings` implements the ratchet anyway for teams that want it. It exits 1 only
when the diff touches a line that already carries a finding. It is off by default, deliberately.

## Honest-negative rules

Three distinctions the report never collapses, because collapsing them is how a tool becomes
untrustworthy:

- **"not computed" ≠ "nothing to report".** An index whose producer never ran the decision
  analysis says *not computed*. Table existence is not evidence — `arch-load` creates the
  `decisions` table unconditionally, so emptiness is checked, not presence.
- **"not in the index" ≠ "no impact".** A changed file the index does not know about is reported
  as UNKNOWN impact, per file.
- **"no test found" ≠ "untested".** If the test binary was not indexed, no test can be found; the
  report says to check what was indexed before concluding.
