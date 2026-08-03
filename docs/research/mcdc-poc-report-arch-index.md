# decision-lint report — epure-team/arch-index (self-scan)

**Date:** 2026-08-02. **Tool:** [`poc/decision-lint`](../../poc/decision-lint/)
(PoC for [`mcdc-coverage-feasibility.md`](mcdc-coverage-feasibility.md)).
**Target:** this repository, directories `lib/ bin/ test/`.
**Command:** `./run.sh <repo>/lib <repo>/bin <repo>/test`.

---

## Summary

**Zero defect findings, from either tier. Three complexity advisories.** The run
takes **0.12 s** without the solver, **0.90 s** with it, over 41 files.

| | |
|---|---|
| files parsed | 41 (0 parse failures) |
| boolean decisions | 385 |
| multi-condition decisions | 147 (38.2 %) |
| decisions above budget → `HIGH_ARITY` | 3 (0.8 %) |
| atoms / unstable atoms | 948 / 499 (52.6 % never merged) |
| **defect findings** | **0** (enumeration and SMT alike) |
| wall clock | 0.12 s enumeration only / 0.90 s with SMT |
| SMT: decisions escalated | 245 of 385 (64 %) |
| SMT: queries / cache hits / `unknown` | 1 433 / 199 / **57** |

A clean result is only worth reading if the instrument is known to work. It is:
the tool detects **22/22** planted defects in
[`test/fixture.ml`](../../poc/decision-lint/test/fixture.ml) with **12/12** true
negatives, and found **17 verified defects** in a comparable OCaml codebase — see
the [octez-manager report](mcdc-poc-report-octez-manager.md). The same binary,
the same run, on this repository finds nothing.

That is a meaningful negative. It is not, however, a claim of correctness: see
*What this does not say* below.

---

## Complexity advisories (`HIGH_ARITY`)

These are not defects. They are decisions whose atom count exceeds the
enumeration budget (`cap_vars = 6`), so **no redundancy verdict was computed for
them** — they are reported rather than silently skipped, per the
degradation-must-be-visible rule (§9 of the design doc), and arity is itself a
maintainability signal (R8).

### 1. `lib/arch_index/arch_index_git.ml:46` — 11 conditions

```ocaml
starts_with line "let " || starts_with line "and " || starts_with line "type "
|| starts_with line "module " || starts_with line "open " || …
```

A flat prefix-alternation. Logically fine and easy to read, but 11 conditions
means the tool cannot certify that none of them is subsumed by another (`"let "`
vs `"let rec "`-style overlaps are exactly the class it would check).

**Suggested change** — not a defect fix, a checkability improvement: replace the
chain with a list membership test.

```ocaml
let toplevel_prefixes = ["let "; "and "; "type "; "module "; "open "; …]
… List.exists (fun p -> starts_with line p) toplevel_prefixes
```

This makes the set explicit and reviewable as data, removes the arity problem,
and makes an accidental duplicate visible at a glance.

### 2. `lib/arch_index/arch_index_line_counter.ml:83` — 7 conditions

```ocaml
(c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c = '_'
```

An identifier-character predicate. Correct and idiomatic; flagged only because
its arity exceeds the budget. Extracting it as a named
`is_ident_char` would both document it and drop the enclosing decision under the
budget. Note the PoC's rung 3 handles integer comparisons but not `char`
comparisons — a real implementation should extend interval semantics to `char`,
at which point this decision becomes decidable rather than `UNKNOWN`.

### 3. `lib/arch_index/comment_parser.ml:112` — 7 conditions

```ocaml
pc.summary = None && pc.pre = Absent && pc.post = Absent && pc.violators = Absent
&& pc.violates = Absent && pc.tests = Absent && …
```

An "is this record entirely empty" test spelled field by field. It is the shape
most likely to acquire a silent bug when a field is added to the record and the
predicate is not updated — the compiler will not warn, because the predicate
still typechecks. Worth a comment tying it to the record definition, or a
derived emptiness function that a new field would force someone to touch.

---

## What the numbers say

**38.2 % of boolean decisions here are multi-condition** (147 of 385) — the
measured figure to replace §4's grep-based estimate. octez-manager measures
24.8 %. Both are well above the ~19 % the grep census suggested, which
undercounted multi-line conditions. **§4 of the design doc should be corrected.**
The conclusion it drew, however, stands: multi-condition booleans are a minority
of decision *sites* once `match` arms are counted, and the OCaml-specific value
still concentrates in arm/exhaustiveness checking.

**52.6 % of atoms were classified unstable and never merged** — the highest rate
of the two corpora (octez-manager: 29.6 %). arch-index's conditions are
call-heavy (`Filename.check_suffix`, `Hashtbl.mem`, `Sys.file_exists`, local
predicates), and the PoC's purity allowlist declines almost all of them. This is
deliberate — an unstable atom can never merge, so it can never produce a false
positive — but it means **recall here is materially lower than on octez-manager**,
and a clean result is correspondingly weaker evidence. The production design
resolves this with `v_pure_functions` / `arch-query pure-fns`, which would
certify most of those local predicates as pure and put them back in scope.

---

## What this does not say

- **Not "arch-index has no dead logic".** It says no dead logic of the kinds this
  PoC detects, at the recall its conservative purity predicate allows. With
  52.6 % of atoms excluded from merging and 57 decisions returning `unknown` from
  the solver, the honest reading is *"nothing found in the half of the conditions
  the tool could reason about"*.
- **The SMT tier ran and found nothing**, but returned `unknown` on 57 decisions
  (rlimit exhaustion) — those carry no verdict at all. Cross-call coupling
  remains invisible regardless: the analysis is intraprocedural.
- **Path conditions are syntactic**, not dominator-derived, so facts requiring a
  join are missed.
- **`match` arms are only checked for guard subsumption**, not for pattern
  redundancy — that is the compiler's warning 11, which is a separate
  recommendation (R1) and is already enforced here: `dune build` in the dev
  profile promotes it to an error, as this PoC's own build confirmed when unused
  fields failed the build.

---

## Cross-corpus comparison

| | arch-index | octez-manager |
|---|---|---|
| files | 41 | 351 |
| boolean decisions | 385 | 3 728 |
| multi-condition | 38.2 % | 24.8 % |
| unstable atoms | 52.6 % | 29.6 % |
| defect findings (enumeration) | **0** | **12** |
| defect findings (SMT) | **0** | **5** |
| `HIGH_ARITY` advisories | 3 | 12 |
| SMT decisions escalated | 245 (64 %) | 2 166 (58 %) |
| SMT `unknown` | **57** | 0 |
| wall clock, enumeration only | 0.12 s | 0.82 s |
| wall clock, with SMT | 0.90 s | 10.7 s |
| defects per 1 000 decisions | 0.0 | 4.6 |

The runtime figures settle the CI question raised in §6.5 of the design doc.
Enumeration alone: **0.82 s for 128 k lines**, single-threaded, no cache, no
solver — the caching and budgeting machinery designed for the SMT tier is not
needed for it at all. With SMT: **10.7 s**, of which only 1.1 s is user CPU; the
rest is one IPC round-trip per `check-sat`. Batching per decision is the obvious
optimisation and was not needed to stay inside budget.

**The 57 `unknown` results on this repository are the one place the two corpora
diverge sharply** (octez-manager: zero). They are decisions where z3 exhausted
the deterministic `rlimit`. Because `rlimit` is a resource counter and not a
wall-clock timeout, that outcome is reproducible on any machine — which is the
point of §6.4 — but it does mean 57 decisions here carry no verdict from either
tier. They are counted and reported, never silently dropped.
