# Control-flow & coverage-analysis theory for stronger reachability

**Status:** research / read-only. **Date:** 2026-07-09. **Scope:** background for
strengthening arch-index's `reaches` (MUST under-approximation) and `unreachable`
(MUST ∪ MAY over-approximation) queries. No source was modified.

Terminology follows [`docs/edge-kind-contract.md`](../edge-kind-contract.md) and
[`docs/rust-sound-callgraph-design.md`](../rust-sound-callgraph-design.md): every
`calls` edge is `MUST` (uniquely resolved, definitely taken), `MAY_ENUMERATED`
(callee in a known finite set), or `MAY_TOP` (⊤: unknown callee/timing, wildcard).
`reaches` uses MUST only; `unreachable` uses the full closure and returns
`UNKNOWN` once a MAY_TOP frontier is reachable.

---

## Executive summary

arch-index already has the right *soundness architecture* — an over-approximate
call graph with an explicit ⊤ element and two dual queries. Its weakness is
**precision of the MUST fragment**: today "MUST = definitely called" is decided
*syntactically* (a call is demoted to MAY_TOP if it sits inside an `if`/`match`
arm, loop body, handler, `&&`/`||` right operand, or a closure/lazy/functor body).
Fifty years of compiler and coverage theory model exactly this question, and the
mature answer is a two-part upgrade: (1) build a real per-function **control-flow
graph (CFG)** and compute a **post-dominator tree** — "call C is executed on every
run of F" is *precisely* "the CFG node for C post-dominates F's entry" — which
turns MUST from a conservative syntactic guess into a provably-correct dominance
test; and (2) recover the ~47% MAY_TOP by climbing the **call-graph precision
ladder** (CHA → RTA → VTA/points-to → k-CFA), whose single highest-leverage rung
for a functional codebase is a cheap flow analysis of *where higher-order function
values (closures passed to `List.iter`-style HOFs) are created and where they are
applied*. MC/DC-style condition analysis is the correct lens for `&&`/`||` but is
lower-leverage than the CFG/dominance work. Details, citations, and a ranked plan
follow.

---

## 1. Dominance / control-dependence: formalizing "executed on every run"

**The exact formalization arch-index wants.** In a CFG with a unique entry node
and a unique exit node, node *d* **dominates** node *n* iff every path from entry
to *n* goes through *d*; *p* **post-dominates** *n* iff every path from *n* to the
exit goes through *p* (Aho, Lam, Sethi & Ullman, *Compilers: Principles,
Techniques, and Tools*, 2nd ed., 2006, §9.6 "dominators"; Muchnick, *Advanced
Compiler Design and Implementation*, 1997, §7.3). The property "call site C runs
on **every** terminating execution of function F" is exactly "**C post-dominates
the entry of F**" — equivalently, in structured code, C is not control-dependent
on any branch. This is the sound, precise replacement for arch-index's syntactic
"is C inside a conditional?" test.

**Control dependence & the PDG.** Ferrante, Ottenstein & Warren define *control
dependence* via post-dominance: node *Y* is control-dependent on node *X* iff
(a) there is a CFG path from *X* to *Y* along which *Y* post-dominates every node
but *X*, and (b) *Y* does not post-dominate *X*. Their **Program Dependence Graph
(PDG)** = **Control Dependence Graph (CDG)** ∪ data-dependence edges; a node with
*no* incoming control-dependence edge (other than the region/entry node) is
executed unconditionally.
- Ferrante, Ottenstein, Warren, "The Program Dependence Graph and Its Use in
  Optimization," *ACM TOPLAS* 9(3):319–349, 1987. PDF:
  <https://web.eecs.umich.edu/~mahlke/courses/583f23/reading/ferrante_toplas_87.pdf>;
  DOI <https://doi.org/10.1145/24039.24041>.

**Computing dominance efficiently.** Two standard algorithms:
- Lengauer & Tarjan, "A Fast Algorithm for Finding Dominators in a Flowgraph,"
  *ACM TOPLAS* 1(1):121–141, 1979. DOI <https://doi.org/10.1145/357062.357071>.
  Near-linear; the textbook fast algorithm.
