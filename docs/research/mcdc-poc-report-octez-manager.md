# decision-lint report — trilitech/octez-manager

**Date:** 2026-08-02. **Tool:** [`poc/decision-lint`](../../poc/decision-lint/)
(PoC for [`mcdc-coverage-feasibility.md`](mcdc-coverage-feasibility.md)).
**Target:** `trilitech/octez-manager` @ `main`, shallow clone, directories
`lib/ src/ test/`. **Command:** `./run.sh <repo>/lib <repo>/src <repo>/test`.

---

## Summary

**17 findings, all manually verified against the source, 0 false positives.**
12 from the enumeration tier (rungs 0–3), **5 more from the SMT tier (rung 4)**.
The run takes **0.82 s** without the solver and **10.7 s** with it, over 351
files / 128 k lines — both inside any CI budget.

| | |
|---|---|
| files parsed | 351 (0 parse failures) |
| boolean decisions | 3 728 |
| multi-condition decisions | 925 (24.8 %) |
| decisions above budget → `UNKNOWN` | 12 (0.3 %) |
| atoms / unstable atoms | 7 908 / 2 343 (29.6 % never merged) |
| **defect findings** | **17** (12 enumeration + 5 SMT) |
| complexity advisories (`HIGH_ARITY`) | 12 |
| wall clock | 0.82 s enumeration only / 10.7 s with SMT |
| SMT: decisions escalated | 2 166 of 3 728 (58 %) |
| SMT: queries / cache hits / `unknown` | 10 477 / 2 468 / **0** |

| kind | count | where |
|---|---|---|
| `CONSTANT_TRUE` | 6 | `test/` — vacuous assertions |
| `IDENTICAL_ARMS` | 4 | `src/ui/` — dead conditionals in production code |
| `DEAD_SUBTERM` | 2 | `src/ui/` + `test/` — duplicated conjuncts |
| `SMT_CONSTANT_TRUE` | 5 | `test/` — vacuous assertions **only the solver can see** |

Four distinct problems, worth reading separately.

---

## A. Six test assertions that assert nothing

This is the highest-value class the tool found, and it is invisible to every
coverage metric — these lines are *covered*, they *pass*, and they check
**nothing**. A test suite reporting green on them is reporting a lie.

### A1 — `test/test_version_checker.ml:55`

```ocaml
let result = Version_checker.compare_versions "v24.0" "24.0" in
(* Should normalize and compare *)
check bool "v24.0 vs 24.0" true (result = 0 || result <> 0)
```

`result = 0 || result <> 0` is a tautology. The comment says the function
*should normalize and compare*, and the test name asserts `"v24.0 vs 24.0"` — so
the intended assertion is almost certainly `result = 0`. As written the test
passes for **every possible implementation**, including one that returns garbage.

**Fix:** `check int "v24.0 vs 24.0" 0 result`.

### A2 — `test/test_version_checker.ml:112`

```ocaml
let result = Version_checker.compare_versions "24.0-rc1" "24.0" in
(* RC handling depends on implementation *)
check bool "handles rc" true (result <> 0 || result = 0)
```

The comment is an admission: the author did not know what the answer should be,
so the assertion was written to accept anything. **Fix:** decide the RC ordering
and assert it, or delete the test. A test that cannot fail is worse than no test
— it occupies a name in the suite that implies coverage.

### A3 — `test/test_version_checker.ml:120`

```ocaml
let result = Version_checker.compare_versions " 24.0 " "24.0" in
check bool "handles whitespace" true (result = 0 || result <> 0)
```

Named "handles whitespace", asserts nothing. **Fix:** `result = 0`.

### A4 — `test/test_version_checker.ml:95`

```ocaml
let enabled = Version_checker.is_check_enabled () in
check bool "has boolean value" true (enabled = true || enabled = false)
```

Asserts that a `bool` is a `bool` — guaranteed by the type checker.
**Fix:** delete, or assert the actual default.

### A5 — `test/test_cli_helpers.ml:138`

```ocaml
(* In test environment, stdin is usually not a TTY *)
let result = CH.is_interactive () in
check bool "is_interactive returns bool" true (result || not result)
```

The comment states the expected value — *not a TTY* — and the assertion then
declines to check it. **Fix:** `check bool "not a tty under test" false result`.

### A6 — `test/test_systemd_templates.ml:242`

```ocaml
check bool "has journald" true
  (contains_s combined "journal" || List.length lines = 0 || true)
```

