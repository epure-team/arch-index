---
name: roster-spec
type: spec
status: live
feature: Exception-identity may-raise sets (roadmap 3.4, strengthened)
brief: briefs/exn-raise-sets-intake.md
date: 2026-09-03
version: 1.0.0
---

# Spec — Exception-identity may-raise sets (`exn-raise-sets`)

Autonomous-mode spec: every clarification below was resolved from the brief, the research, the
compiler interfaces (`typedtree.mli`/`types.mli`/`ident.mli`, verified with a probe), or the
roadmap. No question was put to the user. Decisions the user may want to overturn are marked
**[decision]**.

## Clarifications

| Q | A |
|---|---|
| What is a "raise head"? | **[decision — supersedes the intake's Stdlib-path rule for `raise`]** A `Texp_apply` whose head is `Texp_ident (_, _, vd)` with `vd.val_kind = Val_prim {prim_name = "%raise" \| "%raise_notrace" \| "%reraise"}` and ≥ 1 argument. Primitive-keyed, not Path-keyed: Tezos's protocol environment re-exports `raise` as its own `external … = "%raise"` under a non-`Stdlib` path (challenge C-10), and any `external my_raise : exn -> 'a = "%raise"` is a raise. `Stdlib.failwith` / `Stdlib.invalid_arg` stay **Path-keyed on the persistent `Stdlib` root** (same recogniser as `noreturn_head`): in protocol code `failwith` is `Error_monad.failwith : … tzresult Lwt.t` and must NOT be an origin. `Stdlib.Printexc.raise_with_backtrace` (Path-keyed) is a raise head on its first argument (EC-6). |
| Canonical `exn_path` string? | Root ident `is_predef` ⇒ bare `Path.name` (`Not_found`, `Failure`, `Invalid_argument`, `Match_failure`, `Assert_failure`, …; probe: `persistent=false is_predef=true`). Root `Ident.persistent` ⇒ `Path.name` verbatim (e.g. `Tezos_raw_protocol_alpha__Storage.Missing_key`; `Stdlib.Exit`). Root is an ident declared by a structure item of the current unit (registered while walking `Tstr_exception` / `Tstr_typext` / `Tstr_module` with their `qualify ~prefix` path) ⇒ `<cmt_modname>.<prefix><rest>` — this is what a cross-unit persistent path prints, so raise site in unit A and handler in unit B agree. Anything else (`let exception`, `let module`, functor parameter roots) ⇒ `local:<Ident.unique_name root>[.rest]`. |
| `exception E2 = F.E` rebinding? | Producer records `exn_rebinds(alias_path, target_path)` from `Text_rebind`; the query canonicalises every path to its rebind target (transitively) before set operations (EC-5). |
| Which arms of a handler count as *closing*? | An arm is closing iff it is unguarded (`c_guard = None`) **and** its RHS contains no application of a raise head to a non-literal argument (a raise whose argument is not a `Texp_construct` with `Cstr_extension`). A `raise (Lit …)` inside an arm is an ordinary origin of the node (attributed to the scope's *parent* chain). This subsumes the direct `\| e -> …; raise e` idiom and the indirect `\| e -> match e with … \| o -> raise o` (EC-11): both are non-closing. Over-approximating direction; never under-catches. |
| Caught set of a closing arm? | `Tpat_construct` with `Cstr_extension` ⇒ that path; `Tpat_or` ⇒ union of both sides; `Tpat_alias (p, _)` ⇒ caught(p); `Tpat_any` / `Tpat_var` ⇒ **catch-all**; `Tpat_construct` on a non-extension constructor cannot occur for `exn`; anything else (`Tpat_constant`, `Tpat_lazy`, `Tpat_record`) ⇒ contributes nothing. Scope: `caught = ⋃ arms`, `catch_all = ∃ closing catch-all arm`. |
| What does `try` cover? | Exactly the body expression of `Texp_try`, lexically — including calls made while evaluating arguments inside the body (EC-2) and literal lambdas *occurring* in the body (their parent→lambda occurrence edge carries the scope; their own bodies do not — C-1/US-1.3). |
| What does `match … with exception` cover? | Exactly the scrutinee expression of a `Texp_match` that has ≥ 1 `Tpat_exception` computation case; value cases' RHS are outside. Scope `form = match_exception`; arms are the `Tpat_exception p` cases, with `p` classified as above. |
| Raising primitives other than `raise`? (implementation amendment, 2026-09-03) | Recognised by primitive name like raise heads: polymorphic comparison (`%equal`… `%compare`) → origin `compare`/`Invalid_argument` **only when some argument type may hold a closure** (predef ground types and lists/options/arrays/tuples of them cannot raise — the typed tree decides); `%divint`/`%modint`/`%int32_div`… → `division`/`Division_by_zero`; `%array_safe_get/set`, `%string_safe_get`, `%bytes_safe_get/set` → `index`/`Invalid_argument`. Consequently the query's fixed table (FR-013) also lists those `Stdlib` leaves and the primitives that cannot raise (`ignore`, `not`, `&&`, `\|\|`, integer/float arithmetic and bit ops, `fst`/`snd`, `ref`/`!`/`:=`/`incr`/`decr`, `==`/`!=`, int/float conversions, `\|>`/`@@`, `Array.length`/`String.length`/`Bytes.length`) — without this every function using `ignore` or `>` is ⊤, and the measurement means nothing. |
| Re-raise semantics (implementation amendment) | A `reraise` origin is informational and contributes nothing to `direct(n)`: what a re-raising arm forwards is exactly what the non-closing rule already leaves in the try body's set (`B − closing(P)` ⊇ `B ∩ P_arm`). Storing it with `escapes = 1` keeps the site findable. |
| Origins and their forms? | `raise` (raise head, literal `Cstr_extension` arg → path), `reraise` (raise head whose argument is an identifier bound by the pattern of an enclosing closing-or-not handler arm of the same node → forwards that scope's caught set at query time; `exn_path` NULL; `scope_id` = that scope), `unknown` (raise head, any other argument → ⊤ `unknown_exn_value`), `failwith` → `Failure`, `invalid_arg` → `Invalid_argument`, `assert` → `Assert_failure` (every `Texp_assert`, including `assert false`), `partial_match` → `Match_failure` (a `Texp_match` with `Partial`, a `Tfunction_cases` with `partial = Partial`, or a `function_param` with `fp_partial = Partial`; the origin's line/col is the match/function expression; a root `function` body's origin belongs to the top-level node — C-12). `exit` is not an origin. |
| Escape flag? | `escapes = 1` iff walking the origin's scope chain outward (`scope_id`, `parent_id`, …) no scope is `catch_all` and no scope's `caught` contains the origin's canonical path; a ⊤ origin escapes unless some scope is `catch_all`; a `reraise` origin escapes iff its forwarded set is non-empty after the chain *above* its own scope is applied (query-time; stored `escapes` = 1 conservatively). |
| Transitive semantics (user hard requirement)? | `raises(n) = D(n) ∪ ⋃_{e = (n→m, S)} close_S(raises(m))` with `D(n)` = escaping direct origins (reraise origins contribute `close_{chain above}(caught(scope))`), `S` = chain of `exn_scopes` rows from the call's `call_exn_scopes` scope outward, `close_S(X) = ∅` if any scope in `S` is `catch_all`, else `X − ⋃ caught(S)` with `Top − finite = Top`. Composition across hops is by induction: `raises(m)` already has `m`'s own handlers applied to `m`'s edges, so `close_S` at `n→m` is applied once per edge (C-5). |
| Edge kinds? | `MUST` and `MAY_ENUMERATED` edges propagate `raises(m)`; `MAY_TOP` edges contribute `Top(may_top_edge @ call_site)`; callee `NULL` ⇒ `ext:<name>` leaf ⇒ `Top(external <name>)` unless `<name>` ∈ fixed table {`Stdlib.raise`, `Stdlib.raise_notrace`, `Stdlib.failwith`, `Stdlib.invalid_arg`, `Stdlib.exit`, `Stdlib.Printexc.raise_with_backtrace`} ⇒ ∅ (their effect is already an origin) or `--assume-externals-pure` ⇒ ∅. A dropped node (`dropped_node`) is already `MAY_TOP` in `calls`. Every ⊤ contribution is subject to `close_S` (a catch-all closes ⊤; a constructor set does not). |
| Lattice / termination? | `Known of PathSet \| Top of Reason set`. `Top` absorbs; reason sets are unions (each reason = kind + one witness). Universe of paths is finite (paths occurring in `exn_origins`/`exn_scope_catches` of the DB); join is monotone; worklist over `MUST ∪ MAY_ENUMERATED` edges terminates (C-6). Dominant reason order for `exn-stats`: `may_top_edge` > `external` > `unknown_exn_value` > `dropped_node` (C-8). |
| Verdict vocabulary? | **[decision — replaces "SOUND"]** `BOUNDED: {…}` (no ⊤ in the cone: a sound over-approximation), `UNBOUNDED (⊤): {…} + reasons`, `BOUNDED_UNDER_HYP(externals_pure): {…}` (never collapses to `BOUNDED`; roadmap 3.2 vocabulary). "SOUND" is not used because it would claim what Java's checked exceptions earn and open-world inference does not (C-17). |
| `how` and `via` provenance? | Per `(node, exn)`: `how = direct` if the node has an escaping direct origin for it, else `transitive`; `via` = the callee (first found in deterministic caller-order traversal) whose set carried it. Multi-hop chains are reconstructed by repeating `raises` on the `via` node — one-hop provenance stored, chain derivable (C-7, C-16). |
| `exn_contract` granularity? | Whole-DB, set by the CMT producer run that populated the tables (`comment_db_meta('exn_contract','v1')`); the producer is single-run and all-or-nothing, so a DB with the flag is fully covered (EC-12). |
| ⊤-share threshold on proto_alpha? | None — it is a **measurement**, reported with and without the hypothesis (C-9). What blocks shipping is a spot check contradicting the source (a missed origin, a wrongly-closed edge) — a soundness failure. |
| proto_alpha uses `tzresult`, not exceptions (C-11) | `tzresult`/`Lwt.fail`/`Error_monad` are out of scope and invisible by design (they are values, not raises). The corpus still exercises HARD REQUIREMENT 1: the protocol's stated invariant is "no exception escapes to the shell", so `raises` on `Main`'s exposed entry points (`begin_application`/`apply_operation`/`finalize_block` style) is the meaningful check — every non-⊤ escape there is a finding, every ⊤ reason there is measured. Spot checks include one `try … with` wrapper in the protocol (e.g. around a `Stdlib`/`Data_encoding` call) and one `raise` site. |
| Effects, `Obj.magic`, over-application | Out of scope / residual: effect arms ignored, `perform` is an external call (⊤); `Obj.magic`-fabricated exceptions are `unknown_exn_value` at best (C-13); over-application's residual ⊤ edge is already emitted by the walker (EC-3). Documented in `docs/exception-raise-sets.md`. |
| `-noassert`, warning-8 suppression | The index reflects the `.cmt` as compiled: under `-noassert` there is no `Texp_assert` node, so no origin (EC-7); `partial` is independent of warning suppression, so `Match_failure` is recorded regardless (EC-9). |
| Prior art: row polymorphism (C-14/C-18), value dataflow (C-15) | Deliberately not adopted in v1: closure-flow/parameter resolution is roadmap 3.7 and would change the *call graph*, not this analysis; this analysis consumes whatever edge kinds exist, so any later precision gain flows in for free. `let e = Not_found in raise e` is `unknown_exn_value` — recorded residual with a witness so its frequency can be measured on the corpus and the dataflow extension prioritised on evidence. Shape lints (over-broad catch-alls) are a future `arch-rules` selector, not this task (C-19). |

## User Stories

### US-1: Producer records origins, handler scopes and call↔scope links per node (Priority: P0)
As the CMT producer, I want every raise origin, every exception handler scope and every call's
enclosing scope recorded per function node with resolved exception identity, so that a query can
compute may-raise sets without re-reading source.
**Why this priority**: nothing downstream exists without the rows.
**Scope**: does NOT cover effects, exception declarations as entities, or dataflow on exception values.
**Independent Test**: index a fixture and inspect the four new tables with SQL.
**Acceptance Scenarios**:
1. **Given** `let f () = raise Not_found`, **When** indexed, **Then** `exn_origins` has one row for `f`: `form='raise'`, `exn_path='Not_found'`, `escapes=1`, `scope_id IS NULL`, `line`/`col` of the `raise` application.
2. **Given** `let g () = try f () with Not_found -> 0`, **When** indexed, **Then** `exn_scopes` has one row for `g` (`form='try'`, `catch_all=0`, `parent_id NULL`), `exn_scope_catches` has `(scope, 'Not_found')`, and the `calls` row `g→f` has a `call_exn_scopes` row to that scope.
3. **Given** `let h l = try List.iter (fun x -> if x < 0 then raise Exit) l with Exit -> ()`, **When** indexed, **Then** the origin belongs to `h.<fun:L:C>` (`escapes=1`, `scope_id NULL`), the parent→lambda occurrence edge and the `List.iter` edge both carry `h`'s scope, and the lambda's own calls carry none.
4. **Given** `try f () with e -> cleanup (); raise e`, **When** indexed, **Then** the scope has `catch_all=0` and an empty caught set (non-closing arm), and the `raise e` site is `form='reraise'` with `scope_id` = that scope.
5. **Given** `try f () with Not_found when cond () -> 0`, **When** indexed, **Then** the scope's caught set is empty and `catch_all=0`.
6. **Given** `match f () with exception Not_found -> 0 | v -> g v`, **When** indexed, **Then** a `form='match_exception'` scope covers the `f ()` edge only; the `g v` edge has no `call_exn_scopes` row.
7. **Given** `let k x = assert (x > 0); match x with 1 -> ()` and `let p = function 1 -> ()`, **When** indexed, **Then** `k` has origins `assert`→`Assert_failure` and `partial_match`→`Match_failure`, and `p` has `partial_match`→`Match_failure` attributed to `p` (not a lambda node).
8. **Given** `let q () = let exception Local in raise Local` and `exception Alias = Not_found` with `raise Alias`, **When** indexed, **Then** the first origin's path is `local:Local/<stamp>` and `exn_rebinds` has `(<unit>.Alias, Not_found)`.
9. **Given** a unit declaring `exception E` inside `module M`, a `raise M.E` in the same unit and a `try … with U.M.E -> ()` in another unit, **When** indexed, **Then** both rows carry the identical canonical string `<cmt_modname>.M.E`.
10. **Given** a `.cmt` whose `raise` resolves to a non-`Stdlib` `external … = "%raise"` (protocol-environment style), **When** indexed, **Then** the origin is recorded (primitive-keyed), while a call to a non-Stdlib `failwith` is NOT an origin.

### US-2: `arch-query raises <fn>` computes the transitive, handler-aware, ⊤-honest set (Priority: P0)
As an engineer, I want `raises f` to list what may escape `f` transitively, minus what enclosing
handlers around each call close, with ⊤ reasons when the answer is unbounded.
**Why this priority**: it is the feature.
**Scope**: does NOT cover SARIF, `arch-rules` selectors, or path witnesses beyond one hop.
**Independent Test**: fixture + `arch-query <db> raises <fn>` text output.
**Acceptance Scenarios**:
1. **Given** `f` raises `Not_found` and `g () = try f () with Not_found -> 0`, **When** `raises g`, **Then** `BOUNDED: {}`; and `raises f` → `BOUNDED: {Not_found}` with row `Not_found | - | direct`.
2. **Given** `f cb = cb ()` (MAY_TOP edge) and `g () = try f (fun () -> ()) with _ -> 0`, **When** `raises g`, **Then** `BOUNDED: {}`; `raises f` → `UNBOUNDED (⊤)` with reason `may_top_edge` and the call site.
3. **Given** `k () = f (); failwith "x"` with `f` raising `Not_found`, **When** `raises k`, **Then** rows `Not_found | f | transitive` and `Failure | - | direct`, verdict `BOUNDED: {Failure, Not_found}`.
4. **Given** `a () = b (); raise A` and `b () = a (); raise B`, **When** `raises a`, **Then** `BOUNDED: {A, B}` and the command terminates (same for `b`).
5. **Given** `m xs = List.hd xs`, **When** `raises m`, **Then** `UNBOUNDED (⊤)` reason `external Stdlib.List.hd`; **When** `raises --assume-externals-pure m`, **Then** `BOUNDED_UNDER_HYP(externals_pure): {}`.
6. **Given** US-1.3's `h`, **When** `raises h`, **Then** `UNBOUNDED (⊤)` reason `external Stdlib.List.iter`; with `--assume-externals-pure` → `BOUNDED_UNDER_HYP(externals_pure): {}` (the lambda's `Exit` flows through the occurrence edge and is closed by `h`'s try).
7. **Given** `r () = try f () with e -> log e; raise e` with `f` raising `Not_found`, **When** `raises r`, **Then** `BOUNDED: {Not_found}` (non-closing arm forwards).
8. **Given** US-1.6, `f` raising `Not_found` and `g` raising `Failure`, **When** `raises` on that function, **Then** `BOUNDED: {Failure}`.
9. **Given** a name with no `functions` row, **When** `raises nosuch`, **Then** exit 2 and the same "unknown function" refusal `unreachable` gives.
10. **Given** an index without `callgraph_contract`, **When** `raises f`, **Then** exit 3 `REFUSED — this index is NOT ⊤-marked`.

### US-3: `raisers-of`, `exn-stats`, and NOT_ANALYSED refusal (Priority: P1)
As an engineer, I want the reverse view and a corpus-level measurement, and I want a DB without
exception rows to say so rather than answer "nothing raises".
**Why this priority**: measurement is the acceptance instrument; refusal is the honesty rule.
**Scope**: does NOT cover per-language coverage rows (roadmap 1.3).
**Independent Test**: fixture DBs (CMT-indexed, `arch-load` Flat).
**Acceptance Scenarios**:
1. **Given** the US-2 fixture, **When** `raisers-of Not_found`, **Then** rows for `f` (`direct`) and `k` (`transitive`), `g` absent, and a separate `⊤ (may include it)` section listing `m` and `h`.
2. **Given** the same fixture, **When** `exn-stats`, **Then** output has `nodes`, `bounded` (count, share), `unbounded` (count, share) split by dominant reason, `origins`, `scopes`, `escaping_origins`, and a `hypothesis` line when `--assume-externals-pure` is given.
3. **Given** a Flat DB from `arch-load`, **When** any of the three commands runs, **Then** exit 3 and the message contains `NOT_ANALYSED`.
4. **Given** a CMT-indexed DB whose schema predates the tables (no `exn_contract` meta), **When** `raises f`, **Then** exit 3 `NOT_ANALYSED` naming `arch-callgraph-ocaml` as the remedy.

### US-4: Validation on Tezos `proto_alpha` and residual documentation (Priority: P1)
As the roadmap owner, I want the analysis measured on a large closed-world corpus and its
residuals written down, so the number means something and the next person knows the limits.
**Why this priority**: the roadmap's operating rule — fixture-scale green is not evidence.
**Scope**: does NOT cover whole-Octez or Rust.
**Independent Test**: index `lib_protocol`, run `exn-stats`, hand-check three functions.
**Acceptance Scenarios**:
1. **Given** `/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol` (500 `.cmt`), **When** indexed to `/mnt/ssd-external-2to/arch-index-runs/proto-alpha-exn.db` and `exn-stats` runs twice (with/without hypothesis), **Then** both outputs and the rejection counts are recorded in `briefs/exn-raise-sets-ship-gate.md`.
2. **Given** that DB, **When** `raises` is run on three hand-picked functions (a direct `raise` site, a `try … with` wrapper that must close it, a callback caller that must be `UNBOUNDED may_top_edge`) and on `Main`'s exposed entry points, **Then** each answer is checked against source and the transcript recorded; any contradiction is a soundness NO-GO.
3. **Given** the branch, **When** reviewed, **Then** `docs/exception-raise-sets.md` (semantics, tables, verdicts, residuals: `unknown_exn_value`, HOF/functor ⊤ until 3.7, externals/stdlib summaries, effects, `Obj.magic`, over-application, `-noassert`), `docs/edge-kind-contract.md` (exception-insensitivity note points here), and roadmap 3.4 notes + `exn_contract` in the contract doc exist.

## Challenges

| # | Story | Challenge | Resolution |
|---|---|---|---|
| C-1 | US-1.3 | Does `try` close `Top(external List.iter)`? | No: only a catch-all closes ⊤. Scenario US-2.6 states both outcomes. |
| C-2 | US-1.4 | `exn_origins.form` vocabulary | `raise \| reraise \| unknown \| failwith \| invalid_arg \| assert \| partial_match`, CHECK-constrained. |
| C-3 | US-1 | Or-patterns | Union of both sides. |
| C-4 | US-1 | Walker discards patterns | The hooks retain them: scope ids are minted by `Arch_index_exn`, independent of CFG block ids; the walker calls `Arch_index_exn.enter_try/leave`, `enter_match_exn/leave`, `record_origin`, `current_scope` at the existing `Texp_try`/`Texp_match`/`Texp_assert`/`Texp_apply`/partial sites. |
| C-5 | US-2.2 | Closure composition over hops | Once per edge, by induction on the fixpoint (Clarifications). |
| C-6 | US-2.4 | Termination / join | Finite universe, monotone join, `Top` absorbs, reasons union. |
| C-7 | US-3.1 | `how` when both | `direct` wins; `via` = first found. |
| C-8 | US-3.2 | Dominant reason | Fixed priority order. |
| C-9 | US-4 | Threshold | None; spot-check contradiction is the gate. |
| C-10 | US-4 | Environment shadows `raise` | Primitive-keyed raise heads; `failwith`/`invalid_arg` stay Stdlib-keyed. |
| C-11 | US-4 | `tzresult` idiom | Out of scope; entry-point escapes are the meaningful check. |
| C-12 | US-1 | Root `function` Match_failure owner | The top-level node. |
| C-13 | US-1 | `Obj.magic` | Residual, documented. |
| C-14/18 | prior art | Row polymorphism | Deferred to 3.7; analysis is edge-kind-agnostic so gains flow in. |
| C-15 | prior art | Value dataflow | Residual with witness; measure first. |
| C-16 | prior art | Full paths | One hop stored, chain derivable. |
| C-17 | prior art | "SOUND" overclaims | Vocabulary `BOUNDED / UNBOUNDED (⊤) / BOUNDED_UNDER_HYP`. |
| C-19 | prior art | Shape lint | Out of scope (future `arch-rules`). |

## Edge Cases

- EC-1 [US-1]: `raise (f x)` → `form='unknown'`, ⊤ `unknown_exn_value` with the site as witness.
- EC-2 [US-1]: `try g (raise Not_found) with Not_found -> 0` → the origin is inside the body: closed; the `g` edge carries the scope; CFG deadness is irrelevant to sets.
- EC-3 [US-1]: over-application → the walker's residual `*TOP*` edge yields ⊤ `may_top_edge` (honest).
- EC-4 [US-1]: `let exception` escaping its function → identity `local:…` propagates unchanged; documented.
- EC-5 [US-1]: rebinding → canonicalised via `exn_rebinds`.
- EC-6 [US-1]: `Printexc.raise_with_backtrace (Lit …) bt` → origin `raise`.
- EC-7 [US-2]: `-noassert` → no `Texp_assert`, no origin (index reflects the build).
- EC-8 [US-2]: `Fun.protect ~finally` → external ⊤ (or ∅ under hypothesis); `Finally_raised` is a documented residual of the hypothesis.
- EC-9 [US-2]: warning-8 suppression → `Match_failure` still recorded.
- EC-10 [US-2]: effect nodes → walked as ordinary expressions; `perform` is an external call → ⊤.
- EC-11 [US-2]: indirect re-raise through `match e with …` → the arm is non-closing (sound).
- EC-12 [US-3]: partial coverage → impossible with the single-run producer; `exn_contract` is whole-DB.
- EC-13 [US-4]: `tzresult`-dominated corpus → entry-point escapes are the check.

## Functional Requirements

#### Producer (US-1)
- **FR-001** [US-1]: The CMT producer MUST record one `exn_origins` row per raise head application, `Texp_assert`, and `Partial` match/function, and raising primitive (comparison / division / bounds check) in a function node, with `form ∈ {raise, reraise, unknown, failwith, invalid_arg, assert, partial_match, compare, division, index}`, canonical `exn_path` (NULL for `reraise`/`unknown`), `scope_id` of the innermost enclosing scope of the same node (or NULL), `escapes`, `line`, `col`.
- **FR-002** [US-1]: A raise head MUST be recognised by `val_kind = Val_prim` with `prim_name ∈ {"%raise","%raise_notrace","%reraise"}`, independent of its Path; `failwith`/`invalid_arg`/`Printexc.raise_with_backtrace` MUST be recognised only on the persistent `Stdlib` root.
- **FR-003** [US-1]: The producer MUST record one `exn_scopes` row per `Texp_try` body and per `Texp_match` scrutinee having a `Tpat_exception` case, with `parent_id` = the enclosing scope of the same node, `form`, `line`, `col`, `catch_all`, and its caught paths in `exn_scope_catches`, computed from closing arms only (unguarded, no raise of a non-literal in the RHS).
- **FR-004** [US-1]: Every call recorded while walking inside a scope's covered expression MUST be linked to that scope by a `call_exn_scopes` row; calls outside any scope MUST have no row. Coverage is lexical: `try` body; `match` scrutinee only.
- **FR-005** [US-1]: Origins, scopes and links inside a promoted lambda literal MUST be attributed to the lambda node; a scope of the parent MUST NOT cover the lambda's body, but MUST cover the parent→lambda occurrence edge when the literal occurs inside the covered expression.
- **FR-006** [US-1]: `exn_path` MUST follow the canonicalisation rule (predef bare; persistent `Path.name`; unit-declared `<cmt_modname>.<prefix>…`; otherwise `local:<unique_name>…`), and `Text_rebind` declarations MUST be recorded in `exn_rebinds`.
- **FR-007** [US-1]: All new rows MUST be written with `exec_stmt ~what:"<table>"` so rejections are attributed per table; the producer MUST set `comment_db_meta('exn_contract','v1')` after a run that populated the tables, and no other producer MUST set it.
- **FR-008** [US-1]: The schema additions MUST be `CREATE TABLE IF NOT EXISTS` in `architecture-schema.sql`, MUST NOT alter `calls`/`functions`, and MUST NOT change `schema_version`.
- **FR-009** [US-1]: `Stdlib.exit`, effect cases, effect `perform`, and `tzresult`/`Lwt` error values MUST NOT produce origins or scopes.

#### Query (US-2)
- **FR-010** [US-2]: `arch-query <db> raises [--assume-externals-pure] <fn>` MUST compute `raises(fn)` per the transitive rule (Clarifications) by a worklist fixpoint over `MUST ∪ MAY_ENUMERATED` edges, treating `MAY_TOP` edges and `ext:` leaves as ⊤ contributions subject to `close_S`.
- **FR-011** [US-2]: `close_S` MUST return ∅ when any scope in the chain is `catch_all`, otherwise subtract the union of caught paths; ⊤ minus a finite set MUST remain ⊤.
- **FR-012** [US-2]: The output MUST list one row per escaping exception (`exception | via | how`) then one verdict row `BOUNDED: {…}` when no ⊤ reason exists, `UNBOUNDED (⊤): {…}` followed by one line per reason with witness otherwise, or `BOUNDED_UNDER_HYP(externals_pure): {…}` when the flag was given and ⊤ came only from externals; the flag MUST NOT suppress `may_top_edge`/`unknown_exn_value`/`dropped_node` reasons.
- **FR-013** [US-2]: `ext:` leaves in the fixed table MUST contribute ∅: heads whose effect is already an origin (`Stdlib.raise`, `raise_notrace`, `failwith`, `invalid_arg`, `exit`, `Printexc.raise_with_backtrace`, the comparison operators and `compare`, `/`, `mod`, `Int32/Int64/Nativeint.div/rem`, `Array.get/set`, `String.get`, `Bytes.get/set`) and `Stdlib` primitives that cannot raise (see Clarifications). Every other external MUST be ⊤ `external`.
- **FR-014** [US-2]: Paths MUST be canonicalised through `exn_rebinds` before any set operation.
- **FR-015** [US-2]: `raises` MUST require the ⊤-marking contract (`require_contract`) and a known function (`need_known`), with the same exit codes as `unreachable` (3 and 2).

#### Reverse view, stats, refusal (US-3)
- **FR-016** [US-3]: `raisers-of <Exn>` MUST list every node whose set contains the canonical `Exn` with `how`, and separately every ⊤ node.
- **FR-017** [US-3]: `exn-stats` MUST print node count, bounded/unbounded counts and shares, unbounded split by dominant reason (`may_top_edge > external > unknown_exn_value > dropped_node`), origin/scope/escaping-origin counts, and a hypothesis line when the flag is set.
- **FR-018** [US-3]: All three commands MUST exit 3 with a message containing `NOT_ANALYSED` and naming `arch-callgraph-ocaml` when `exn_contract` meta is absent (Flat DBs, pre-feature DBs), before any other check except the ⊤-marking contract.

#### Validation and docs (US-4)
- **FR-019** [US-4]: The ship gate MUST include `exn-stats` on proto_alpha with and without the hypothesis, rejection counts, and the three spot checks + entry-point transcript; any spot-check contradiction MUST be a NO-GO.
- **FR-020** [US-4]: `docs/exception-raise-sets.md` MUST exist with semantics, tables, verdict vocabulary and residual list; `docs/edge-kind-contract.md` MUST reference it; the roadmap 3.4 notes MUST be updated; a tezt MUST cover US-1/2/3 scenarios; the self-index golden MUST be regenerated.

## Acceptance Criteria

- AC-1 [US-1 happy path]: US-1.1–1.6 rows present with the stated values → `tezt/tests/exn_raise_sets.ml` SQL assertions pass.
- AC-2 [US-1, C-10]: primitive-keyed `raise` origin recorded for a non-Stdlib `%raise` external; non-Stdlib `failwith` not an origin → fixture assertion.
- AC-3 [US-1, C-12/EC-9]: `assert`, `match` Partial, root `function` Partial origins on the right node → fixture assertion.
- AC-4 [US-1, EC-5/FR-006]: canonical path agreement across two units + rebind row → fixture assertion.
- AC-5 [US-2 happy path]: US-2.1, 2.3 outputs exact → text assertions.
- AC-6 [US-2, HARD REQ 1]: US-2.2, 2.6, 2.7, 2.8 (call-site closure, catch-all closes ⊤, non-closing arm forwards, match-exception scrutinee-only) → text assertions.
- AC-7 [US-2, C-6]: mutual recursion terminates with the union → text assertion under a timeout.
- AC-8 [US-2, C-17/FR-012]: external ⊤ vs `BOUNDED_UNDER_HYP` → text assertions; flag does not hide `may_top_edge`.
- AC-9 [US-2, FR-015]: unknown name exit 2; un-⊤-marked DB exit 3.
- AC-10 [US-3 happy path]: `raisers-of`, `exn-stats` shapes → text assertions.
- AC-11 [US-3, FR-018]: Flat DB and pre-feature DB → exit 3 with `NOT_ANALYSED`.
- AC-12 [US-4, FR-019]: ship gate carries the proto_alpha numbers and transcript; no contradiction.
- AC-13 [US-4, FR-020]: docs, roadmap notes, golden regenerated; `dune build`, `dune test --force`, `arch-rules --on-vacuous fail` green.
- AC-14 [US-1, FR-008]: `git diff` on `architecture-schema.sql` shows only additive `IF NOT EXISTS` statements; `schema_version` write sites untouched.

## Runnable Checks

- CHECK-1 [AC-1..AC-4, AC-5..AC-9, AC-10, AC-11]: `dune test --force` with `tezt/tests/exn_raise_sets.ml` registered — red before the producer/query exist, green after.
- CHECK-2 [AC-13]: `dune build && dune test --force && BIN=./_build/default/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe && $BIN --build-dir=_build/default/lib/arch_index --db-path=/tmp/self.db --schema-path=architecture-schema.sql && ./_build/default/bin/arch_rules/arch_rules.exe /tmp/self.db arch-rules.txt --on-vacuous fail && sqlite3 /tmp/self.db "SELECT 'modules: '||count(*) FROM modules; SELECT 'functions: '||count(*) FROM functions; SELECT 'calls: '||count(*) FROM calls;" | diff test/fixtures/self-index-stats.txt -`
- CHECK-3 [AC-12]: `$BIN --build-dir=/home/mathias/dev/tezos/tezos/_build/default/src/proto_alpha/lib_protocol --db-path=/mnt/ssd-external-2to/arch-index-runs/proto-alpha-exn.db --schema-path=architecture-schema.sql && arch-query <db> exn-stats && arch-query <db> exn-stats --assume-externals-pure` plus the spot-check transcript (human-read, recorded in the ship gate).
- CHECK-4 [AC-14]: `git diff origin/main -- architecture-schema.sql | grep '^+' | grep -vE 'IF NOT EXISTS|^\+\+\+|^\+\s*--|^\+\s*$|^\+\s{4}' ; git diff origin/main --stat -- lib/arch_index/runner.ml lib/arch_index/arch_index_db.ml` → the first prints only column/index lines of the new tables; the second is empty.

## Entities

- `exception origin`: a site in a function node that can raise — a raise-head application, an `assert`, or a `Partial` match/function — with a form and, when literal, a canonical exception path.
- `handler scope`: the lexical region covered by a `try` body or a `match … with exception` scrutinee, in one function node, with its parent scope, its caught path set and its catch-all flag.
- `closing arm`: an unguarded handler arm whose RHS applies no raise head to a non-literal argument; only closing arms contribute to a scope's caught set / catch-all flag.
- `call scope link`: the innermost handler scope enclosing a call site, recorded per `calls` row in `call_exn_scopes`.
- `canonical exception path`: the string identity of an exception constructor (rule in Clarifications), rebind-normalised at query time.
- `raise-set`: the lattice value `Known of PathSet | Top of Reason set` computed per node; `Top` reasons ∈ {`may_top_edge`, `external`, `unknown_exn_value`, `dropped_node`} each with a witness.
- `verdict`: `BOUNDED` / `UNBOUNDED (⊤)` / `BOUNDED_UNDER_HYP(externals_pure)`.
- `exn_contract`: `comment_db_meta` flag `v1` set only by the CMT producer; its absence means NOT_ANALYSED.
- (unchanged, from `specs/cfg-postdom-dominance.md`) `lambda node`, `noreturn head`, `call kind`, `MAY_TOP edge`.
