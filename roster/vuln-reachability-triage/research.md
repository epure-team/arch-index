# Research — vuln-reachability-triage

_Generated: 2026-09-06_
_Mode: full (4 parallel specialists)_
_Online research: enabled_

Every specialist was required to run a **positive control** on any absence claim — a
demonstration that the probe returns non-zero on a known-present input. Controls are
reproduced per question. An uncontrolled zero measures the pattern, not the repository.

---

## Question 1: unresolved/⊤ edges — representation, and forward closure

**Finding:** `calls.kind TEXT` carries `MUST | MAY_ENUMERATED | MAY_TOP`, required of every
backend by `comment_db_meta('callgraph_contract','v1')`. Classification is
`Head_unknown → MAY_TOP`, `Head_enumerated → MAY_ENUMERATED`,
`Head_local`/`Head_qualified` unconditional+saturated `→ MUST`, conditional/partial
`→ MAY_ENUMERATED`. `Arch_db.kind_sql` treats a NULL kind as `MUST` on legacy indexes.

**TWO CLOSURE DISCIPLINES COEXIST, and they differ on the point this task turns on:**

| closure | ⊤ handling | site |
|---|---|---|
| `Arch_graph.closure` over `g.fwd` / `g.must_fwd`, then `g.tops` consulted for escaping nodes | **⊤-aware** | `lib/arch_tools/arch_graph.ml:129-146`, used by `arch_rules.ml:589-605` |
| SQL `WITH RECURSIVE … WHERE c.kind IN ('MUST','MAY_ENUMERATED')` | **silently drops ⊤ edges** | `bin/arch_query/arch_effects_queries.ml:78, 114, 123` |

The second stops at every unresolved edge and reports what it found, with nothing in the
result recording that the walk was truncated. Correct for effects queries; it is the exact
mechanism that would manufacture a false negative here.

**References:**
- `architecture-schema.sql:218-287` — `calls` table, edge-kind contract in comments
- `lib/arch_index/arch_index_cmt.mli:602-614` — `type call_head`; `top_reason` variants
  `Callback_param | Module_param | Dropped_node | Ambiguous_unit`
- `lib/arch_index/arch_index.ml:870-920`, `1410-1460` — classification and `top_reason` strings
- `lib/arch_tools/arch_graph.ml:129-146` — `closure seeds adj`, BFS, excludes the seeds
- `lib/arch_tools/arch_db.ml:47, 403, 412` — `kinded` detection and `kind_sql`

**Controls run:** `"CREATE TABLE calls"` → 1 vs `"nonexistent_table"` → 0;
`"Head_enumerated\|Head_unknown"` → 30+ vs `"Head_nonexistent"` → 0.

---

## Question 2: `forbid reach`, selectors, and the verdict type

**Finding: the verdict lattice already exists and already implements the ⊤ discipline.**
`reach_verdict` (`bin/arch_rules/arch_rules.ml:589-605`), read directly:

```
NO_SOURCE            src selector empty
NO_TARGET            dst selector empty
VIOLATION            MUST-closure ∩ dst ≠ ∅
POSSIBLE             (MUST∪MAY)-closure ∩ dst ≠ ∅
UNKNOWN              a node in (cone ∪ src) holds a ⊤ edge   (`escaping`)
UNKNOWN_NO_CONTRACT  index not ⊤-marked
PASS                 none of the above
```

Verdicts are **plain strings**, not an OCaml variant — `result = { …; verdict : string; … }`.
The vocabulary is enumerated only in a module doc comment, which adds `NOT_COMPUTED`.

Selectors are shared: `type kind = File | Fn | Module | Ext | Exported`, `type t = kind * string`,
parsed by `Arch_sel.parse ~allow tok` with a mandatory per-site allow-list —
`cone_source = [File; Fn; Module; Exported]` for a reach SOURCE, `with_ext` for its TARGET.

