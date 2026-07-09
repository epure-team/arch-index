---
name: roster-spec
type: spec
status: live
feature: CFG post-dominator dominance + lambda nodes + enumerated demotion
brief: briefs/cfg-postdom-dominance-intake.md
date: 2026-07-09
version: 1.0.0
---

# Spec — Precise CFG post-dominance, lambda nodes, enumerated demotion

## Clarifications

| Q | A |
|---|---|
| Nested lambda inside a lambda — naming? | **Chained**: `parent.<fun:L1:C1>.<fun:L2:C2>`; the inner lambda's parent IS the outer lambda node (matches attribution and Go/Rust precedent). |
| Two lambdas on one line collide under `<fun:LINE>`? | **Always `<fun:LINE:COL>`** — line:column (1-based column) of the literal's `loc_start`. Never collides in human code; stable; locatable. |
| Lambda both invoked AND passed — one edge or two? | **Per-occurrence edges**: the calls table is per-call-site; each occurrence gets its own edge with its own kind (invocation site MUST iff always-exec; any other occurrence MAY_ENUMERATED). |
| `LINE`/`COL` source? | The literal's `exp_loc.loc_start` (`pos_lnum`, `pos_cnum - pos_bol + 1`). |
| Noreturn "no fall-through" — is a lone `raise` body exit-less? | No: noreturn blocks **edge to the virtual exit** (divergence is an exit — matches Go, where a panic block is terminal and feeds the exit). `hasExit=false` (→ nothing MUST) fires only for genuinely exit-less bodies (`while true do () done`). Code *after* a noreturn is entry-unreachable → demoted, never dropped. |
| Does `reaches` now work through `List.iter (fun …)`? | **No** — `reaches` stays MUST-only; a passed callback is MAY_ENUMERATED. The win for callbacks is in `unreachable` (REACHABLE instead of UNKNOWN) and `escapes` (⊤ noise gone). |
| Does the parent→lambda edge replace the old `*TOP*` arg-escape row for literals? | **Yes, replaces.** Named-function arguments keep today's behavior. |
| Do lambda bodies get their own CFG? | Yes — MUST inside a lambda = post-dominates the *lambda's* entry. Attribution moves exclusively to the lambda node (main path). Effects extractor unchanged (accepted inconsistency: lambda effects still lump into the parent). |
| Demotion target for a conditional call with uniquely-resolved callee? | **MAY_ENUMERATED (candidate set of one), in BOTH backends** (OCaml + Go). MAY_TOP is reserved for truly unknowable targets (computed heads, parameter calls, FFI, reflection). Equally sound; erases fake ⊤ frontier. |

## User Stories

### US-1: Computed post-dominance replaces the syntactic nested-counter (R1) (Priority: P0)
As a security engineer running `arch-query reaches/unreachable`, I want MUST edges computed by
post-dominance over a real per-function CFG so that conditional/diverging control flow can never
forge a MUST edge and unconditional divergence no longer over-claims `reaches`.
**Why this priority**: keystone — everything else (lambda CFGs, demotion kinds) builds on it; closes the documented divergence residual.
**Scope**: does NOT cover lambda promotion (US-2), demotion-kind refinement (US-4), cross-arm MUST merging (forbidden), or general noreturn inference (fixed head list only).
**Independent Test**: index a corpus module exercising straight-line/branch/raise/try shapes and assert `reaches`/`unreachable` verdicts.
**Acceptance Scenarios**:
1. **Given** `let f x = g x; h x`, **When** indexed, **Then** both `g` and `h` edges are MUST.
2. **Given** `let f b x = if b then g x else 0`, **When** indexed, **Then** the `g` edge is not MUST (branch does not post-dominate entry) and is never dropped.
3. **Given** `let f x = raise Exit; g x` (warnings suppressed), **When** indexed, **Then** `raise` is MUST and `g` is demoted (post-raise block entry-unreachable) — `reaches f g` = no MUST path.
4. **Given** `let f x = try g x with Not_found -> h x`, **When** indexed, **Then** `g` is MUST, `h` is demoted; **and given** `try raise Exit with Not_found -> h x`, `h` is NOT MUST (handler never post-dominates: the raise also edges to the virtual exit).
5. **Given** `let f () = loop (); g ()` where `loop` may not terminate, **Then** `g` remains MUST (termination/exception-insensitivity residual stands for ordinary calls; only syntactic noreturn heads terminate blocks).
6. **Given** the existing soundness corpus, **When** `STRICT=1 ./selftest-callgraph-soundness.sh`, **Then** every P1 assertion passes and no call is dropped (all fixture callees present with a valid kind).

