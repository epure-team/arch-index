# Spec — sound qualified-name resolution (arch-index)

Adversarial spec for the `MUST`-to-wrong-homonym defect. PR #20 failed for lack of a stated
property; this file states it, then states what would falsify it.

**Relationship to `specs/qualified-unit-resolution.md`** (added round-5 review): THIS file states
the REQUIRED property (P1/P2/P3) and the GWT scenarios/falsifiers a change must satisfy — it is the
adversarial spec, not a description of the implementation. `qualified-unit-resolution.md` is the
descriptive account of what the resolver in `lib/arch_index/arch_index.ml` actually does,
including its disclosed residuals. On a point of FACT about the code, that file wins; on what
SHOULD be required, this file's scenarios and falsifiers win. See this file's S3 status note for
the one place the two were found to disagree, and how it was resolved.

## The property

**P1 (soundness of MUST).** For every row in `calls` with `kind = 'MUST'`, the `callee_id` is the
function that the OCaml compiler itself resolved at that call site. Formally: a `MUST` edge is
emitted **only** when the producer can name the owning compilation unit of the callee; when it
cannot, the edge is `MAY_ENUMERATED` (bounded candidate set) or `MAY_TOP` (unknown) — never absent,
never `MUST`.

This is not new policy: `docs/edge-kind-contract.md:5` already defines `MUST` as
"uniquely-resolved", and `SPEC-sound-callgraph.md:44-46` already forbids collapsing a site to one
target. P1 makes the *homonym* case explicit, which the contract left unsaid.

**P2 (honest degradation).** Loss of library identity (dune `(wrapped false)`, LSP path, vendored
sources) degrades the edge kind. It never degrades into a guess. `UNKNOWN ≠ NO`, and
`UNKNOWN ≠ pick one`.

**P3 (no regression of precision without cause).** Edges that are genuinely uniquely-resolved today
stay `MUST`. A fix that made everything `MAY_TOP` would satisfy P1 vacuously and is rejected —
see the falsifier F3.

## GWT scenarios

**S1 — cross-library homonym (the defect).**
- *Given* two dune libraries, `liba` and `libc`, each with an `api.ml` defining `run`
- *And* a third library `libb` whose `caller.ml` calls `Liba.Api.run ()`
- *When* the OCaml CMT producer indexes the project
- *Then* the `calls` row for that call site resolves to `run` in **`liba/api.ml`**
- *And* if the producer cannot establish that, `kind` is `MAY_ENUMERATED` or `MAY_TOP`
- *And* in no case is there a `MUST` row pointing at `run` in `libc/api.ml`

