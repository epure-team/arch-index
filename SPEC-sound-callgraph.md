# Spec — arch-index: language-agnostic sound(y) over-approximate call-graph

**Roster phase:** spec (research → **spec** → plan → implement → review → qa). Produced from a
3-agent research redo (multi-language documentarian + language-agnostic-core/prior-art + per-language
Tier-1 resolvers). Work lands in vendored `whitehat/tools-shared/arch-index/`; upstream to
`epure/src/arch_index/` later. **Supersedes the earlier Go-only draft** — that broke arch-index's
target-agnostic premise.

## Problem (re-framed: it is NOT Go-specific)

arch-index gives an *under-approximate* call-graph (good for **reachability**), but cannot prove
**un**reachability — the high-value pruning direction (a sink no entrypoint can reach fails G2 *by
construction* → kill the lead deterministically). The blocker is universal across every backend:

- **No backend marks ⊤ ("could-call-anything").** The LSP `callHierarchy` path (all 5 langs) records
  *only server-resolved edges* — a dynamic/interface call it can't resolve is **silently absent**, not
  flagged (`call_graph_extractor.ml:116-147`). The OCaml CMT path *walks every call site*
  (`Tast_iterator`, `arch_index_cmt.ml:347-370`) but **drops every non-`Texp_ident` callee** (functor /
  method / first-class-module — i.e. exactly the dynamic ones) at `| _ -> ()` (`:363`). TS records no
  edges. **tree-sitter is absent everywhere.**
- **Consequence:** "no path" is never trustworthy — a dropped dynamic edge could reach the sink. Sound
  unreachability is impossible on the current data **for any language**, not just Go.