**References:**
- `lib/arch_tools/arch_sel.ml:22-23, 94-115, 187-211` — kinds, parse, `select`
- `bin/arch_rules/arch_rules.ml:237-249` — `type body = Reach of Arch_sel.t * Arch_sel.t | …`
- `bin/arch_rules/arch_rules.ml:449-452` — `forbid reach from <a> to <c>` parser clause
- `bin/arch_rules/arch_rules.ml:528-555` — `type result`
- `bin/arch_rules/arch_rules.ml:1179-1184` — verdict→SARIF level; `NO_SOURCE|NO_TARGET → VACUOUS`
- `bin/arch_rules/arch_rules.ml:46-58` — usage text already shows
  `forbid reach from exported:** to fn:Vuln.parse`

---

## Question 3: exposed/exported, and explicit entry symbols

**Finding:** `functions.exposed BOOLEAN DEFAULT 0` ("appears in .mli"), indexed by
`idx_functions_exposed`. Populated for OCaml by `collect_exposed : string list -> (string * string, bool) Hashtbl.t * …`
reading `.cmti` files, keyed `(module_name, name)`. Entry symbols today come from
`--roots exported` (keyword) or `--roots <selector>`; `Exported` filters `n.exported` before
the glob applies.

**References:** `architecture-schema.sql:82-170`; `lib/arch_index/arch_index_cmt.mli:171-200`;
`lib/arch_tools/arch_sel.ml:1-62, 94-220`; `bin/arch_coverage/arch_coverage.ml:21-92`.

**Controls run:** `"collect_exposed"` → found vs `"collect_nonexistent"` → 0;
`"exported:"` → 8+ vs `"nonexistent:"` → 0.

---

## Question 4: exact string form of qualified paths — and the functor case has NO representable target

**Finding:** `functions.name` is built once by `qualify ~prefix name = prefix ^ name`
(`arch_index_cmt.ml:152-155`). `calls.callee_name` holds the dotted external reference for an
unresolved call. Module aliasing is spliced by `build_module_alias_stamps`, which records
`Ident.unique_name id -> Path.name target` **only** when the target's root is `Ident.persistent`,
declining functor-parameter and unit-local aliases to avoid a false rewrite (ADR 003 / SA-1).

**`path_to_module_name` renders a `Papply` prefix as the literal string `"<apply>"`**
(`arch_index_cmt.ml:746-756`), falling back to `Path.name` when the whole path is rooted at an
application.

| probe | whole2.db | c88-r4.db |
|---|---|---|
| `calls.callee_name LIKE '%<apply>%'` | **0** | **0** |
| `functions.name LIKE '%(%'` | **0** | **0** |

**Controls:** `SELECT '<apply>foo' LIKE '%<apply>%'` → 1 (mechanism live);
`functions.name LIKE '%.%'` → 205 513; `calls.callee_name LIKE '%.%'` → 1 011 209.

So the zeros are measurements. **`Cohttp_lwt.Make().resolve_local_file` has no representable
target under any spelling** — the advisory writes `Make()`, the index would write `<apply>`, and
neither string occurs. Likewise no C-primitive naming form (`caml_*`, `%prim`) appears as a value
identifier in either corpus.

Observed forms: `Agnostic_accuser_config.default_daily_logs_path`;
position-encoded lambdas `commands.<fun:104:7>`, `commands.<fun:51:7>.<fun:54:23>`;
external references `Tezos_base.TzPervasives.Lwt_result_syntax.let*` (25 277),
`Stdlib.Format.fprintf` (9 090), `Stdlib.+` (3 423).

---

## Question 5: is a qualified path a parsed STRUCTURE anywhere? — the load-bearing question

**Finding: yes, upstream, and it is destroyed at one named site.**

`Path.t` from compiler-libs (`Pident | Pdot | Papply | Pextra_ty`) is a genuine parsed structure,
live in the producer. **`Papply` is precisely the functor-application case** — on the index side
it is already representable, not a string oddity.

It is flattened by **`path_to_module_name : Path.t -> string option * string`**
(`arch_index_cmt.ml:749-757`) *before* `Head_qualified` is built, so
`Head_qualified of string option * string` (`arch_index_cmt.ml:605`) is already a pair of
strings. Note `module_target_path : module_expr -> Path.t option` (`arch_index_cmt.ml:728-736`)
keeps `Path.t` **unflattened** — both styles already coexist in the same file.

