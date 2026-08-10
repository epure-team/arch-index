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

## Machine output contract (`--format json`)

`--format json` prints **exactly one JSON object** on stdout — no preamble, no log line; every
diagnostic goes to stderr. Every value in the tree is `null`/`bool`/`string`/int/array/object —
no floats, no exponent notation. Absence of data is stated, never implied: a field name never
disappears to mean "not applicable" — its sibling `computed`/`reason` pair says so explicitly.
**"Effects crossed"** (the text/md-only section — see the table above) has no JSON key yet; a
consumer that needs it today has to parse the `text`/`md` output, or query `function_effects`
directly.

| field | type | meaning |
|---|---|---|
| `computed` | bool | the reachability analysis ran (always `true` when this object is printed at all — kept as a field, not assumed, so a gate can require its presence rather than its absence of failure) |
| `contract_ok` | bool | same value as `sound_reachability`: is this index ⊤-marked, so the closed-cone claim is trustworthy. Computed by `Arch_db.contract_ok`, the same helper `arch-rules` uses for its own `contract_ok` — never `t.contract <> None` alone, which a flag-set-but-NULL-kind-edge index would satisfy while still being unsound |
| `verdict` | `"pass"` \| `"fail"` \| `"refused"` | the `--fail-on-new-findings` decision, restated so a consumer with only stdout reaches the same conclusion as one with only the exit code. `"pass"` when the flag was not requested at all (informational run) |
| `new_findings` | int | count of `findings.decisions` — the same number `--fail-on-new-findings` gates on |
| `findings.computed` | bool | did this index carry decision analysis at all (mirrors `decision_analysis_available`) |
| `findings.reason` | string \| null | set when `findings.computed` is `false` |

`verdict` and the exit code are two views of the same decision, kept in lockstep intentionally:

| exit code | `verdict` | meaning |
|---|---|---|
| 0 | `"pass"` | no gate requested, or requested and clean |
| 1 | `"fail"` | `--fail-on-new-findings` found a finding on a touched line |
| 3 | `"refused"` | `--fail-on-new-findings` was requested but this index carries no decision analysis — a gate whose input was never computed cannot report "clean" |

Exit code 2 (malformed input, or `Arch_db.Broken`) is an infrastructure failure, raised before the
JSON object is assembled — there is no stdout to parse on that path, by design: a consumer that
only reads stdout must never mistake "the tool crashed" for a considered verdict.

**A gate must read `verdict`, not `computed`, to catch a refusal.** Root-level `computed` is
`true` on every path that reaches the JSON print — including a `--fail-on-new-findings` refusal,
since the object is assembled and printed *before* the refusal check runs (the refusal only
decides the exit code and the `verdict` string; it happens too late to still be `false`).
`findings.computed` is the field that goes `false` on that path — but a caller who only checks
root `computed` (a plausible-looking but wrong choice) sees `true` straight through a refusal.
Any gate meant to enforce "this diff was actually judged, not waved through" must check `verdict
== "pass"` (which subsumes both `findings.computed` and `new_findings == 0`), not `computed`
alone.

All the richer fields (`touched`, `affected_exported`, `top_frontier`, …) are unchanged and remain
available for the same consumer that wants the full briefing, not just the gate decision. Every
list under this contract is printed **in full** — `--max-list`/the text-mode cap only apply to
the human-readable `text`/`md` formats, never to `--format json`. `findings.dead_sites` is
reserved for a future finding kind and is currently always `[]`.

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
# Decision Completion

`--fail-on-new-findings` accepts only a validated `decision_contract=v1`
completed run. A complete zero-finding run passes. Missing, stale, malformed,
or partial evidence produces JSON `verdict:"refused"` and exit 3; a new finding
produces `fail`/1 and a complete clean run produces `pass`/0. Unknown,
duplicate, missing-value, invalid-enum, and surplus CLI arguments exit 2.