- Cooper, Harvey & Kennedy, "A Simple, Fast Dominance Algorithm," Rice TR, 2001 —
  an iterative dataflow formulation over the reverse-postorder that is O(N²)
  worst-case but faster in practice on real CFGs and *much* simpler to implement
  (≈ one page). PDF: <https://www.cs.rice.edu/~keith/EMBED/dom.pdf> (mirror
  <https://www.cs.tufts.edu/comp/150FP/archive/keith-cooper/dom14.pdf>). **This is
  the recommended algorithm for arch-index** — post-dominators are just dominators
  on the reversed CFG.
- Dominance frontiers (the machinery that makes CDG construction efficient and is
  the same primitive used for SSA φ-placement): Cytron, Ferrante, Rosen, Wegman &
  Zadeck, "Efficiently Computing Static Single Assignment Form and the Control
  Dependence Graph," *ACM TOPLAS* 13(4):451–490, 1991. DOI
  <https://doi.org/10.1145/115372.115320>. Note: the **reverse** dominance
  frontier of the reverse CFG yields control dependences directly.

**How arch-index would use it.** Per function F: build a CFG (nodes = basic
blocks / call sites, edges = intraprocedural control flow incl. branch, loop-back,
exception, and short-circuit edges — see §5); add a synthetic unique exit; compute
the post-dominator tree (Cooper-Harvey-Kennedy on the reversed CFG). A call C is
`MUST` iff C's node post-dominates F's entry (⇔ C is control-dependent only on the
entry/region node). Every other intraprocedural call is conditionally executed and
demotes to `MAY_TOP` (or `MAY_ENUMERATED` if its target set is bounded). This
replaces "syntactic conservative approximation" with "provably every-run,"
recovering as MUST the calls that today are demoted merely because they are
lexically nested but in fact post-dominate (e.g., a call after an `if` that both
arms fall through, or the sole call in a function body that happens to be inside a
`let`).

---

## 2. Coverage criteria as edge semantics (statement / branch / condition / MC/DC)

Classical structural-coverage criteria form a subsumption hierarchy; each answers
a different "when does control reach here" question. Standard reference: Ammann &
Offutt, *Introduction to Software Testing*, 2nd ed., 2016 (logic-coverage chapter),
and the DO-178C aviation objectives.

- **Statement coverage** — every statement executed at least once. Weakest;
  ignores branch outcomes. Corresponds to "node is reachable on *some* run," i.e.
  arch-index's `reaches` existence question, not the every-run MUST question.
- **Branch / decision coverage** — every decision (the whole boolean controlling a
  branch) takes both `true` and `false`. This is the criterion whose *dual* defines
  MUST: a call is every-run iff it is *not* guarded by any decision that can go the
  other way — i.e., iff it post-dominates entry (§1).
- **Condition coverage** — every atomic boolean *condition* takes both values, but
  says nothing about the decision outcome; does not subsume branch coverage.
- **MC/DC (Modified Condition/Decision Coverage)** — requires decision coverage
  **plus** that each individual condition is shown, by a pair of test cases
  differing only in that condition, to **independently affect the decision's
  outcome**. This is the DO-178C Level-A objective for compound booleans.
  - Chilenski & Miller, "Applicability of modified condition/decision coverage to
    software testing," *Software Engineering Journal* 9(5):193–200, 1994. DOI
    <https://doi.org/10.1049/sej.1994.0025>.
  - Hayhurst, Veerhusen, Chilenski & Rierson, "A Practical Tutorial on Modified
    Condition/Decision Coverage," NASA/TM-2001-210876, May 2001. PDF:
    <https://shemesh.larc.nasa.gov/fm/papers/Hayhurst-2001-tm210876-MCDC.pdf>.
    This is the definitive worked tutorial (independence pairs, coupling, the
    unique-cause vs. masking variants).
  - RTCA DO-178C, "Software Considerations in Airborne Systems and Equipment
    Certification," 2011 (defines the coverage objectives; the source of MC/DC as
    a certification requirement). Overview:
    <https://en.wikipedia.org/wiki/DO-178C>.