Past `arch_index.ml:1439-1441` the pair collapses to `m ^ "." ^ n`. Everything downstream is
flat: `(string * string)` hashtable keys, `calls.callee_name TEXT`,
`Arch_graph.node.name : string` compared with `=` (`arch_graph.ml:255`), SQL `LIKE`/`=`,
and `String.split_on_char '.'` / `String.concat "."` re-flattening in `unit_readings` /
`facade_readings` (`arch_index.ml:920-1002, 1037-1049`). The only project type whose name
contains "qualified" is `violator_entry.qualified_name : string`
(`arch_index_comment_parser.ml:16`) — flat.

**Control:** the same grep style that found no project-defined structure *did* find
`Path.Pident`/`Pdot`/`Papply`/`Pextra_ty`. The zero is a measurement.

**Two-sided consequence:** on the **index** side, closing the domain is "stop flattening", with
one primary site — a much smaller claim than it appeared. On the **advisory** side the binding
arrives from OSV as a string and nothing upstream carries structure for it, so a parser is
required there regardless, and its failures must be `UNKNOWN` rather than silent misses.

---

## Question 6: existing durable records

**Finding:** three JSON-Schema-validated structures plus a DB provenance table.

| record | required fields | file |
|---|---|---|
| QA state | `status` (GO/NO-GO), `round`, `cycle`, `rounds_audit[]` | `schema/qa-state.schema.json` |
| review finding | `severity`, `confidence`, `path`, `line`, `category`, `summary`, `evidence`, `fix`, `fingerprint`, `specialist`; optional `status` (OPEN/RESOLVED/ACCEPTED), `first_seen_round`, `resolved_round`, `check_encodable`, `red_verified` | `schema/review-finding.schema.json` |
| review trace | `schema_version`, `ts`, `task`, `round`, `cycle`, `event`, `actor`, `outcome` | `schema/review-trace.schema.json` |

Validated by a hand-rolled zero-dep validator supporting only `type`/`enum`/`required`/
`properties`/`additionalProperties`/`items`, **failing closed on unsupported keywords**
(`scripts/lib/review/finding-schema.js:1-50`).

**`producer_runs`** already stores tool provenance per run —
`producer, producer_version, invocation_digest, soundness_class CHECK(… IN ('sound_with_top','heuristic','asserted')), created_at`
(`architecture-schema.sql:32-60`). `comment_db_meta` is the flat-schema equivalent
(`:289-293`).

---

## Question 7: SARIF, coverage, and where `heuristic` is assigned

**Finding:** `lib/arch_tools/arch_sarif.ml` has `type level = Error | Warning | Note` **and a
separate `soundness_class : string option`** carrying the ADR-002 vocabulary, precisely because
`level` alone collapses `UNKNOWN`/`UNKNOWN_NO_CONTRACT` onto one severity; `properties.verdict`
mirrors the real verdict string.

**ADR-002 is normative and already states the governing rule:** *"a heuristic fact may raise a
finding but may never discharge a ⊤ anchor and may never license a PASS."* SARIF-in is ingested
as `heuristic`; SCIP-in as `MAY_ENUMERATED`, never `MUST`.

`arch_coverage.ml:298-330` reports API-reachable functions with no coverage data as
**"not instrumented, NOT unreachable"**, and separately counts functions the coverage tool
observed running that the graph can only reach through an unresolved/⊤ edge.

**References:** `lib/arch_tools/arch_sarif.ml:22, 29-31, 55-65`;
`docs/adr/002-external-tool-integration.md:28-38, 48-54`; `bin/arch_coverage/arch_coverage.ml:298-330`.

---

## Question 8: zero rows, and the refusal taxonomy

**Finding:** fifteen guards execute in order, all before any header is printed
(`bin/arch_query/arch_query.ml:459-770`): contract flag → `modules`/`functions` tables →
`exn_origins` table → `exn_origins.channel` column → duplicate-flag → `--forms` whitelist →
empty `--forms` → `--channel` resolution (distinguishing **"nothing recorded"** from
**"nothing found"**) → `--roots` required → `functions.exposed` present → empty function name →
`n_roots = 0 && exported_roots` → `n_roots = 0` generic → ambiguity refusals (candidates
printed, then refused — **never unioned**).

