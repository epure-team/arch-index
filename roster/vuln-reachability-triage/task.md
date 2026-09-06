# Task — vuln-reachability-triage

Roadmap 3.1 — vulnerability triage by SOUND reachability.

Worktree `/mnt/ssd-external-2to/arch-index-wt-vuln`, branch `feat/vuln-reachability-triage`
(created on `6930d3c`; main is now `090f832` — rebase before implementation). Mode: **full**,
confirmed by the human against the Tier A `--critical` suggestion — he chose `--full`.

**THE PRODUCT IN ONE LINE:** a scanner says "not called" and discharges a vulnerability
finding; this tool says `UNKNOWN` and names the unresolved edges standing between it and a
proof. 3.1 is worth building not because it will say `PASS` but because it will refuse to.

## Settled, measured input — do not re-derive; DO carry the supersession

**A prior conclusion of mine was wrong and the artefacts must say so.** On 2026-09-05 I
measured osv-scanner 1.9.2's SARIF and concluded "symbol-level data is Go-only; the
function-level grade has no input here; build one ingest path, SARIF." FALSE, overturned
2026-09-06. I searched for the **Go-shaped key** (`ecosystem_specific.imports[].symbols`)
across npm/PyPI/Go; a peer added crates.io and the agreement read as breadth. It was one
question asked four times. Nobody queried **opam** — this repository's own ecosystem.
(`"OCaml"`/`"Opam"` return `{"code":3,"message":"invalid ecosystem"}`; only `"opam"` works —
a wrong spelling and a missing capability return the same result.) A spec that reads as
though the answer was always obvious teaches nobody to run a census instead of a sample.

**Census, complete** (`osv-vulnerabilities.storage.googleapis.com/opam/all.zip`), 26 opam
advisories: `imports[].symbols` **0/26**; `affected_bindings` **7/26, 49 bindings**. The
bindings are fully-qualified OCaml value paths. **Growing, not legacy:** 2016–2025 = 9
advisories, 0 with bindings; 2026 = 17 advisories, 7 with bindings, all 49.

**osv-scanner 1.9.2 cannot scan opam:** `strings | grep -cF opam` = 0 against working
controls (crates.io 1, Packagist 21, PyPI 45, Cargo.lock 1). Ingest is the OSV API/archive
by package name; **SARIF-vs-JSON is moot** — the scanner is not in the path.

**Resolvability, two corpora, reported broken down and never merged:**

| | arch-index self | Tezos `src` |
|---|---|---|
| modules / functions / calls | 105 / 3 198 / 17 862 | 8 615 / 304 323 / 1 198 104 |
| 49 bindings as nodes | 0 | 0 |
| 49 bindings as call targets | 0 | 0 |
| unresolved | 9 718 — 54.4 % | 713 090 — 59.5 % |
| `MAY_TOP` | 1 290 — **7.2 %** | 230 072 — **19.2 %** |

Positive controls: arch-index `Cohttp.%` 3, `Eio.%` 68, `Sqlite3.%` 256, `Unix.%` 33;
Tezos `Cohttp.%` 80, `Bigarray.%` 4. **A zero and a broken probe are the same output** —
every presence/absence claim in this task needs a control. (My own `grep -x` probe returned
0 for *every* ecosystem including supported ones, and I nearly reported it.)

**The `MAY_TOP` factor of 2.7 is a property of the tool, not a footnote about measurement:**
at 19.2 % almost nothing reaches `PASS`; at 7.2 % the question is live. The verdict a user
sees depends on which corpus they point it at, and the spec must say so.

**THE WORKED EXAMPLE — build the spec around this, not around proto_alpha.** arch-index
depends on cohttp and calls it six times (`Cohttp_eio.Client.post`, `Cohttp.Header.of_list`,
`Cohttp.Code.code_of_status`, `Cohttp.Response.status`, `Cohttp_eio.Body.of_string`,
`Cohttp_eio.Client.make`). The vulnerable binding is `Cohttp.Path.resolve_local_file` — a
**server**-side function; this repo is a **client**. A scanner says "vulnerable dependency";
a naive reachability tool says "not called, PASS"; the honest answer is **UNKNOWN**, because
54.4 % of this repo's calls are unresolved and no cone here is ⊤-free. Small, checkable by a
reader in a minute, and it exhibits all three verdict boundaries at once.

**CORRECTED 2026-09-06, by measurement, after the artefacts below were written.** The claim
"all 7 binding-carrying advisories grade `UNKNOWN` today by measurement" was **not measured, and
is wrong twice**. `reach_verdict` returns `NO_TARGET` **before** any cone is walked
(`arch_rules.ml:590-591`), so a binding that resolves to nothing never reaches the `UNKNOWN`
branch. And a corpus-wide unresolved rate does not imply that any *particular* cone contains a ⊤
edge — `escaping` is filtered over the closure of **that rule's own source set**, so ⊤ is
**per-rule**, not per-corpus.

Measured on proto_alpha (`crash-pa.db`, 468 modules / 14 452 functions, index rebuilt
2026-09-06), 31 generated rules — 30 targets that exist in the index, plus
`fn:Cohttp.Path.resolve_local_file` which does not:

    0 proved · 1 violation · 3 possible · 26 unknown · 1 vacuous