> **STATUS (round-6 review): MET for this scenario's own fixture (scenario A); NOT MET as the
> general principle it states.** Scenario A itself is green and stays green — `Liba.Api.run` and
> `Libb.Api.run` each resolve within their own library, never crossing. Read more broadly, though —
> "in no case is there a `MUST` row pointing at the wrong library's homonym" — the property is
> violated by disclosed residuals F, J and L (see F1's status note below), and was violated by
> scenario M until `6e7b429` closed that specific shape (a `(wrapped false)`/wrapped-main-module
> unit-name collision resolved entirely in the PREFIX tier, never reaching the facade tier this
> spec's S3 amendment governs). Re-checked here because an earlier round of review found this
> clause violated by M's then-fixture and it needed re-verifying after M was closed: M no longer
> violates it, but F/J/L still do, unrelated to M's fix. See F1.

**S2 — same-name module, single library (must not regress).**
- *Given* one library where a qualified path is unambiguous (existing `arch_tezt_qual` shape)
- *Then* the edge stays `MUST` and resolves as it does today

**S3 — re-export and alias (already safe, must stay safe).**
- *Given* `module A = Liba.Api` / `include A` and a call through the alias
- *Then* the edge is `MAY_TOP` — never a `MUST` to any candidate

> **AMENDED by roadmap 1.6 (round-5 review; found by the contradiction between this line and
> scenario D, `tezt/tests/qualified_library_scoping.ml`).** As first written, S3/CHECK-2 forbade
> `MUST` through *any* alias or `include` unconditionally — the safe default before a function-table
> arbitration existed. Roadmap 1.6 introduces exactly that arbitration (the 1 / 2+ / 0 rule: every
> reading of a qualified name is tried, and the count of DISTINCT function ids they reach is the
> verdict), and it is what scenarios A, B and D depend on: `module Bar = Bar` (scenario B) and a
> cross-library re-export facade (scenario D, `Facade.Protocol.Script_int` → `Rawlib__Script_int`,
> verified on proto_alpha as `Tezos_protocol_alpha.Protocol.Main.acceptable_pass` →
> `lib_protocol/main.ml`) are BOTH aliases/re-exports through which a `MUST` is now legitimately
> emitted, precisely because exactly one candidate answers. S3 is not violated by this for the
> TWO-OR-MORE case — it is narrowed: an alias/`include` call site is `MAY_TOP` when the function
> table finds TWO-OR-MORE candidates (scenario C), and `MUST` when it finds exactly ONE (scenarios
> A, B, D).
>
> **CORRECTED, round-6 review.** The zero-candidate half of the amendment above, as first written
> ("`MAY_TOP`... exactly when the function table finds ZERO or TWO-OR-MORE candidates"), is FALSE:
> scenarios E and G are alias/`include` call sites where the function table finds ZERO candidates
> (the row is reachable only through `include`, not at the referenced path) and the SHIPPED tests
> assert `kind = MUST && dir = None`, verified live against this branch's own producer. So CHECK-2
> as first amended is unsatisfiable against the shipped suite — it demands `MAY_TOP` on every
> zero-candidate alias/include site, and E/G are exactly that shape with `MUST`.
>
> The honest zero-candidate statement: when the deepest reading names an INDEXED unit (the anchor
> exists — `Inca__Api`, `Ginca__Api`) but the function table finds no row there, the reference is
> emitted `MUST` with a NULL callee — a proof-shaped edge into a unit the graph indexes, at a row
> the graph also holds (reachable via `include`), which it fails to find. This is a DEFECT, not a
> narrowing of S3: it is a real violation of F1 (a `MUST` edge that is not the compiler's own
> resolution — here, no resolution at all, dressed as an external leaf), pinned as DISCLOSED
> RESIDUALS by scenarios E and G (`tezt/tests/qualified_library_scoping.ml`), in the same style as
> F, J and L. It is not fixed by this change because closing it means following `include` to find
> the row, a separate capability (`briefs/linkage-evidence-followup.md`). Per §10.6, each of E and
> G's tests also asserts (a) the true callee row exists in the index and is reachable, and (b) a
> companion reference in the SAME fixture with no `include` indirection resolves correctly — so a
> resolver mutated to answer `` `Not_found `` unconditionally (which trivially satisfies
> `kind=MUST, dir=None`) now FAILS both tests, where before round 6 it passed both. Measured: before
> the added assertions, that mutation left E and G green while 9 other scenarios failed; after, the
> same mutation fails 23 of 142 tests, E and G among them.
>
> CHECK-2 is therefore NOT MET as originally stated for the zero-candidate case: see its own status
> note below. See `specs/qualified-unit-resolution.md` for the resolver-level statement of the 1 /
> 2+ / 0 rule and the facade tier this amendment sanctions.

**S4 — the three sites.**
- *Given* the same cross-library homonym shape
- *When* module dependencies (`arch_index.ml:421`) and type usages (`:479`) are resolved
- *Then* neither attributes the dependency/usage to the wrong library

> **STATUS after roadmap 1.6 (`feat/qualified-unit-resolution`): NOT MET, deliberately.**
> Only the CALL site is fixed. `module_deps` and `type_usage` still key on the capitalised file
> basename in a last-writer-wins table, so both still attribute a cross-library homonym to the
> wrong library — and `arch-rules` derives its `forbid dep` verdict directly from
> `module_deps.target_module`, so a real architecture violation can report **pass** while a
> nonexistent one reports **FAIL**. This is retained from `main`, not introduced.
> Pinned by scenario K of `tezt/tests/qualified_library_scoping.ml`, which asserts the defect and
> fails when it is closed. Closing it means re-keying `type_lookup` on `(path, name)` the way
> `fn_lookup` already is and routing both sites through `unit_readings` — its own slice, with its
> own corpus validation, because both feed consumers that treat their output as proof.
> Found by adversarial review, which is the only reason it is written down here rather than
> silently unmet. (Moved here from S3, round-5 review: this block is entirely about `module_deps`
> and `type_usage`, i.e. S4, and had been sitting inside the S3 section since it was first added.)

**S5 — self-index integrity.**
- *When* arch-index indexes itself after the change
- *Then* `arch-rules … --on-vacuous fail` still passes, and the golden stats file is updated with
  the edge-kind delta explained in the commit

## Falsifiers (what would prove the fix wrong)

- **F1** — any `MUST` row whose callee lives in a library other than the one named by the
  qualified path's root. This is the defect; the red test asserts its absence.

  > **STATUS (round-6 review): NOT MET, deliberately, for three disclosed residuals.** As stated,
  > F1 demands absence everywhere; scenarios F, J and L assert its PRESENCE and are green — each is
  > a `MUST` row whose callee's library differs from the qualified path's named root, pinned as a
  > DISCLOSED RESIDUAL rather than fixed by this change (F: a reference rooted entirely outside the
  > index; J: an aliased nested module reaching an unlinked homonym; L: a homonym unit below the
  > anchor binding a LINKED wrong library). All three need the caller's `.cmt` import list —
  > linkage evidence not captured today, see `briefs/linkage-evidence-followup.md` — to close. F1
  > holds for every shape this change actually addresses (the PREFIX-tier and anchored-facade-tier
  > cases: scenarios A, B, D, H, and the zero/two-candidate cases C, I, M), and does not hold for
  > shapes below the facade tier's anchor or entirely outside the index. Not found by this test
  > suite failing — found by adversarial review reading the suite's own green results.
- **F2** — a single-candidate narrowing path that re-stamps `MUST` after filtering removed the true
  owner. This is exactly why PR #20 was closed; any implementation reintroducing it fails.
- **F3** — a collapse in `MUST` count on the self-index disproportionate to the correctness gain.
  `test/fixtures/self-index-stats.txt` holds only `modules`/`functions`/`calls` (23 / 803 / 5168 on
  this branch) — no edge-kind breakdown, so it cannot itself falsify F3; an earlier revision of
  this line cited MUST 1107 / MAY_ENUMERATED 2106 / MAY_TOP 178 "against" that golden, which sums
  to 3391, not 5168, and does not reproduce (found round-6 review). The edge-kind distribution,
  reproduced by running the exact CI self-index command
  (`.github/workflows/ci.yml`'s `Self-index smoke test` step) and then
  `SELECT kind, count(*) FROM calls GROUP BY kind` on `/tmp/self.db`, is
  **MUST 1736 / MAY_ENUMERATED 3136 / MAY_TOP 296** (sums to 5168, matching the golden `calls`
  row) on this commit. Re-measure at the same command any time this falsifier is invoked; do not
  copy this triple forward, for the same reason `unit_readings`' join-recipe comment (LOW-9) gives.
- **F4** — the new fixture passing before the fix. A test that is green on the defective code
  proves nothing; the red run must be recorded.

## Runnable checks

- **CHECK-1** → S1: new multi-library Tezt fixture; assert `callee_id` is `liba`'s `run`, or
  `kind ∈ {MAY_ENUMERATED, MAY_TOP}`; assert **no** `MUST` row to `libc`'s `run`.
  Red-then-green: must fail on `main` before the fix.
- **CHECK-2** → S3 (amended, see the status note under S3): assert an AMBIGUOUS alias/include call
  site (two or more distinct function ids answer to it — scenario C's shape) is `MAY_TOP`, and that
  an UNAMBIGUOUS one (scenarios A, B, D) stays `MUST`. Guards against a fix that over-reaches into
  a genuine two-answer case in EITHER direction: demoting an unambiguous alias to `MAY_TOP`
  (scenario B's regression) is as much a failure as promoting an ambiguous one to `MUST`
  (scenario C's would-be regression).

  > **STATUS (round-6 review): MET for the two/one-candidate cases above; the zero-candidate case
  > is OUT OF SCOPE for this check, NOT MET by the resolver, and NOT what CHECK-2 tests.** CHECK-2
  > as written above never asserted a zero-candidate outcome; it was the S3 status note's prose
  > that claimed zero behaves like two-or-more (`MAY_TOP`), and that claim is what scenarios E and
  > G falsify (see S3's status note). The zero-candidate, anchor-exists case is pinned separately,
  > as a DISCLOSED RESIDUAL rather than a runnable spec check, by scenarios E and G in
  > `tezt/tests/qualified_library_scoping.ml` — deliberately not folded into CHECK-2, since CHECK-2
  > is a REGRESSION GUARD for the arbitration this change ships (S3's 1/2+/0 rule) and the
  > zero-candidate-with-anchor defect is not something this change fixes or claims to fix.
- **CHECK-3** → S5: `arch-callgraph-ocaml` on self + `arch-rules --on-vacuous fail` exit 0; golden
  diff reviewed, not auto-accepted.

## Explicitly not specified here

The 4th site (`call_graph_extractor.ml` raw-function-name keying), `arch_query`'s `WHERE name=?`,
the `is_dune_alias_module` wrapper shape, and the LSP nominal path. Same pattern, separate work.
