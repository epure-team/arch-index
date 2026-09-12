# Research — guard-division-analysis

_Generated: 2026-09-12T20:01:28.867Z_
_Mode: full_
_Online research: enabled_

Three fresh-context agents answered the closed neutral manifest (five codebase and two ecosystem questions): Sol analyzer Q2–4, Terra locator/pattern librarian Q1/Q5, Sol external Q6/Q7. Locator/pattern roles combined to respect the three available child slots. Root synthesis is intent-aware; underlying research threads did not receive task/brief/roadmap text. Pattern agent initially inspected main, disclosed and reverified all accepted excerpts in the assigned worktree; discarded initial links are not evidence. No product edits or research builds.

## Question 1: Where are the repository’s OCaml CLI components defined, and how are their binaries, libraries, commands, fixtures, and tests organized?

**Finding:** directory-local Dune executables under bin, public arch_index library with private CMT/exn modules, separate decision-lint PoC, central Tezt registration/generated CLI dependency paths.
**References:** bin/arch_callgraph_ocaml/dune:1; bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml:3; lib/arch_index/dune:1; poc/decision-lint/bin/dune:1; tezt/lib/dune:71.
See [verified snippets](research-patterns.md).

## Question 2: How does the existing code classify OCaml syntax and operands, and where does it consume Typedtree or CMT data, including compiler primitive identities?

**Finding:** Cmt_format reads typed Implementation structures; application primitive identity is Val_prim. Existing divisor context records original slot2 as integer literal/identifier/other/missing, without evaluation. Closed primitive list includes int/int32/int64/nativeint division and remainder.
**References:** lib/arch_index/arch_index_cmt.ml:2751; lib/arch_index/arch_index_exn.ml:435; lib/arch_index/arch_index_exn.ml:464; lib/arch_index/arch_index_exn.ml:478; tezt/tests/exn_raise_sets.ml:296.
See [full analyzer trace](research-analyzer.md).

## Question 3: What integer semantics are currently encoded or assumed, including machine-integer width, overflow behavior, division behavior, and representation of unknown or unsupported expressions?

**Finding:** searched live OCaml paths encode integer kinds and syntax but no numeric range, width, overflow or quotient interpreter; a nonzero literal still creates a Division_by_zero origin. Unsupported syntax is other/missing, separately from exception Top.
**References:** lib/arch_index/arch_index_exn.ml:478; lib/arch_tools/arch_origin_context.ml:134; tezt/tests/exn_raise_sets.ml:300; lib/arch_tools/arch_exn.ml:497.
Absence claim is bounded to searched paths, not all historical/unmerged branches.

## Question 4: Where are control-flow states represented, and how do existing analyses handle branches, joins, unreachable states, top/bottom values, and unsupported constructs?

**Finding:** per-function mutable CFG blocks/successors/termination solve Boolean arrays for reachability/liveness/postdominance. If/match/try/loops create arms/joins. No numeric environment is represented. Exception propagation has Known sets/Top with known contribution and reasons, union joins and a predecessor worklist, not an integer domain.
**References:** lib/arch_index/arch_index_cfg.ml:20,62,85; lib/arch_index/arch_index_cmt.ml:1782,1943; lib/arch_tools/arch_exn.ml:57,464,533.
Default Typedtree traversal visits unsupported children without dedicated CFG lowering.

## Question 5: How are deterministic diagnostics, provenance, coverage scope, rule verdicts, allowances, and coverage references currently produced and tested?

**Finding:** rule results separate verdict from policy, sorted origin identities and count-bounded allowances. Producer provenance links persisted rows. Generic analysis-coverage statuses are distinct from recurring reference comparisons. Consumer validates totals/groups/module population and six-file status-dependent report publication.
**References:** lib/arch_tools/arch_rule_eval.ml:117,522,1016; tezt/tests/rules_origin.ml:263; tezt/tests/provenance.ml:24; lib/arch_index/coverage_matrix.ml:8; scripts/origin-consumer.js:63,89,122,216; scripts/origin-consumer-artifacts.js:9.
The pattern agent's scripts/test-only filename search excludes checks/ and tezt/, so it is not evidence of absent tests; checks/origin-recurring-consumer.js and tezt/tests/origin_recurring_consumer.ml are present.