The most instructive one. A real check is present — `contains_s combined
"journal"` — and then neutered by a trailing `|| true`. This is the signature of
a failing test made to pass without fixing the cause. Note the middle disjunct
`List.length lines = 0` is *also* dead, for the same reason.

**Fix:** delete `|| true`, run it, and deal with whatever it reveals.

### A6b — `test/test_zcash_params.ml:84` (`DEAD_SUBTERM`)

```ocaml
check bool
  (Printf.sprintf "path '%s' doesn't have double slash" path)
  false
  (String.contains path '/' && String.contains path '/'
   && Str.string_match (Str.regexp ".*//.*") path 0)
```

`String.contains path '/'` appears twice — rung 0 catches it. Logically harmless
(the duplicate is idempotent), but it means the predicate was assembled without
being read back, and the first conjunct is redundant with the regex anyway.

**Fix:** `Str.string_match (Str.regexp ".*//.*") path 0`.

---

## B. A logic bug in production code (`DEAD_SUBTERM`)

### B0 — `src/ui/signatory_scheduler.ml:73`

```ocaml
if String.contains trimmed '"' then
  (* Has labels - check for success/error *)
  if String.contains trimmed 's'
     && String.contains trimmed 'u'
     && String.contains trimmed 'c'
  then successful_requests := Some value
  else if String.contains trimmed 'e'
          && String.contains trimmed 'r'
          && String.contains trimmed 'r'
  then failed_requests := Some value
```

**The most valuable finding in the run, and the only one that changes runtime
behaviour.** The first branch spells `s`,`u`,`c` — "suc" for *success*. The
second branch was meant to mirror it with `e`,`r`,`r` — "err" for *error*. But
`String.contains` is idempotent: testing `'r'` twice is the same as testing it
once. The intended "contains a doubled r" check does not exist.

The effective predicate is `contains 'e' && contains 'r'`, which is strictly
weaker than intended and matches many labels that are not errors — anything
containing both an `e` and an `r`. Metrics can be attributed to
`failed_requests` that are not failures.

The duplicated conjunct is what the tool detects; the misclassification is what
it reveals. Note that character-membership testing is a fragile way to match
label substrings in the first place — the fix is probably to match the label
properly, not to repair the character list.

---

## B2. Five more vacuous assertions, visible only to the solver

The rung-4 payoff (§6.1 of the design doc): the two atoms are **syntactically
different**, so no canonicalisation rung merges them. Only an implication check
sees that `= None` and `<> None` are complementary.

### B2a — `test_snapshots.ml:48`, `:57`, `:231`, `test_version_checker.ml:99`

```ocaml
let result = Snapshots.slug_of_network "unknown-network-xyz" in
(* Unknown networks might return None or a default slug *)
check bool "handles unknown" true (result = None || result <> None)
```

A tautology, four times over — three of them in `test_snapshots.ml`, testing
`slug_of_network` against an unknown network, a URL, and special characters.
**None of the three checks anything.** The comment admits it: *"might return None
or a default slug"*.

The contrast is five lines below: `test_slug_empty_string` does the job properly
with `check_string_opt "empty string" None result`. The vacuous form and the
correct form sit in the same file.

**Fix:** decide the expected slug for each input and use `check_string_opt`, as
the neighbouring test already does.

### B2b — `test/test_common_extended.ml:283`

```ocaml
(* Should return non-empty strings (unless in weird environment) *)
check bool "returns values" true
  (String.length user >= 0 && String.length group >= 0)
```

**An off-by-one in the assertion itself.** The comment says *non-empty*; the code
tests `>= 0`, true of every string including `""`. The intended assertion is
`> 0`. Decidable only because the encoder knows a length is non-negative — a fact
about OCaml, asserted as such, not an assumption about the program.

**Fix:** `String.length user > 0 && String.length group > 0`.

---

## C. Four dead conditionals in production UI code

All four are `if c then E else E` — the condition is computed and then ignored.

### C1 — `src/ui/pages/responsive_tabs_widget.ml:19`

```ocaml
let make tabs = if tabs = [] then {tabs; selected = 0} else {tabs; selected = 0}
```

The archetype. An empty-list special case was written and never differentiated
from the general case. Equivalent to `let make tabs = {tabs; selected = 0}`.
Either the special case is unnecessary — delete it — or it was *meant* to do
something else and never did.

### C2 — `src/ui/pages/rpc_browser/rpc_browser.ml:233`

