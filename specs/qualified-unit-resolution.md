# Spec — qualified-unit-resolution

**Date:** 2026-09-04 (**v2** — supersedes v1, which contained four factual errors about the code;
see §11)
**Mode:** full
**Status:** VALIDATED
**Intake:** `briefs/qualified-unit-resolution-intake.md`
**Research:** `briefs/qualified-unit-resolution-research.md`

## 1. Problem

A qualified call resolves by walking the dotted name and looking up each **bare segment** in a
project-wide `capitalize(basename) -> path` table with last-writer-wins semantics. The library
that owns a file is therefore erased, and a reference into one library resolves into a same-named
file in another — stamped `MUST`, i.e. asserted as proven.

## 2. What the code ACTUALLY does (verified against `origin/main@cde3aad`)

> v1 of this spec described a function `resolve_module_root` and a "two readings (a)/(b)" model.
> **Neither exists on main.** Both were carried over from the abandoned `rebase/sound-qual`
> branch without verification. Everything below was read from the source.

`mod_name_to_path` (`arch_index.ml:398-405`) — built with `Hashtbl.replace` from
`SELECT path FROM modules`, keyed `capitalize(basename(path))`. **Last writer wins.**

`resolve_qualified` (`arch_index.ml:451-468`) — a recursive walk over **suffixes**, not a
two-case match. For `Foo.Bar.baz` it tries, in order:

| step | key looked up | residual name sought |
|---|---|---|
| 1 | `Foo` | `Bar.baz` |
| 2 | `Bar` | `baz` |

taking the first step whose `(path, residual)` pair hits `fn_lookup`.

### 2.1 The consequence that changes the whole risk profile

**The alias case (FR-002) passes today *because of* the basename erasure this task removes.**
For `Foo.Bar.baz` where `foo.ml` is a pure alias, step 1 misses (the alias defines no function)
and **step 2 hits by looking up the bare segment `Bar`** → `libfoo/bar.ml` → `baz`.

So the change is **not** "re-key one table and everything else is preserved". Removing bare-segment
lookup removes the mechanism FR-002 currently relies on. FR-002 passing after the change proves
continuity only if the replacement independently reaches the same file. This is the single most
important correction in v2, and R1 below exists because of it.

### 2.2 The invariant the design rests on

Both `Head_qualified` construction sites (`arch_index_cmt.ml:1027`, `:1430`) are guarded by
`qualified_is_dynamic` (`:969-971`, `not (Ident.persistent root)`). Non-persistent roots (local
aliases, functor parameters) become `Head_unknown`/`Module_param` instead. **Therefore segment 1
of any `Head_qualified` name is a real, persistent compilation-unit name as the compiler saw it.**
Nothing enforces this if a third construction site is ever added — noted as an assumption, not a
guarantee.

### 2.3 Where the unit name is available

`arch_index_cmt.ml:1644` already binds `modname = info.cmt_modname`, and there is exactly **one**
`insert_module` site (`:1673`) with it in scope. The DB is dropped and recreated every run
(`arch_index.ml:168-175`). So an in-memory `unit_name -> rel_path` registry populated at that site
is **complete by construction** — no schema column, no migration, no stale-row hazard, and
nothing for `bin/arch_serve` to disagree with.

Unit names must come from `cmt_modname`, **never** from `.cmt` filenames: on disk they are
lowercase-prefixed (`arch_index__Arch_index_cfg.cmt`).

## 3. Requirements

### FR-001 — a qualified call resolves within the library it names
Two libraries, each owning a module of the same basename, both linked by the caller; each
reference names its own library explicitly. Each call resolves to its **own** library's function.
*Fails today: both resolve to whichever was indexed last.*

### FR-002 — an alias still resolves to the implementation (REGRESSION GUARD)
A wrapped library owning both `bar.ml` (unit `Foo__Bar`) and a main module `foo.ml` containing
`module Bar = Bar`. `Foo.Bar.baz` resolves `MUST` to `bar.ml`'s `baz`.
*Passes today — via §2.1's bare-segment step, which this change removes. Must still pass after.*

