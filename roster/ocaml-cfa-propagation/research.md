# Research — ocaml-cfa-propagation

_Generated: 2026-09-16T14:07:35+02:00_
_Mode: full_
_Online research: enabled_

## Question 1: How are callable identities, finite target sets, uncertainty reasons, and source metadata currently represented, joined, and propagated by the OCaml analysis worklist?

**Finding:** The abstract value is the product of two independent finite string sets, one for callable targets and one for uncertainty reasons. Bottom is the pair of empty sets. Copy constraints are directed cell edges; component-wise set union and a deduplicated FIFO worklist compute the least fixed point. The CMT layer separately maps compiler binder identities to cells and stores each application as an occurrence carrying argument counts and residual metadata. Finalization seeds rejected declarations/literals, solves once, seals the session, and only then permits occurrence queries.

**References:**
- `lib/arch_index/arch_index_cfa.ml:1-14` — product value, integer cell and explicit bottom.
- `lib/arch_index/arch_index_cfa.ml:31-73` — enqueue-on-change, independent seeds, copy edges, union and solver.
- `lib/arch_index/arch_index_cfa_cmt.ml:1-44` — occurrence, owner, root, literal and session state.
- `lib/arch_index/arch_index_cfa_cmt.ml:292-337` — final solve and per-occurrence query result.

---

## Question 2: Which typedtree expression and binding forms currently create or connect values for function parameters, arguments, return positions, captured variables, recursive bindings, and partial applications?

**Finding:** Existing CFA enrollment is limited to non-recursive, single-variable bindings. Root and same-callable transfers recognize function literals, `Pident` aliases, two-way conditionals, match-arm results and sequence tails. Named and expression-headed applications record occurrences and argument-slot counts, but the public CFA API has no actual-to-formal, formal cell, body-result-to-call-result or closure-environment operation. Recursive call heads are handled by a separate direct classifier, and cross-callable captures remain explicit uncertainty. Partiality is occurrence metadata refined per candidate arity during expansion, not a propagated closure value.

**References:**
- `lib/arch_index/arch_index_cfa_cmt.ml:83-146` — root expression grammar and non-recursive enrollment.
- `lib/arch_index/arch_index_cfa_cmt.ml:201-267` — same-owner aliases and local expression transfer.
- `lib/arch_index/arch_index_cfa_cmt.mli:13-32` — current public registration surface.
- `lib/arch_index/arch_index_cmt.ml:2140-2153` — collector integration for local non-recursive bindings.
- `lib/arch_index/arch_index_cmt.ml:2508-2560` — call-head classification and named CFA occurrences.
- `lib/arch_index/arch_index_cmt.ml:2597-2619` — expression heads, direct literals and unknown computed heads.
- `lib/arch_index/arch_index_cmt.ml:676-706` — per-candidate partiality and residual handling.

---

## Question 3: How does the existing implementation distinguish declaration identity from individual occurrences when aliases, recursive references, or repeated applications share the same callable?

**Finding:** Declaration cells use `Ident.unique_name`; accepted root declarations also require the exact physical Typedtree body and canonical name. Function literals are tracked initially by physical expression identity and authenticated by owner/observation/storage state. Owners are session-local `(session, serial)` tokens. Every application receives a fresh monotone token and a separate occurrence record even when it points to the same abstract cell; private markers are expanded one occurrence at a time.

**References:**
- `lib/arch_index/arch_index_cfa_cmt.ml:10-13` — owner identity.
- `lib/arch_index/arch_index_cfa_cmt.ml:66-81` — physical literal and binder cell identities.
- `lib/arch_index/arch_index_cfa_cmt.ml:179-199` — authenticated roots and owner allocation.
- `lib/arch_index/arch_index_cfa_cmt.ml:269-290` — fresh token per named or expression occurrence.
- `lib/arch_index/arch_index_cmt.ml:715-733` — marker expansion by occurrence token.
- `tezt/tests/ocaml_cfa_foundation.ml:58-77` — same-line multiplicity and copied metadata assertions.

---

## Question 4: Which current transfer paths preserve an unknown component alongside known targets, and where do unsupported expressions or unseeded cells enter the analysis state?

**Finding:** Every domain copy and join propagates targets and reasons independently. Root aliases add callback uncertainty when their source was not enrolled, while conditionals and matches can therefore retain known candidates beside that frontier. Local cross-owner, parameter-like or absent identifiers become callback uncertainty. Unsupported expression forms, missing `else` branches, rejected or unauthenticated roots/literals and unknown arities also introduce explicit reasons. Fresh cells and unseeded cycles remain bottom; invoked bottom is retained as the original unresolved occurrence during expansion. Persistence currently recognizes `dropped_node` explicitly and collapses every other reason string to `callback_param`.

