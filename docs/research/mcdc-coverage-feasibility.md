# MC/DC-grade coverage for arch-index: feasibility study

**Status:** research / read-only. **Date:** 2026-08-02. **Scope:** can arch-index
push its coverage model from "lines/points visited" toward a condition-level
model (MC/DC), and would that actually catch the failure mode we care about —
LLM-authored code with useless branches, unreachable arms, and redundant guards?
No source was modified.

Companion to [`control-flow-coverage-analysis.md`](control-flow-coverage-analysis.md),
which surveyed the same literature from the *reachability* angle and ranked MC/DC
as **R4, low leverage**. That verdict was correct *for the question it asked*
(does MC/DC improve MUST/MAY edge classification? — no, post-dominance already
does). This document asks a different question and reaches a different answer.

---

## Executive summary

**Yes, but not as a coverage metric.** MC/DC is a *test-adequacy* criterion: it
measures the test suite, not the code. Run as a metric, an unsatisfied MC/DC
obligation is ambiguous — it means either "the tests are weak" or "the condition
is useless", and the metric cannot tell you which. Gating on an MC/DC percentage
would therefore not detect agent-authored dead logic; worse, the cheapest way for
an agent to satisfy such a gate is to write tests that reach branches, not to
delete branches that shouldn't exist.

**The valuable half of MC/DC is its static dual.** MC/DC's core object is the
*independence pair*: for condition `c` in decision `D`, a pair of inputs
differing only in `c` that flips `D`'s outcome. Ask that question **statically**,
over the abstract boolean function rather than over a test suite, and the answer
becomes a proof rather than a measurement:

| independence pair for condition `c` | verdict |
|---|---|
| exists statically, observed dynamically | fine |
| exists statically, never observed | **test gap** — classic MC/DC shortfall |
| **provably does not exist** | **useless code** — `c` cannot affect anything, delete it |
| decision arity above cap / impure atom | `UNKNOWN` — never a gate failure |

Row 3 is the one the request is about, it needs **no tests, no instrumentation
and no runtime** — only the Typedtree arch-index already parses — and it is
decidable by enumeration because real decisions have ≤ 6 atomic conditions.

The whole check rests on knowing when two conditions are *the same* condition.
§3.2 grades that into four rungs, and the two cheapest ones already cover the
canonical LLM shape — rebinding a value to a friendlier name and then testing
both (`let a = x in if a && x then …`). That is aliasing, not semantic coupling,
and OCaml makes it near-trivial: immutable bindings mean no SSA and no dataflow
fixpoint, and unique `Ident` stamps make shadowing safe for free. It is also
**only correct on the Typedtree** — a Parsetree ppx has neither stamps nor
resolved paths, which is a positive argument that this check belongs in
arch-index rather than in a linter. §3.3 gives the test that stays correct once
occurrences are merged; the per-condition formulation of §3.1 does not.

**An SMT tier is worth it — for a reason other than the obvious one (§6).** The
tempting use, closing the residual coupling rungs 0–3 miss, is a small class. The
class only a solver can reach is **path-sensitive redundancy**: a check implied
or contradicted by the guards already established on every path to it
(`if x > 5 then … if x > 0 then …`, a `match` guard subsumed by an earlier arm).
Those atoms are syntactically *different*, so no canonicalization merges them —
and this is the most characteristic LLM shape there is, because a model generates
each block with only local context and re-validates what an enclosing branch
already guaranteed. It is also exactly what makes code unmaintainable: a reader
cannot tell which of two overlapping checks is load-bearing. It stays CI-fast by
taking path conditions from the **dominator chain** rather than by enumerating
paths — linear in nesting depth, not exponential in branch count — and by
caching verdicts content-addressed in the DB, so an unchanged decision never
reaches the solver.

**Three further findings from reading the code:**

1. arch-index **already computes** statically-unreachable basic blocks and throws
   the result away. `Arch_index_cfg.reachable` (`lib/arch_index/arch_index_cfg.mli:40`)
   is read only by the unit tests (`test/test_cfg.ml:62,82,95`); no production
   path consumes it — the sole indexing call site, `arch_index_cmt.ml:1109`, uses
   `always_exec` alone (which folds reachability in, so demotion is correct, but
   the *fact* that a block is dead never leaves the walker). Dead-block detection —
   one of the three things the request names — is a persistence-and-query change,
   not an analysis change. This is the cheapest win available.
2. **bisect_ppx cannot be upgraded to MC/DC by post-processing.** Its on-disk
   datum is one integer counter per source offset
   (`src/common/bisect_common.mli:26`), and independence pairs are provably not
   reconstructible from per-condition counters (§2.3, with counterexample). MC/DC
   requires recording *condition vectors per decision evaluation*. That is a new
   runtime datum, not a new report.
3. **In OCaml, MC/DC touches ~5% of decision sites.** A census of this repo
   (§4) finds ~1385 decision points, of which only ~73 are boolean decisions with
   more than one condition — the only places where MC/DC differs from plain
   decision coverage. MC/DC comes from DO-178C, i.e. from C and Ada, where
   compound `if` is the dominant control structure. In OCaml the dominant
   structure is `match`, where the right criterion is arm coverage plus
   exhaustiveness — and the compiler gives exhaustiveness away for free.

**It stays language-agnostic the same way arch-index already is (§8):** not by
being generic, but by keeping the *contract* generic and the producers specific.
The boolean engine, the SMT encoding, the cache and the queries are agnostic;
decision extraction, atom lowering and sort semantics are per-language — and
SMT-LIB is already the neutral IR, so nothing new needs inventing. The backends
that can carry this are exactly the ones that already carry edge kinds (Go SSA,
OCaml CMT, a future Rust MIR producer); the LSP-only languages cannot, which is
the fault line that already exists rather than a new one.

**Recommendation:** build the static tier (R1–R3), skip the dynamic tier until
the static tier has proven its hit rate on real agent output. Ranked plan in §10.

---

## 1. What arch-index has today