- (Go additionally can't even *enumerate*: empty `workspace/symbol` query → 0 functions on large modules.)

Prior art confirms the gap: **no production tool combines a shared cross-language call-graph schema
WITH sound over-approximation for security unreachability** — CodeQL is sound-but-per-language;
Glean/FASTEN/Endor are shared-but-unsound. This is genuinely unoccupied space.

## Architecture (the chosen design)

Three language-agnostic layers + per-language resolvers behind a contract.

### 1. Edge-kind contract (language-agnostic — the headline)

Every call edge carries an **approximation tag** (FASTEN URIs + CodeQL must/may semantics + an explicit
tag — the one field no standard ships first-class):

| tag | meaning | trust |
|-----|---------|-------|
| **MUST** | uniquely-resolved static call | a path of MUST edges → **reachable** (under-approx; trust the positive) |
| **MAY_ENUMERATED** | dynamic call resolved to a BOUNDED candidate set (e.g. all interface implementers) | over-approx; a node with no incoming MUST/MAY edge is **dead** |
| **MAY_TOP** | unresolvable dynamic/reflective/FFI call — could call anything | kills downstream unreachability unless bounded |

**Inviolable rule: an unresolvable call site becomes MAY_TOP — NEVER dropped.** This is the actual fix;
the current bug is lying-by-omission, not "no CHA". `static` is emitted ONLY on provably-unique
resolution (never collapse a dynamic site to one target — that's an unsound under-approx).

### 2. Tier-0 — universal call-site enumeration (language-agnostic substrate)

Use **tree-sitter** (one call-node query per grammar; call *shape* — direct/method/computed — is
decidable from the callee child node) to enumerate EVERY call site for any supported language:
resolve-by-name against the function table → MUST (if unique) else → MAY_TOP. PLUS stamp MAY_TOP
**anchors** for the soundiness holes that never appear as resolvable nodes — macros/codegen, `eval`,
reflection, FFI, conditional-compilation. This gives **sound(y)** over-approximation for *any*
tree-sitter language immediately (weak — many UNKNOWN — but never wrong-by-omission).

### 3. Tier-1 — per-language precise resolvers (incremental; turn MAY_TOP → MAY_ENUMERATED)

| lang | Tier-1 feasible now? | mechanism | hard MAY_TOP |
|------|----------------------|-----------|--------------|
| **Go** | **yes, off-the-shelf** | `go/ssa` + `go/callgraph/cha` + `go/types.Implements` (also fixes enumeration: `go/packages` LoadAllSyntax) | reflect, cgo, go:linkname, unsafe |
| **OCaml** | **yes — extend the EXISTING CMT walk** | fix the `Texp_ident`-only drop → MAY_TOP; add functor-arg-union + structural-CHA `Texp_send` resolution (both genuinely sound) | Obj.magic, computed Tmod_unpack, external/FFI, Marshal, Dynlink, effects |
| **Rust** | feasible, **must build** | rustc MIR + monomorphize-collector ∩ trait-impl set (no-`dylib` whole-program); shipped tools (rust-analyzer/cargo-call-stack) silently drop edges = unsound | dlopen/dylib, transmute-fn-ptr, extern"C", asm! |
| **TS/JS** | only with TAJS-class abstract interp (doesn't scale); Jelly/CodeQL are incomplete | treat incompleteness flags as forced MAY_TOP → effectively **Tier-0** | eval/Function, dynamic import/require, Proxy, with, monkey-patch |
| **Python** | **no — Tier-0** | no sound tool (PyCG ~70% recall, archived); assume MAY_TOP at every non-constant-foldable site | eval/exec, dynamic getattr, C-extensions, monkey-patch |

### 4. Query layer (language-agnostic)

- `reaches A B` — path over **MUST** edges (under-approx) → "must-reach" ground truth (trust positive).
- `unreachable A B` — UNREACHABLE iff **no path** over MUST∪MAY_ENUMERATED∪MAY_TOP **and** no reachable
  MAY_TOP node, **within a closed internal universe**; else REACHABLE / UNKNOWN. Sound (modulo the
  soundiness holes, which are surfaced as MAY_TOP anchors).
- `escapes A` — the MAY_TOP nodes reachable from A (the boundary that forces UNKNOWN).

## Decisions

- **DR-1:** the contribution is the **language-agnostic contract + Tier-0 ⊤-substrate + query layer**,
  with **per-language Tier-1 resolvers behind it** — NOT a Go-only feature. Every language gets sound(y)
  unreachability at Tier-0 immediately; precision improves as Tier-1 resolvers land.
- **DR-2:** first Tier-1 resolvers = **Go** (off-the-shelf; unblocks sei/cosmos) and **OCaml** (cheap —
  the CMT walk is already 90% there; native validation of the architecture). Rust = build-later; TS =
  Tier-0 (incompleteness→⊤); Python = Tier-0.
- **DR-3 (honesty):** the design is **soundy, not sound** (CST holes per Livshits et al. CACM 2015).
  Unreachability is asserted ONLY within a closed universe with all soundiness holes marked MAY_TOP;
  the verdict is labelled with the under-approximation markers crossed.

## Functional requirements

- **FR-001 — edge-kind contract.** Schema: every `calls` row has `kind ∈ {MUST, MAY_ENUMERATED, MAY_TOP}`
  (back-compat: missing ⇒ MUST). Node identity carries a language tag + internal/external universe flag.
- **FR-002 — never-drop ⊤ (Tier-0).** For every supported language, an unresolvable/dynamic call site
  emits a MAY_TOP edge; no call site is silently dropped. (Replaces the LSP-only/`Texp_ident`-only loss.)
- **FR-003 — sound(y) `unreachable` query.** Returns UNREACHABLE only under the §4 closed-universe +
  no-reachable-MAY_TOP rule; REACHABLE on a MUST/MAY path; else UNKNOWN. `reaches` stays MUST-only.
- **FR-004 — Go Tier-1.** `go/packages`+`go/ssa`+`cha` backend: complete enumeration (functions > 0 on a
  large module; loud failure on build error, never silent-empty) + interface calls as MAY_ENUMERATED +
  reflect/cgo/linkname/unsafe as MAY_TOP.
- **FR-005 — OCaml Tier-1.** Extend the CMT typedtree walk: non-`Texp_ident` callee → MAY_TOP (not
  dropped); functor-application targets resolved by arg-union and `Texp_send` by structural CHA →
  MAY_ENUMERATED; Obj.magic/external/Marshal/Dynlink → MAY_TOP.
- **FR-006 — soundiness markers.** A macro/`eval`/reflection/FFI/conditional-compilation construct seen
  by Tier-0 produces a named MAY_TOP anchor even when its expansion is invisible; the `unreachable`
  verdict reports which holes were crossed.
- **FR-007 — build/scope contract.** Per-language prerequisites (Go module builds; OCaml `.cmt` present)
  are explicit; a load failure is reported, never an empty graph. Languages without a Tier-1 resolver
  are documented as Tier-0 (sound but many UNKNOWN).

## GWT (illustrative)

- **FR-002/003 (OCaml):** *Given* a functor application and a `obj#m` call, *when* indexed, *then* both
  appear as edges (MAY_ENUMERATED to the arg-union / structural-CHA set), and an `Obj.magic` call is a
  MAY_TOP edge; `unreachable f g` over a closed module with no reachable MAY_TOP returns UNREACHABLE.
- **FR-004 (Go):** *Given* `type I interface{M()}` with impls `A`,`B` and `f(i I){i.M()}`, *then* edges
  `f→A.M`,`f→B.M` (MAY_ENUMERATED); `unreachable f C.M` → UNREACHABLE; a `reflect.Value.Call` site →
  MAY_TOP and `unreachable` past it → UNKNOWN.

## Challenges / risks

- **C1 — soundiness holes are irreducible** (macros/eval/reflection/FFI/cfg). Mitigation: FR-006 named
  anchors; never assert UNREACHABLE across one. Under-cataloguing a hole is the one wrong-dangerous way.
- **C2 — tree-sitter is a NEW dependency** (absent today); per-grammar query completeness (Rust macros,
  OCaml operators/`|>`) needs care.
- **C3 — CHA blow-up** (Go/OCaml structural) on large modules; fine for set-membership, monitor size.
- **C4 — Rust/TS/Python have no shipped sound tool**; Rust/OCaml Tier-1 must be built; TS/Python stay
  Tier-0. Document the asymmetry; don't over-promise.
- **C5 — novel niche** (no production precedent) ⇒ no off-the-shelf validation; lean on FASTEN+CodeQL
  schema semantics + the runnable checks.

## Runnable checks (acceptance harness)

Per-language `testdata/` fixtures (small, build/compile): Go (interface+2 impls+reflect+cgo), OCaml
(functor + object method + `Obj.magic`), and a tree-sitter-only language (e.g. Python: a dynamic
`getattr` site → MAY_TOP). `selftest.sh` asserts: every call site present (none dropped, FR-002);
correct `kind` per edge; `unreachable` REACHABLE/UNREACHABLE/UNKNOWN verdicts per FR-003; Go
enumeration > 0 and loud-fail on broken build (FR-004); OCaml functor/`Texp_send` resolved + Obj.magic
⊤ (FR-005). CI-gated before the tool is trusted for G2 pruning.

## Roadmap (plan phase)

- **PR-A** — edge-kind contract + schema (`kind`, universe) + language-agnostic query layer
  (`reaches`/`unreachable`/`escapes`) + soundiness markers. Foundation; testable with hand-written DBs.
- **PR-B** — Tier-0 tree-sitter call-site enumeration + universal MAY_TOP (the never-drop fix).
- **PR-C** — Go Tier-1 (`go/packages`+`ssa`+`cha`); fixes enumeration + precise Go over-approx.
- **PR-D** — OCaml Tier-1 (extend CMT walk: fix drop→MAY_TOP, functor + structural-CHA resolution).
- Rust Tier-1 / TS-Python Tier-0 hardening: later, documented.