## Question 6: [ecosystem] How do existing OCaml compiler APIs expose Typedtree/CMT primitive identities and machine-integer operations across supported compiler versions?

**Finding:** typed identifiers expose compiler value descriptions/Val_prim separately from printed spelling. OCaml compiler-libs is version-sensitive (notably function representation changed between4.14 and5.2). OCaml5.3 int arithmetic is modular, Sys.int_size bits, with division truncating toward zero. Polymorphic comparison primitive names differ from specialized integer names. Public5.3 docs do not separately spell out min_int/-1 result; no special-case result inferred here.
**References:** [OCaml5.3 Int](https://ocaml.org/manual/5.3/api/Int.html), [5.3 Stdlib](https://github.com/ocaml/ocaml/blob/5.3/stdlib/stdlib.mli), [5.3 primitive translation](https://github.com/ocaml/ocaml/blob/5.3/lambda/translprim.ml), [5.2 Typedtree](https://github.com/ocaml/ocaml/blob/5.2/typing/typedtree.mli).
Local declared compiler floor is >=5.3.0 (dune-project:10); CI pins5.3. This does not certify every later compiler.
See [full external report and version caveats](research-external.md).

## Question 7: [ecosystem] How do established intraprocedural abstract interpreters represent integer division, overflow, branches, joins, top/bottom, and conservative unknown results?

**Finding:** existing analyzers use overapproximating state domains, bottom for infeasibility, top for imprecision, branch reduction, joins and widening for loops. Goblint checks zero/possibly-zero/nonzero before division. C-language overflow/alarm semantics are not OCaml modular semantics.
**References:** [Eva Abstract_domain](https://www.frama-c.com/api/frama-c-eva/Eva/Abstract_domain/index.html), [Goblint analysis](https://github.com/goblint/analyzer/blob/master/src/analyses/base.ml), [Infer analysis lab](https://github.com/facebook/infer/blob/main/infer/src/labs/README.md).

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| Thin Cmdliner wrapper | bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml | 3–24 | library execution then diagnostic/exit |
| Compiler primitive identity | lib/arch_index/arch_index_exn.ml | 464–506 | typed descriptor, not operator spelling |
| Intraprocedural graph solver | lib/arch_index/arch_index_cfg.ml | 85–152 | reachability and postdominance |
| Set-domain join | lib/arch_tools/arch_exn.ml | 464–474 | Top with known sets/reasons |
| Separate census and policy | scripts/origin-consumer.js | 216–244 | reference drift cannot waive policy |

## External prior art

| Tool / Paper / Approach | Source | Key finding |
|---|---|---|
| OCaml5.3 integer API | https://ocaml.org/manual/5.3/api/Int.html | modular machine ints, overflow not an exception |
| OCaml compiler-libs | https://github.com/ocaml/ocaml/blob/5.2/typing/typedtree.mli | typed identities; version-sensitive shapes |
| Frama-C Eva | https://www.frama-c.com/api/frama-c-eva/Eva/Abstract_domain/index.html | overapproximating domains, Top/Bottom and separate alarms |
| Goblint | https://github.com/goblint/analyzer/blob/master/src/analyses/base.ml | zero/possible/nonzero checks, unsupported integer operators→Top |
| Infer lab | https://github.com/facebook/infer/blob/main/infer/src/labs/README.md | branch join and loop leq/widen for termination |

## Coverage gaps

- No numeric value interpreter found in searched live paths; not a proof none exists in historical worktrees.
- Compiler public docs do not separately specify min_int/-1; general modular contract is documented.
- External sources span versions;5.3 addendum is the version-matched arithmetic reference.
- No single universal interval division formula established for intervals straddling zero.
- Generic matrix decision-lint detail says not integrated, while Tezt's dependency builds it: reported metadata text is not evidence the binary is unavailable.
- Graph orientation skipped: no installed research-orientation pack; no graph-derived authority used.