The `cfg-postdom-dominance` work (shipped, PR #9) put the hard part in place.

**`lib/arch_index/arch_index_cfg.ml`** — 143 lines, no Typedtree dependency:
int-indexed blocks, successor lists, a `terminate` marker for diverging
terminators, one virtual exit collecting terminal and diverging blocks, and
`solve` computing post-dominance by the iterative intersection fixpoint on the
reversed CFG (descending-index iteration, one reused scratch row). It exposes two
verdicts: `always_exec` (block post-dominates entry ∧ reachable) and `reachable`
(block reachable from entry).

**`lib/arch_index/arch_index_cmt.ml`** — the lowering. Every branching construct
is explicitly modelled: `Texp_ifthenelse` (`:759`), `Texp_match` with a
`Match_failure` bypass edge when the compiler marks the match `Partial` (`:778`),
`Texp_try` with a handler-dispatch block so handlers can never post-dominate
(`:800`), `Texp_while` (`:828`), `Texp_for` (`:846`), `Texp_assert` with the
`assert false` special case (`:860`), `Texp_letop` (`:871`), and short-circuit
`&&`/`||` at the `Texp_apply` level (`:994`). Lambdas are promoted to synthetic
nodes with their own CFG (`:683`).

**What this means for the request.** Two of the three named problems are already
one query away:

- *unreachable code* — `reachable` computes it per block, today, and discards it.
- *useless branching* — a conditional region whose blocks are all
  entry-unreachable is a branch that can never be taken.

What is genuinely missing is the third: a branch that *is* reachable but whose
*condition* cannot influence anything. That is the MC/DC-shaped question, and it
needs structure the CFG deliberately erases.

**The structural gap.** The lowering flattens boolean structure. In
`Texp_ifthenelse` the condition is walked as ordinary straight-line code
(`self.expr self cond`) and only *then* do the arms branch; `&&`/`||` are handled
generically at `Texp_apply` as "the right operand is a conditional region"
(`:994–1012`), correct for post-dominance but with no link back to the enclosing
`if`. After lowering, `if a && b then …` and `if a then (if b then …)` are the
same graph, and neither records that `a` and `b` are conditions *of one
decision*. There is no `decision` entity and no `condition` entity anywhere in
the codebase or the schema.

**Schema.** `architecture-schema.sql:148` has a `coverage` table — but it is
line-granular (`covered_lines`/`total_lines`) and **nothing writes to it**; the
only reference in the tree is the view name `v_low_coverage` in
`arch_index_support.ml:22`. It is a stub from the original epure extraction, and
it is the wrong shape for anything discussed here. Treat it as replaceable.

`dead-code` in `arch-query:373` is *function*-granularity (unreachable from
exported roots over MUST ∪ MAY_ENUMERATED ∪ MAY_TOP). It answers "is this
function ever called", never "is this branch ever taken".

---

## 2. What bisect_ppx actually measures

Read at `aantron/bisect_ppx@master`, `src/ppx/instrument.ml` (1803 lines) and
`src/common/bisect_common.mli`.

### 2.1 The data model

```ocaml
type instrumented_file = {
  filename : string;
  points   : int array;   (* byte offsets of the points placed in the file *)
  counts   : int array;   (* visitation counts, one for each point *)
}
```
— `src/common/bisect_common.mli:26`

One counter per source offset. Instrumentation is `___bisect_visit___ i; e` or
`___bisect_post_visit___ i e` (`instrument.ml:161`). There is no decision
identity, no outcome field, and no relation between points. Everything the
reporter can say is derived from this array.

### 2.2 Where the points go

| construct | rewriting | what you learn |
|---|---|---|
| `if c then a else b` | point on `a`, point on `b` (`:1386–1400`) | full decision coverage |
| `if c then a` | **`else` branch returns `None` — no point** (`:1391`) | **`c`-false is unobservable** |
| `a && b` | `a && (visit; b)` (`:1215–1223`) | `a` was true ≥ once. Nothing else |
| `a \|\| b` | `if a then (visit_a; true) else (if b then (visit_b; true) else false)` (`:1183–1210`) | `a`-true and `b`-true. Not `b`-false |
| `match` arms | point per arm RHS, **with or-pattern rotation** so `A \| B -> e` yields one point per constructor (`:215–300`, `:1350`) | genuine multi-way decision coverage |
| `try`, `while`, `for`, `function`, `letop` | point on body/arm entry | statement-level |

The or-pattern handling is the strongest part of the tool and is exactly right
for OCaml: it recovers per-constructor granularity that a naive arm counter
loses. The `if`-without-`else` hole and the `&&`/`||` treatment are the weak
parts — and they are precisely the sites where MC/DC would apply.

**Classification:** bisect_ppx is statement/point coverage with *partial* branch
coverage. It is not decision coverage (the missing implicit `else`), not
condition coverage (no false-outcome points), and structurally not MC/DC.

### 2.3 Why post-processing cannot close the gap

Per-condition counters do not determine MC/DC. Counterexample — decision
`D = a && b`, whose single bisect point `p` sits on `b`'s entry, so
`count(p) = #{evaluations where a was true}`:

- Suite A = `{(T,T), (T,T)}` → `count(p) = 2`. Condition `b` has **no**
  independence pair (no evaluation ever had `b = F`).
- Suite B = `{(T,T), (T,F)}` → `count(p) = 2`. Condition `b` **has** an
  independence pair: the two evaluations differ only in `b` and `D` flips.

Identical observable data, opposite MC/DC verdicts. No reporter, however clever,
can distinguish them. MC/DC is a property of the *set of evaluated condition
vectors*, and a bag of independent counters does not carry it.

What *is* sufficient is recording, per decision, the set of condition vectors
reached — `(vector, evaluated-mask, outcome)`. This is what LLVM's
`-fcoverage-mcdc` (Clang 18+) does: a per-decision test-vector bitmap, `2^n`
bits, with `n` capped (6 by default). Any OCaml MC/DC implementation must take
that shape.

**Consequence for OCaml short-circuit semantics.** `&&`/`||` always
short-circuit, so in `a && b` the vector `(a=F, b=?)` has `b` *unevaluated*.
Unique-cause MC/DC, which requires pairs differing in exactly one condition with
all others fixed, is unsatisfiable for many such decisions. DO-178C accepts a
second variant — **masking MC/DC** — where a condition may differ as long as it
is masked out of the outcome. For OCaml, masking MC/DC is the only sensible
target; unique-cause should not be offered. (Hayhurst et al., NASA/TM-2001-210876,
§5, treats both variants and the short-circuit interaction explicitly.)

---

## 3. The reframe: MC/DC's obligation as a static lint

### 3.1 The check

Let `D` be a decision with atomic conditions `c₁ … cₙ`, `n ≤ CAP` (default 6).
Interpret the atoms as free booleans and evaluate `D` under OCaml's
short-circuit order over all `2ⁿ` assignments, tracking which atoms are masked.

- **`D` constant** over every assignment → `CONSTANT_TRUE` / `CONSTANT_FALSE`.
  The branch is decorative: one arm is dead, the other always runs.
- **Atom `cᵢ` has no independence pair** — no assignment `v` with `cᵢ`
  unmasked in both `v[cᵢ:=0]` and `v[cᵢ:=1]` and `D` differing → `MASKED`.
  `cᵢ` provably cannot influence the outcome under any input.
- Otherwise → `INDEPENDENT`. This atom's MC/DC obligation is satisfiable, so a
  dynamic shortfall on it is an honest test gap.

Cost is `n · 2ⁿ` boolean evaluations per decision; at `n = 6` that is 384
operations, and the §4 census puts the whole repo at ~73 candidate decisions.
Above `CAP`, emit `UNKNOWN` — never a finding.

### 3.2 Atom identity: when are two conditions the same condition?

Everything above assumes we know which atom *occurrences* denote the same
*variable*. This is where the analysis's real power and its only false-positive
risk both live, and it is worth a ladder rather than a single rule. The canonical
LLM failure — rebinding a value to a friendlier name and then forgetting the
original is still in scope, `let a = x in if a && x then …` — sits on rung 1, not
in the SMT-hard tier.

**Rung 0 — syntactic identity.** Normalize the atom's Typedtree (drop locations
and attributes), hash it. Catches `a && a`, `x = 0 || x = 0`, and the guard
copy-pasted from the enclosing `if`. Free.