The generic backstop is `missing_schema_ref` + `ok` (`lib/arch_tools/arch_db.ml:149-201`):
pattern-matches the driver's `"no such column: "` / `"no such table: "` text, strips a trailing
period and any table-alias qualifier, and raises **`Refused`** (named, documented) rather than
**`Broken`** (undifferentiated crash). Other SQL errors stay `Broken`.

Exit-code conventions differ per binary and are documented at `arch_db.ml:110-134`:
`arch-query`/`arch-report` map `Refused` to exit 3; `arch-impact`, `arch-rules`,
`arch-coverage`, `arch-mutants` use exit 2 for the same refusal.

---

## Question 9 [ecosystem]: where opam advisories come from, and the schema of the symbol field

**Finding: `ecosystem_specific.affected_bindings` is NOT specified in the normative OSV schema,
and has no written semantics anywhere in its production chain.**

The OSV schema says of `affected[].ecosystem_specific`: *"The meaning of the values within the
object is entirely defined by the ecosystem and beyond the scope of this document."* The
ecosystems table's opam row is one line naming the package manager and nothing else.

Chain of production: advisories are hand-authored Markdown with an opam-file-format header in
`ocaml/security-advisories`; a CI workflow converts them to OSV JSON via `hannesm/advisories`,
publishing to a `generated-osv` branch. In that tool `affected_bindings : string list` is
declared **optional** (`~dec_absent:[]`) with **no doc comment**, unlike neighbouring enum types
in the same file which do carry explanatory comments.

**Nothing states whether the list is exhaustive, whether it names public API only, or how
functor-produced and C-stub names should be written.** The `Make()` convention is a single
observed instance — precedent, not documented rule.

Other ecosystems each invented their own field: Go's `ecosystem_specific.imports[].{path,symbols,goos,goarch}`,
Rust's `ecosystem_specific.functions`. There is **no normative cross-ecosystem symbol field**.

**References:** ossf/osv-schema `docs/schema.md`; ossf/osv-schema PR #473 (adds the opam row, no
field-level spec discussed); github.com/ocaml/security-advisories (README + `advisories/2026/OSEC-2026-16.md`
+ `.github/workflows/generate-osv.yml`); github.com/hannesm/advisories `bin/advisories.ml`;
go.dev/security/vuln/database. Live query 2026-09-06 confirms the field.

**Lower confidence, flagged by the researcher:** the RUSTSEC `functions` convention came from a
search snippet, not a direct fetch.

---

## Question 10 [ecosystem]: how other tools report incompleteness — the split, and a mirror-image divergence

**Tools with a status distinct from "unreachable":**

| tool | the third state, verbatim |
|---|---|
| **Endor Labs** | *"Potentially Reachable Function: Endor Labs is unable to determine whether a finding is reachable or unreachable, typically because call graph analysis is unsupported…"* — three-way at both function and dependency level |
| **Semgrep Supply Chain** | *"No Reachability Analysis"* — used when a rule is missing and, categorically, for every non-GA language. Plus *"Conditionally Reachable"* as a third state on the positive side |
| **Snyk** | *"if a no path found status is given, do not assume that the vulnerability is totally unreachable… Snyk doesn't have enough information to decide"*; a separate *"Not Applicable"* where analysis is unsupported |

**Tools that collapse, or never attempt it:** **govulncheck** — two-way, vulnerabilities without
call stacks go under `=== Informational ===`; **osv-scanner** — reachability only via
`--experimental-call-analysis` (Go/Rust), inheriting govulncheck's split, absent entirely
elsewhere; **Dependabot** — *"does not perform reachability analysis"*, the dimension is absent
from the data model.

**The genuine design divergence, flagged rather than smoothed:** govulncheck resolves analysis
failure **toward "reachable"** — *"if the compiler cannot prove a function is unreachable,
govulncheck assumes it is reachable and reports it"* — the mirror image of Endor/Semgrep, which
resolve it toward an explicit unknown. Both are internally consistent conservative designs that
put uncertainty in opposite buckets. **A third position — uncertainty as its own reported state
with the blocking edges named — is what `UNKNOWN` + `top_reasons` already is here.**