### FR-003 — genuine ambiguity degrades to ⊤, it never guesses
**Predicate (v1 was ambiguous here; this is the binding definition):** after enumerating all
candidates, collect the set of **distinct `functions.id`** reached. Exactly one → resolve. Two or
more → `MAY_TOP`, `callee_id IS NULL`, `top_reason` set. Zero → FR-004.

Two candidate readings landing on the *same* function are **not** ambiguous. A unit name borne by
two files where only one defines the residual name is **not** ambiguous.

### FR-004 — a genuine external stays a resolved external leaf
A root naming no indexed unit keeps today's external-leaf treatment (`callee_id IS NULL`, kind per
existing dominance rules) — **not** ⊤. Over-generalising this is what inflated the abandoned
branch's MAY_TOP 660 → 875.

### FR-005 — roadmap 1.4 dropped-node behaviour preserved
`dropped_qualified` (`arch_index.ml:489-505`) walks the *same* segment chain against
`dropped_unit_names`. It must be re-targeted to the new candidate enumeration **in the same
commit** as the resolver — an intermediate state where the two walks disagree is FR-005's exact
failure mode.

### FR-006 — no new MUST-with-NULL-callee edges
The count of `kind='MUST' AND callee_id IS NULL` rows whose root resolves to an **indexed** unit
must not increase. **Its value on `main` must be measured BEFORE any edit** (§5 S0); v1 asserted
it should be `0` after without anyone having measured it before. If it is non-zero on `main`,
clearing it is a separate decision, not a silent obligation.

Unresolved `Head_qualified` falls to `arch_index.ml:573` `else (None, display_name, kind, None)`
where `kind` is already `MUST` unless demoted. **Any narrowing of candidate generation directly
manufactures rows in this shape** — the abandoned branch shipped 582 of them.

### FR-007 — coverage of shapes v1 omitted
Fixtures must include: a `(wrapped false)` library (where the unit name *is* the basename, so
unit-keying provides no disambiguation and the FR-001 defect **persists** — see §7); a reference
qualified 3+ levels deep; two executables sharing a module basename (`Dune__exe__Main`); and a
functor-application segment (`path_to_module_name`, `arch_index_cmt.ml:591-601`, emits a literal
`<apply>` mid-path that reaches `Head_qualified`).

## 4. Candidate enumeration (the actual mechanism)

For `Head_qualified (Some mod_name, n)` with segments `s₁ … s_k`:

for `j = 1 … k`: candidate unit `String.concat "__" [s₁;…;s_j]`, residual
`String.concat "." ([s_{j+1};…;s_k] @ [n])`.

- `j = 1` — the root IS the compilation unit, the rest is a nested-module path (`(wrapped false)`
  libraries, main modules).
- `j = k` — fully wrapped (`Root__File`).
- intermediate `j` — nested wrappers, `include_subdirs qualified`.

A **bare** `s_j` for `j > 1` is deliberately **not** a candidate — that is precisely the erasure
being removed, and per §2.1 it is also what FR-002 relies on today, which is why FR-002 must be
re-verified rather than assumed.

## 5. Plan (sequenced; slices 1–3 are behaviour-neutral by construction)

- **S0 — measure first, no code.** Index this repo (and a corpus if available) with `main`'s
  binary. Record: `calls` by kind; MUST-with-NULL total and Stdlib-excluded; **FR-006's metric on
  main**; a full `(caller, callee_name, kind, callee_path)` dump for set-diffing.
- **S1 — ambiguity census.** How many `cmt_modname` values map to ≥2 distinct paths, and how many
  currently-resolving MUST edges land on one. This is FR-003's blast radius. Known local
  candidates: three `main.ml` (`tezt/tests`, `bin/arch_sidecar_load`, `bin/arch_effects_load`).
  **Unit names are not globally unique either** — if this census is large, FR-003's ⊤ rule is the
  660→875 regression under a new name.