**Which criterion maps onto MUST vs MAY?** The MC/DC notion of a condition that
**independently affects the outcome** is precisely the notion arch-index needs for
short-circuit `&&`/`||`. In `a && f()`, the call `f()` runs iff `a` is true; `f()`
is control-dependent on `a`, so it is *not* MUST — it is exactly a decision whose
`false` branch skips the call. The right operand of `&&`/`||`, the arms of a
ternary/`match`, and the body of a loop are all "conditions/decisions that
independently determine whether the call fires," so **branch/decision coverage
supplies the MUST-demotion rule and MC/DC supplies the finer per-condition reason**
(useful if arch-index ever wants to say *which* guard makes a call conditional, or
to keep a call MUST when the guard is a tautology it can prove). For the pure
MUST/MAY decision, decision coverage's dual (post-dominance) is sufficient; MC/DC
is the tool if you later model *why* and want per-condition provenance.

Loops: all criteria treat the loop *body* as conditionally executed (a `while`/
`for` may iterate zero times), so any call only in a loop body is MAY, never MUST —
matching arch-index's current demotion and §5's CFG modeling.

---

## 3. Must vs may analysis as dataflow lattices

arch-index's three kinds are a **lattice**. Order them by information/precision;
the natural encoding is a product of (resolution certainty) × (target set):

```
        MAY_TOP  (⊤ — could call anything; least precise, sound for over-approx)
           |
      MAY_ENUMERATED  (finite candidate set {c1..cn})
           |
        MUST  (singleton, every-run)
           |
         ⊥  (no call / unreachable)
```

This is the classic **over/under-approximation duality** of dataflow analysis,
formalized as monotone frameworks over a lattice with a meet/join and a transfer
function; the fixpoint is computed by iteration to convergence. The canonical
textbook treatment is:
- Nielson, Nielson & Hankin, *Principles of Program Analysis*, Springer, 1999
  (corrected 2nd printing 2005). Chs. 1–2 develop the four classical bit-vector
  analyses and the *may vs must* / *forward vs backward* taxonomy. Publisher:
  <https://link.springer.com/book/10.1007/978-3-662-03811-6>.
- Kildall, "A Unified Approach to Global Program Optimization," *POPL* 1973
  (the monotone-framework / lattice fixpoint foundation). DOI
  <https://doi.org/10.1145/512927.512945>.

The four textbook analyses show the same duality arch-index lives in:

| analysis | direction | may/must | combine at joins | dual in arch-index |
|---|---|---|---|---|
| Reaching definitions | forward | **may** | ∪ (union) | over-approx closure for `unreachable` (a def *may* reach) |
| Live variables | backward | **may** | ∪ | " (a use *may* occur) |
| Available expressions | forward | **must** | ∩ (intersection) | MUST-path: an expr is available iff computed on *every* path — same "every run" test as MUST |
| Very-busy (anticipable) expressions | backward | **must** | ∩ | dual: definitely-will-be-used |

The pattern: **must-analyses meet with ∩ and answer "on every path"** — this is
literally arch-index's MUST question and is why post-dominance (a must property)
computes it. **May-analyses meet with ∪ and answer "on some path"** — this is the
`unreachable` over-approximation, where MAY_TOP is ⊤ and any reachable ⊤ forces
`UNKNOWN` (the lattice top swallows information, exactly as `⊤ ∪ x = ⊤`). Framing
the edge kinds this way also gives a principled rule for *combining* edges along a
path: MUST ∘ MUST = MUST; anything ∘ MAY_TOP = MAY_TOP; MUST ∘ MAY_ENUMERATED =
MAY_ENUMERATED — a monotone transfer function over the lattice above.