```ocaml
let left =
  (* OpenCode style: clean header with subtle focus indicator *)
  let header_text = if browser_focus then " Browser" else " Browser" in
```

**A functional bug, not just dead code.** The comment promises a *subtle focus
indicator*; the two strings are byte-identical, so the indicator does not exist.
The feature described in the comment is missing from the implementation.

### C3 — `src/ui/pages/diagnostics/diagnostics_page.ml:252`

```ocaml
( (if recorder_on then "●" else "○"), (if recorder_on then ok_fg else off_fg), "recorder" );
( (if is_root  then "●" else "●"), (if is_root  then err_fg else ok_fg), "root"/"user" );
```

The neighbouring row uses `"●"`/`"○"` for on/off. The `is_root` row uses `"●"` in
both branches — copy-paste from the row above with only the colour and label
updated. Colour and label *do* differentiate, so the display still works; the
glyph conditional is dead.

**Fix:** `"●"` unconditionally — or, if the glyph was meant to differ, decide
which it should be.

### C4 — `src/ui/pages/sandbox_page.ml:873`

```ocaml
| None ->
    if s.cursor = 0 then render_create_detail ~size
    else render_create_detail ~size
```

Both branches identical. Either `s.cursor` was meant to select a different
renderer, or the conditional is vestigial.

---

## What to fix first

1. **B0** (`signatory_scheduler.ml:73`) — the only finding that changes runtime
   behaviour: request metrics can be misattributed to `failed_requests`.
2. **A6** (`|| true`) — a real check was disabled; whatever it was hiding is
   still there.
3. **C2** — a documented UI behaviour (focus indicator) that does not exist.
4. **B2a** — three `slug_of_network` tests and one `get_current_version` test
   that cannot fail. `slug_of_network` is untested for unknown networks, URLs and
   special characters, despite three named tests claiming otherwise.
5. **A1–A3** — three version-comparison tests that cannot fail.
   `compare_versions` is effectively untested for normalisation, RC ordering and
   whitespace.
6. **B2b** — `>= 0` where the comment says non-empty; should be `> 0`.
7. **C1, C3, C4, A4, A5, A6b** — dead code and vacuous assertions; low risk,
   trivial to remove, and each is a small lie about what the code checks.

**13 of the 17 findings are in `test/`, and every one is a test that passes
unconditionally.** That is the sharpest available argument against coverage
percentage as a quality gate: all of these lines are *covered*.

---

## Reading the numbers

**The SMT tier escalated 2 166 of 3 728 decisions (58 %) and returned zero
`unknown`.** Every query was decided inside the deterministic `rlimit`, so no
verdict here depended on machine speed. Wall clock rises from 0.82 s to 10.7 s,
but user CPU is only 1.1 s — the difference is IPC round-trips, one per
`check-sat`. Batching per decision would remove most of it, and the
content-addressed cache already absorbed 2 468 of 12 945 lookups (19 %).

**29.6 % of atoms were classified unstable and never merged.** That is the PoC's
conservative purity allowlist declining to reason about anything containing a
non-allowlisted call. Every one of those is potential recall left on the table:
the real design uses `v_pure_functions` (`arch-query pure-fns`), which would
certify far more atoms as pure and merge them. **The 12 findings are a floor, not
a ceiling.**

**Only 12 decisions (0.3 %) exceeded the enumeration budget.** They are reported
as `HIGH_ARITY` advisories rather than silently dropped, and they are a
maintainability signal in their own right (§6.8 / R8 of the design doc). The two
worst are `src/ui/pages/wallets_page.ml:1499` and `test/unit_tests.ml:119`, both
with **17 atomic conditions in a single boolean** — no reviewer verifies that by
reading. Also notable: `src/node_env.ml:52` and
`src/rewards/payout_executor.ml:40` at 12 each.

**24.8 % of boolean decisions are multi-condition** — the measured figure that
should replace the design doc's grep-based estimate in §4.

---

## Verification status

Every one of the 17 findings was read back against the source before being
written up here; the excerpts above are verbatim. **No finding was dismissed as a
false positive**, and none required a judgement call about intent to classify as
a defect — in all 17, the code as written does something other than
what it appears to do.

**Not claimed:** that these are the only such defects in the repository. Purity
is an allowlist rather than an analysis (29.6 % of atoms refused a merge), path
conditions are syntactic rather than dominator-derived, and the encoder models
integers, equality and closed literals but not strings-as-strings, records, or
higher-order values. All cost recall, none cost soundness.