- **S2 — `top_reason` value.** The taxonomy is a closed enum with a schema CHECK and
  `tezt/tests/top_anchor_taxonomy.ml`. Decide new member vs reuse; land it isolated and green.
- **S3 — registry, capture only, no consumer.** `unit_paths` in `arch_index_cmt.ml` beside the
  dropped registries, populated at `insert_module` (`:1673`) and `record_dropped_unit` (`:1707`),
  reset in `reset_dropped`. Ship with a runtime counter of stored `modules` rows lacking a registry
  entry, asserted **0** — non-zero silently manufactures MUST-with-NULL.
- **S4 — swap the call-site resolver.** Build a **new** `unit_to_paths` table; leave
  `mod_name_to_path` untouched so §7's out-of-scope claim is true by construction rather than by
  hope. Enumerate per §4, collect distinct `fn_id`s, apply FR-003. Re-target `dropped_qualified`
  in the same commit (FR-005).
- **S5 — re-measure and attribute.** Set-diff, not counts. Every moved edge classified: fixed
  mis-attribution / newly-⊤ / **newly-unresolved (regression)**. The third bucket must be empty or
  individually justified. *This is the gate both prior rounds failed.*
- **S6 — fixtures** per FR-007, in tezt (§6). Prove they fail against a `main` build, don't assert
  it.
- **S7 — golden + peer coupling** (§8).

## 6. Test placement: tezt, NOT `checks/*.js`

v1 said to port checks into `checks/` and wire them into CI. **That reverses a decision already
taken on main.** `.github/workflows/ci.yml:70-73` records that the standalone Node checks were
migrated *off* that runtime into `tezt/tests/nested_module_qualification.ml` and
`tezt/tests/must_null_ceiling.ml` "so they run here like everything else". `checks/` still exists
on main with an orphaned `mid-caller-shadow-attribution.js`, wired nowhere.

All gates for this task go in tezt. FR-006's ratchet extends the existing `must_null_ceiling.ml`
rather than adding a fourth parallel runtime with a drifting metric.

**Already covered, do not duplicate:** `nested_module_qualification.ml` pins the *unlinked decoy*
shape (caller links `aaalib` only; an unrelated wrapped `foo` emits `Foo__Bar`; the edge must
never name the decoy, and `MAY_TOP` is accepted as honest). This spec's FR-001 is the
**complementary** shape — both libraries legitimately linked — which that file deliberately does
not cover.

## 7. Scope, and an honest residual v1 hid

**In scope:** the call-resolution site only.

**Out of scope:** `module_deps` (`arch_index.ml:646-690`, which *re-populates* `mod_name_to_path`
with its own inlined basename derivation after call resolution) and `type_usage`
(`:703-718`, which builds its **own** `type_lookup` keyed `(basename, type_name)` — independent
code with an independent latent defect, unmeasured). v1 claimed all three "share
`resolve_module_root`"; they do not — they share only the hashtable, and only two of them.

**Residual v1 did not disclose:** for a `(wrapped false)` library the compiled unit name **is** the
capitalised basename, so unit-keying disambiguates nothing and **FR-001's defect persists** for
such libraries. This is a strict subset of the same bug, reachable by FR-001's own wording, and
must be stated as a boundary rather than discovered as "the fix sometimes doesn't work". FR-007
requires a fixture that pins the boundary explicitly.

**Known internal inconsistency created:** after this change, for the same source reference,
`calls` will point precisely while a `module_deps` row can still point at the wrong library. A
consumer joining the two sees a contradiction. Accepted deliberately (the call site is where MUST
edges feed reachability and rules), recorded so review does not have to rediscover it.

## 8. Peer coupling — corrected