**And the failure this task exists to avoid, documented in a shipped tool:** govulncheck's
soundness caveats are real and are *not surfaced as an output status* — *"Calls to functions made
using package reflect are not visible to static analysis. Vulnerable code reachable only through
those calls will not be reported."* A documented false-negative source, silent in the report.

**Academic:** Ponta/Plate/Sabetta, *Beyond Metadata* (ICSME 2018, arXiv:1806.05893, Eclipse
Steady) — static ∪ dynamically-observed reachability, no explicit unknown tier.
arXiv:2511.20313 reports a 92.0 % false-positive rate from flagging unreachable code and 61.9 %
prunable by call-graph analysis — **abstract only, full taxonomy not confirmed in this session.**

**Contradictions:** none factual. The govulncheck-vs-Endor divergence above is a design
difference, not a source disagreement.

---

## Patterns found

| Pattern | File | Lines | Notes |
|---|---|---|---|
| ⊤-aware verdict lattice | `bin/arch_rules/arch_rules.ml` | 589–605 | `escaping` checked before `PASS` |
| ⊤-dropping SQL closure | `bin/arch_query/arch_effects_queries.ml` | 78, 114, 123 | correct there, wrong here |
| per-site selector allow-list | `lib/arch_tools/arch_sel.ml` | 94–115 | refusal names the granted positions |
| layered refusal before any header | `bin/arch_query/arch_query.ml` | 459–770 | 15 guards, ordered |
| schema-drift → named refusal | `lib/arch_tools/arch_db.ml` | 149–201 | `Refused` vs `Broken` |
| DB-enforced provenance enum | `architecture-schema.sql` | 32–60 | `producer_runs.soundness_class` |
| fail-closed schema validator | `scripts/lib/review/finding-schema.js` | 1–50 | unsupported keyword ⇒ reject |
| "not instrumented, NOT unreachable" | `bin/arch_coverage/arch_coverage.ml` | 298–330 | the existing precedent for this task's distinction |

## External prior art

| Tool / Paper | Source | Key finding |
|---|---|---|
| Endor Labs | docs.endorlabs.com/scan/sca/reachability-analysis | three-way lattice, explicit "Potentially Reachable" |
| Semgrep Supply Chain | docs.semgrep.dev/semgrep-supply-chain/overview | "No Reachability Analysis" as its own status |
| Snyk | support.snyk.io article + docs.snyk.io | "No Path Found" explicitly disclaimed as ≠ unreachable |
| govulncheck | go.dev/doc/tutorial/govulncheck, pkg.go.dev/…/govulncheck | two-way; resolves uncertainty toward *reachable*; `reflect` false negatives silent |
| osv-scanner | google.github.io/osv-scanner | reachability Go/Rust-only, experimental; absent elsewhere |
| Dependabot | docs.github.com | no reachability analysis at all |
| OSV schema | ossf/osv-schema `docs/schema.md` | `ecosystem_specific` explicitly out of normative scope |
| ocaml/security-advisories + hannesm/advisories | github.com | `affected_bindings` hand-authored, optional, undocumented semantics |
| Ponta/Plate/Sabetta | arXiv:1806.05893 | static ∪ dynamic; no explicit unknown tier |

## Coverage gaps

- **Q9** — no source states whether `affected_bindings` is exhaustive, public-API-only, or how
  C-stub/functor names should be written. This is an absence in the world, not in the research:
  the field has no spec to find.
- **Q9** — the RUSTSEC `ecosystem_specific.functions` convention is from a search snippet, not a
  direct fetch. Lower confidence than the OCaml and Go material.
- **Q10** — Snyk's canonical reachability doc page 404'd during the session; its statuses are
  sourced from a support article and search-summarised doc text.
- **Q10** — arXiv:2511.20313 read at abstract level only; the 92.0 % / 61.9 % figures are quoted
  from the abstract, and its survey of tool statuses was not confirmed.
- **Q2** — the verdict vocabulary is enumerated only in a module doc comment
  (`arch_rules.ml:10-33`), which lists `NOT_COMPUTED` in addition to the seven `reach_verdict`
  returns. Whether `NOT_COMPUTED` is produced anywhere was not established.