**References:**
- `lib/arch_index/arch_index_cfa.ml:14-29` — fresh bottom cells.
- `lib/arch_index/arch_index_cfa.ml:46-63` — independent target/reason propagation.
- `lib/arch_index/arch_index_cfa_cmt.ml:87-100` — root unknown entry points.
- `lib/arch_index/arch_index_cfa_cmt.ml:126-137` — root alias known-plus-unknown preservation.
- `lib/arch_index/arch_index_cfa_cmt.ml:201-260` — same-owner policy and unsupported local expressions.
- `lib/arch_index/arch_index_cfa_cmt.ml:294-317` — rejected/unobserved roots and literals.
- `lib/arch_index/arch_index_cmt.ml:686-713` — persistence mapping, arity uncertainty, residual and bottom fallback.

---

## Question 5: What regression fixtures and assertions currently cover propagation fixed points, arity mismatches, duplicate occurrences, metadata retention, and mixed known/unknown target sets?

**Finding:** Native tests compare the worklist against an independent repeated-scan oracle over mixed values, seeded and unseeded cycles, every directed three-node graph under order/duplication changes, late seeds/edges/re-solves and a 2,000-cell chain. Authentic CMT tests cover same-line duplicate occurrences, metadata, mixed known/unknown joins, literals, unknown/negative arity, omitted labels, partial and over-applied calls, independent residual uncertainty, and consumer query semantics. Current capture tests assert that captures stay unknown; they do not exercise captured callable propagation, argument/formal flow or return flow because those APIs do not exist.

**References:**
- `test/test_cfa.ml:11-48` — independent oracle and production-domain comparison.
- `test/test_cfa.ml:50-107` — fixed point, ordering, duplicate, late-update and long-chain cases.
- `tezt/tests/ocaml_cfa_foundation.ml:58-104` — occurrence identity, metadata and injected arities.
- `tezt/tests/ocaml_cfa_foundation.ml:395-413` — capture remains unknown.
- `tezt/tests/ocaml_cfa_foundation.ml:441-529` — mixed joins, literals, occurrence multiplicity and arity boundaries.
- `tezt/tests/ocaml_cfa_foundation.ml:558-573` — reachability and absence-query effects.

---

## Question 6: What pinned Tezos and Irmin inputs, baselines, comparison metrics, and reproducibility checks are already used to evaluate OCaml call-graph changes?

**Finding:** CHECK-3 freezes 410 selected CMT inputs from Tezos revision `1727d7e192f2374edda7ad7adceef6f4ec51f71a`, a 45,052-row baseline, canonical and artifact hashes, and separate Irmin/protocol relation counts of 4,849/12,171. It compares canonical row multisets and caller/site/target relation sets, records wall time and sampled peak RSS, and rejects input drift, relation losses or newly introduced `MUST` rows. The checker labels this structural accounting, not a semantic soundness or physical-occurrence proof.

**References:**
- `roster/ocaml-cfa-foundation/check-tezos.js:4-6` — explicit evidence limitation.
- `roster/ocaml-cfa-foundation/check-tezos.js:19-27` — frozen row, relation and hash baseline.
- `roster/ocaml-cfa-foundation/check-tezos.js:55-81` — relation key and Irmin/protocol partition.
- `roster/ocaml-cfa-foundation/check-tezos.js:125-170` — reproducibility metadata and frozen validation.
- `roster/ocaml-cfa-foundation/check-tezos.js:188-248` — resource sampling and delta report.
- `roster/ocaml-cfa-foundation/check-tezos.js:260-289` — pinned revision, replay and no-loss/no-new-MUST gates.

---

## Question 7: Which existing architectural review findings constrain the current analysis boundary, ownership model, convergence behavior, or evidence requirements?

**Finding:** Three recorded findings remain relevant. Several mutation entry points lack the finalized-session guard even though finalization performs the sole solve. Targets and semantic reasons share unrestricted strings and persistence has a catch-all reason mapping. Root and callable-local expression walkers duplicate the same Typedtree grammar while applying different ownership/literal authentication. The fixed point itself relies on finite union, edge deduplication and enqueue-on-change. Review evidence also distinguishes authentic per-occurrence fixtures from corpus-level structural comparison.

**References:**
- `roster/ocaml-cfa-foundation/architect-round2-findings.json:3-14` — incomplete finalized-session boundary.
- `roster/ocaml-cfa-foundation/architect-round2-findings.json:17-28` — unrestricted reasons and catch-all mapping.
- `roster/ocaml-cfa-foundation/architect-round2-findings.json:31-42` — duplicated transfer grammar.
- `lib/arch_index/arch_index_cfa.ml:31-73` — convergence mechanics.
- `roster/ocaml-cfa-foundation/round2-resolved-ledger.json:3-34` — resolved root-alias uncertainty loss and evidence record.

---

## Question 8: [ecosystem] How do documented production OCaml call-graph or control-flow analyses model argument-to-parameter flow, returned functions, closures, recursion, and partial application?