v1's G-1 measured the wrong artifact. Exception identities come from
`Arch_index_exn.canonical_path ~unit_declared ~cmt_modname` (`arch_index_exn.ml:166`), computed in
the cmt pass from `cmt_modname`. They **never touch `mod_name_to_path`**, so this change
**provably cannot alter an identity spelling**, and a clean spelling diff would be false
reassurance.

What it *can* change: which functions a `fails-with <E>` query returns, because raise sets
propagate along `calls` edges and this change moves which function some calls resolve to.

- **G-1 (corrected)** Diff `fails-with`/`raises` **result sets** per identity, and the underlying
  `calls`-edge set diff that drives them.
- **G-2** Attribute any movement in `docs/exception-raise-sets-validation.md`; never edit expected
  values.
- **G-3** `exn_rebinds (alias_path, target_path)` as a belt-and-braces diff — if the
  canonicalisation table moves, something unmodelled has happened.
- **G-4** Ping `arch-index-0e` with the result-set diff before merge.

### 8.1 Authoritative pre-change baseline @ `origin/main = 7fcf3c0`

Measured by `arch-index-0e` from a **detached worktree at `origin/main` itself**, not from a
feature branch, and identical to the pre-merge frozen set — so neither the #60 linearisation nor
its `||` fix moved anything. This is the baseline every S5/S7 delta is attributed against; it is
not to be re-established unilaterally mid-task.

**octez-manager** — nodes 12317 · bounded 3024 (24.6%) · 47.6% under `--assume-externals-pure` ·
⊤ external 2834 · ⊤ may_top_edge 6459 · origins 765 · exception scopes 491 · exception links 2245.

**proto_alpha** (`--errors-profile tezos`) — nodes 14452 · bounded 3436 (23.8%) · 46.4% under-hyp ·
⊤ external 3273 · ⊤ may_top_edge 7743 · origins 1219 · exception scopes 19 · exception links 35 ·
tzresult 585/2137 (27.4%).

**Cheap tripwires (proto_alpha), one query each:**

| metric | baseline | meaning if it moves |
|---|---|---|
| distinct exception identities (`exn_origins`, non-NULL) | **11** | wholesale spelling shift — should be impossible (§8) |
| distinct tzresult identities | **377** | same |
| `exn_rebinds` rows | **6** | **"something neither of us understands"** — this table is pure aliasing and cannot be reached by a resolver change |

Weaker than the full answer-set diff G-1 requires, but they cost one query and catch a gross
regression immediately. `exn_rebinds` moving is the loudest possible signal that a premise is wrong.

**Counting caveat:** `exn_scopes`/`call_exn_scopes` are shared across channels since #60. A
channel-blind count reads **4386** links on octez-manager (vs 2245) and **487** on proto_alpha
(vs 35). Always filter `WHERE s.channel='exception'`.

## 9. Rejected designs