### US-2: Nested lambdas become synthetic graph nodes (R2) (Priority: P0)
As an engineer auditing callback-heavy code, I want each `fun`/`function` literal to be its own
function node (`parent.<fun:LINE:COL>`, chained for nesting, exposed=0, parent's module) with its
own CFG, so callback-body calls are precise MUST edges of the lambda instead of ⊤ noise on the parent.
**Why this priority**: the measured prize — 2032/2193 self-index MAY_TOP edges have known callees, dominated by callback bodies.
**Scope**: does NOT cover lazy/object/functor bodies (stay plain deferred, attributed to parent), lambda function-rows on the LSP flat path (names flow through only), or the effects extractor.
**Independent Test**: index a corpus with passed/invoked/unused/nested lambdas and assert node existence, edge kinds, and verdicts.
**Acceptance Scenarios**:
1. **Given** `let lam_map xs = List.map (fun y -> island y) xs`, **When** indexed, **Then** node `lam_map.<fun:L:C>` exists with a MUST edge to `island`; parent→lambda is MAY_ENUMERATED; `unreachable lam_map island` = REACHABLE (may-reach); `reaches lam_map island` = no MUST path.
2. **Given** `let invoked x = let h () = island x in h ()`, **When** indexed, **Then** parent→lambda is MUST (invocation post-dominates entry; local stamp→node resolution) and lambda→island is MUST, so `reaches invoked island` = PATH EXISTS.
3. **Given** `let unused x = let h () = island x in ignore h; x`, **Then** parent→lambda is MAY_ENUMERATED (the `ignore h` occurrence is an escape site) — `unreachable unused island` = REACHABLE (may-reach).
4. **Given** a lambda bound and NEVER referenced (`let h () = island x in x`), **Then** no parent→lambda edge exists (the lambda is genuinely dead) and `unreachable f island` may honestly report UNREACHABLE.
5. **Given** nested literals, **Then** nodes chain (`f.<fun:10:12>.<fun:11:4>`) with attribution at each level, and inner-node calls are MUST of the inner node when post-dominating its entry.

### US-3: Query-surface and pipeline integrity with synthetic rows (Priority: P1)
As an arch-query/arch-index user, I want every existing consumer to stay correct when synthetic
lambda rows exist, so added precision cannot corrupt other results.
**Why this priority**: guards the blast radius; the feature is unshippable without it.
**Scope**: does NOT add subcommands or schema columns; audits and (only if the audit requires) minimally adjusts existing queries.
**Independent Test**: run the full selftest suite + a one-time audit of all 15 functions/calls-reading subcommands.
**Acceptance Scenarios**:
1. **Given** an index with lambda nodes, **Then** `exported` lists none of them (exposed=0) and `find '<fun:'` locates them.
2. **Given** a lambda whose only incoming edge is MAY_ENUMERATED, **Then** `dead-code` does not flag it (closure includes MAY edges).
3. **Given** the corpus fixture `lam_map`, **Then** `escapes lam_map` reports an empty ⊤ frontier (absolute assertion replacing "smaller than before").
4. **Given** the LSP fallback path on a lambda-bearing module, **Then** `call_graph_extractor`/`runner` load flat rows with synthetic caller names without error (kind-less schema unaffected).
5. **Given** the new index, **Then** `callgraph_contract=v1` is still stamped, loader kind-validation passes, and the self-index golden is regenerated deliberately with the new counts.

### US-4: Enumerated demotion for uniquely-resolved conditional calls (OCaml + Go) (Priority: P1)
As a user of `unreachable`/`escapes`, I want a conditional call whose callee is uniquely resolved
demoted to MAY_ENUMERATED (candidate set of one) instead of MAY_TOP, in both backends, so the ⊤
frontier contains only truly unknowable targets.
**Why this priority**: erases most of the 1683 fake-⊤ edges; restores `unreachable`'s discriminating power.
**Scope**: does NOT change `reaches` (MUST-only), the kind vocabulary, or the loader contract; MAY_TOP remains for computed heads, parameter calls, FFI/reflection, and true unknowns.
**Independent Test**: corpus assertions on both backends: conditional known-callee → MAY_ENUMERATED; `unreachable` returns REACHABLE/UNREACHABLE (not UNKNOWN) when no true ⊤ is reachable.
**Acceptance Scenarios**:
1. **Given** OCaml `let f b x = if b then g x else 0` (g top-level), **Then** the f→g edge kind is MAY_ENUMERATED and `unreachable f island` = UNREACHABLE (island not in g's subtree; no ⊤ reachable).
2. **Given** Go `func F(b bool) { if b { G() } }`, **Then** the F→G edge is MAY_ENUMERATED and `unreachable F island` is decidable (not UNKNOWN).
3. **Given** a conditional call through a parameter (`if b then f x` where f is a parameter), **Then** the edge stays MAY_TOP (target unknowable) and `unreachable` stays UNKNOWN.

## Challenges

| ID | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1 | Shadowed `failwith`/`exit` treated as terminator? | Noreturn detection is **resolved-Path-based** (Typedtree already resolved `raise` → `Stdlib.raise`); a local shadow resolves to a different path → ordinary call. Shadow-proof by construction. |
| C-2 | US-1 | What is a noreturn *application*? | Terminator iff a `Texp_apply` **head** resolves to a known-noreturn path AND is saturated (all listed heads have arity 1). `raise` as an argument/eta-expanded/partial → ordinary occurrence. |
| C-3 | US-1 | "raise is MUST" — to what? | Existing representation: unresolved MUST leaf (`Stdlib.raise`, callee_id NULL) — unchanged; selftest asserts the row's kind. |
| C-4 | US-1 | Try-body exception edges can forge MUST via handlers | Model: ordinary calls in a try body get NO exceptional edges (accepted exception-insensitivity residual, same as Go). A **noreturn head inside a try body** gets two successors: handler-dispatch AND virtual exit (handler may not match). Handlers branch from dispatch and flow to the post-try join. Consequences: handler never post-dominates entry (no false MUST even for `try raise Exit with Not_found -> h`); the raise itself stays MUST; post-try code after a noreturn-only body is conditional (reachable only via handlers). |
| C-5 | US-1 | hasExit semantics when all paths diverge | Divergence counts as exit (noreturn → virtual exit). `if b then raise A else raise B; g ()`: both raises conditional (neither post-dominates), `g` entry-unreachable → demoted. `hasExit=false` only for genuinely exit-less loops. Same semantics as Go panic blocks. |
| C-6 | US-1 | Unmodeled-construct fallback granularity | Unmodeled `Texp_*` nodes are opaque straight-line nodes: their subexpressions walk in conditional mode (demoted, never dropped); the node itself falls through (code after keeps its position). |
| C-7 | US-1 | Guards / partial matches | All `when` guards and all arms are conditional (even the first arm's pattern can fail). Partial-match `Match_failure` is NOT modeled (accepted residual; post-match code keeps position). |
| C-8 | US-1 | `assert false` vs `assert cond` | `Texp_assert` whose argument is the literal `false` constructor → terminator (compiler does not elide `assert false` under `-noassert`). Any other assert: condition conditional, fall-through only, no exit edge. |
| C-9 | US-1 | How is "no call dropped" verified? | Corpus assertions (every fixture callee present with a valid kind) + `kind NOT NULL/invalid = 0` invariant + one-time dev diff of callee populations old-vs-new (modulo the sanctioned `*TOP*`-literal replacement) + codex adversarial rounds. |
| C-10 | US-1 | `nested`-counter consumers (arg-escapes, letop) | The counter's role is replaced by block-conditionality: `!nested > 0` → "current block does not post-dominate entry (or is in a deferred region)". Same demotion rule, computed. Inside a lambda body, depth-0 is the lambda's own CFG. |
| C-11 | US-1 | `while true do … done; g ()` | No constant-folding; loops always get an exit edge; `g` stays MUST (termination-insensitivity residual). Documented; accepted divergence from Go's structural `for{}` detection. |
| C-12 | US-2 | Local `let h = fun … in h ()` → MUST needs a mechanism | New scoped table: `Texp_let` with `Tpat_var` and a literal RHS records local stamp → (lambda node name, literal arity). Head applications of that stamp resolve to the node (MUST iff always-exec and saturated). Conditional bindings (`if b then fun… else fun…`), tuple patterns, rebinding: NOT recorded → today's MAY_TOP behavior stands. |
| C-13 | US-2 | Identical LINE:COL (ppx/ghost locs) | Ghost-loc literals still get nodes. On name collision within a module, append a deterministic occurrence ordinal INSIDE the marker: `<fun:LINE:COL#2>`, `<fun:LINE:COL#3>`. |
| C-14 | US-2 | COL base; brief says `<fun:LINE>` | 1-based column. Intake brief's naming corrected to `<fun:LINE:COL>` (chained). |
| C-15 | US-2 | Lambda inside a top-level NON-function binding | **Erratum (plan-phase, verified in code):** every top-level `Tpat_var` binding gets a functions row (`arch_index_cmt.ml:830`), including non-function bindings, and calls are collected from them (`:1019`). So the parent DOES have a node: `table.<fun:L:C>` chains normally and the parent→lambda edge resolves. No residual. |
| C-16 | US-2 | Returned literal after a sequence; escape-kind taxonomy | Every non-peeled literal is a node. Taxonomy is two-way: parent→lambda = MUST (invocation at always-exec site) else MAY_ENUMERATED (passed/stored/returned/any other occurrence). MAY_TOP never applies to a named literal. Brief's "MAY_TOP if escapes into unknowable positions" is superseded. |
| C-17 | US-2/4 | Conditional invocation; parallel edges | Conditional invocation of a known lambda/function → MAY_ENUMERATED (US-4). Parallel edges of different kinds to one target are fine (per-site rows; closures dedup by id). |
| C-18 | US-2 | Bound-but-never-referenced lambda | No occurrence → no edge → orphan node, honestly dead (may be UNREACHABLE — sound and more precise than today). Any non-head occurrence of the stamp = escape site → MAY_ENUMERATED edge there. |
| C-19 | US-2 | "Drops substantially" untestable | CI gates only deterministic corpus assertions. The self-index MAY_TOP share is recorded in the QA brief (expectation: well under 40%, from 77.9%) as a manual check, not a CI gate. |
| C-20 | US-2 | Synthetic row columns | Same INSERT path; exposed=0; line_start/line_end from the literal's loc; signature derived from `exp_type` when cheap else NULL; comment fields NULL (NULL quality scores fall out of `< 50` filters naturally). |
| C-21 | US-2 | Partial application of a bound lambda | The scoped table records the literal's syntactic arity; under-saturated invocation → MAY_ENUMERATED (closure created, body deferred), never MUST. |
| C-22 | US-3 | "Every subcommand" over-claims | Plan includes a one-time audit of all 15 functions/calls-reading subcommands (arch-query is one file); selftest asserts the risky five (exported, dead-code, escapes, find, stats). |
| C-23 | US-3 | dead-code closure assumptions | Research confirms dead-code's closure is MUST∪MAY_ENUMERATED∪MAY_TOP. Audit re-verifies roots vs exposed=0. Orphan lambdas flagged dead = correct. |
| C-24 | US-3 | Comparative escapes assertion | Replaced by absolute corpus assertion: `escapes lam_map` = empty frontier. |
| C-25 | US-3 | LSP path unowned | Owned by US-3 scenario 4: flat path loads synthetic caller names without error. |
| C-26 | US-3 | Contract doc / version honesty | `callgraph_contract=v1` stays (kind vocabulary and query semantics unchanged in shape; MUST stricter = sound direction). `docs/edge-kind-contract.md` updated: "no CFG" phrase removed, divergence residual narrowed (closed for syntactic noreturn outside try), lambda-node semantics + MAY_ENUMERATED demotion documented. Owned by US-3/ship. |

## Functional Requirements

#### CFG + post-dominance (US-1)
- **FR-001** [US-1]: The OCaml producer MUST lower each function body (and each lambda body) to a per-function CFG in which sequences/let-bindings are straight-line, and if/match/try/while/for/`&&`/`||`/letop-continuations introduce branch structure.
- **FR-002** [US-1]: The producer MUST classify a call edge MUST only if the call's basic block post-dominates the CFG entry (computed by an iterative post-dominance fixpoint over the reversed CFG with a virtual exit), and the existing head-resolution/saturation rules also hold.
- **FR-003** [US-1]: A saturated application whose head resolves (Path-based) to `Stdlib.raise`, `Stdlib.raise_notrace`, `Stdlib.failwith`, `Stdlib.invalid_arg`, `Stdlib.exit`, or an `assert false` node MUST terminate its block with an edge to the virtual exit (plus a handler-dispatch edge when inside a `try` body); blocks unreachable from entry MUST have their calls demoted, never dropped.
- **FR-004** [US-1]: The producer MUST NOT treat a shadowed/eta-expanded/argument occurrence of a noreturn name as a terminator (detection is on the resolved Path in head position, saturated).
- **FR-005** [US-1]: The producer MUST NOT merge across match/if arms to prove MUST (per-block post-dominance only, consistent with the Go backend).
- **FR-006** [US-1]: Any Typedtree construct the lowering does not model MUST degrade conservatively as an OPAQUE STRAIGHT-LINE node (per EC-6): subexpressions walk in the current block via the default iterator (recorded, never skipped), fall-through preserved. (Erratum: the original "conditional mode" wording contradicted EC-6; every construct with conditionally-executed subexpressions is explicitly lowered, so the fallback only ever sees straight-line constructs — a new compiler constructor with deferred subexpressions must be added to the explicit matrix.)
- **FR-007** [US-1]: Exception-insensitivity for ordinary calls (code after a possibly-raising call keeps its CFG position) SHALL remain the documented residual; handlers MUST never post-dominate entry.

#### Lambda nodes (US-2)
- **FR-010** [US-2]: Every non-peeled `fun`/`function` literal MUST produce a synthetic functions row named `<enclosing-node>.<fun:LINE:COL>` (chained through enclosing lambdas; 1-based column; `#N` ordinal inside the marker on collision), with exposed=0, the parent's module_id, and the literal's line range.
- **FR-011** [US-2]: Calls inside a lambda body MUST be attributed to the lambda node (not the parent) on the main indexing path, and classified by post-dominance within the lambda's own CFG.
- **FR-012** [US-2]: Each occurrence of a lambda MUST yield a parent→lambda edge at that occurrence's call_site: MUST when the occurrence is a saturated head-invocation whose block post-dominates entry; MAY_ENUMERATED for every other occurrence (argument, store, return, partial application, conditional invocation). A literal argument's edge REPLACES the previous `*TOP*` arg-escape row.
- **FR-013** [US-2]: A bound lambda with zero occurrences MUST produce no parent→lambda edge (the node may be reported dead).
- **FR-014** [US-2]: Local `let`-bound literals MUST be resolvable at head-application sites via a scoped stamp→node table carrying the literal's syntactic arity; bindings that are not a single literal (conditional, tuple, rebound) MUST NOT be recorded.
- **FR-015** [US-2]: `lazy`, object-method, and functor bodies MUST NOT be promoted to nodes (remain deferred, attributed to the parent, demoted).
- **FR-016** [US-2]: The LSP fallback path MUST keep producing kind-less flat rows without error when caller names are synthetic; it MUST NOT be required to create function rows.

#### Query-surface integrity (US-3)
- **FR-020** [US-3]: `exported` MUST NOT list synthetic lambda rows; `find` MUST locate them by name.
- **FR-021** [US-3]: `dead-code` MUST NOT flag a lambda reachable from a root via MUST∪MAY_ENUMERATED∪MAY_TOP edges.
- **FR-022** [US-3]: The producer MUST still stamp `callgraph_contract=v1`; every emitted edge MUST carry a valid kind; the self-index golden MUST be regenerated deliberately with the new counts.
- **FR-023** [US-3]: All 15 functions/calls-reading arch-query subcommands MUST be audited against synthetic rows before ship; any required adjustment is in scope only if the audit demonstrates incorrect output.
- **FR-024** [US-3]: `docs/edge-kind-contract.md` MUST be updated to describe computed post-dominance, lambda-node semantics, the narrowed divergence residual, and enumerated demotion.

#### Enumerated demotion (US-4)
- **FR-030** [US-4]: In both the OCaml and Go producers, a demoted call whose callee is uniquely resolved MUST be emitted as MAY_ENUMERATED; MAY_TOP MUST be reserved for unresolvable targets (computed heads, parameter calls, FFI/reflection anchors, over-application residuals).
- **FR-031** [US-4]: `reaches` semantics MUST NOT change (MUST-only closure).
- **FR-032** [US-4]: `unreachable` MUST return a decidable verdict (REACHABLE/UNREACHABLE) on programs whose only dynamic behavior is conditional dispatch to resolved callees (no reachable true ⊤).

## Acceptance Criteria

- AC-1 [US-1, C-4]: `try raise Exit with Not_found -> h x` → `h` has no MUST edge; the raise is MUST; no call dropped.
- AC-2 [US-1 happy path]: straight-line calls MUST; branch calls demoted; post-raise calls demoted; existing P1 suite green under STRICT.
- AC-3 [US-2, C-12]: `let h () = island x in h ()` → `reaches parent island` = PATH EXISTS via the lambda node.
- AC-4 [US-2, C-18]: unused bound lambda → no parent edge; `unreachable` may say UNREACHABLE.
- AC-5 [US-3, C-24]: `escapes lam_map` = empty frontier on the corpus.
- AC-6 [US-4]: `unreachable cond_if island` on the corpus = UNREACHABLE (was UNKNOWN) — decidable without ⊤.
- AC-7 [US-1..4]: `STRICT=1 ./selftest-callgraph-soundness.sh`, `./selftest-callgraph-go.sh`, `dune test`, and all other selftests green; golden matches; no NULL/invalid kinds.

## Edge Cases

- EC-1 [US-1]: non-matching handler with noreturn-only try body → handler NOT MUST (C-4 model).
- EC-2 [US-1]: shadowed `failwith` → ordinary call (Path-based detection).
- EC-3 [US-1]: `if b then raise A else raise B; g ()` → raises conditional, `g` demoted (entry-unreachable).
- EC-4 [US-1]: `while true do () done; g ()` → `g` MUST (no constant folding; documented residual).
- EC-5 [US-1]: call in a `when` guard → conditional, all arms.
- EC-6 [US-1]: `Texp_letmodule`/`Texp_letexception`/unknown ppx nodes → opaque straight-line fallback (FR-006).
- EC-7 [US-1]: `Option.iter raise o` → raise is an argument, not a terminator.
- EC-8 [US-2]: ghost-loc/ppx duplicate LINE:COL → ordinal suffix.
- EC-9 [US-2]: literal in non-function top-level binding → node exists; parent edge dropped (pre-existing residual, documented).
- EC-10 [US-2]: `let h = if b then (fun…) else (fun…) in h ()` → stamp not recorded → invocation MAY_TOP (unknowable which literal), both literals are nodes with MAY_ENUMERATED escape edges at their occurrence sites… (their occurrence = being the if-arms' values: recorded as escape occurrences).
- EC-11 [US-2]: `h (); List.iter h xs` → MUST + MAY_ENUMERATED parallel edges; closures dedup by id.
- EC-12 [US-2]: `let g = h 1 in g 2` (h local lambda, arity 2) → partial at first site (MAY_ENUMERATED), `g` not recorded (not a literal) → second site MAY_TOP.
- EC-13 [US-2]: `let rec f x = List.iter (fun y -> f y) l` → cycle f→lambda (MAY_ENUMERATED) →f (MUST); closures terminate (visited-set semantics of recursive CTEs).
- EC-14 [US-3]: orphan lambda under `dead-code` → flagged (correct).
- EC-15 [US-4]: conditional call through a parameter → stays MAY_TOP; `unreachable` stays UNKNOWN.

## Runnable Checks

- CHECK-1 [AC-2, AC-7]: `eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch) && dune build && dune test` → exit 0.
- CHECK-2 [AC-1..6]: `STRICT=1 ./selftest-callgraph-soundness.sh` → exit 0, `P1: N passed, 0 failed` (suite extended with P2→P1 targets for every AC above).
- CHECK-3 [US-4/Go]: `./selftest-callgraph-go.sh` → exit 0 (extended with a MAY_ENUMERATED demotion assertion).
- CHECK-4 [FR-022]: self-index → `diff test/fixtures/self-index-stats.txt <(stats query)` → empty; `SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN (...)` → 0.
- CHECK-5 [FR-016]: `./selftest-callgraph-ocaml.sh && ./selftest-load.sh && ./selftest-effects.sh && ./selftest-contract.sh` → exit 0.
- CHECK-6 [C-19]: manual — record self-index kind distribution in the QA brief; expectation MAY_TOP well under 40%.
- CHECK-7 [FR-023]: manual — audit table of the 15 subcommands in the review/QA brief.

## Entities

- `CFG block`: a maximal straight-line sequence of call sites within one function/lambda body; edges from branch constructs; virtual exit collects terminal and diverging blocks.
- `post-dominance MUST`: edge kind for a saturated, uniquely-resolved call whose block post-dominates its CFG's entry.
- `lambda node`: synthetic functions row `<parent-chain>.<fun:LINE:COL>` (exposed=0) representing one `fun`/`function` literal, with its own CFG.
- `escape occurrence`: any occurrence of a lambda/function value other than a saturated always-exec head invocation → MAY_ENUMERATED edge.
- `noreturn head`: Path-resolved `Stdlib.{raise,raise_notrace,failwith,invalid_arg,exit}` in saturated head position, or `assert false` — terminates its block.
- `enumerated demotion`: a conditional call with a uniquely-resolved callee → MAY_ENUMERATED (candidate set of one), both backends.
