# Intake Brief — vuln-reachability-triage

**Date:** 2026-09-06
**Status: VALIDATED**
**Type:** feature
**Trust boundary:** yes

> **On the two fields above.** `Type: feature` — this adds a capability that does not exist.
> `Trust boundary: yes` — the step-4.5 keyword heuristic fired (`evidence`), and it fired for the
> right reason rather than incidentally: this feature emits verdicts a reader may use **as evidence
> to discharge a vulnerability finding**. Both were set without a human gate under an explicit
> autonomy instruction; both are the *conservative* value, so neither removes rigour — `yes`
> makes `/roster-spec` run rather than skip. The human separately chose `--full` over `--critical`
> against the Tier A keyword hit, with the recommendation that the load-bearing invariant is a
> property of a query path and testable by a red-verified fixture rather than a claim needing a
> proof assistant.

## Goal

Grade each external security advisory that names affected OCaml functions against this
repository's sound call graph, and report — per advisory — whether those functions are reachable
from the program's API surface. The value is **not** the `PASS`. Every comparable tool either
resolves analysis failure toward *reachable* (govulncheck has no inconclusive tier, and documents
that code reachable only through `reflect` "will not be reported" — a false-negative source that
is documented but **silent in its output**) or toward *unreachable* (Snyk's "No Path Found",
explicitly disclaimed in Snyk's own docs as not meaning unreachable). This tool takes a third
position that the repository already implements: uncertainty is its own reported state, and the
edges blocking the proof are **named**.

**The research phase shrank this slice, and that correction belongs here rather than being
presented as though the smaller scope were always the plan.** This task was dispatched describing
"`PASS` requires an empty ⊤ frontier on the cone" as the thing to build. It already exists:
`reach_verdict` (`bin/arch_rules/arch_rules.ml:589-605`) computes
`NO_SOURCE | NO_TARGET | VIOLATION | POSSIBLE | UNKNOWN | UNKNOWN_NO_CONTRACT | PASS`, with the
escaping-⊤ check evaluated *before* `PASS`; and `docs/adr/002-external-tool-integration.md` already
states normatively that "a heuristic fact may raise a finding but may never discharge a ⊤ anchor
and may never license a PASS". Two of the four constraints handed to this task were already built.

**So 3.1 is INGESTION + RULE GENERATION + LEDGER, not a reachability engine.** It supplies inputs
to machinery that exists, and keeps a durable record of what those inputs produced.

## Scope Boundary

Explicitly OUT of scope:

- **Building or modifying the verdict lattice.** `reach_verdict` is used as-is.
- **Extending the corpus to the opam dependency closure.** A separate task; it only pays off after
  the ⊤ frontier work.
- **Resolving the ⊤ frontier itself.** Measured dependency, not this slice — see Architecture Notes.
- **Un-flattening `Path.t` in the producer.** Surfaced as an Open Question with its cost stated;
  not assumed in or out by this brief.
- **Ecosystems other than opam.** Measured: symbol-level data is absent from npm (0/6), PyPI
  (0/38) and crates.io (0/28 across three informative packages), and Go's `imports[].symbols` is a
  different field this corpus has no consumer for.
- **`osv-scanner` as an ingest path.** It cannot scan opam at all (`strings | grep -cF opam` → 0
  against working controls: crates.io 1, Packagist 21, PyPI 45, Cargo.lock 1).
- **Merging.** A permanent instruction from the repository owner; PRs stay ready for his decision.

## Relevant Files

| File | Role | Key snippet |
|---|---|---|
| `bin/arch_rules/arch_rules.ml` | The verdict engine this feature feeds. Rule DSL parser, `reach_verdict`, SARIF mapping | `589-605` the lattice; `449-452` `[ "forbid"; "reach"; "from"; a; "to"; c ]`; `1179-1184` `NO_SOURCE\|NO_TARGET -> "VACUOUS"`; `46-58` usage already shows `forbid reach from exported:** to fn:Vuln.parse` |
| `lib/arch_tools/arch_sel.ml` | Selector language a generated rule must emit | `22-23` `type kind = File \| Fn \| Module \| Ext \| Exported`; `94-115` `parse ~allow`; `cone_source = [File; Fn; Module; Exported]` for a reach SOURCE, `with_ext` for its TARGET |
| `lib/arch_tools/arch_graph.ml` | ⊤-aware closure | `129-146` `closure seeds adj`; `g.tops` consulted by `reach_verdict` |
| `bin/arch_query/arch_effects_queries.ml` | **The trap.** ⊤-dropping SQL closure | `78, 114, 123` `WHERE c.kind IN ('MUST','MAY_ENUMERATED')` |
| `lib/arch_index/arch_index_cmt.ml` | Where `Path.t` is flattened | `746-756` `path_to_module_name`, `Papply \| Pextra_ty -> "<apply>"`; `728-736` `module_target_path` keeps `Path.t` **unflattened**; `605` `Head_qualified of string option * string` |
| `lib/arch_tools/arch_sarif.ml` | Output path | `22, 65` `soundness_class : string option` — separate from `level`, because `level` alone collapses `UNKNOWN`/`UNKNOWN_NO_CONTRACT` onto one severity |
| `docs/adr/002-external-tool-integration.md` | Normative constraint | `28-38` the three-class table; `48-54` SARIF-in is `heuristic` |
| `architecture-schema.sql` | Where provenance already lives | `32-60` `producer_runs(producer, producer_version, invocation_digest, soundness_class CHECK(… IN ('sound_with_top','heuristic','asserted')), created_at)` |
| `lib/arch_index/arch_index_db.ml` | Schema version, bumped by hand | `90` `current_schema_version = "1.12"` |
| `lib/arch_index/arch_index_support.ml` | Drop list — any producer-written table absent from it is unsound on re-index | `56` `schema_tables_to_drop` |
| `schema/review-finding.schema.json` | Precedent for a durable record + its fail-closed validator | required: `severity, confidence, path, line, category, summary, evidence, fix, fingerprint, specialist`; validator at `scripts/lib/review/finding-schema.js:1-50` rejects unsupported keywords |
| `bin/arch_coverage/arch_coverage.ml` | The existing precedent for this task's core distinction | `298-330` reports API-reachable functions with no coverage data as **"not instrumented, NOT unreachable"** |

## Architecture Notes

**Measured settled input — do not re-derive.**

Complete census of the opam OSV ecosystem archive: **26 advisories**;
`ecosystem_specific.imports[].symbols` **0/26** (the Go spelling); `ecosystem_specific.affected_bindings`
**7/26, 49 bindings**. Adoption is **growing, not legacy**: 2016–2025 = 9 advisories, 0 with
bindings; 2026 = 17 advisories, 7 with bindings, all 49.

Resolvability, two corpora, **reported broken down and never merged**:

| | arch-index self-index | Tezos `src` |
|---|---|---|
| modules / functions / calls | 105 / 3 198 / 17 862 | 8 615 / 304 323 / 1 198 104 |
| 49 bindings as `functions` rows | 0 | 0 |
| 49 bindings as `calls.callee_name` | 0 | 0 |
| unresolved (`callee_id IS NULL`) | 9 718 — **54.4 %** | 713 090 — **59.5 %** |
| `MAY_TOP` | 1 290 — **7.2 %** | 230 072 — **19.2 %** |

Positive controls, per corpus: arch-index `Cohttp.%` 3, `Eio.%` 68, `Sqlite3.%` 256, `Unix.%` 33;
Tezos `Cohttp.%` 80, `Bigarray.%` 4. The zeros are measurements, not broken probes.

**The `MAY_TOP` factor of 2.7 is a property of the tool, not a footnote about measurement.** At
19.2 % almost nothing will ever reach `PASS`; at 7.2 % the question is live. The verdict a user
sees depends on which corpus they point it at, and the spec must say so rather than quoting a
single figure.

**Consequence — CORRECTED 2026-09-06 by measurement; the original claim was wrong twice.** This
brief said "no cone in either corpus is ⊤-free, so all seven binding-carrying advisories grade
`UNKNOWN` today **by measurement**". That was **not measured**, and it is wrong in two independent
ways. (a) `reach_verdict` returns `NO_TARGET` **before** any cone is walked
(`arch_rules.ml:590-591`), so a binding resolving to nothing never reaches the `UNKNOWN` branch.
(b) A corpus-wide unresolved rate does not imply a *particular* cone contains a ⊤ edge —
`escaping` is filtered over the closure of **that rule's own source set**, so ⊤ is **per-rule**,
not per-corpus. A rate was projected onto a population without measuring it.

Measured on proto_alpha (`crash-pa.db`, 468 modules / 14 452 functions, rebuilt 2026-09-06), 31
generated rules — 30 targets present in the index plus `fn:Cohttp.Path.resolve_local_file`, absent:

    0 proved · 1 violation · 3 possible · 26 unknown · 1 vacuous

The absent target yields **VACUOUS** — which is what all 49 real bindings do **today**. On targets
that resolve: **26/30 = 87 % `UNKNOWN`**, **4/30 usable** (1 `VIOLATION`, 3 `POSSIBLE`).

**So the blocker today is INGESTION, not the ⊤ frontier**: while bindings resolve to nothing,
resolving ⊤ edges converts nothing. The re-export / ⊤-frontier work is a dependency of this
feature's *eventual* usefulness, not of its current output — and the 87 % is a projection about a
population that does not exist yet, to be stated as such and never again as a measurement.

**The worked example, and the spec should be built around it rather than around proto_alpha.**
arch-index depends on cohttp and calls it six times (`Cohttp_eio.Client.post`,
`Cohttp.Header.of_list`, `Cohttp.Code.code_of_status`, `Cohttp.Response.status`,
`Cohttp_eio.Body.of_string`, `Cohttp_eio.Client.make`). The vulnerable binding is
`Cohttp.Path.resolve_local_file` — a **server**-side function; this repository is a **client**. A
scanner says "vulnerable dependency"; a naive reachability tool says "not called, PASS"; the
honest answer is `UNKNOWN`. Small, checkable by a reader in a minute, and it exhibits all three
verdict boundaries at once.

### Three findings that shape the design

**1. A third kind of absence, which needs its own verdict.** `path_to_module_name`
(`arch_index_cmt.ml:746-756`) renders a `Papply` prefix as the literal string `"<apply>"`.
Measured on both corpora, with the LIKE mechanism positive-controlled live first
(`functions.name LIKE '%.%'` → 205 513; `calls.callee_name LIKE '%.%'` → 1 011 209):

| probe | arch-index | Tezos |
|---|---|---|
| `callee_name LIKE '%<apply>%'` | 0 | 0 |
| `functions.name LIKE '%(%'` | 0 | 0 |

So `Cohttp_lwt.Make().resolve_local_file` has **no representable target under any spelling** — the
advisory writes `Make()`, the index would write `<apply>`, and neither occurs. `caml_ba_reshape`
is the same shape. This is neither a failed join nor a missing path but **a target the index has
no vocabulary for**, and folding it into `UNKNOWN` loses the distinction that says *nobody can
express this yet*.

**2. `affected_bindings` has no specification anywhere — an absence in the world, not in the
research.** OSV's schema declares `ecosystem_specific` explicitly out of scope: "the meaning of the
values within the object is entirely defined by the ecosystem and beyond the scope of this
document". opam advisories are hand-authored Markdown in `ocaml/security-advisories`, converted by
`hannesm/advisories`, where the field is **optional** (`~dec_absent:[]`) with **no doc comment**,
unlike neighbouring types in the same file that carry one. Nothing states exhaustiveness,
public-API scope, or how functor and C-stub names should be written. `Make()` is **one observed
precedent, not a rule**. A design keyed on this field is keyed on a convention that can change
without notice, and the record must be able to say so afterwards.

**3. The closed-domain question is two-sided.** `Path.t` (`Pident | Pdot | Papply | Pextra_ty`)
already carries the functor case, so on the **index** side closing the domain is *stop flattening*
— one principal site, `path_to_module_name` at `arch_index_cmt.ml:749-757`, before
`Head_qualified` is built — not *write a parser*. Note `module_target_path`
(`arch_index_cmt.ml:728-736`) already keeps `Path.t` unflattened, so both styles coexist in that
file. On the **advisory** side a parser is unavoidable and its failures must be `UNKNOWN`, never
silent misses. **Cost, stated rather than assumed:** the producer is the highest-blast-radius file
in the repository.

### A trap recorded so nobody reuses it

Two closure disciplines coexist and only one is ⊤-aware:

| closure | ⊤ handling | site |
|---|---|---|
| `Arch_graph.closure` + `g.tops` consulted for escaping nodes | ⊤-aware | `arch_graph.ml:129-146`, used by `arch_rules.ml:589-605` |
| `WITH RECURSIVE … WHERE c.kind IN ('MUST','MAY_ENUMERATED')` | **silently drops ⊤ edges** | `arch_effects_queries.ml:78, 114, 123` |

The second stops at every unresolved edge and reports what it found, with nothing in the result
recording that the walk was truncated. Correct for effects queries; here it would manufacture the
exact false negative this feature exists to prevent. **Nothing marks it as unsuitable at its call
site.**

### Prior art, and where this lands among it

| tool | its third state |
|---|---|
| Endor Labs | "Potentially Reachable Function: unable to determine whether a finding is reachable or unreachable" |
| Semgrep Supply Chain | "No Reachability Analysis"; plus "Conditionally Reachable" |
| Snyk | "No Path Found", explicitly disclaimed: "do not assume that the vulnerability is totally unreachable" |
| govulncheck | **none** — two-way, and it resolves failure *toward reachable* |
| osv-scanner | none (Go/Rust experimental only) |
| Dependabot | no reachability analysis at all |

govulncheck and the commercial tools are both coherent conservative designs that put uncertainty
in **opposite buckets**. This tool's position is a third one, already realised by `UNKNOWN` +
`top_reasons`.

## Quality Gates

```bash
# Environment — required; the default switch gives spurious eio/cohttp/mirage-crypto errors
eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)

# Build
dune build

# Tests — full suite
dune runtest --force

# Scoped run (mutation kills; the suite aborts on first failure, so a suite-wide
# run credits every kill to whichever test sits earliest)
dune build && ./_build/default/tezt/tests/main.exe --file <path>

# Lint/format — not documented as a project gate
```

**Ratchets that must be RE-DERIVED on the tree that exists, never carried:**
`tezt/tests/must_null_ceiling.ml` (`clean_measured`, currently 383 on `090f832`, measured by this
session on `4edfc3f` whose tree is main's) and the self-index golden
`test/fixtures/self-index-stats.txt`. Attribute by **row-set diff**, never by subtracting counts —
a count cannot distinguish an addition from an addition plus a removal, and this file's own
history records a phantom pair caught only by luck.

**Environment constraints:** never write into `/home/mathias/dev/arch-index` or
`/home/mathias/dev/tezos` (other sessions' checkouts, read-only). `osv-scanner` and `govulncheck`
live at `~/go/bin/` and are **not on PATH** — invoke by absolute path, edit no profile. Disk
`/mnt/ssd-external-2to` is at 95 %; if a measurement looks strange, check disk before believing
it. Branch is at `6930d3c`, one behind main `090f832` — rebase before implementation, not before,
so research is not measured against a moving base.

## Open Questions

- [ ] **"Fail loudly" on zero targets — verdict, exit code, or both?** The stated constraint is
      that a `forbid reach` rule with an empty source or target set must fail loudly. Today
      `NO_SOURCE`/`NO_TARGET` produce a verdict string mapped to SARIF level `VACUOUS`
      (`arch_rules.ml:1179-1184`). A verdict inside a report is not an exit code, and a reader
      scanning for `FAIL` will not see it. This is the **normal** case today — 49 of 49 bindings
      resolve to zero targets on both corpora — so whatever is chosen governs the default
      experience, not an edge case. Implementers must not assume the existing `VACUOUS` mapping
      is sufficient.
- [ ] **Does the third kind of absence get its own verdict value, or a property on an existing
      one?** A binding the index has no vocabulary for (`Papply`-produced, C stub) is
      distinguishable at ingest from a binding that simply matched nothing. The verdict vocabulary
      is currently a set of plain strings with no closed type
      (`result = { …; verdict : string; … }`), so adding a value is cheap and unchecked — which
      cuts both ways. Implementers must not silently merge this into `NO_TARGET`.
- [ ] **Is un-flattening `Path.t` in the producer in scope?** Closing the identity domain on the
      index side is one site, but that site is in the highest-blast-radius file in the repository,
      and the advisory side needs a parser regardless. This brief deliberately does not decide it;
      the spec phase should, with the cost above on the table.
- [ ] **Where does the ledger live — a new schema table, or a file artefact?** `producer_runs`
      already stores `producer/producer_version/invocation_digest/soundness_class` with a
      DB-enforced CHECK, and `schema/*.schema.json` + `finding-schema.js` are the file-artefact
      precedent with a fail-closed validator. A new producer-written table also requires a
      `current_schema_version` bump (`arch_index_db.ml:90`, currently `1.12`) **and** an entry in
      `schema_tables_to_drop` (`arch_index_support.ml:56`) — a table absent from that list is
      unsound on re-index, and a tezt test closes that class.
- [ ] **`NOT_COMPUTED` appears in the verdict vocabulary documented at `arch_rules.ml:10-33` but
      is not among the seven values `reach_verdict` returns.** Whether anything produces it was not
      established by research. Implementers must not assume it is dead.