- **`cmt_imports` digest disambiguation** (the abandoned branch's approved round-3 plan) —
  disproved empirically: the caller imports **all** candidate units (`Foo`, `Foo__`, `Foo__Bar`).
  Research Finding 3.
- **Rebasing `rebase/sound-qual`** — decided with the human, 2026-09-04.
- **Candidate narrowing to a single guess** — forbidden by FR-003.
- **Editing `mod_name_to_path` in place** — would leave the dep phase writing basenames into a
  unit-keyed table (§7).

## 10. Verification obligations

- `dune build --root . @all` and `dune test --root . --force`. **`--root .` is mandatory**: dune
  searches upward for its project root and this environment's `/tmp` contains stray
  `dune-project` files, which silently reroots a bare invocation (research Finding 6 — also the
  true cause of the `callgraph-go`/`pcc` failures previously written off as environmental).
- Self-index golden regenerated per ADR 001 **with the delta attributed**. It is a change
  detector, not a correctness gate — it is provably blind to this defect class.
- S5's three-bucket set diff is the real gate.

### 10.1 Measurement scope — the trap this task kept falling into

Every measurement error on this task so far has been a **correct number at the wrong scope**, never
a miscount. Seven instances, same shape:

| wrong scope | right scope | what it would have caused |
|---|---|---|
| `must_null_ceiling`'s `clean_measured = 321` (a constant calibrated 2026-09-01) | `main`'s **live** value, 340 at `7fcf3c0` | chasing a +18 "regression" that was #60's drift, not mine |
| indexing `lib/arch_index` alone (reads **142**) | the whole repo `_build/default` (reads **340**) — what this ratchet actually indexes | the drift would have looked imaginary (credit: `arch-index-0e`) |
| channel-blind `call_exn_scopes` count (**4386** on octez-manager) | `WHERE s.channel='exception'` (**2245**) | a false regression alarm on a shared table |
| identity **spellings** (`exn_origins.exn_path`) | `fails-with` **answer sets** | a clean diff misread as safety, §8 |
| a normal clone with an empty ancestor chain | a worktree under a shared `/tmp` | CI green because `dune`/`go` found the right root by luck, #61 |
| indexing `src/proto_alpha` (**690** modules / **22267** fns) | `src/proto_alpha/lib_protocol` (**468** / **14452**) — the frozen baseline's scope | a base-vs-new diff that is internally valid and not comparable to the baseline, S7 |
| indexing **each worktree's own** `_build/default` | ONE fixed build dir, both binaries | two different corpora compared as one; caught only because the call TOTALS disagreed (12830 vs 13009), S7 |

**Rule:** before trusting any number here, state what it is measured OVER and confirm that matches
what the claim is about. A constant is not a measurement; a subdirectory is not the repo; an
unfiltered count is not the metric; and a name is not an answer.

**Every wrong scope above produced a PLAUSIBLE number.** None errored, none looked absurd, and that
is why they survive review. "Measure carefully" is therefore useless advice — careful and careless
return identical-looking numbers. What caught all seven was **comparing two scopes against each
other**, never one scope against an expectation.

### 10.2 The measured artifact is not the one under test — a DIFFERENT class

Found by `arch-index-0e` while verifying the #62 fix, and it does not belong in the table above,
because no scope comparison can detect it.

`dune exec tezt/tests/main.exe` does **not** rebuild the producer. `tezt/tests/dune:35-36` declares
`%{exe:../../bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe}` in `deps`, but `deps` applies to
`dune runtest`, not to `dune exec` of an executable target — and `arch_tezt.ml:51` locates the
producer by PATH on disk, so it happily runs the previous build's stale `.exe`.

**The boundary is exact, and both halves were measured** — the first attempt to check this tested
the wrong command and concluded the whole thing was a non-issue:

| command | after a lib mutation |
|---|---|
| `dune test` / `dune runtest --force` | **safe** — producer rebuilt (hash changes), suite reddens |
| `dune exec <test target>` | **unsafe** — producer hash UNCHANGED, reports SUCCESS |

So neither "always rebuild first" (noise) nor "it's fine" (false) is the rule. `dune exec` of a
test target builds that target and nothing else.

Demonstrated, not deduced: fix removed + `dune exec` → SUCCESS; then an explicit
`dune build bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe`, same test, same command → FAILURE
with 2 assertions. Only binary freshness changed.

The number here is not at the wrong scope — it faithfully describes a binary. Just not the one in
the diff. So a second measurement cannot expose it, and the control is not another number but a
**source mutation that must change the result**.

**This is what red-then-green already buys, for free.** S7's scenario D was verified by disabling
the second resolution tier in-tree and observing FAILURE. Had the producer been stale that run
would have passed GREEN, because the pre-edit binary contained the fix. So a test asserted red
before it is asserted green is simultaneously a freshness proof of the artifact under test, and
that is the reason the discipline is mandatory here rather than merely encouraged.

**Rule:** run the suite through `dune test` / `dune runtest`, never `dune exec`; and never accept a
green from a test that has not been seen red on this machine, on this build.

### 10.3 A number in a comment is a measurement without a harness

`arch-index-0e`'s formulation, and it explains why round 2 of review found *three* unreproducible
figures in one branch when the same branch's test assertions and doc tables were largely sound.

Every number this task got wrong in a **comment** — `2385`, `-1638/-1616`, `86`, the O(N²)
timings — sat where nothing re-runs it. A number in a test fails when it drifts. A number in a
golden fixture fails when it drifts. A number in a `(* … *)` is asserted once, by someone who had
just measured it, and is thereafter read as evidence by people who cannot check it and will not
try. It ages into authority precisely because it is inert.

Two of the three were worse than stale, and in the same direction: they were *correct
measurements of something else* — `2385` from a wider corpus scope through a set-diff that counts
a re-target as a loss, `25116` from the facade-tier-disabled variant rather than the conjunct it
was cited for. Which is §10.1's trap again, now with no harness to catch it.

**Rule:** a measurement in a comment must carry the scope it was taken over and the command that
reproduces it, or it must not carry a number at all. "Doubling the corpus multiplied the overhead
by ~6" survives a machine change; "0.109s → 0.174s" does not. Where the number is load-bearing —
where it is the stated reason a design was rejected — it belongs in a test or a fixture, not in
prose.

### 10.4 The exit status lies about what ran

`arch-index-0e`'s generalisation, after the same defect surfaced three times in one day. It is not
§10.1's trap — the number is not at the wrong scope. It is a case where **the exit status describes
something other than the work you asked for**, so no comparison of numbers can expose it.

| where | what happened |
|---|---|
| `dune exec tezt/tests/main.exe` | `deps` applies to `runtest`, not `exec`, and the harness finds the producer by PATH — so a green test described the PREVIOUS build's binary |
| `scripts/recalibrate.sh` | `dune build … \| tail -20` exits with **tail's** status, always 0, so `\|\| { build failed; exit 2; }` was dead code and a tree that failed to compile was measured with the previous producer |
| `scripts/callgraph-diff.sh` | `set -eu` but no `pipefail`, same `\| tail`; the baseline was safe (fresh worktree, no binary, `-x` guard fired) but the working tree normally HAS a stale `.exe`, so both binaries existed, both databases populated, and the tool emitted a plausible non-empty diff describing the wrong binary |

Two of the three were in tooling built specifically to catch stale-artifact problems.

**Rule, two halves.** A pipeline returns the status of its LAST command, so `set -e` stops
protecting anything the moment a `|` appears — `set -euo pipefail`, and never `| tail` a build whose
failure matters. And the operational corollary, which is the half that actually costs: **a binary
that exists is not a binary that was just built.** A fresh worktree fails safe because there is
nothing stale to fall back on; the tree you work in does not.

**What already catches it for free:** a test asserted RED before it is asserted green. If the
producer were stale, the red run would pass, because the pre-edit binary contains the fix. So
red-then-green is simultaneously a freshness proof of the artifact under test — which is why the
discipline is mandatory here rather than encouraged, and why the exposure is confined to checks
made WITHOUT a prior red: confirmation runs and corpus measurements.

### 10.5 A three-state verdict reported as one number

Found by the human, from a one-line challenge: *"arch-rules 4/0 ?"*.

`arch-rules` was reported all day as **"4 rules, 0 failing"**, including in ship-gate summaries for
three separate branches. What it actually returns:

```
[ pass  ] the comment parser must not reach the SQLite layer
[UNKNOWN] the CFG builder must not reach the SQLite layer
[UNKNOWN] the line counter must not reach the SQLite layer
[UNKNOWN] the LSP client must not reach the CMT walker
```

**One of four invariants is proved.** The other three abstain: their source cone escapes through a
⊤ edge, so nothing is established either way — and `arch-rules.txt`'s own header says exactly that
(*"UNKNOWN = the cone escapes through a ⊤ edge, so nothing is proved either way; pass = proved
unreachable in a closed universe"*). "0 failing" is a true statement about the third state only.

The escaping edges are `callback_param` (36) and `module_param` (6) — higher-order calls and
functor arguments. Not one is a resolution failure, so no amount of work on this task moves those
three verdicts; they need roadmap 3.7. Identical on `main` and on this branch, which is the correct
thing to claim: **the gate is unchanged**, not **the gate passes**.

Two lessons, and the second is the general one:

**`--on-vacuous fail` does not cover this.** That flag exists because a rule whose selector stops
matching turns green forever and looks like coverage. But UNKNOWN is not vacuous — the selector
matches; the cone escapes. So the guard against a silently-decaying rule does not guard against a
rule that has become unprovable, which is the state three of the four are in.

**Rule:** a verdict with N states must be reported with N numbers. Collapsing `proved / UNKNOWN /
violated` into "0 failing" is not a summary, it is the loss of the distinction the tool exists to
draw — and it fails in the reassuring direction, which is why it survived being repeated for a
whole session. Report `1 proved / 3 UNKNOWN / 0 violations`.

### 10.6 A check that looks like a check

`arch-index-0e`'s generalisation, and the most expensive family identified in this work: a control
that passes review **as proof** while testing nothing. Five instances, all found in one day, three
of them in tooling built to catch exactly this:

| where | why it wasn't a check |
|---|---|
| `or_mixed`'s exception assertion (#65) | its scrutinee cannot raise, so `BOUNDED: {}` held whether or not the arm closed — removing the exception channel's or-flattening **entirely** left the suite 130/130 green |
| the exception channel's or-flattening itself | zero coverage, so deleting the precedent the whole PR argued from was a silent no-op |
| `recalibrate.sh`'s golden write (#64) | round 2 moved the write to a scratch file and moved the verification with it, so an unchecked `mv` printed `✓ WROTE … byte-identical` and exited 0 having written nothing |
| `metric_well_formed` (#64) | the guard between a silently-failed query and a written constant, stubbed to `return 0`, left `--self-test` reporting "all cases pass" |
| scenarios E and G (roadmap 1.6) | asserted `dir = None \|\| dir = Some "inca"` without constraining `kind`, so they **blessed** a `MUST` with a NULL callee into an indexed unit — the shape the same file calls "a resolver miss dressed as a proven external leaf" |

The common shape is not a wrong assertion. It is an assertion whose expected value is **also what a
broken implementation produces** — `{}`, the full set, `None`, "current" — so it is satisfied by
absence. Review does not catch it, because reading it tells you what it *intends*; only running it
against a broken implementation tells you what it *detects*. And it is worse than no check, because
it occupies the slot where a real one would have gone.

**Rule:** for every assertion, name the mutation that makes it fail. If you cannot name one, it is
not a check. Then apply it — break exactly what the assertion claims to cover and watch it fall.
Suspect any expected value that a broken analysis also yields: an empty set, a full set, a `None`,
a "no change".

This is why red-then-green is not a nicety here. A characterisation test on already-correct
behaviour has no natural red, so the red has to be **manufactured**: that is the only step that
distinguishes "I derived this by hand" — a claim about the author's process — from evidence in the
repository.

## 11. Errors in v1 of this spec, corrected here

Recorded because this task has already failed twice on unexamined assumptions, and a spec that
quietly rewrites itself teaches nobody.

1. Scoped against **`resolve_module_root`, which does not exist on main** — a symbol carried over
   from the abandoned branch without verification.
2. Claimed the fix "preserves the `fn_lookup` check so FR-002 keeps working". FR-002 actually
   passes today **via the bare-segment erasure being removed** (§2.1). The fix is materially
   riskier than v1 described.
3. Claimed all three resolution sites share one function. They share a hashtable, and only two do;
   `type_usage` has its own independent table (§7).
4. Directed tests into `checks/*.js` + CI wiring, **reversing a migration already made on main**
   (§6), and described porting files that had already been ported.

Additionally, the peer-coupling gate measured identity spellings, which this change provably
cannot move (§8).