**Finding:** Shivers-style 0-CFA models variables and expression labels with sets of abstract closures and constrains applications so the operator's closures connect actual arguments to formal binders and function-body results to application results. The formalized Isabelle development proves a safe approximation. Abstracting Abstract Machines obtains finite higher-order analyses by bounding stores after allocating bindings and continuations in the store; this includes recursive and return flow in the machine state. OCaml Flambda instead operates after closure conversion: it represents recursive groups as sets of closures, exposes closure environments, propagates approximations to discover indirect callees, and uses wrappers/surrogates when rewriting closure variables or arguments. MLton documents higher-order control-flow analysis and defunctorization as whole-program optimizations.

**References:**
- https://www.ccs.neu.edu/home/shivers/papers/gcfa.pdf — abstract closure sets and 0-CFA application constraints (Shivers et al.).
- https://isa-afp.org/entries/Shivers-CFA.html — executable/formalized safe control-flow approximation (Breitner, 2010; current archive release 2026).
- https://www.khoury.northeastern.edu/home/dvanhorn/pubs/vanhorn-might-icfp10.pdf — store allocation and finite abstract machines (Van Horn & Might, 2010).
- https://ocaml.org/p/ocaml-base-compiler/4.12.0/doc/ocamloptcomp/Closure_conversion/index.html — OCaml closure sets, mutual recursion and normalized applications.
- https://ocaml.org/manual/5.5/flambda.html — indirect-callee approximation propagation, closures, recursive groups and wrappers.
- https://www.mlton.org/WholeProgramOptimization — documented higher-order CFA and defunctorization in a whole-program compiler.

---

## Question 9: [ecosystem] What conservative handling of unsupported typedtree constructs and unresolved callees is documented in established static-analysis frameworks for higher-order functional languages?

**Finding:** The cited CFA formulations compute safe over-approximations: a finite abstract state represents all possible concrete closures rather than choosing one unresolved callee. The abstract-machine formulation makes this explicit as nondeterministic transitions over a finite state space. Infer's documented abstract domains distinguish bottom from unknown and expose a sound-unknown-set join mode; missing interprocedural summaries are returned explicitly as absent rather than silently treated as a known callee. OCaml Flambda also documents limits on which higher-order-return cases it can discover, rather than claiming complete resolution.

**References:**
- https://isa-afp.org/entries/Shivers-CFA.html — safe approximation and correctness proof.
- https://www.khoury.northeastern.edu/home/dvanhorn/pubs/vanhorn-might-icfp10.pdf — nondeterministic finite approximation.
- https://github.com/facebook/infer/blob/main/infer/src/labs/README.md — interprocedural dependency lookup returns `None` for missing/native callees.
- https://github.com/facebook/infer/blob/main/infer/man/man1/infer-full.txt — bottom/unknown and sound unknown-set join options.
- https://ocaml.org/manual/5.5/flambda.html — documented supported and unsupported higher-order discovery after closure conversion.

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---:|---|
| Product lattice | `lib/arch_index/arch_index_cfa.ml` | 1–73 | Finite targets and reasons propagate independently. |
| Root expression transfer | `lib/arch_index/arch_index_cfa_cmt.ml` | 83–101 | Identifier/literal/if/match/sequence grammar. |
| Same-owner expression transfer | `lib/arch_index/arch_index_cfa_cmt.ml` | 223–261 | Parallel grammar with owner authentication. |
| Per-occurrence expansion | `lib/arch_index/arch_index_cmt.ml` | 676–733 | Candidate arity and unknown residuals preserve the source occurrence. |
| Independent fixed-point oracle | `test/test_cfa.ml` | 11–48 | Full scans rather than the production queue implementation. |
| Pinned corpus replay | `roster/ocaml-cfa-foundation/check-tezos.js` | 125–289 | Hash-checked Tezos input and exact delta accounting. |

## External prior art

| Tool / Paper / Approach | Source | Key finding |
|---|---|---|
| Shivers CFA formalization | https://isa-afp.org/entries/Shivers-CFA.html | Safe functional call-graph approximation is formalized and proved correct. |
| Abstracting Abstract Machines | https://www.khoury.northeastern.edu/home/dvanhorn/pubs/vanhorn-might-icfp10.pdf | Finite stores turn higher-order machine semantics into a computable fixed point. |
| OCaml closure conversion / Flambda | https://ocaml.org/manual/5.5/flambda.html | Closure environments and propagated approximations support indirect-call discovery after closure conversion. |
| MLton whole-program optimization | https://www.mlton.org/WholeProgramOptimization | Production compiler combines defunctorization and higher-order CFA. |
| Infer interprocedural analysis | https://github.com/facebook/infer/blob/main/infer/src/labs/README.md | Missing callee summaries remain explicit at the analysis boundary. |

## Coverage gaps

- The repository contains no current CFA transfer API or regression for actual-to-formal flow, returned callable flow, or captured callable propagation.
- The pinned corpus establishes exact structural gains/losses but cannot establish semantic soundness, completeness, or physical occurrence identity.
- The ecosystem sources describe analysis semantics or compiler optimizations at different IR levels; they do not provide a drop-in Typedtree transfer grammar.