- The absent target → **VACUOUS** (`NO_TARGET`). This is what all 49 real bindings do **today**.
- On targets that DO resolve: **26/30 = 87 % `UNKNOWN`**, and **4/30 give a usable answer**
  (1 `VIOLATION`, 3 `POSSIBLE`).

**What this changes.** Today's blocker is **ingestion**, not the ⊤ frontier: while bindings
resolve to nothing, resolving ⊤ edges converts nothing. The 87 % figure describes what this
feature would return *once ingestion works*, and it is a projection about a different population
— stated as such, never again as a measurement of current output.

**Consequence:** no cone in either corpus is ⊤-free, so all 7 binding-carrying advisories
grade `UNKNOWN` today **by measurement**. This makes the re-export / ⊤-frontier work a
**measured dependency** of 3.1, not an adjacent roadmap item.

## Join / identity hazards in the 49

1. A **functor application inside a path**: `Cohttp_lwt.Make().resolve_local_file`. A pattern
   built from the plain dotted form misses it and returns a clean-looking zero.
2. The advisory data **contradicts itself on case**: both `P256.Dsa.pub_of_octets` and
   `P256.DSA.pub_of_octets`. An **identity** question, not a matching one — and it must not
   be resolved by picking one.
3. A **C stub shares the list with OCaml paths**: `caml_ba_reshape` beside `Bigarray.reshape`.
   Two namespaces, one field, no discriminator.

## Four constraints from the roadmap owner, given

1. **Entry points:** `functions.exposed = 1` in main-shaped modules plus an explicit
   `--entry` list. Without either the verdict is `UNKNOWN (no entry set)`, **never an empty
   PASS**. Machinery just shipped: PR #87 pinned MAIN/FLAT `exposed`-vs-`exported`
   normalisation; PR #88 gave `--roots exported` its shadowing rules and refusals.
2. **`PASS` requires the ⊤ frontier empty on the cone.** A cone with unresolved edges is
   `UNKNOWN`. This distinction is the whole product.
3. **osv-scanner's own "unexecuted" claim is a `heuristic` hint under ADR 002 and discharges
   nothing.**
4. **Zero targets is absence of a join, never absence of a path.** A `forbid reach` rule with
   an empty source set MUST fail loudly. Today that is the **normal** case, 49 of 49. And a
   binding may name code the graph has no node for **by construction** (`Bigarray` ships with
   the compiler; `caml_ba_reshape` is a C stub) — a different absence from a failed
   resolution, identical output, different verdict.

## Ledger-design constraints, gathered from three sessions

- **Identity is never a coordinate**, and a **string is an OPEN domain** so no matcher closes
  it. The live question is not "how careful can a string matcher be" but **can the binding be
  parsed into a structure at ingest, once, so the rest of the system works over a closed
  domain?** If yes the limit dissolves; if no it is real and must be labelled. Much cheaper at
  ingest than anywhere downstream, so it must be settled before the vocabulary is fixed.
- **Field, not pass:** status, provenance, corpus, tool version, and whether the rule's source
  set was non-empty must be required at **write** time. A pass runs over whatever exists when
  it runs; everything filed afterwards is invisible to it.
- **Match on structure, never on prose:** a report discussing a CVE must not thereby discharge
  it; a gate whose evidence is text is satisfiable by writing.
- **A status is a statement about an index at a commit.** Store the commit each verdict was
  derived at; an inherited `UNKNOWN` is not a current one.
- **Three states, not two:** "could not determine" must never fold into the negative answer —
  a failed resolution, an unreadable index, an erroring scanner are each `UNKNOWN`, never
  `PASS`.
- **A nearly-right count is the most plausible wrong answer:** suspect the instrument before
  the population, and read only from an artefact whose writer has exited.
- **Superseded-and-unrecoverable** is a third status beside right and wrong, for verdicts
  derived under a corpus or tool version that no longer exists.
- **Sampling with a declared selection** beats "we could not check" where exhaustive
  verification is unaffordable.

Acknowledged limit, not a solution: **an explicit field makes a claim deliberate, not
truthful.** It removes the paragraph that happened to contain a package name; it cannot
remove an agent that writes the field for work it did not do.

## Environment

Build: `eval $(opam env --switch=/home/mathias/dev/arch-index --set-switch)`. Tests:
`dune runtest --force`; never `dune exec tezt/tests/main.exe` (scoped runs are a full
`dune build` then `./_build/default/tezt/tests/main.exe --file <path>`). **Never write into
`/home/mathias/dev/arch-index` or `/home/mathias/dev/tezos`** — other sessions' checkouts,
read-only. `osv-scanner` and `govulncheck` are at `~/go/bin/`, **not on PATH**: invoke by
absolute path, edit no profile. Read-only reference DBs in scratchpad: `whole2.db` (Tezos
src), `c88-r4.db` (arch-index self). Full write-up: `scratchpad/osv-s0/S0-REVISED.md`.
Disk `/mnt/ssd-external-2to` is at 95 % — if a measurement looks strange, check disk before
believing it.

**I do not merge** — a permanent instruction from Mathias. PRs stay ready for his decision.