**Rung 1 — alias / copy propagation.** Maintain, during the existing `.cmt`
walk, an environment `Ident.stamp → canonical atom`: on
`Texp_let (Nonrecursive, [{vb_pat = Tpat_var id; vb_expr = e}], _)` with `e`
*stable* (below), record `stamp(id) ↦ canon(e)`; `canon (Texp_ident (Pident id))`
then follows the chain. This is classical copy propagation / global value
numbering (Alpern, Wegman & Zadeck, "Detecting Equality of Variables in
Programs," *POPL* 1988, <https://doi.org/10.1145/73560.73561>), and in OCaml it
is unusually cheap for three reasons:

- **Bindings are immutable.** `let a = x` means `a` *is* `x` for the whole scope.
  No reassignment ⇒ no SSA construction and no dataflow fixpoint; a single
  lexical pass with an environment suffices.
- **`Ident` stamps are unique per binder**, so shadowing is handled for free:
  `let a = x in let x = … in a && x` yields different stamps and no merge. The
  codebase already relies on exactly this property — `local_lam_stamps` keyed by
  `Ident.unique_name` (`arch_index_cmt.ml:733`), justified in
  `specs/cfg-postdom-dominance.md` C-12.
- **Mutation is explicit and enumerable**: `ref`/`!`, `mutable` record fields,
  arrays, and effectful calls. Everything else is stable by construction.

This rung is what makes `let a = x in if a && x` a *detected* redundancy rather
than a known blind spot, and it is roughly a few dozen lines.

**Rung 1 is only correct on the Typedtree.** A Parsetree-level ppx —
bisect_ppx's world — cannot do it: it has no `Ident` stamps, so it cannot tell
shadowing from aliasing, and no resolved paths, so it cannot tell `List.length`
from a locally-shadowed `length`. This is a positive argument that the check
belongs in arch-index's `.cmt` path and not in a linter ppx.

**Rung 2 — structural normalization.** Canonicalize before hashing: strip double
negation, rewrite `c = true`/`c <> false` to `c`, orient comparisons
(`k < x` → `x > k`), and sort operands of commutative equality. Catches
`a && not (not a)` and `x <> 0 || not (x = 0)`. Purely syntactic, no analysis.

**Rung 3 — same-subject relational atoms.** The second-most-common slop shape is
redundant bounds and null-ish checks: `i >= 0 && i < n && i >= 0`,
`n > 0 && n >= 1`, `x > 0 && x > 5`. These are not free booleans, but they are
also not general SMT: group atoms by *subject* (their canonical non-constant
side) and, for each subject whose atoms are all of the form `subject ⋈ constant`,
replace free-boolean semantics with **interval semantics** — enumerate the finite
set of regions the constants cut the ordered domain into instead of `2ⁿ` bit
vectors. Decidable, small, no solver dependency. This is one-variable difference
logic and it covers the overwhelming majority of real comparison coupling.

**Rung 4 — everything else** (`x + y > 0 && x > -y`, coupling through function
results, interprocedural `is_valid x && x <> None`). Needs a real decision
procedure or interprocedural summaries. **Out of scope: report `UNKNOWN`.**

**The stability predicate, which decides soundness.** Merge two occurrences only
when the expression is *stable* — its value provably cannot change between the
two evaluation points:

- Root is an immutable path, a literal, a constructor of stable arguments, or a
  comparison/boolean combination of such → stable.
- Contains `!`, a `mutable` field read, an array access, or an application of a
  function not provably pure → **not stable, never merge**. `read_flag () &&
  read_flag ()` must stay two independent variables; merging it would
  manufacture a false redundancy claim.
- The purity side already exists and is already sound: `v_pure_functions` /
  `arch-query pure-fns` (`arch-query:316`) defines purity as *not* in the
  backward closure over MUST ∪ MAY_ENUMERATED seeded by direct-effect functions
  and by functions with an outgoing MAY_TOP edge** — i.e. ⊤ blocks purity
  certification. That is exactly the conservatism this rule needs, and it comes
  for free on any index that carries the effects tables.

**Effects survive redundancy.** A subterm can be redundant *as a boolean* while
still mattering: in `f () && (a || g ())`, proving `(a || g ())` value-irrelevant
does not make it deletable — that would drop the call to `g`. So an
impure-but-value-irrelevant subterm is reported `UNKNOWN` (or at most an advisory
"the value of this expression is never used"), never `MASKED`. And the tool
**reports, never rewrites**.

Net effect: rungs 0–2 are cheap and cover the aliasing family including the case
that motivated this section; rung 3 is bounded and covers the comparison family;
rung 4 is honestly declined. The analysis stays a **sound under-approximation of
redundancy** — it misses real redundancy above its rung, and never claims
redundancy that is not there. For a check whose output is "delete this code",
that is the only acceptable direction of error.

### 3.3 The correct test once conditions can be coupled

Merging occurrences breaks the classical MC/DC framing, and §3.1's per-condition
independence test must be refined — MC/DC is *defined* for pairwise-independent
conditions, and coupled conditions are its documented hard case (Chilenski &
Miller 1994, §"coupled conditions"). With `n` occurrences over `m ≤ n` variables,
occurrences of the same variable move together and cannot be flipped
individually, so "flip `cᵢ`, hold the rest" is not a well-defined operation.

The right generalization is a **subterm-substitution test**, applied to every
subterm `s` of the decision (leaves included), over all `2ᵐ` assignments to the
canonical *variables*:

> `s` is **dead logic** iff `D ≡ D[s := true]` or `D ≡ D[s := false]` as
> functions over the `m` variables.

Worked cases:

| decision | subterm | result |
|---|---|---|
| `X && X` (after rung 1 merges `a` and `x`) | 2nd occurrence | `D[s:=true] = X ≡ D` → **dead** |
| `a && b` | `b` | `D[s:=true] = a ≢ D`, `D[s:=false] = false ≢ D` → live |
| `a && (a \|\| b)` | `(a \|\| b)` | `D[s:=true] = a ≡ D` → **dead**, whole disjunct |
| `x \|\| not x` | whole decision | constant → `CONSTANT_TRUE` |

**Detection needs only the leaves; subterms decide the reporting scope.** An
earlier draft claimed the leaf test would miss row 3 because neither `a`
occurrence is individually deletable. That is false — substituting `true` for the
inner `a` gives `a && (true || b) ≡ a ≡ D`, so the leaf test does fire. Checked
by enumeration: over **all 182 712 formulas of depth ≤ 3 on 2 variables**,
180 780 have a dead proper subterm and **none of them lacks a dead leaf**; a
randomized sweep at depth 4 on 4 variables (300 000 formulas, 134 532 with a dead
subterm) also found none. Empirical, not proved — but strong enough to design on.

Two consequences, both good:

- **Cost drops** from `|subterms| · 2ᵐ` to `n · 2ᵐ`: run the test on leaves to
  *detect*, which at `m = 6` and `n = 6` is 384 boolean operations per decision,
  over ~73 decisions repo-wide (§4).
- **Subterms still matter for the report.** Once a leaf fires, walk *outward* to
  the largest enclosing dead subterm and report that — "delete this whole
  disjunct" is a far more actionable finding than "this one occurrence of `a` is
  redundant". Detection is leaf-driven, presentation is subterm-driven.

This is the boolean-logic analogue of an untestable stuck-at fault in
combinational test generation: a signal whose value cannot propagate to the
output is exactly a redundant gate — the same duality between *coverage* and
*redundancy* the whole document turns on. A BDD is the textbook representation,
but at this size a truth table is simpler and faster.

Verdict vocabulary for `decisions.verdict` / `conditions.verdict` (§5) gains
`DEAD_SUBTERM`; `MASKED` retains its §3.1 meaning for the uncoupled case.

### 3.4 Sibling checks that ride along

Once decisions are first-class entities, three more agent-slop detectors are
nearly free and share the reporting surface:

- **Identical arms** — `if c then e else e`, or two `match` arms with
  structurally equal bodies and no guard. Structural equality on the Typedtree,
  modulo locations.
- **Dead blocks** — `Arch_index_cfg.reachable = false`, already computed (§1).
- **Redundant match arms and inexhaustive matches** — the OCaml compiler already
  finds these: warning 11 (`this match case is unused`), warning 8 (`this pattern
  matching is not exhaustive`), warnings 26/27 (unused `let`/variable), 32–39
  (unused declarations). An agent that adds an arm the type system proves
  unreachable is caught by the compiler for zero implementation cost. The repo's
  `dune` files carry no explicit `flags` stanza, so this depends entirely on the
  active dune profile — CI runs `dune build` in dev, which promotes these, but
  the release profile does not. **Make it explicit** rather than implicit: an
  `(env (dev (flags ...)))` or per-library `(flags (:standard -w +8+11+26+27 -warn-error +8+11))`
  stanza, so the guarantee survives a profile change. Cost: one stanza; this is
  the highest value-per-line item in the whole document.

---

## 4. How much of this codebase would MC/DC even touch?

Grep census over `lib/` + `bin/` (36 files, 8558 lines). **Approximate**: counts
include occurrences in comments and strings, and multi-line conditions with
`&&` on a continuation line are undercounted. Directionally reliable, not exact.

| construct | count |
|---|---|
| `if` | 341 |
| `match` / `function` | 487 |
| match arms (`\| pat ->`) | 991 |
| `when` guards | 53 |
| `&&` occurrences | 147 |
| `\|\|` occurrences | 63 |
| **`if` lines containing `&&` or `\|\|`** | **73** |

Decision sites total ≈ 341 `if` + 991 arms + 53 guards ≈ **1385**. Boolean
decisions with more than one condition — the *only* sites where MC/DC differs
from decision coverage — ≈ **73**, i.e. **~5% of all decision sites and ~19% of
boolean decisions**.

Two conclusions:

1. **MC/DC is a narrow instrument here.** Four fifths of this codebase's
   branching is pattern matching, where MC/DC has nothing to say and where the
   type checker plus arm coverage already do the work. Anyone proposing "let's do
   MC/DC" for an OCaml codebase should see this number first.
2. **But 73 sites is a tractable, high-signal target.** Compound boolean guards
   are exactly where a language model bolts on a plausible-looking extra
   conjunct, and 73 sites is small enough that a `MASKED` finding can be reviewed
   by a human every time it fires. The check earns its place as a *lint with a
   near-zero false-positive budget*, not as a coverage percentage.

The same census should be re-run on the target corpus before committing: a
codebase with heavy validation or protocol logic will skew far more `if`-heavy
than this one.

### 4.1 Measured figures (supersede the grep estimate)

The PoC (§11) parses the sources properly and reports the real numbers. **The
grep census above undercounts**, mainly because it misses conditions whose
`&&`/`||` sits on a continuation line:

| | arch-index | octez-manager |
|---|---|---|
| boolean decisions (`if`/`while`/`assert`/`when`/short-circuit) | 385 | 3 728 |
| multi-condition, i.e. where MC/DC differs from decision coverage | **147 (38.2 %)** | **925 (24.8 %)** |
| atoms the conservative purity predicate refuses to merge | 52.6 % | 29.6 % |

So the share of *boolean* decisions that are multi-condition is roughly **25–38 %**,
not the ~19 % estimated above. The doc's conclusion is unchanged — once `match`
arms enter the denominator, multi-condition booleans remain a minority of all
decision sites, and the OCaml-specific value still concentrates in
arm/exhaustiveness checking — but the boolean half is a larger target than the
grep suggested.

---

## 5. Data model

Three static tables, one dynamic. Independent of the `coverage` stub (§1), which
should be dropped or left to rot.

```sql
-- One row per branching site.
CREATE TABLE decisions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  function_id   INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
  site          TEXT NOT NULL,   -- file:line:col of the decision root, 1-based col
  form          TEXT NOT NULL,   -- if | match | while | for | guard | assert | try
  arity         INTEGER NOT NULL,-- # atomic conditions (0 for a pure match)
  n_outcomes    INTEGER NOT NULL,-- 2 for boolean, #arms for match
  verdict       TEXT NOT NULL    -- OK | CONSTANT_TRUE | CONSTANT_FALSE
                                 --  | DEAD_SUBTERM | IDENTICAL_ARMS | UNKNOWN
);

-- One row per atomic condition of a boolean decision.
CREATE TABLE conditions (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  decision_id   INTEGER NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
  ordinal       INTEGER NOT NULL,  -- short-circuit evaluation order, 0-based
  site          TEXT NOT NULL,
  atom_key      TEXT,              -- canonical variable id after §3.2 merging;
                                   -- NULL when the atom is not stable
  merge_rung    INTEGER NOT NULL,  -- 0..4: which §3.2 rung assigned atom_key
  verdict       TEXT NOT NULL,     -- INDEPENDENT | MASKED | DEAD_SUBTERM | UNKNOWN
  decided_by    TEXT NOT NULL,     -- 'enumeration' | 'smt' | 'budget_exhausted'
                                   -- | 'no_solver'  (§6.4: degradation is never silent)
  evidence      TEXT               -- §6.7: unsat core as guard sites, or a sat
                                   -- model. NULL for enumeration verdicts
);

-- One row per CFG basic block. Persists what solve() already computes.
CREATE TABLE blocks (
  id              INTEGER PRIMARY KEY AUTOINCREMENT,
  function_id     INTEGER NOT NULL REFERENCES functions(id) ON DELETE CASCADE,
  block_index     INTEGER NOT NULL,
  site            TEXT,
  always_exec     BOOLEAN NOT NULL,
  entry_reachable BOOLEAN NOT NULL
);

-- Dynamic tier only (§7). One row per distinct observed condition vector.
CREATE TABLE decision_vectors (
  decision_id INTEGER NOT NULL REFERENCES decisions(id) ON DELETE CASCADE,
  vector      INTEGER NOT NULL,  -- bitmask over conditions.ordinal
  mask        INTEGER NOT NULL,  -- 1 = condition was actually evaluated
  outcome     INTEGER NOT NULL,
  hits        INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (decision_id, vector, mask, outcome)
);
```

Query surface, following `arch-query`'s existing subcommand style:

```
useless-branches       conditions.verdict IN ('MASKED','DEAD_SUBTERM')
                       ∪ decisions.verdict IN ('CONSTANT_TRUE','CONSTANT_FALSE',
                                               'DEAD_SUBTERM','IDENTICAL_ARMS')
                       -- report merge_rung alongside: a rung-1 finding
                       -- ("these two names are the same value") reads very
                       -- differently to a reviewer than a rung-0 one.
dead-blocks [fn]       blocks.entry_reachable = 0
mcdc-gaps [fn]         conditions.verdict='INDEPENDENT' with no independence
                       pair in decision_vectors   -- dynamic tier only
```

`useless-branches` and `dead-blocks` need **no test run and no instrumentation**.

**Decision identity is the one hard integration problem** if the dynamic tier is
ever built. The static analysis reads `.cmt` (post-typing); any instrumentation
is a ppx reading the Parsetree (pre-typing). They must agree on which decision is
which, and the only join key that survives both is a source location. Use the
decision root's `loc_start` as `file:line:col`, 1-based column — the identical
convention already chosen for lambda nodes (`<fun:LINE:COL>`, spec
`cfg-postdom-dominance.md` C-14) — and reuse its collision handling for
ghost/ppx-generated locations (the `#N` ordinal, C-13). Do not invent a second
naming scheme.

---

## 6. The SMT tier

Rung 4 of §3.2 was declined as "needs a decision procedure". This section takes
it, because the decision procedure buys far more than rung 4.

### 6.1 SMT's real prize is not intra-decision coupling

Closing rung 4 *inside* a decision (`x + y > 0 && x > -y`) is a small class — the
§4 census caps the whole multi-condition population at ~73 sites, and rungs 0–3
already handle most of them. If that were all SMT bought, it would not be worth a
solver dependency.

The class that *only* a solver can reach is **path-sensitive redundancy**: a
decision that is implied, or contradicted, by the conditions already established
on every path leading to it.

```ocaml
if x > 5 then begin
  …
  if x > 0 then …        (* dead: implied by the enclosing guard *)
end

match n with
| n when n > 10 -> …
| n when n > 20 -> …     (* dead: subsumed by the first guard *)
| _ -> …

let f = function
  | Some v when v <> None -> …   (* dead: v is not an option *)
```

No rung of §3.2 can see these: the atoms are *syntactically different*, so no
amount of canonicalization merges them. Only an implication check does. And this
is the single most characteristic shape of LLM-authored code — defensive
re-validation of something a caller or an enclosing branch already guaranteed,
because the model generates each block with only local context. It is also
precisely the thing that makes code hard to maintain: a reader cannot tell which
of two overlapping checks is load-bearing.

arch-index is unusually well placed to do this, because path conditions need a
CFG and it **already has one** (§1).

### 6.2 Keeping it CI-fast: dominator chains, not path enumeration

The naive formulation — "for each path to this block, …" — is exponential and
disqualifying. The right formulation is linear.

Compute the **dominator tree** (not just post-dominators). This is nearly free:
`Arch_index_cfg.solve` already runs the iterative intersection fixpoint on the
*reversed* CFG; dominators are the same fixpoint on the forward CFG. It is a
parameterization of existing code, not a new algorithm.

Then, for a decision at block `b`, walk `b`'s dominator chain up to the entry.
For each dominator `d` that ends in a two-way branch on condition `c`:

- if `b` is dominated by `d`'s *then*-successor, conjoin `c`;
- if by the *else*-successor, conjoin `¬c`;
- otherwise (`b` sits after the join) conjoin nothing.

The resulting conjunction `P` holds on **every** path reaching `b`, so using it
as a hypothesis is sound. Note the direction: `P` is an *under*-approximation of
the true path condition (it omits facts that need a join or a loop invariant),
which means the state space is *over*-approximated — exactly the direction in
which a proof of "always true" stays valid. Omitting a fact can only make the
proof harder, never wrong.

Cost per decision: one query with as many hypotheses as the nesting depth,
typically ≤ 5. **Linear in nesting depth, not exponential in branch count.** This
is what makes the tier CI-viable at all.

Queries: `P ∧ ¬D` unsat → `D` is always true under `P` → the check is dead.
`P ∧ D` unsat → always false → the guarded block is dead code. Both sat → live.

### 6.3 Encoding: abstract by freeness, never by assumption

The soundness rule for the whole tier, in one line: **the encoding must
over-approximate the reachable state space**. Then `unsat` in the abstraction
implies `unsat` in reality, and a "dead" verdict is a real proof. Adding *any*
unjustified constraint inverts this and manufactures false findings.

| OCaml | SMT-LIB | note |
|---|---|---|
| `int` | `(_ BitVec 63)` | **not `Int`.** OCaml's native int wraps at 63 bits; in LIA `x + 1 > x` is valid but it is *false* at `max_int`, so an LIA encoding would prove a real guard dead. Width is platform-dependent — record the assumption. **This row is OCaml's answer, not the core's**: the sort and its overflow semantics are declared by the producer, never assumed by the encoder (§8.3) |
| `bool` | `Bool` | |
| `char` | `(_ BitVec 8)` | |
| immutable variant / record / `option` | `declare-datatypes` | Z3 and cvc5 both support algebraic datatypes. This is where OCaml wins: constructor guards become exact, and arm subsumption is decided rather than guessed |
| `string` | uninterpreted sort + equality | the Strings theory is expensive and rarely needed for guards; equality-only is sound (over-approximating) |
| `float` | **decline → `UNKNOWN`** | NaN breaks the identities one reflexively assumes (`not (x < y)` ≠ `x >= y`, `x <> x` is satisfiable). Either use the FP theory properly or stay out. Never encode as `Real` |
| `f a`, `f` certified pure | uninterpreted function `f(a)` | congruence gives `f a = f a` for free |
| `f a`, `f` not certified pure | **fresh constant per occurrence** | no congruence, so no false merge |
| anything unmodelled | fresh constant of a fresh sort | never an axiom |

The UF row is worth dwelling on: **uninterpreted-function congruence subsumes
rungs 0 and 1 automatically.** Once the encoding exists, syntactic identity and
alias merging stop being a separate semantics and become a fast path that avoids
calling the solver. The purity predicate (`v_pure_functions`, §3.2) is what
decides between the two UF rows, and it is already sound in the right direction:
a `MAY_TOP` edge blocks purity certification, so an unresolvable call can never
be given congruence.

### 6.4 Determinism, because this is a gate

A gate that flaps is worse than no gate. Two rules:

- **Never use wall-clock timeouts.** They vary with machine load, so the same
  commit passes on one runner and fails on another. Use Z3's
  `(set-option :rlimit N)` — a deterministic resource counter, reproducible
  across machines and runs. cvc5 has `--rlimit`. This is the single most
  important operational detail in this section.
- **Pin and record the solver.** Stamp solver name, version, and the rlimit into
  `comment_db_meta` alongside the existing `callgraph_contract` key, so every
  verdict is attributable to a specific solver build. The repo already has this
  stamping pattern and `arch-query` already refuses to answer on an unstamped DB.

`unknown`, rlimit exhaustion, or a missing solver → `UNKNOWN`, never a finding —
**and counted, and reported**. A degraded run must not be silently
indistinguishable from a clean one (same rule as §9's degradation clause).

### 6.5 Cost control

Five mechanisms, in order of impact:

1. **Tiered escalation.** Rungs 0–3 first; the solver sees only the residual.
   Most decisions never reach it.
2. **Content-addressed cache in the SQLite DB.** Key = hash of the canonical
   SMT-LIB query text; value = verdict + solver id + rlimit. On a typical PR
   almost every decision is textually unchanged, so almost every query is a cache
   hit and the solver is never invoked. The DB is already there, already
   versioned, and already the artefact CI produces — this is what turns "we run a
   solver in CI" from alarming into routine.
3. **One long-lived solver process** with `push`/`pop` per query, so process
   startup is paid once. The repo already has a stdio child-process transport to
   model this on: `lib/jsonrpc_client/stdio_transport.ml`.
4. **Parallelism.** Queries are independent; fan out across cores.
5. **Hard budgets** — per-query rlimit, per-function query cap, global cap.
   Exceeded → `UNKNOWN` + reported count.

### 6.6 Integration shape: a pipe, not bindings

**Option A — the `z3` opam package** (OCaml bindings to the C API). In-process
and fast, but it hard-links a large C++ dependency into a project whose release
build is *static*: the root `dune` sets
`(static (link_flags (:standard -ccopt -static -ccopt -no-pie)))` and the CI
release matrix builds static binaries. Statically linking Z3 plus `libstdc++`
across that matrix is a real and recurring maintenance cost, and it hard-pins the
solver version to the build.

**Option B — SMT-LIB text over a pipe to an external `z3`/`cvc5`.** The solver
becomes an *optional runtime* dependency: absent → the SMT tier reports `UNKNOWN`
and every other tier still works. That composes perfectly with the
"never a gate failure" rule, keeps the static release build untouched, makes the
query text the natural cache key (§6.5), and lets a user swap or upgrade solvers
without rebuilding arch-index.

**Recommend B.** The stated constraint is that arch-index must stay fast and
CI-usable but *may* be complex. Option B puts the complexity in the encoder —
where it is wanted — instead of in the build system, where it is not.

### 6.7 Explainability is not optional

A finding that says "this condition is dead" with no reason is unusable by a
reviewer and dangerous if acted on blindly. Every SMT verdict must carry its
justification, and the solver already produces both halves:

- **sat (live)** → the **model** is a concrete input under which the condition
  matters. Ideal for dismissing a suspected false alarm.
- **unsat (dead)** → the **unsat core** (`:produce-unsat-cores`) is the minimal
  set of hypotheses that kills it. Rendered against source locations it becomes
  *"this check is dead because the `x > 5` at line 42 already implies it"* — a
  citation instead of an assertion.

Store the core as a list of guard sites on the finding. This matters more than
usual here: the consumer is often an agent applying the fix, and an agent given
an unexplained "delete this" will delete the wrong thing.

### 6.8 What the SMT tier does not fix

- **Maintainability is broader than logical redundancy.** SMT answers "is this
  provably dead". It says nothing about duplication, naming, module coupling, or
  abstraction quality. Two adjacent signals do fall out of the same data for free
  and are worth emitting: **decision arity** and **dominator-chain guard depth**
  (deeply nested conditional logic). Both are honest complexity metrics; neither
  needs a solver.
- **Still intraprocedural.** `if is_valid x && x <> None` needs a summary for
  `is_valid`. Function summaries over this encoding are the natural next step and
  a genuinely larger project.
- **Loops.** The dominator-chain condition carries no loop invariant, so facts
  established by a loop are invisible. Sound (§6.2), just imprecise.
- **The `match`-heavy shape of OCaml (§4) still bounds the boolean half.** The
  datatype encoding is what makes the tier pay off on idiomatic OCaml, not the
  arithmetic one.

---

## 7. If the dynamic tier is wanted later

Three options, worst to best:

1. **Patch bisect_ppx.** Rejected: §2.3 shows the counter array is the wrong
   datum, and it is load-bearing across the file format, the reporter, and
   `merge`. This is a fork of the instrumenter plus a new runtime, not a patch.
2. **Fork bisect_ppx's instrumenter.** Inherits the genuinely hard-won parts —
   `[@coverage off]` attributes and the exclusion file parser
   (`src/ppx/exclusions.ml`), tail-position preservation so instrumentation does
   not break TCO (`~is_in_tail_position` threaded through all 1800 lines),
   or-pattern rotation, ghost-location handling, dune integration. Most of
   `instrument.ml`'s size is these subtleties, and they are all still needed.
   Replace `Generated_code.instrument_expr`'s point model with a per-decision
   vector recorder.
3. **Write a decision-scoped ppx from scratch**, borrowing the *lessons* rather
   than the code. Smaller because it instruments only decisions (~73 sites here,
   not every expression), so it never needs the whole-expression traversal that
   dominates bisect_ppx. Runtime datum: per decision, a `2ⁿ`-bit reached-vector
   bitmap (LLVM's model). Emit alongside, not instead of, bisect_ppx — the two
   answer different questions and can coexist in one build.

Option 3 is the right shape, but **it should not start until the static tier has
run on real agent output and produced a measured hit rate.** If `useless-branches`
fires ten times a week on agent PRs, the dynamic tier is worth building. If it
fires twice a year, MC/DC coverage is not the tool for this problem and the
budget belongs elsewhere.

---

## 8. Multi-language portability

arch-index is language-agnostic by design, so the honest question is which parts
of §3 and §6 port and which are OCaml artefacts. The answer is already settled by
the architecture: **arch-index is not agnostic, its *contract* is** — and the
same split applies here, unchanged.

### 8.1 The layering that already exists

`docs/edge-kind-contract.md` states it directly: "Both backends define `MUST` as
execution-sound dominance computed over a real CFG (Go: SSA post-dominators;
OCaml: Typedtree lowered onto a per-node CFG …) — the definitions agree, so a
`reaches`/`unreachable` verdict means the same thing regardless of source
language."

Concretely, three layers already:

- **Producers, per language.** `callgraph-go/main.go` (653 lines, `go/ssa`, with
  its own `alwaysExec` post-dominance fixpoint at `:212`), `arch-callgraph-ocaml`
  (Typedtree → `arch_index_cfg.ml`), and the generic LSP path
  (`language_registry.ml:37–46`: ocaml, typescript, rust, go, python).
- **A wire format**, deliberately minimal — NDJSON, two record types
  (`arch-load:14–16`): `{"type":"function",…}` and
  `{"type":"call",…,"kind":"MUST"}`. Any language that can emit those joins.
- **An agnostic consumer**: the SQLite schema and `arch-query`.

And a **two-class system already exists**: backends that can tag edge kinds stamp
`callgraph_contract = v1`; those that cannot must not produce a DB at all, and
`unreachable`/`escapes` refuse on an unstamped index rather than answering with
false confidence. Everything below reuses that pattern rather than inventing one.

### 8.2 What ports, what doesn't

| tier | agnostic part | per-language part | verdict |
|---|---|---|---|
| R1 compiler warnings | the idea only | the whole mechanism: dune flags, `go vet`, `#[deny(unreachable_patterns)]`, `tsc --noUnusedLocals` | ports everywhere, but **lives outside arch-index** |
| R2 dead blocks | `blocks` schema + `dead-blocks` query | needs a CFG with entry-reachability | Go ✅ (`alwaysExec` exists today), OCaml ✅, Rust ✅ via MIR, **LSP-only ❌** |
| R3 rungs 0 & 2 | the boolean engine, leaf test, subterm scoping | decision/atom extraction + a canonical atom key | any backend that can emit decisions |
| R3 rung 1 (aliasing) | nothing | needs immutable bindings with unique binder ids **or** an SSA IR | OCaml ✅, **Go ✅ — `go/ssa` is already SSA**, Rust ✅ (MIR), TS/Python ❌ |
| R3 rung 3 (intervals) | the interval engine | lowering an atom to (subject, op, constant) | any typed backend |
| R7a dominator guards | schema + query | the dominator computation | same as R2 |
| R7b SMT | encoder, cache, rlimit, unsat cores | sort semantics + term lowering | any backend emitting typed terms |

One correction to §3.2, which claimed rung 1 is uniquely cheap in OCaml: it is
cheap on any backend with **either** immutable bindings and unique binder ids
(OCaml `Ident` stamps) **or** an SSA IR — and `go/ssa` and Rust MIR both qualify,
by a different route. The claim holds against *surface-syntax* analysis, not
against SSA backends.

The tidy consequence: **the "sound backend" class and the "decision-capable"
class coincide.** Exactly the backends with a real CFG (Go SSA, OCaml CMT, a
future Rust MIR producer) are the ones that can carry this work; exactly the
LSP-only languages (TypeScript, Python) cannot — and those are already the ones
that cannot tag edge kinds. No new fault line is introduced.

### 8.3 Don't invent an IR — SMT-LIB already is one

§6.3 contains a leak: it hardcodes `(_ BitVec 63)` for integers. That is *OCaml's*
int width leaking into what should be agnostic core logic. The fix is structural
— **the producer declares the sort and its semantics; the core never assumes
them.** Producers lower their own AST into SMT-LIB terms plus sort declarations,
and the core is a pure enumeration/SMT engine that never learns what language it
is looking at.

That this must be producer-declared is not theoretical — the right answer differs
per language for the *same* syntax:

| language | integer | why |
|---|---|---|
| OCaml | `(_ BitVec 63)` | native int is 63-bit (tagged), wraps |
| Go | `(_ BitVec 64)` | defined wrapping at 64 |
| Rust | `(_ BitVec 32/64)` | **and the overflow semantics differ by profile** — panics in debug, wraps in release. The same source has two meanings; the producer must say which it compiled |
| Python | `Int` (LIA) | arbitrary precision, so the encoding that is *wrong* everywhere else is the correct one here |
| TypeScript | IEEE-754 float64 | every `number` comparison is float semantics with NaN. Under §6.3's decline-floats rule, most TS arithmetic guards become `UNKNOWN` — a real and large limitation, not a footnote |

### 8.4 A decision contract, mirroring the edge-kind contract

Stamp `decision_contract = v1` in `comment_db_meta` next to `callgraph_contract`,
and extend the NDJSON wire format with three record types — `decision`,
`condition` (carrying an SMT-LIB term and its declared sort), and `guard` (one
dominator-chain entry). Division of labour:

- **Producer**: extract decisions and conditions, compute the dominator chain,
  lower atoms to typed terms, declare sorts and profile semantics.
- **Core**: canonicalization, the leaf/subterm enumeration, the SMT encoding,
  the cache, `rlimit`, unsat cores, and every query.

**Report capability per DB, never silently.** A producer stamps which rungs it
armed; `useless-branches` prints the armed set. Without this, a clean run on a
TypeScript repo — where rung 1 is unavailable, no CFG exists, and float guards
are declined — is indistinguishable from a clean run on an OCaml repo where
everything was checked. That is the multi-language form of §9's
degradation-must-be-reported rule, and it matters more here, because the failure
is total rather than partial.

### 8.5 One caveat on cross-language verdict meaning

The edge-kind contract's selling point is that a verdict means the same thing
regardless of source language. That survives here **only relative to declared
semantics**. The Rust row above is the sharp case: a bounds check that is
provably dead under release wrapping may be live under debug panicking. So the
verdict must be stamped with the profile semantics it was computed under, the
same way the solver id and rlimit are (§6.4). A verdict without its semantic
stamp is not portable and should not be compared across indexes.

---

## 9. Limits, residuals, and one strategic warning

**Do not gate on an MC/DC percentage.** A percentage target is gameable in the
exact direction that makes the problem worse: the cheapest way to raise MC/DC%
is to add tests that reach existing branches, and the second cheapest is to
*write fewer branches*, which penalises legitimate defensive code. The static
verdicts (`MASKED`, `CONSTANT_*`, `entry_reachable=0`) are not gameable this way
— each one is a specific claim about a specific line, refutable by inspection.
Gate on **zero new static findings versus a golden count**, in the same ratchet
style as the existing self-index golden (`docs/adr/001-self-index-golden.md`, CI
step *Self-index smoke test*). That pattern is already established in this repo
and fits without new machinery.

**Inherited residuals** — all documented in `cfg-postdom-dominance.md` and all
still applying:

- *Exception insensitivity* (FR-007): ordinary calls get no exceptional edges, so
  code after a possibly-raising call keeps its CFG position. A block can read
  `entry_reachable` while being unreachable in practice via an always-raising
  call.
- *Termination insensitivity* (EC-4): `while true do () done; g ()` leaves `g`
  reachable. No constant folding on loop conditions.
- *Partial matches* (C-7): `Match_failure` is modelled only as a bypass edge, not
  as a reachability constraint.

**New limits specific to this analysis:**

- Without the SMT tier (§6), condition coupling is handled only up to rung 3 of
  §3.2 and rung 4 reports `UNKNOWN`. With it, rung 4 closes for anything
  intraprocedural and expressible in the §6.3 encoding — but **not** across a
  call boundary (`is_valid x && x <> None` needs a summary), **not** through
  loop-established facts (§6.2 carries no loop invariant), and **not** for
  floats, which are declined by design.
- Rung 1 depends on the stability predicate, and therefore on the effects tables
  being present. On an index built without them, every atom containing an
  application is unstable and the analysis silently degrades to rungs 0 and 2.
  That degradation is sound but should be *reported*, not silent — otherwise a
  clean `useless-branches` result is indistinguishable from an unarmed one.
- `CAP` on decision arity means genuinely huge boolean expressions report
  `UNKNOWN`. That is correct behaviour — but a decision with 9 conditions is
  itself a review finding, so consider surfacing `arity > CAP` as its own
  low-severity signal.
- The analysis is intraprocedural. `if is_valid x then …` where `is_valid` always
  returns `true` is invisible; catching it needs interprocedural constant
  propagation, well beyond scope.
- The `match`-heavy shape of OCaml (§4) bounds the total reach of the boolean
  half of this work. The arm/exhaustiveness half — compiler warnings, §3.4 — is
  where the OCaml-specific value concentrates.

---

## 10. Ranked recommendations

Tags: **cost** S/M/L, **catches** (which of the three named problems), **needs
tests?**

### R1 — Promote warnings 8/11/26/27 to errors explicitly. **[cost: S; catches: useless branches, unreachable arms; needs tests: no]**
One `flags` stanza. The OCaml compiler already proves that a redundant `match`
arm is redundant and that a match is inexhaustive; the repo currently relies on
the dev profile's implicit defaults, which do not survive a profile change. Make
the guarantee explicit and profile-independent. Highest value per line of change
in this document — do it regardless of everything else.

### R2 — Persist and query the block-level reachability already computed. **[cost: S; catches: unreachable code; needs tests: no]**
`Arch_index_cfg.reachable` (`arch_index_cfg.mli:40`) is computed by `solve`, is
asserted on by `test/test_cfg.ml`, and is then discarded by the indexer — the
sole production call site, `arch_index_cmt.ml:1109`, reads `always_exec` alone.
Add the `blocks` table (§5) and an `arch-query dead-blocks`
subcommand. No new analysis, no instrumentation, no test run. This turns an
existing internal invariant into a shippable feature.

### R3 — Static MC/DC lint: `decisions` + `conditions` + `useless-branches`. **[cost: M; catches: useless branching, redundant guards; needs tests: no]**
The core proposal (§3, §5). Model decisions and atomic conditions as first-class
entities during the existing `.cmt` walk, run the `n·2ⁿ` independence-pair
enumeration, and report `MASKED` / `CONSTANT_*` / `IDENTICAL_ARMS`. Requires the
`Texp_ifthenelse` and `&&`/`||` lowering to *additionally* record boolean
structure that it currently flattens (§1) — the CFG lowering itself does not
change, this is a parallel collection pass. Use the subterm-substitution test
(§3.3), not the per-condition test, so coupled occurrences are handled
correctly. Stability predicate from `v_pure_functions` / `arch-query pure-fns`,
with the never-merge-unstable-atoms rule (§3.2) as the soundness guarantee.
**Land the merge ladder incrementally**: rung 0 (syntactic identity) and rung 2
(normalization) need no environment at all and can ship first; rung 1 (alias /
copy propagation, which is what catches `let a = x in if a && x`) adds the
`Ident.stamp` environment to the existing walk and is the highest-value single
increment; rung 3 (interval semantics for same-subject comparisons) is a
separate, self-contained follow-up.

### R4 — Ratchet gate on static findings. **[cost: S; catches: regression; needs tests: no]**
CI step asserting zero new `useless-branches` / `dead-blocks` findings against a
golden count, mirroring the self-index golden pattern. Do this *after* R2/R3 have
run on the corpus and the baseline count is known and triaged. Explicitly **not**
an MC/DC percentage (§9).

### R5 — Measure the hit rate before building anything dynamic. **[cost: S; catches: nothing directly]**
Run R2+R3 over a body of real agent-authored PRs for a few weeks and count
findings, split by true/false positive. This number decides whether R6 is worth
its cost, and no amount of design work substitutes for it.

### R6 — Decision-scoped MC/DC instrumentation ppx. **[cost: L; catches: test gaps, not code slop; needs tests: yes]**
Only if R5 justifies it. Per-decision reached-vector bitmap (§7 option 3),
masking MC/DC (§2.3), joined to the static tables by the decision's
`file:line:col` using the lambda-node location convention (§5). Adds the
`mcdc-gaps` query — genuine test-adequacy reporting, which is a different and
lesser goal than the one that motivated this study.

### R7 — Dominator-chain path conditions + SMT for implied/contradicted checks. **[cost: L; catches: defensive re-validation, subsumed guards, unmaintainable overlapping checks; needs tests: no]**
The largest *new* capability in this document, and the one that best serves the
stated goal (§6.1). Depends on R3 for the decision/condition entities, and on
forward dominators — a parameterization of the fixpoint `Arch_index_cfg.solve`
already runs on the reversed CFG, not a new algorithm. Ships in two halves that
are independently useful:

- **R7a — dominator-chain guard extraction, no solver.** Persist, per decision,
  the conjunction of guards holding on every path to it (§6.2). Already valuable
  on its own: it powers a *guard depth* complexity metric (§6.8) and catches the
  syntactically-identical re-check (`if x > 5 then … if x > 5 then …`) with the
  rung-0 machinery R3 already built. No dependency, no solver, no risk.
- **R7b — the solver.** SMT-LIB over a pipe (§6.6 option B), `rlimit` not
  wall-clock (§6.4), content-addressed verdict cache in the DB (§6.5), unsat
  cores rendered as source citations (§6.7). The solver stays an *optional*
  runtime dependency: absent → `UNKNOWN`, everything else still works.

Sequence R7a before R7b and measure what R7a alone finds; the split means the
solver only gets built if the guard data justifies it.

**Portability.** R7a needs a CFG with dominators, so it lands on the same
backends as R2 (Go SSA, OCaml CMT, Rust MIR) and not on the LSP-only languages.
R7b's encoder is agnostic provided producers declare sorts (§8.3) — do not let
the OCaml integer width reach the core.

### R8 — Emit complexity signals that fall out for free. **[cost: S; catches: maintainability, not correctness]**
Decision arity and dominator-chain guard depth (§6.8) are byproducts of R3 and
R7a. Neither needs a solver and both are honest maintainability signals. Cheap,
but keep them advisory — they are metrics, and §9's warning about gating on
metrics applies to them too.

### R9 — Define `decision_contract = v1` before the second backend exists. **[cost: S; catches: nothing directly — prevents a rewrite]**
Extend the NDJSON wire format with `decision`/`condition`/`guard` records and
stamp the contract in `comment_db_meta`, mirroring `callgraph_contract` (§8.4).
Cheap now, expensive later: R3 built OCaml-first without a contract will bake
Typedtree assumptions into the core, and the Go backend — which already has SSA
and post-dominance and is therefore the *easiest* second implementation — will
force a refactor instead of dropping in. Draft the contract while writing R3,
even if only one producer implements it at first. Include the per-DB capability
report (which rungs are armed), so a clean result on a backend that checked
nothing is never mistaken for a clean result.

**Bottom line.** The instinct is right — condition-level analysis is the correct
lens for agent-authored dead logic — but the useful artefact is MC/DC's
*obligation checked statically*, not MC/DC's *coverage measured dynamically*.
Two thirds of the target (unreachable code, redundant arms) is reachable with an
afternoon's work on machinery that already exists (R1, R2). The genuinely new
analysis (R3) is a bounded, self-contained pass over ~73 sites in this codebase.
The dynamic tier is a real project and should have to earn its budget with
measured findings first.

The SMT tier (R7) is the exception to "start small": it is the only thing here
that reaches the defensive-re-validation class, which is both the most
characteristic LLM output shape and the one that most directly degrades
maintainability. It is also the piece where the "fast in CI, may be complex"
constraint is met by specific engineering choices rather than by scope
reduction — dominator chains instead of path enumeration, `rlimit` instead of
timeouts, a content-addressed cache instead of re-solving, and an optional
external solver instead of a linked one. Those four choices are what make it a
CI tool instead of a research prototype, and none of them can be retrofitted
cheaply, so they belong in the design from the start.

---

## 11. PoC: the idea, built and measured

A working proof of concept lives in [`poc/decision-lint`](../../poc/decision-lint/):
a standalone analyser implementing §3 (merge rungs 0–3, the leaf/subterm test),
the syntactic form of §6.2 (path conditions from enclosing guards), **and the
SMT tier of §6** (rung 4). Parsetree frontend, so it needs no build of the
analysed project and no dependency beyond `compiler-libs` plus an optional `z3`.

**Validation:** 22/22 planted defects detected, 12/12 true negatives silent
(`poc/decision-lint/test/fixture.ml`).

**Results:**

- [octez-manager](mcdc-poc-report-octez-manager.md) — 351 files, 128 k lines:
  **17 verified defects, 0 false positives** (12 from enumeration, 5 from SMT).
  One changes runtime behaviour; four are dead conditionals in production UI
  code; **13 of the 17 are test assertions that pass unconditionally.**
  0.82 s enumeration only, 10.7 s with SMT.
- [arch-index](mcdc-poc-report-arch-index.md) — 41 files: 0 defects from either
  tier, 3 high-arity advisories. 0.12 s / 0.90 s.

**What the PoC settles:**

- *Does the static dual find real defects?* Yes, including one class the design
  doc did not anticipate: **test assertions that are tautologies**. These are
  invisible to every coverage metric — the lines are covered, the tests pass, and
  they check nothing. That is the sharpest possible illustration of §7's argument
  that coverage percentage is the wrong instrument.
- *Is it CI-fast?* Yes. Enumeration alone: 0.82 s for 128 k lines,
  single-threaded, no cache, no solver — the SMT tier's caching and budgeting
  machinery (§6.5) is not needed for it at all. **With SMT: 10.7 s**, of which
  only 1.1 s is user CPU; the rest is one IPC round-trip per `check-sat`, which
  batching would remove. Both fit a CI budget.
- *Is rung 1 worth it?* It is armed and costs ~60 lines, but contributed **no
  additional findings** on either corpus. The alias shape that motivated §3.2
  (`let a = x in if a && x`) is detected by the fixture and did not occur in
  either codebase. Rung 1 stays in the design — it is cheap and it is what makes
  the check robust to renaming — but it should not be sequenced first on the
  strength of these two corpora alone.
- *Where is recall actually lost?* Not in rung 4 (SMT), but in the **purity
  predicate**. 30–53 % of atoms are refused a merge because the PoC uses an
  allowlist instead of an analysis. R3's dependency on `v_pure_functions` is
  therefore more load-bearing than the SMT tier, and should be sequenced ahead of
  R7b.

**R5 is now answered** — see
[`mcdc-poc-report-r5-hit-rate.md`](mcdc-poc-report-r5-hit-rate.md). A third
corpus (sarek, 125 k lines, explicitly AI-assisted) and a replay of 25
squash-merged pull requests give: **4.8 findings per 1 000 decisions** tree-wide,
and **1 PR in 25 (4 %)** introducing a finding in its own diff. Conclusions:
a blocking gate is not justified at that rate, a **ratchet (R4) is**, and the
bulk of the value is the one-time sweep rather than the per-PR check. The
hypothesis that AI-assisted code is denser in dead logic is **not supported** —
octez-manager 4.6 and sarek 4.8 per 1 000 are indistinguishable at this sample
size. The third corpus also exposed a false-positive class (float/NaN) that two
corpora had not, which is the strongest argument for having run R5 at all.

**What the SMT tier added, and what it cost.**

The five SMT-only findings are all the same shape and all real: `result = None ||
result <> None`, and `String.length user >= 0 && String.length group >= 0`. The
two atoms are *syntactically different*, so no canonicalisation rung merges them
— only an implication check sees that `=` and `<>` on the same operands are
complementary. That is precisely the rung-4 class §3.2 declined, and it is worth
**+42 % findings** on this corpus (12 → 17).

Three design decisions from §6 were load-bearing rather than decorative:

- **BitVec 63, not LIA.** The fixture originally expected `x + 1 <= x - 1` to be
  a contradiction. Under OCaml's actual 63-bit wrapping it is *true* at
  `max_int`, and the tool was right to stay silent. An LIA encoding would have
  reported a live guard as dead. This is now pinned as a true negative.
- **`rlimit`, not a timeout.** octez-manager returned zero `unknown`;
  arch-index returned **57**. Because `rlimit` is a resource counter, those 57
  are the *same* 57 on any machine — a reproducible gap rather than a flaky one.
- **Escalation gating.** Only decisions with relational content go to the solver
  (58 % on octez-manager, 64 % on arch-index). Sending everything would have
  roughly doubled the query count for no findings.

**What it still does not settle:** §6.1 claimed path-sensitive redundancy is the
largest class. It is not, on this evidence — `SMT_IMPLIED_TRUE`/`FALSE` fired on
the fixture but on **neither corpus**. Every SMT finding here was an
intra-decision contradiction, not a path-sensitive one. Two caveats before
concluding: the guard stack is lexical rather than dominator-derived, and the
encoder is intraprocedural, so the most interesting shape — a check implied by a
*caller's* validation — is out of reach by construction. The claim needs
R7a (real dominator chains) plus function summaries before it can be tested
properly.

---

## Verification notes

- Line references into `lib/`, `bin/`, `arch-query`, and `architecture-schema.sql`
  were read directly at commit `5df03fb`.
- bisect_ppx claims were read from a fresh clone of `aantron/bisect_ppx@master`
  (`src/ppx/instrument.ml`, `src/common/bisect_common.mli`,
  `src/runtime/native/runtime.mli`). Line numbers are from that clone and will
  drift with upstream.
- The §4 census is **grep-based and approximate**; it has since been superseded
  by the parsed figures in §4.1, which show it undercounted multi-condition
  decisions (measured 25–38 % of boolean decisions, versus the ~19 % estimated).
  The grep numbers are left in place because the *ratio* they were used for —
  multi-condition booleans against all decision sites including `match` arms —
  still holds directionally.
- **Unverified:** the exact warning set dune's dev profile enables as errors at
  the pinned dune version. R1 stands regardless — the point is to stop depending
  on the implicit default — but the "CI already covers this in dev" parenthetical
  in §3.4 should be confirmed before being quoted.
- **Unverified:** LLVM's default MC/DC condition cap (stated as 6) was recalled,
  not re-read from Clang's docs in this session.
- The §3.3 leaf-vs-subterm claim was **checked by enumeration**, not asserted: all
  182 712 boolean formulas of depth ≤ 3 over 2 variables (exhaustive) plus
  300 000 sampled formulas of depth ≤ 4 over 4 variables. Of the 180 780 and
  134 532 respectively that have a dead proper subterm, none lacks a dead leaf.
  An earlier draft of §3.3 claimed the opposite and was wrong. This is empirical
  evidence, **not a proof** — a counterexample would cost detection recall (not
  soundness), so a proof or a wider search is worth having before R3 ships.
- **No SMT solver was available in this environment** (an OCaml 5.3 switch was
  built for the PoC; no solver was). §6 is therefore design, not measurement: the encoding table, the rlimit
  determinism argument, and the cache design are unvalidated by execution. The
  Z3 `:rlimit` / cvc5 `--rlimit` options and Z3/cvc5 datatype support were
  recalled, not re-read from current documentation — confirm before building.
- §8's backend claims were read from `docs/edge-kind-contract.md`,
  `callgraph-go/main.go` (`alwaysExec`, `:212`), `arch-load` (`:14–16`), and
  `lib/arch_index/language_registry.ml` (`:37–46`). **Unverified:** the Rust
  overflow-semantics row in §8.3 (debug panics / release wraps) was recalled, not
  re-read from the Rust reference; and no Rust or TypeScript producer exists yet,
  so both rows are projections from those languages' IRs, not from code in this
  repo.
- Minor, unrelated: `control-flow-coverage-analysis.md` cites
  `docs/rust-sound-callgraph-design.md` twice (its header and §4), and that file
  does not exist in the tree. Dangling cross-reference, worth fixing or removing.
- **Unverified:** that OCaml's native `int` is 63-bit on every platform in the
  release matrix (the §6.3 encoding assumes it; 32-bit platforms would need
  width 31, and the assumption should be recorded in the DB alongside the solver
  stamp).
- MC/DC definitions, the unique-cause/masking distinction, and the coupling
  caveat follow Chilenski & Miller (SEJ 9(5):193–200, 1994) and Hayhurst et al.
  (NASA/TM-2001-210876), both already cited in
  [`control-flow-coverage-analysis.md`](control-flow-coverage-analysis.md) §2.
