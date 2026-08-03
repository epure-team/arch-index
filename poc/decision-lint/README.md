# decision-lint — PoC for the static MC/DC dual

Proof of concept for [`docs/research/mcdc-coverage-feasibility.md`](../../docs/research/mcdc-coverage-feasibility.md).

Answers the question the design doc raised: **does the static dual of MC/DC find
real defects in real code, cheaply enough for CI?** The two reports say yes.

- [Report — arch-index](../../docs/research/mcdc-poc-report-arch-index.md)
- [Report — octez-manager](../../docs/research/mcdc-poc-report-octez-manager.md)

## What it does

Extracts every boolean **decision** from an OCaml source tree, canonicalises its
atomic **conditions**, and reports the ones that provably cannot influence the
outcome — on their own, or given the guards that hold on every path to them.

| finding | meaning | doc reference |
|---|---|---|
| `DEAD_SUBTERM` | a subterm can be replaced by a constant without changing the decision — removable | §3.3 |
| `CONSTANT_TRUE` / `CONSTANT_FALSE` | the decision has the same outcome under every input | §3.1 |
| `IMPLIED_TRUE` / `IMPLIED_FALSE` | an enclosing guard already settles the decision | §6.1 |
| `UNREACHABLE_PATH` | the guards leading here are mutually contradictory | §6.2 |
| `IDENTICAL_ARMS` | both branches of an `if` are structurally identical | §3.4 |
| `HIGH_ARITY` | above the enumeration budget: no verdict computed, reported not dropped | §6.8 / R8 |
| `SMT_*` | the same verdicts, proved by the solver where canonicalisation cannot reach | §6 |

## Running it

```sh
opam switch create . 5.3.0        # or any 5.3+ switch
dune build --root .

# Parsetree frontend — parses .ml sources, no build of the target required
./_build/default/bin/decision_lint.exe <dir> [<dir> …]

# Typedtree frontend — reads .cmt, so the target must have been BUILT
./_build/default/bin/decision_lint.exe --cmt <build-dir> [<build-dir> …]
```

Output is NDJSON on stdout either way.

## Two frontends, one engine