Abstract interpretation (Cousot & Cousot, "Abstract Interpretation," *POPL* 1977,
DOI <https://doi.org/10.1145/512950.512973>) is the theory that guarantees such an
over-approximation is *sound* by construction via a Galois connection — the formal
backing for arch-index's "never drop a call site; unresolved → ⊤" invariant.

---

## 4. Call-graph construction precision ladder (recovering the 47% MAY_TOP)

The standard survey that unifies all of these as instances of one parameterized
algorithm is:
- Grove & Chambers, "A Framework for Call Graph Construction Algorithms," *ACM
  TOPLAS* 23(6):685–746, 2001. PDF:
  <http://projectsweb.cs.washington.edu/research/projects/cecil/pubs/cgc-toplas.pdf>;
  DOI <https://doi.org/10.1145/506315.506316>. They show CHA/RTA/k-CFA differ only
  in how much context/flow they track; each is a point on a cost/precision curve.

The ladder, cheapest→most precise, and what each buys arch-index:

1. **CHA — Class Hierarchy Analysis** (Dean, Grove & Chambers, "Optimization of
   Object-Oriented Programs Using Static Class Hierarchy Analysis," *ECOOP* 1995,
   <https://doi.org/10.1007/3-540-49538-X_5>). A virtual/interface call resolves to
   *all* subtype implementations of the static receiver type. This is exactly what
   the Go backend already does (`MAY_ENUMERATED` = CHA candidate set). Cheap, sound,
   coarse.
2. **RTA — Rapid Type Analysis** (Bacon & Sweeney, "Fast Static Analysis of C++
   Virtual Function Calls," *OOPSLA* 1996, <https://doi.org/10.1145/236337.236371>).
   Prunes CHA to types actually *instantiated* anywhere in the program. Big cheap
   win over CHA; still context-insensitive.
3. **VTA — Variable Type Analysis** (Sundaresan, Hendren, Razafimahefa,
   Vallée-Rai, Lam, Gagnon & Godin, "Practical Virtual Method Call Resolution for
   Java," *OOPSLA* 2000, <https://doi.org/10.1145/353171.353189>). Propagates the
   set of types that can flow to each variable/field along assignment edges —
   distinguishes candidate sets per call site, not per type globally.
4. **Points-to / pointer analysis** — the flow of *values* (incl. function/closure
   values) to variables:
   - Andersen, "Program Analysis and Specialization for the C Programming
     Language," PhD thesis, DIKU, 1994 — *inclusion-based* (subset constraints),
     O(n³), more precise. <https://users-cs.au.dk/amoeller/papers/andersen-thesis.pdf>.
   - Steensgaard, "Points-to Analysis in Almost Linear Time," *POPL* 1996 —
     *unification-based* (equality constraints), near-linear, coarser.
     <https://doi.org/10.1145/237721.237727>.
   These are what resolve **a closure stored in a variable/field and later
   applied** — the dominant arch-index MAY_TOP source.
5. **k-CFA — context-sensitive control-flow analysis** for higher-order languages
   (the functional-language analogue of points-to; resolves "which lambda flows to
   this application site"):
   - Shivers, "Control-Flow Analysis of Higher-Order Languages," PhD thesis, CMU
     CMU-CS-91-145, 1991. <https://www.cs.tufts.edu/~nr/cs257/archive/olin-shivers/diss.pdf>.
   - Might & Van Horn's re-derivation via abstract machines (practical, implementable
     recipe): Van Horn & Might, "Abstracting Abstract Machines," *ICFP* 2010,
     <https://matt.might.net/papers/vanhorn2010abstract.pdf>; arXiv
     <https://arxiv.org/abs/1007.4446>. (ICFP 2020 Most-Influential-Paper.) 0-CFA
     is the sweet spot: monovariant, cubic, resolves most first-order closure flow.
   - Complexity caveat: Van Horn & Mairson, "Deciding k-CFA is complete for EXPTIME,"
     *ICFP* 2008 (<https://doi.org/10.1145/1411204.1411243>) — k≥1 context
     sensitivity is expensive; 0-CFA is the pragmatic target.
6. **Demand-driven analysis** — compute points-to/CFA facts only for the query at
   hand instead of whole-program, matching arch-index's per-query model: Reps,
   "Program Analysis via Graph Reachability," *Information & Software Technology*
   40(11–12):701–726, 1998 (<https://doi.org/10.1016/S0950-5849(98)00093-7>);
   Sridharan & Bodík, "Refinement-Based Context-Sensitive Points-To Analysis for
   Java," *PLDI* 2006 (<https://doi.org/10.1145/1133981.1134027>).

**For OCaml's ~47% MAY_TOP specifically:** the dominant case (per the edge-kind
contract) is an *ordinary named call sitting inside a closure/lambda passed to a
HOF* like `List.iter (fun x -> f x) xs`. Two orthogonal fixes:
- The **deferred-body linking** the OCaml Phase-2 redesign already plans (model a
  lambda body as deferred, link its calls only when the lambda is invoked/passed)
  handles *whether* those calls happen. This is a control-flow, not a data-flow,
  fix and is the cheapest large win.
- A **0-CFA-style closure-flow pass** handles *which* function is called when the
  callee itself is a first-class value (a `fun`/first-class-module/functor argument
  applied inside the body). This turns many MAY_TOP into `MAY_ENUMERATED` (the set
  of lambdas that can flow there). Andersen-style inclusion constraints over
  OCaml's known-arity applications are the standard recipe.

---

## 5. Loops, exceptions, and short-circuit operators in the CFG

Correct dominance depends entirely on modeling non-straight-line control in the
CFG. A syntactic `Tast_iterator` walk (arch-index today) cannot compute dominance
because it has no edges — it only has lexical nesting, which is why it must
*conservatively* demote everything nested. Building a real CFG fixes this. Standard
constructions (Aho-Lam-Sethi-Ullman §8.4; Muchnick §7; Appel, *Modern Compiler
Implementation*, ch. on control flow):

- **Loops.** A `while`/`for` becomes: header block → (body block → back-edge to
  header) and (exit edge to after-loop). Because the exit edge bypasses the body,
  the body does **not** post-dominate the header ⇒ calls only in the body are
  correctly non-MUST (loop may run 0 times). A `loop {}`/infinite loop with no
  break gives the body post-dominance of the header — a subtlety a syntactic walk
  gets wrong in both directions.
- **Exceptions.** Each instruction that can raise gets an edge to the enclosing
  handler (or to the function's exceptional exit). This is the "double-barrelled"
  control flow OCaml itself models (normal return + exception return; see the
  Flambda2 CPS design, <https://ocamlpro.com/blog/2024_01_31_the_flambda2_snippets_1/>).
  Consequence: a call *after* a possibly-raising call does **not** post-dominate
  entry unless the intervening call cannot escape — so `try/with` bodies and
  post-`raise` code are correctly conditional. Sound modeling of exception edges is
  well studied: Sinha & Harrold, "Analysis and Testing of Programs with Exception
  Handling Constructs," *IEEE TSE* 26(9):849–871, 2000
  (<https://doi.org/10.1109/32.877847>); Choi, Grove, Hind & Sarkar, "Efficient and
  Precise Modeling of Exceptions for the Analysis of Java Programs," *PASTE* 1999
  (<https://doi.org/10.1145/316158.316171>).
- **Short-circuit `&&`/`||`.** These desugar to branches, not straight-line code:
  `a && b` ≡ `if a then b else false`. So the CFG has a branch after evaluating
  `a`, and the node evaluating `b` (and any call inside it) is control-dependent on
  `a` ⇒ not MUST. This is the CFG-level justification for arch-index's current
  `&&`/`||`-right-operand demotion, and it becomes *automatic* once the CFG exists
  (§2, MC/DC).

**What arch-index gains from a real per-function CFG vs the Tast_iterator walk:**
1. MUST becomes a *computed* dominance property, not a conservative syntactic
   guess — recovers falsely-demoted calls (calls that are lexically nested but
   actually post-dominate, e.g. the tail call of a function whose only branching is
   a fully-covered `match`).
2. Correct handling of the cases a syntactic walk *silently gets wrong*: infinite
   loops (body IS every-run), fallthrough `if` with no else, early `raise`/`return`
   making later code conditional.
3. A substrate for everything in §1–§4: control dependence, slicing, and per-block
   points-to all need the CFG.

The cost is building the CFG from the Typedtree (branch/loop/handler/short-circuit
lowering) — real but bounded, and a one-time per-function pass.

---

## 6. Concrete tools & prior art to study

**Dominators / CFG in compilers.**
- **LLVM** — `DominatorTree` / `PostDominatorTree` analysis passes (Cooper-Harvey-
  Kennedy-style incremental algorithm), and `opt -view-cfg` / `-dot-cfg` to dump a
  function CFG. Docs: <https://llvm.org/docs/Passes.html>; source
  `llvm/lib/Support/GenericDomTreeConstruction.h`. The reference implementation to
  mirror.
- **Frama-C** — the `Dominators` plugin and the **Eva** (value/abstract-
  interpretation) plugin compute dominators/post-dominators and reachable states
  over C CFGs; sound-by-construction abstract interpretation. <https://frama-c.com/>;
  Eva: <https://frama-c.com/fc-plugins/eva.html>. Closest "sound + precise
  dominator + value analysis" analogue to what arch-index wants.

**Whole-program call graphs / PDG (Java).**
- **Soot** — CHA/RTA/VTA/SPARK (Andersen points-to) call-graph builders and a PDG;
  the VTA paper (§4) is Soot's. <https://github.com/soot-oss/soot>. Its
  `SPARK`/`Paddle` points-to is the reference for closure/pointer resolution.
- **WALA** (IBM) — 0-CFA/k-CFA/RTA call graphs, pointer analysis, and slicing/PDG.
  <https://github.com/wala/WALA>. The most directly reusable design for the
  precision ladder in §4.

**Sound-ish industrial analyzers.**
- **Infer** (Meta) — compositional shape analysis via **bi-abduction** over
  separation logic; per-procedure Hoare-triple summaries. Calcagno, Distefano,
  O'Hearn & Yang, "Compositional Shape Analysis by Means of Bi-Abduction," *POPL*
  2009 / *JACM* 58(6):26, 2011 (<https://doi.org/10.1145/2049697.2049700>);
  overview <https://cacm.acm.org/research/separation-logic/>. Relevant as a model
  of **compositional, summary-based** interprocedural analysis (analyze each
  function once, reuse the summary) — a scaling pattern for arch-index's per-query
  reachability. Its interprocedural precision is high but it is not a general
  call-graph tool.
- **CodeQL** (GitHub) — dataflow/taint as **Datalog-style** recursive queries over
  a relational program DB. Docs <https://codeql.github.com/docs/>. Directly
  relevant: arch-index *already* stores the call graph in SQLite; CodeQL shows the
  mature version of "reachability as a declarative recursive query," and its
  global-dataflow library is the model for adding path/flow conditions. (See also
  the Doop framework, Bravenboer & Smaragdakis, "Strictly Declarative Specification
  of Sophisticated Points-to Analyses," *OOPSLA* 2009,
  <https://doi.org/10.1145/1640089.1640108> — points-to *as* Datalog, which maps
  cleanly onto arch-index's SQLite substrate.)

**MC/DC / coverage in practice.**
- **gcov / lcov** — GCC branch/line coverage (`gcc --coverage`, `gcov -b`);
  <https://gcc.gnu.org/onlinedocs/gcc/Gcov.html>. Branch coverage only, not MC/DC.
- **BullseyeCoverage** — condition/decision coverage commercially;
  <https://www.bullseye.com/>. Documents the practical "C/DC" measurement.
- **LDRA / VectorCAST** — the certified DO-178C MC/DC tools (verification of §2's
  independence pairs in industry). Vendor docs; treat as prior art for how MC/DC is
  operationalized, not as a library.
- Note: LLVM's `-fcoverage-mcdc` (Clang 18+) now emits MC/DC instrumentation —
  <https://clang.llvm.org/docs/SourceBasedCodeCoverage.html> — a modern reference
  for how compound-boolean independence is tracked in a real toolchain.

**OCaml-specific — can arch-index reuse compiler IR instead of Typedtree?**
- **Lambda IR** (`lambda/lambda.ml`) — desugared, untyped; branches and loops are
  explicit (`Lifthenelse`, `Lswitch`, `Lwhile`, `Lfor`, `Ltrywith`,
  `Lstaticraise`), so short-circuit/loop/exception control flow is already lowered
  — a *better* substrate than Typedtree for CFG/dominance, at the cost of losing
  some source-level names. (OCaml manual, "Lambda" / compiler sources.)
- **Cmm** (`backend/cmm.ml`) — lower-level, near-C--; still control-flow explicit.
- **Flambda2 / OxCaml `Cfg`** — the native backend has an explicit basic-block
  **`Cfg`** representation (`backend/cfg/`) used for register allocation and
  optimization; OxCaml exposes it. OCamlPro's Flambda2 series documents the
  CPS/double-barrelled (normal + exception) control-flow model:
  <https://ocamlpro.com/blog/2024_01_31_the_flambda2_snippets_1/> and
  <https://ocamlpro.com/blog/2024_03_18_the_flambda2_snippets_0/>. **Whether the
  upstream compiler exposes a *dominator* API over this `Cfg` as a reusable library
  is unverified** — the `Cfg` data structure exists and is standard, but arch-index
  would likely compute dominance itself (Cooper-Harvey-Kennedy) over a CFG it
  builds from Lambda, rather than depending on an internal, unstable backend module.
- Trade-off: consuming Lambda/Cmm requires running (a fork of) the compiler
  pipeline and pins to a compiler version (the same maintenance cost the Rust MIR
  producer accepts, per `rust-sound-callgraph-design.md` §4). Building a CFG from
  the *Typedtree* arch-index already parses is lower-risk and keeps source names;
  Lambda is the upgrade if Typedtree lowering proves fiddly. (Community discussion
  of OCaml control-flow-analysis tooling gaps:
  <https://discuss.ocaml.org/t/tools-or-pointers-for-control-flow-analysis-of-ocaml-code/3805>.)

---

## 7. Recommendations for arch-index

Ranked by leverage. Tags: **soundness impact** (does it change whether verdicts are
sound), **precision gain** (how much MAY_TOP / false-demotion it recovers),
**cost** S/M/L.

### R1 — Build a per-function CFG + post-dominator tree; define MUST = post-dominance. **[soundness: preserved/strengthened; precision: HIGH; cost: M–L]**
**Yes — arch-index should do this, and it is the keystone.** Replace the syntactic
"nested ⇒ demote" rule with a computed test: a call is MUST iff its CFG node
post-dominates the function entry (§1, §5). Use Cooper-Harvey-Kennedy dominance
(§1) on the reversed CFG — ~one page of code, no external dependency. This is
strictly *more precise* (recovers falsely-demoted every-run calls) and *at least as
sound* (any call not proven every-run stays MAY). Everything else in this list
builds on the CFG. Recommended substrate: build the CFG from **Lambda IR** if
feasible (control flow already lowered; §6) else from Typedtree with explicit
branch/loop/handler/short-circuit lowering. Cost is M if Typedtree lowering is
clean, L if exception/short-circuit modeling is involved — but exceptions and
`&&`/`||` must be modeled for soundness regardless (§5).

### R2 — Fix HOF/closure MUST via deferred-body linking (the OCaml Phase-2 plan). **[soundness: fixes a latent false-MUST AND false-UNREACHABLE; precision: HIGH; cost: M]**
This is the **single highest-leverage change to cut the 47% MAY_TOP soundly**, and
it is *already scoped* in `docs/edge-kind-contract.md` / the callgraph-soundness
task. The 47% is dominated by ordinary calls lexically inside lambdas/callbacks
passed to HOFs (`List.iter (fun x -> f x)`). Modeling a lambda body as *deferred*
and linking its calls only where the lambda is actually invoked/passed (a
control-flow reachability fix, not data-flow) is what legitimately moves those
edges out of MAY_TOP. It also closes the two soundness bugs the contract flags
(false MUST for un-invoked nested bodies; false UNREACHABLE for computed-callback
calls). Do R2 in tandem with R1 — both need the "when does this body run" model.

### R3 — 0-CFA closure-flow pass to turn MAY_TOP into MAY_ENUMERATED for first-class-value calls. **[soundness: preserved; precision: MEDIUM–HIGH; cost: M–L]**
For calls whose *callee* is a first-class value (a `fun`/first-class-module/functor
parameter applied in the body), a monovariant 0-CFA / Andersen-inclusion pass
computes the finite set of lambdas that can flow to each application site (§4),
turning MAY_TOP into MAY_ENUMERATED. This directly sharpens `unreachable` (fewer ⊤
frontiers ⇒ fewer `UNKNOWN`). Start with 0-CFA (cubic, monovariant); avoid k≥1
(EXPTIME, §4). Do after R1/R2.

### R4 — MC/DC-style per-condition analysis for `&&`/`||`. **[soundness: preserved; precision: LOW–MEDIUM; cost: S–M]**
**Not worth it as a MUST/MAY decider** — once R1's CFG models short-circuit
operators as branches (§5), decision coverage's dual (post-dominance) *already*
correctly demotes `&&`/`||`-guarded calls; MC/DC adds no soundness or coarse-
precision. MC/DC becomes worthwhile *only* for two optional refinements: (a)
proving a guard is a tautology/constant so a guarded call can be *promoted* back to
MUST (needs a value/condition analysis — small win, niche), and (b) attaching
*provenance* ("this call is conditional because of condition `a` in decision
`a && b`") to explain `escapes`/`UNKNOWN` results to users. Defer; low leverage
relative to R1–R3.

### R5 — Represent the edge lattice + path-composition explicitly (per §3). **[soundness: preserved/clarified; precision: neutral; cost: S]**
Encode MUST ⊑ MAY_ENUMERATED ⊑ MAY_TOP as a real lattice with an explicit
path-composition transfer function (MUST∘MUST=MUST; anything∘MAY_TOP=MAY_TOP;
etc.) and cite the must-analysis (∩, "every path") / may-analysis (∪, "some path")
duality (Nielson-Nielson-Hankin) in the design docs. Cheap; makes the existing
design provably a monotone framework and eases proving future changes sound.

### R6 — Consider a Datalog/recursive-query formulation for reachability (CodeQL/Doop pattern). **[soundness: preserved; precision: neutral; cost: M]**
Longer-term: arch-index already stores the graph in SQLite; expressing `reaches` /
`unreachable` (and future flow conditions) as recursive Datalog-style queries
(CodeQL, Doop; §6) scales the query layer and makes adding context-sensitivity
declarative rather than procedural. Not urgent; strategic.

**Bottom line.** The highest-leverage soundness-preserving cut to the 47% MAY_TOP
is **R2 (deferred HOF-body linking)**, and it should be built on **R1 (real CFG +
post-dominator MUST)**, which is the keystone that also makes loop/exception/
short-circuit handling correct-by-computation instead of correct-by-conservatism.
R3 (0-CFA closure flow) is the follow-on precision win. MC/DC (R4) is a low-
priority refinement, not a core need.

---

## Verification notes

- All papers/DOIs above are standard, well-attested references; DOIs and PDF URLs
  were confirmed via search.
- **Unverified:** that the upstream OCaml/OxCaml compiler exposes a *reusable
  dominator API* over its backend `Cfg` module (the `Cfg` structure exists; a
  public dominance library over it was not confirmed — arch-index should assume it
  computes dominance itself).
- **Unverified:** the exact current numeric breakdown of *which* constructs make up
  the 47% MAY_TOP (the "mostly HOF/callback" attribution is from
  `docs/edge-kind-contract.md` and the task brief, not independently re-measured in
  this research).
- Chilenski-Miller page range (193–200, SEJ 9(5), 1994) and the NASA TM number
  (2001-210876) are confirmed; DO-178C is a purchased RTCA standard (only secondary
  descriptions were consulted).