The atom payload is a small **frontend-neutral term IR** (§8.3 of the design
doc: *don't invent an IR — SMT-LIB already is one*). A frontend lowers its own
tree into it; canonical merging, the enumeration engine and the SMT encoder
consume it and never learn which tree produced it.

| | Parsetree (`.ml`) | Typedtree (`--cmt`) |
|---|---|---|
| needs the target built | no | **yes** |
| rung 1 (aliasing) | lexical scoping — drops aliases on `open`, and any unmodelled binder would be a false-positive source | **`Ident` stamps — sound.** A stamp is fresh per binder, so shadowing cannot merge two values and nothing needs unbinding |
| allowlist | qualified names, shadowable in principle | **resolved `Path`s — shadow-proof**, the same rule arch-index uses for noreturn heads |
| sees | what the author wrote | post-ppx code |
| purity join (`v_pure_functions`) | impossible — no resolved names | possible; **not implemented yet** |

**Cross-validated:** on `test/fixture.ml` both frontends produce the *identical*
set of 27 findings, and on arch-index both report the same 2 advisories and 0
defects. That agreement is the regression gate for the Typedtree frontend.

## Design

**Parsetree frontend.** The design doc computes this over the Typedtree, where
`Ident` stamps make shadowing safe for free. This PoC parses sources instead, so
it needs no build of the target. Rung 1 (alias/copy propagation) is recovered by
an explicit lexical environment: any binder that is not an alias-shaped `let`
*drops* the name, and an `open` drops every alias in scope, because it can rebind
a name with no pattern for the walk to see. Losing an alias is harmless; keeping
one across a shadow would be a false positive.

**Atom canonicalisation** — the merge ladder of §3.2:

| rung | what it merges | example caught |
|---|---|---|
| 0 | syntactically identical stable atoms | `a && b && a` |
| 1 | alias / copy chains | `let a = x in a && x` |
| 2 | structural normalisation: `not (not e)`, `e = true`, comparison orientation, commutative operand order | `a && not (not a)`, `k < x` ≡ `x > k` |
| 3 | same-subject integer comparisons, by interval semantics rather than free booleans | `x > 5 && x > 0` |
| 4 | **SMT** — coupling between syntactically different atoms | `s = "a" && s <> "a"`, `x > y && y > x`, `v = None && v = Some 3` |

### The SMT tier

SMT-LIB over a pipe to `z3` (§6.6 option B): the solver is an **optional runtime
dependency** — absent, the tier reports `UNKNOWN` and everything else still
works. `NO_SMT=1` disables it.

- **`(set-option :rlimit 2000000)`, never a wall-clock timeout** (§6.4). A gate
  that flaps across runners is worse than no gate; `rlimit` is a deterministic
  resource counter, reproducible on any machine.
- **Integers encode as `(_ BitVec 63)`, not `Int`** (§6.3). OCaml's native int
  wraps at 63 bits, so in LIA `x + 1 > x` is valid but *false* at `max_int` — an
  LIA encoding would prove real guards dead. The fixture pins this: `x + 1 > x`
  and `x + 1 <= x - 1` must both stay silent.
- **Abstract by freeness, never by assumption.** Anything unmodelled becomes a
  fresh constant. The only facts asserted are ones that hold in OCaml: distinct
  closed literals denote distinct values, and `String.length` is non-negative.
- **Escalation only.** The solver sees a decision when enumeration settled
  nothing *and* at least one atom carries relational content — when every atom is
  an opaque boolean the solver can prove nothing enumeration did not.
- **Content-addressed cache** keyed on the query text (§6.5).

**Stability predicate.** An atom is merged only if its value provably cannot
change between two evaluation points: identifiers, literals, constructors,
tuples, field projections, comparison/arithmetic operators, and a
**qualified-only** allowlist of pure stdlib calls. Any other application, `!`,
array access or mutation makes the atom unstable, and unstable atoms get a fresh
variable per occurrence — they can never merge. `!r && !r` correctly does not
fire.

**Budgets.** `cap_vars = 6` free boolean variables, `cap_combos = 4096`
enumeration combinations per decision. Above either, the decision reports
`UNKNOWN` and is counted in `unknown_over_cap` — never silently dropped.

## Validation

`test/fixture.ml` holds 22 known-slop cases and 12 cases that must stay silent.

```sh
./_build/default/bin/decision_lint.exe test
```

**22/22 true positives, 12/12 true negatives.** The fixture is the regression gate:
a change that loses a detection or gains a false positive shows up immediately.

Measured on the two corpora (see the reports): **17 verified defects, 0 false
positives** on octez-manager (351 files; 0.82 s enumeration, 10.7 s with SMT) and
**0 defects** on arch-index (41 files; 0.12 s / 0.90 s).

Three fixture bugs found during validation, each worth recording because each was
*the tool being right and the test being wrong*:

- `while true do … done` is the idiomatic OCaml unbounded loop, not a constant
  decision. It was flagged on the first run; it is now excluded by construction.
- `| m when m > 100 -> … | m when m > 5 -> …` is a legitimate descending
  cascade, not slop. The dead shape is the *ascending* one, where the first arm
  already caught everything the second tests for. The original fixture had the
  order backwards.
- `x + 1 <= x - 1` is **not** a contradiction in OCaml. Under 63-bit wrapping it
  is *true* at `max_int`, where `x + 1` becomes `min_int`. The fixture assumed
  LIA semantics; the BitVec encoding was right to stay silent. Both this and
  `x + 1 > x` are now pinned as true negatives.

## Known residuals

- **Rung 1 is scope-based, not stamp-based.** Sound for every binder the walker
  models (`let`, function params, `for`, `let*`, match/try arm patterns) plus
  `open`/`let module` clearing. A binding construct that is *not* modelled would
  be a false-positive source — the Typedtree frontend the design doc recommends
  removes this class entirely.
- **Purity is an allowlist, not an analysis.** The real design uses
  `v_pure_functions` / `arch-query pure-fns`. Here, 29.6 % of atoms on octez-manager
  and 52.6 % on arch-index are classified unstable and never merged — detection
  recall is left on the table, deliberately, to keep false positives at zero.
- **SMT `unknown` is a real outcome.** 57 decisions on arch-index exhausted the
  rlimit (0 on octez-manager) and carry no verdict from either tier. Counted and
  reported, never silently dropped.
- **The encoder models integers, equality and closed literals** — not strings as
  strings, records, or higher-order values, and it is intraprocedural, so
  `is_valid x && x <> None` needs a function summary it does not have.
- **One IPC round-trip per `check-sat`.** User CPU is 1.1 s of the 10.7 s
  octez-manager run; batching per decision is the obvious optimisation.
- **Path conditions are syntactic.** The guard stack is the lexical
  `if`/`when` nesting, not a computed dominator chain, so it misses facts that
  need a join. Under-approximating is the sound direction (§6.2).
- **Floats are not special-cased.** No finding in either corpus involved float
  comparison, but the NaN hazard of §6.3 is unhandled — a float atom is treated
  as an opaque boolean, which is sound here only because opaque atoms never
  merge.
