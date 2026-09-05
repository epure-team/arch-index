# Changelog

## [Unreleased]

### Fixed
- **A newer binary reading an older index refuses instead of crashing, and the refusal names what
  is missing.** The class is *any* column or table a tool's query names that the index in front of
  it does not have — not, as this work was first scoped, "the `channel` column that arrived at
  schema 1.8". `channel` is where the class was found and five guarded sites is the right count
  *for that column*; it is not the count for the class, and the class is not confined to 1.8. The
  first unguarded column the backstop below actually catches is `functions.exposed`, read by
  `Arch_graph.load` and far older than the error-channels work.

  `Arch_db.ok` converts the driver's `no such column: …` / `no such table: …`
  into `Arch_db.Refused` rather than `Arch_db.Broken`, extracting the name and reporting "this
  index predates column *X*" — a backstop for every query site that has no `has_col` guard of its
  own, not a replacement for the two scoped guards (`raises`, `escaping-origins`) that give a
  better-worded refusal. A qualified reference keeps its alias in parentheses
  (`column channel (written s.channel in the failing query)`): both `exn_scopes` and `exn_origins`
  carry `channel`, so the bare name alone does not say which of a query's tables was the old one.

  **The conversion improves the MESSAGE everywhere; it does not make every binary exit 3.** Exit 3
  is a contract each tool signs separately and only `arch-query` and `arch-report` have signed it.
  `arch-impact` keeps exit 2 because `docs/change-impact.md` pins its exit 3 to the
  `--fail-on-new-findings` refusal and keeps it in lockstep with the JSON `verdict` field, on the
  stated ground that exit 2 is the code that prints no stdout to parse; `arch-rules` keeps exit 2
  because `docs/fitness-functions.md` states it has no process-level sound-refusal path, and its
  own vocabulary refusals already abort at 2. An earlier revision of this backstop's comment
  claimed exit 3 for all of them; it now says which four tools get only the better message.

  **In four of those tools the message was not even reaching the user.** `arch-impact`,
  `arch-rules`, `arch-coverage` and `arch-mutants` caught `Refused`/`Broken` around `open_ro`
  only, so a refusal raised by any LATER query escaped the binary and came out through OCaml's
  uncaught-exception path — `Fatal error: exception Arch_tools.Arch_db.Refused("…")`, exit 2.
  Each now wraps its whole `main`, printing the same `tool: message` line their `open_ro` handler
  already printed. **No exit code changes**: 2 before, 2 after.

- **`arch-query raises`/`escaping-origins` name the table that is actually missing.** The
  pre-1.8-schema refusal was built from a conjunction over `exn_scopes` and `exn_origins`, so it
  named both tables even when only one lacked `channel`, and — because `has_col` also answers
  `false` for a table that does not exist — reported an absent `exn_scopes` as a column that
  "predates" schema 1.8. Those are different repairs, and the message now distinguishes them.
- **An omitted optional argument is no longer recorded as a returned `None`** (roadmap 3.14).
  `Typecore.option_none` synthesises a `None` constructor for every optional argument a call
  leaves out, and the walker recorded each as an origin of the `option` error channel — so
  `f x`, where `f` takes `?title` and `?description`, produced **two** origins claiming the
  function can return `None`.

  These were not position-less rows needing a position. They were rows about something that never
  happened. Measured on proto_alpha (`lib_protocol`, 500 `.cmt`, indexed from `origin/main`
  `8e48ec7` with `--errors-profile=tezos`): **30 526 → 3 344 origins**, every one of the 27 182
  `line = 0` rows gone and nothing else — the `exception` (1 219) and `tzresult` (763) channels are
  byte-identical across the change, and `option` falls 28 532 → 1 350.

  **Sound before and after, which is why it survived.** The class only ever *added* `None`
  origins, so no downstream answer was ever unsound — it was a precision loss that drowned the
  real signal twenty to one. And it moved no test: the suite was 197/0 before and after, because
  nothing asserted on the table's shape. A table can lose 89 % of its rows with every assertion
  still green.

  Guarded on `pos_lnum > 0`, **not** on `loc_ghost`: ghost is also set on legitimately desugared
  nodes and on ppx output that carry a usable position, so it would drop real origins. A zero line
  is the compiler saying the node has no source.

  `note_seen_value_path` deliberately stays **outside** the guard. It answers *is this declared
  path plausible for this corpus* — a question about the config, not about the program — and a
  synthetic `None` is still a `None` node in the tree. Skipping it would make `--errors-strict`
  report a correctly-declared channel as never observed on a corpus whose only `None`s are
  synthetic.

  **Both constructor arms are guarded**, not only the one that produced the measured class. On
  1 751 `.cmt` from the opam switch, position-less constructor nodes that are *not* `None` number
  seven in total and none is plausible as a declared origin — so the second arm had no live
  defect, which is exactly why it would have stayed unguarded and undocumented.

  **A number withdrawn while the surrounding claim stands.** `docs/fitness-functions.md` cited
  *"arch-index 394 / 394"* for this attribution; 394 reproduces under no build state. Re-derived
  with the `0982a42` producer, `line = 0` `option` origins are **245** over
  `_build/default/lib/arch_index` and **1 205** over the whole `_build/default`; a reviewer on
  their own checkout measured 253 and 1 310, and the gap is which units were compiled. The
  attribution claim is unaffected — it was verified on proto_alpha independently.

  **Two texts this change falsifies are corrected in the same commit**, because it is the only
  moment that can be done honestly: `docs/fitness-functions.md`'s pre-3.14 counts are now labelled
  as such, and the allow-list justification in `bin/arch_rules/arch_rules.ml` — which said in its
  own words that its 88 % *"would have gone false the day 3.14 lands"* — keeps the half that
  survives (5–8 % collisions on real-position rows, worst group nine) and marks the other half as
  a population that no longer exists.

  **Known residual, not closed here:** `exn_origins.line` is `NOT NULL`, so an origin with no
  position remains indistinguishable from one at line 0. That set is now empty, but the invariant
  holds by absence of counter-example rather than by the schema. Making the columns nullable is a
  separate slice with its own version bump.

### Added

- **`exported:<glob>` — a selector for the API surface, so `forbid reach` has a `from` that can
  be written at repository scale.** `fn:` restricted to nodes flagged exported; valid only as the
  SOURCE of `forbid reach`. `forbid reach from exported:** to fn:Vuln.parse` is now expressible,
  which is the shape a reachability gate is for — the question vulnerability triage asks of a CVE
  symbol, and a blast-radius review asks of a refactor.

  `functions.exposed` has carried the answer since the beginning, with its own index, and nothing
  that selects ever read it.

  **Spelled `exported:`, not `entry:`, deliberately.** The concept is already named three times —
  `Arch_graph.node.exported`, `arch-query --roots exported`, and the `forbid exported outside`
  rule form. A fourth spelling for one set is how two names for the same thing come to disagree
  in the one place it matters, which is what rendered a failed SARIF import as `covered` on #80.
  The rule verb and the selector kind are different namespaces; the parser cannot confuse them.
  The flag itself is normalised before any selector sees it: MAIN spells the column `exposed`,
  FLAT spells it `exported`, and `Arch_graph` reads both into `node.exported`, so the selector
  goes through the node and never through SQL.

  **Granted per position, never inherited.** It is absent from `Arch_sel.structural` — the list
  `arch-coverage` and `arch-mutants` pass — and lives in a new `Arch_sel.cone_source` that only
  `forbid reach`'s source uses. The hazard is the mirror of `ext:`'s, which `Arch_sel` documents
  against itself: a selector answerable in one position, accepted in another, matches a
  population that position never ranges over, comes back empty, and the empty result is reported
  as a **proof rather than as vacuity**. That false green was measured on this repository before
  (`forbid dep from module:src/** to file:bar` printed "1 proved"), so `forbid dep` refuses
  `exported:` at parse time with exit 2 and a message naming the POSITION rather than claiming
  the kind is unknown.

  **Accepted in exactly one position, and that is pinned across all seven the parser has.**
  A review noted the first evidence covered one direction only. Measured: `exported:` is taken
  at `forbid reach`'s source and refused — exit 2, naming the position — at `reach`'s target,
  both `dep` operands, `exported outside`, `effect`'s source and `origin`'s source. Each row
  carries a control (the same body with `fn:`), because an exit 2 for the wrong reason looks
  identical to one for the right reason: the first sweep scored `forbid origin` as a refusal
  when both spellings were failing on a missing `allow-file:` clause and neither had reached
  selector parsing.

  **The target-position hazard is not the mirror it looks like, and the honest measurement says
  so.** `ext:` as a *source* is structurally always-PASS — an external leaf has no outgoing edge,
  so the cone can never reach anything. `exported:` as a *target* selects real nodes and asks a
  meaningful question ("does this reach the API surface?"); with the kind admitted there,
  `forbid reach from fn:hidden to exported:**` reports `1 proved` and that PASS is **earned** on
  the fixture. It is refused because a kind must be granted deliberately, with tests, at each
  position — not because it was measured to lie there.

  Both halves are red-verified with distinct binaries rather than argued. Widening `dep_allow`
  to accept `Exported` (`ecc35d3b7bb4`) makes the refusal test fail; dropping the exported filter
  so the kind aliases `fn:` (`6de7538ef672`) makes the filter test fail. The fixture is built to
  discriminate: the UNEXPORTED function is the one that reaches the target, so a selector that
  quietly matched every node would report a violation identically to the control.
- **`arch-report <db> --out <dir>` — one query pass, three artifacts** (roadmap 2.2,
  `specs/reporting-and-integration.md`). Writes `report.json` (the machine contract),
  `report.sarif` (SARIF 2.1.0, one run per analysis with distinct categories) and `report.html`
  (a single self-contained file, no external assets, usable as a CI artifact). The database is the
  fourth artifact and is neither regenerated nor copied.

  **CHECK-5 — every finding appearing identically in all three — is a construction constraint, not
  a verification one.** `Arch_report.collect` runs the queries once; the three renderers are total
  functions of that one value and issue no query of their own. Building three renderings
  independently and then asserting they agree is a test that cannot fail for the right reason:
  three collections can be wrong the same way. The round-trip is asserted anyway, because a
  guarantee nothing checks expires the first time someone adds a fourth renderer.

  **The header carries all eight verdicts**, zero included, not the four the spec first named —
  bucketing eight into four collapses `UNKNOWN` (a cone escaping a ⊤ edge) with
  `UNKNOWN_NO_CONTRACT` (an index that never marked ⊤), and `NOT_COMPUTED` (never ran) with
  `NO_SOURCE` (ran over nothing). The ⊤ frontier is a **count** in `run.properties`, never a
  result list: 286 356 edges on Octez against GitHub's 25 000-result cap.

  **An analysis has four states, and an empty table is not one of the clean ones.** A coverage row
  is believed; an absent table is `not_analysed`; a table with rows is `covered`; and a table that
  is **present and empty** is `unknown` — it may have run and found nothing, or never run, and the
  database cannot tell them apart. Writing `covered` there is exactly the failure FR-003 forbids.
  Every known analysis gets a labelled section whether or not it has findings (FR-024).

### Changed
- **`specs/reporting-and-integration.md` amended in three places**, in the same slice as the code
  rather than in a separate PR — a slice updates code, evidence and card together, and an
  amendment that lands later leaves a window where the spec instructs the next reader wrongly.
  FR-005 declared its own blocker (`functions.language`/`universe` "currently unimplemented";
  both are populated — `universe = internal` and `language = ocaml` for all 14 452 functions on
  proto_alpha `lib_protocol`, 500 `.cmt`, from `origin/main` `0982a42`). FR-021's verdict split
  omitted five real verdicts and named one, `PASS_UNDER_HYP`, that no tool can emit — reserved for
  roadmap 3.2 rather than deleted, so the discharge ledger cannot reinvent it without the
  constraint that makes it safe. CHECK-1 and CHECK-3 are marked as the ingest slice's (2.3): they
  require adapters the same document declares unwritten.
- **`arch-sarif-load <db> <file.sarif>` — import a foreign analyser's findings as heuristic facts**
  (roadmap 2.3, `specs/reporting-and-integration.md` FR-010/FR-012). Opens Semgrep OSS, clippy,
  staticcheck, gosec and anything else that emits SARIF 2.1.0. New table `imported_findings`
  (schema **1.12**).

  **ADR 002's guarantee is structural, not remembered.** A `heuristic` fact may raise a finding and
  may never discharge a ⊤ anchor or license a `PASS`. That is enforced by where the rows go:
  imported findings land in a table no reachability or effect query reads, and create no `calls`
  row, no `callee_id` and no edge kind. A Semgrep finding cannot discharge anything because there
  is nothing for it to discharge *through* — measured, the call graph is byte-identical across an
  import. `soundness_class` is carried by the `producer_runs` row, so the class lives in one place
  rather than one copy per finding.

  **A `uri` that matches no indexed module — or matches several — is recorded as `unresolved` with
  a NULL `module_id`, never attached to the nearest candidate.** The path is written by a tool that
  knows nothing of this tree: absolute, relative to a `uriBaseId` we do not have, or
  percent-encoded. A finding on the wrong function is worse than a finding on none, and a suffix
  match produces one cheerfully. Ambiguity is absence of proof here for the same reason it is in
  the qualified-name resolver.

  **A `level` outside SARIF's closed vocabulary is refused and counted, never folded into a
  default.** The input is foreign and the standard evolves, so a value we do not know is a fact
  about the producer rather than noise to swallow.

  **The two failure states are kept apart.** An input that cannot be parsed exits non-zero and
  writes **no facts** — the whole document is parsed before any write is opened, so a malformed
  file never reaches the writer (`Arch_db` has no transactions, and a loop that stops at the bad
  record leaves everything before it written). An input that parses while records are refused
  exits 0, writes the survivors, and records `partial` with the rejected count. The coverage row is
  a write about the *failure*, not about the program.

### Changed
- **`specs/reporting-and-integration.md` amended again, in the same slice as the code.** FR-012's
  "writes nothing" and CHECK-3's "no rows written **and** a coverage row" could not both hold
  literally — a coverage row is a row. Scoped to *writes no **facts***, with the transactional
  reading and its mechanism stated, and the residual named: a *write* that fails part-way is not
  covered and would need a transaction. CHECK-3 split in two, because "a `partial` or `failed`
  coverage row" for a malformed input conflates the two states FR-012 keeps apart — CHECK-3-bis
  now covers `partial`, which otherwise no test ever produced. CHECK-1's second clause needed
  `PASS_UNDER_HYP` (roadmap 3.2, unreachable today) and is replaced by the stronger property the
  design actually gives: the import changes no verdict and no edge.

### Added
- **`arch-rules --format sarif` — SARIF 2.1.0 output (roadmap 2.1).** `arch-rules` can now emit
  its verdicts as a SARIF 2.1.0 log, one `run` per invocation, for upload to GitHub code scanning
  or any other SARIF consumer. `VIOLATION`/`POSSIBLE` map to `error`/`warning`; the five
  "nothing proved" verdicts (`UNKNOWN`, `UNKNOWN_NO_CONTRACT`, `NOT_COMPUTED`, `NO_SOURCE`,
  `NO_TARGET`) map to `note` but carry the exact verdict string in `results[].properties.verdict`
  and the ADR-002 soundness-gap vocabulary (`unknown_top` vs. `no_contract` — two different
  causes) in `properties.soundness`, so a machine consumer never has to re-parse `message.text`
  to tell them apart. A `PASS` verdict is a proof, never a result. `run.properties` mirrors
  `--format json`'s own `contract_ok`/`computed`/`proved`, plus the roadmap 1.3 coverage matrix
  and the roadmap 1.4/1.5 ⊤-frontier count and witness `codeFlows`. `Arch_sarif.log` refuses two
  runs sharing `(producer, category)`, since GitHub overwrites a run sharing tool+category with a
  later one rather than merging — ahead of roadmap 2.2 (`arch-report`), the caller that will
  actually emit several runs per log. New vendored schema at `vendor/sarif/` (OASIS SARIF
  spec, draft-04; a specification artifact under OASIS's own IPR Policy — RF on RAND Terms Mode
  for TC-member contributions, the OASIS Feedback License for others — not an OSI open-source
  licence; see `vendor/sarif/README.md` for the full citation) and a new CI dependency
  (`pip install jsonschema`, probed before use) to validate output against it.

- **`arch-rules` gains `forbid origin` — a crash-surface regression gate** (roadmap 3.12).
  `forbid origin from <sel> form:<f1,f2,...> [channel:<name>] allow-file:<path>` walks the forward
  cone of `<sel>` and reports every escaping `exn_origins` site of the named forms, on one error
  channel, that the allow-file does not cover.
  **An allow-list, not a baseline, and deliberately no `--regenerate` flag.** A site list can grow
  for three reasons — a real regression, widened coverage, or a proof that strengthened
  `MAY → MUST` — and a line-diff conflates all three, so the gate forces a human rather than
  automating an excuse. A **coverage figure** is printed on every verdict for the same reason:
  without it, a widened-coverage failure reads as a regression and the rule gets disabled.
  **Allow-file format is `fn | file:line | form | exn | ×N`**, and the count is load-bearing: the
  four fields alone are not a key, so without it an entry is a *set* exemption whose membership can
  grow after review. Lines are split from the right so an OCaml operator name containing `|` does
  not break the file; a duplicate identity is refused rather than silently first-winning.
  **`channel:` defaults to `exception`, and the default matters**: `exn_origins` holds every error
  channel, and on `option` "raising" means returning `None`. On proto_alpha `form:raise` sees 1
  origin on `exception` against 75 on `option` and 161 on `tzresult` — an unscoped rule quantified
  over 237 origins while appearing to police crashes.

  channel, and on `option` "raising" means returning `None`. Measured — on proto_alpha (`lib_protocol`, indexed from `origin/main` `0982a42` with

  channel, and on `option` "raising" means returning `None`. Measured — on proto_alpha (`lib_protocol`, 500 `.cmt` indexed from `origin/main` `0982a42` with
`--errors-profile=tezos`) `form:raise` from `file:**/main.ml` sees **1** origin on `exception`,
**128** on `option` and **247** on `tzresult` — so the unscoped rule quantified over **376**
origins while appearing to police crashes. An independent reviewer measured 1 / 75 / 161 on their
own build of the same tree; both are internally consistent and the gap is corpus COVERAGE, not
disagreement — which is why a number here names its build state and not just its tree.
  **What a PASS claims:** on a real index the cone almost always escapes through a ⊤ edge, so the
  rule normally reports `UNKNOWN` and says how many. It proves *no new site among those it can
  see*, never *no fatal origin exists*. `VIOLATION` fails regardless of ⊤, which is what makes it
  useful while completeness is out of reach.
### Added
- **`scripts/recalibrate.sh` — attribution-gated recalibration of the pinned constants**, and it
  is now wired to something. The two constants this repository pins (the self-index golden in
  `test/fixtures/self-index-stats.txt`, and `must_null_ceiling.ml`'s `clean_measured` ratchet)
  both go stale on rebase, and the cheapest way to make CI green is to overwrite them with
  whatever the branch measures — which is also how both stop working. The script instead
  ATTRIBUTES the movement across a 2x2 (base vs new binary, base vs new corpus) and writes only
  the part it can prove is source-only, never a ratchet loosening.

  `--self-test` runs in the Tezt suite (`tezt/tests/recalibrate_self_test.ml`) and `--check` runs
  in CI. Before this it was invoked by nothing at all: no CI step, no dune rule, no Makefile
  target.
  The CI step separates the two non-zero exits. A **refusal** (exit 2 — a degraded cell, a corpus
  below the adequacy floor, a component collapsed below half its pin, an unreadable or
  doubly-defined constant) fails the build, because a gate that cannot measure must not report
  success. But those causes are *not* alike, and the step says so rather than lumping them:
  three of them mean the gate itself is broken, while **implausibility may genuinely be a
  property of the branch** — a real >50% resolution gain has exactly the same shape as a query
  that stopped matching, and this repository has recorded a MAY_TOP move of 79% → 3.9%. Telling
  the author of such a branch that the gate is broken is both wrong and unactionable, so the
  script prints a machine-readable `refusal-class=` line for every exit-2 cause and CI takes the
  "this may be your branch, recalibrate by hand and say why" arm only when **every** class line
  in the run is `implausible`. With no class line at all it falls to the "the gate is broken"
  arm — fail-closed. A
  **stale** constant (exit 1) is a warning here only because it is already hard-gated twice over —
  the self-index smoke test diffs the golden, and `must_null_ceiling` fails the suite on a breach.
  So the step adds no new way for an ordinary PR to fail, and one new way for a broken measurement
  to be caught.

- **A head spelled through a module alias is resolved instead of going to ⊤.** `S.safe_int`, where
  the file declares `module S = Saturation_repr`, had a path rooted at a local binder;
  `qualified_is_dynamic` judged it dynamic and the edge became `MAY_TOP` with
  `top_reason='module_param'` — *I cannot tell what this module is*. The producer now rewrites such
  a head to the qualified name it denotes, at the site where the binder's `Ident` is in hand, and
  the edge flows through ordinary qualified resolution. Rows carry `edge_form='module_alias'`
  (schema `1.10` → **`1.11`**, flat `1.2` → **`1.3`**) and are demoted to `MAY_ENUMERATED`: the
  rewrite discharges only the *naming* conjunct of MUST. Measured: `module_param` ⊤ falls
  5 464 → 2 240 on proto_alpha and 5 334 → 213 on octez-manager, with **zero** change to the MUST
  count and no edge created or destroyed on either corpus.

  **This does not bound more nodes, and the release note says so rather than quoting the ⊤ drop.**
  With externals open it bounds one extra node on proto_alpha and nine on octez-manager — ⊤ is
  absorbing. What changes is *why* the rest are unbounded: `may_top_edge` falls while `external`
  rises, trading an unknowable cause for a fixable one. With externals assumed pure the slice is
  worth **+0.9 pt** and **+8.1 pt** respectively — reported per corpus, because an average of two
  numbers that differ ninefold describes neither.

  The CI step separates the two non-zero exits. A **refusal** (exit 2 — a degraded cell, a corpus
  below the adequacy floor, a component collapsed below half its pin, an unreadable or
  doubly-defined constant) fails the build, because a gate that cannot measure must not report
  success. But those causes are *not* alike, and the step says so rather than lumping them:
  three of them mean the gate itself is broken, while **implausibility may genuinely be a
  property of the branch** — a real >50% resolution gain has exactly the same shape as a query
  that stopped matching, and this repository has recorded a MAY_TOP move of 79% → 3.9%. Telling
  the author of such a branch that the gate is broken is both wrong and unactionable, so the
  script prints a machine-readable `refusal-class=` line for every exit-2 cause and CI takes the
  "this may be your branch, recalibrate by hand and say why" arm only when **every** class line
  in the run is `implausible`. With no class line at all it falls to the "the gate is broken"
  arm — fail-closed. A
  **stale** constant (exit 1) is a warning here only because it is already hard-gated twice over —
  the self-index smoke test diffs the golden, and `must_null_ceiling` fails the suite on a breach.
  So the step adds no new way for an ordinary PR to fail, and one new way for a broken measurement
  to be caught.

- **`ext:<glob>` — a selector that names external leaves.** `arch-rules` can now write
  `forbid reach from <sel> to ext:<glob>` to forbid reaching a callee with no body in the index
  (an unresolved external, such as `Stdlib.+`), valid only as the target of `forbid reach`. On a
  flat (NDJSON) index it is `NOT_COMPUTED`: `arch-load`, this repo's one producer of that schema,
  synthesises a `functions` row for every callee it writes, so the population `ext:` needs is
  never populated on that producer's actual output — a property of what `arch-load` writes, not
  of what the flat schema can hold. `docs/fitness-functions.md`'s selector table now lists it.

  **Observable gate change for consumers.** `forbid dep` now only accepts `module:` on either
  side; `file:` and `fn:` operands, previously accepted, now **abort with exit 2**. Before this,
  `forbid dep` threw the selector kind away and globbed every operand straight against
  `module_deps` strings regardless of what prefix was written, so a rule written as
  `forbid dep from file:lib/core/** to module:Web.**` looked like a file-path check but was
  silently re-run as a module-path glob — `forbid dep from module:src/** to file:bar` printed
  `[ pass ]`, "1 proved", against a target that could never match anything real. That was a false
  green, not a working check, so the fix is a refusal, not a relaxation: a rule file using
  `file:`/`fn:` on a `dep` operand now fails fast at parse time instead of silently passing.
  `docs/fitness-functions.md` documents the restriction and why.

  An alias whose target is **not a real compilation unit** — a functor parameter (`module M = X`
  inside `module Make (X : S)`) or a unit-local module — is deliberately **not** rewritten: its ⊤
  was honest, and rewriting it would point a resolved edge at whatever unit happened to share the
  parameter's name. **That is not hypothetical**: without the guard, the whole `src` tree acquires
  **73 forged resolved edges** — `List.map` ×18, `Context.Tree.*`, `E.Tree.find`, `P.Tree.*` —
  functor parameters resolved to unrelated same-named modules.

  **A rewritten edge is not guaranteed to resolve, and the release note says so.** On the whole
  `src` tree 41 622 rewrites yield 32 664 with a `callee_id` (78.5 %); on a dune-**wrapped** corpus
  the ratio inverts, because `module S = Saturation_repr` inside a wrapped library renders a name
  the resolver cannot bind. An unresolved rewrite is still an improvement on the ⊤ it replaces —
  the persistent-root guard guarantees the new head names a real compilation unit, so the edge is
  bounded by a named target that merely sits outside the index, the same standing as any external
  leaf.

### Added
- **`ext:<glob>` — a selector that names external leaves.** `arch-rules` can now write
  `forbid reach from <sel> to ext:<glob>` to forbid reaching a callee with no body in the index
  (an unresolved external, such as `Stdlib.+`), valid only as the target of `forbid reach`. On a
  flat (NDJSON) index it is `NOT_COMPUTED`: `arch-load`, this repo's one producer of that schema,
  synthesises a `functions` row for every callee it writes, so the population `ext:` needs is
  never populated on that producer's actual output — a property of what `arch-load` writes, not
  of what the flat schema can hold. `docs/fitness-functions.md`'s selector table now lists it.

  **Observable gate change for consumers.** `forbid dep` now only accepts `module:` on either
  side; `file:` and `fn:` operands, previously accepted, now **abort with exit 2**. Before this,
  `forbid dep` threw the selector kind away and globbed every operand straight against
  `module_deps` strings regardless of what prefix was written, so a rule written as
  `forbid dep from file:lib/core/** to module:Web.**` looked like a file-path check but was
  silently re-run as a module-path glob — `forbid dep from module:src/** to file:bar` printed
  `[ pass ]`, "1 proved", against a target that could never match anything real. That was a false
  green, not a working check, so the fix is a refusal, not a relaxation: a rule file using
  `file:`/`fn:` on a `dep` operand now fails fast at parse time instead of silently passing.
  `docs/fitness-functions.md` documents the restriction and why.

### Fixed
- **`arch-rules` reports the verdict and the gate as two different numbers, and `--on-vacuous`
  now covers every rule form.** The summary line collapsed a seven-state verdict into
  `N rule(s), M failing`, which reads as a pass for a run that proved almost nothing: on this
  repo's own four-rule file, `4 rules, 0 failing` was really *1 proved / 0 violations /
  3 UNKNOWN*. It is now two lines — a census that partitions the rules (every state printed even
  at zero) and a separate `gate:` line carrying `failing` plus the policy flag values actually in
  force, since `failing` overlaps six of the seven census counts and must never be added to them.
  `--format json` gains `possible`, `unknown_escaping`, `unknown_no_contract` and
  `not_computed`; every pre-existing field is unchanged.

  **Observable gate change for consumers.** `forbid dep`, `forbid exported` and `forbid effect`
  previously had no vacuity check at all — only `forbid reach` did — so they emitted `PASS` for a
  rule whose selector had stopped matching, and `--on-vacuous fail` (the default) covered one
  rule form in four. They now emit `NO_SOURCE` over the population each actually quantifies over.
  For `reach`-only rule sets, including this repository's own `arch-rules.txt`, nothing moves and
  the exit code is identical. A rule set containing `dep` / `exported` / `effect` rules can now go
  from exit 0 to exit 1 — for instance a single `forbid exported` rule against an index whose
  producer does not record export status. That is the fix working, not a regression: the old
  exit 0 was a rule that could not fail. `--on-vacuous warn` restores the previous behaviour while
  the selector or the producer is corrected. `forbid dep` deliberately gains no target-side check
  — a `dep` target ranges over modules *already depended on*, so "nothing matches `Web.**`" is the
  preventive rule succeeding, and calling it vacuous would fail the build precisely when the
  codebase is clean.

- **The recalibration gate would write a degenerate measurement over a pinned constant.** A query
  that succeeds but matches nothing returns `0`, not an error: sqlite3 writes nothing to stderr,
  `0` passes an is-it-an-integer check, and `A=B=C=D=0` is the cleanest possible "attributable to
  source change only". Simulating a column rename in the ceiling predicate made
  `--write --only ceiling` report `TIGHTENED clean_measured 347 -> 0 (installed file re-read and
  confirmed)` and exit 0; the same hole left the golden — the *change detector* — reading
  `modules: 0 / functions: 0 / calls: 0`, "verified byte-identical", exit 0.

  Two adequacy floors now stand between a measurement and a write, and every cell of the 2x2 is
  gated, not just the one that gets written. A *relative* floor refuses any component that has
  collapsed below half the pinned value; an *absolute* floor requires each cell's database to
  hold at least `min_total_calls` rows in `calls` — read out of `must_null_ceiling.ml` rather
  than copied, so the two cannot drift apart. `--check` now exits 2 on these inputs.

  This is also a correction to the "a ratchet may always be TIGHTENED automatically" axiom the
  script was built on. That axiom is about DIRECTION and says nothing about MAGNITUDE, but every
  way a measurement can silently break moves the number DOWN — into the direction it calls
  always-safe. A tighten is safe for the invariant and destructive for the constant:
  `clean_measured = 0` cannot fail CI, and it can never catch anything again either.
- **An unanchored read of `let headroom` truncated a legal OCaml literal.** `let headroom = 1_000`
  means 1000 and was read as **1**, with no refusal and no diagnostic, because the pattern ended
  in `.*` and the result was passed through a plain integer check. Measured: with the pin at 400
  and `headroom = 1_000`, `--write --only ceiling` rewrote 400 -> 340 and reported success, when
  340 is inside the real band and nothing should have been written. Read-only, the same misread
  reported a healthy tree as `STALE`, exit 1. Every read of a pinned integer now goes through one
  anchored reader, which also refuses a constant that is defined twice rather than silently
  taking the first with `head -1`.
- `is_int` accepted values `$(( ))` cannot evaluate. `08` passed, then made the band comparison
  abort with "value too great for base" — so no arm of the `if/elif/else` ran, the currency
  verdict silently kept its previous value, and a bash error went to stderr. The self-test had
  pinned the wrong half of this by asserting `00` as a pass.
- The refusal message for an unreadable pinned CONSTANT blamed sqlite3 and told the reader to
  "check the column names against the current schema", when no query is involved. Cell failures
  and pin failures now print separate diagnostics; the pin one names the file, the anchored
  regex, and the candidate lines.
- Each metric's four cell databases now get per-metric paths. They were four fixed names reused
  across metrics, so correctness depended on an unstated (and untested) assumption that the
  producer truncates rather than appends.

- **A completion marker can no longer outlive its evidence.** `comment_db_meta`'s
  `error_contract` / `exn_contract` / `callgraph_contract` keys claim that an analysis RAN; they
  are now cleared twice — once before the schema is demolished, once after it is rebuilt — so a
  producer killed mid-analysis cannot leave the previous run's marker answering for work that
  never happened. Previously `INSERT OR REPLACE` was relied on to keep them current, which is
  true only of a run that REACHES the write.

  **Observable contract change for consumers:** a re-index over a tree that is temporarily
  un-built now leaves a database with no markers, so `arch-query`'s exception/error-channel
  entry points and `arch-coverage-matrix` REFUSE (`NOT_ANALYSED`, exit 3 / `not_analysed`,
  exit 1) where they previously answered. That is the intended direction — the old answer was
  produced from a marker with no rows behind it — but it is a behaviour change, not a silent
  internal fix. Re-index to restore the markers.

  Measured: a SIGKILL sweep across the demolition window found 21 torn states in 60 attempts
  before the fix and 0 in 60 after. The marker list is now one exported value
  (`Arch_index_support.completion_marker_keys`), and `tezt/tests/completion_markers.ml` fails if
  a new `comment_db_meta` key is neither a declared marker nor declared non-load-bearing.

- **`fan-in`, `god-modules` and `callers-of` excluded a real call site.** They tested
  `edge_form IS NULL`, i.e. every non-NULL value rather than the one value that is not a call site.
  That was correct only while `'value_alias'` was the vocabulary's sole member. The predicate is now
  `COALESCE(edge_form,'') <> 'value_alias'`; without the fix these commands would have silently
  dropped 3 247 genuine edges on proto_alpha (500 `.cmt`, `0982a42`, `--errors-profile=tezos`). `docs/edge-kind-contract.md` stated the wrong
  predicate and is corrected with it.
- **A completion marker can no longer outlive its evidence.** `comment_db_meta`'s
  `error_contract` / `exn_contract` / `callgraph_contract` keys claim that an analysis RAN; they
  are now cleared twice — once before the schema is demolished, once after it is rebuilt — so a
  producer killed mid-analysis cannot leave the previous run's marker answering for work that
  never happened. Previously `INSERT OR REPLACE` was relied on to keep them current, which is
  true only of a run that REACHES the write.

  **Observable contract change for consumers:** a re-index over a tree that is temporarily
  un-built now leaves a database with no markers, so `arch-query`'s exception/error-channel
  entry points and `arch-coverage-matrix` REFUSE (`NOT_ANALYSED`, exit 3 / `not_analysed`,
  exit 1) where they previously answered. That is the intended direction — the old answer was
  produced from a marker with no rows behind it — but it is a behaviour change, not a silent
  internal fix. Re-index to restore the markers.

  Measured: a SIGKILL sweep across the demolition window found 21 torn states in 60 attempts
  before the fix and 0 in 60 after. The marker list is now one exported value
  (`Arch_index_support.completion_marker_keys`), and `tezt/tests/completion_markers.ml` fails if
  a new `comment_db_meta` key is neither a declared marker nor declared non-load-bearing.

### Added
- Configurable **error channels** (roadmap 3.4-bis), generalising the exception analysis to
  error-carrying values. A channel is one way of failing; `exception`, `result` and `option` are
  built in, and `arch-errors.toml` declares any others (carrier type and aliases, origins, binds,
  `add`/`replace` transforms, converters that close one channel and open another, and sinks).
  Merge order is built-in < profile < user file, the effective config is digested into
  `comment_db_meta.error_config_digest`, and a shipped `profiles/tezos-errors.toml` covers the
  Tezos protocol environment's `tzresult` — built from a verified inventory of all 276 units of
  `lib_protocol`, not from the documented API surface, because the two disagree.
  `arch-query may-fail <fn> --channel <name|all>`, `fails-with <E>`, `error-stats`, all with
  `--assume-externals-pure` and `--builtin-summaries`. Verdicts distinguish `BOUNDED`,
  `UNBOUNDED (⊤)` with witnesses, `BOUNDED_UNDER_HYP(externals_pure)`, `NOT_A_CARRIER` ("looked;
  it cannot fail this way") and `NOT_ANALYSED` (exit 3, "nobody looked") — the last two are kept
  apart because an empty set and an unperformed analysis must never be confusable. Polymorphic
  variants are recognised as error identities, which matters: real corpora spell errors
  `` Error `Msg `` far more often than with ordinary constructors. Schema **1.8**, additive
  (`channel` columns, `exn_edges`, `channel_carriers`, and `call_exn_scopes` keyed on
  `(call_id, scope_id)` so a call site can carry one scope per channel). Config errors — a bad
  path, an unknown TOML key, a declared carrier type that matches nothing in the corpus, or a
  channel structurally shadowed by an earlier one — exit 1 rather than degrade silently;
  `--errors-strict` promotes unmatched-path warnings to fatal, counting only paths your own
  config files spell. Declaring a channel that already exists **extends** it field by field, so a
  profile adds vocabulary to a built-in without restating it. The effective config's digest
  (`comment_db_meta.error_config_digest`) is SHA-256.
  See `docs/error-channels.md`, the adapter contract in `docs/error-channels-porting.md`, and
  `specs/error-channels.md`.
- Witness paths (roadmap 1.5): `arch-rules` `VIOLATION`/`POSSIBLE`/`UNKNOWN` verdicts now carry a
  concrete call path (`results[].witness` in `--format json`, also shown in text/md output) instead
  of only a rule name and an offender list — the path a reviewer would otherwise have to
  reconstruct by hand from the graph. `Arch_graph` gains `shortest_path`/`witness_to_top`
  (single-source) and `shortest_path_from_set` (multi-source — used internally by `arch-rules`,
  since a rule's source selector resolves to a set of seeds, not one), sharing one BFS core.
  `PASS` and every non-`reach` rule form carry no witness, since none of them assert a
  reachability claim a path could illustrate.
- Exception-identity may-raise sets for OCaml (roadmap 3.4): the CMT producer records raise
  origins with the resolved constructor path, handler scopes with their caught sets, and the
  handler scope enclosing **each call site** (`exn_origins` / `exn_scopes` /
  `exn_scope_catches` / `call_exn_scopes` / `exn_rebinds`, additive). `arch-query raises <fn>`
  computes the transitive set minus what the handlers around each call catch, with ⊤ reasons
  (`may_top_edge`, `external`, `unknown_exn_value`) and verdicts `BOUNDED` / `UNBOUNDED (⊤)` /
  `BOUNDED_UNDER_HYP(externals_pure)`; `raisers-of <Exn>`, `exn-stats`,
  `--assume-externals-pure`. A DB without `comment_db_meta.exn_contract` refuses `NOT_ANALYSED`.
  Raise heads are recognised by the `%raise` primitive (protocol-environment safe); raising
  primitives (comparison on closure-capable types, integer division, bounds checks) are typed
  origins. See `docs/exception-raise-sets.md` and `specs/exn-raise-sets.md`.
- `arch-impact`: per-diff change-impact briefing over the sound call graph — touched functions,
  affected exported API, blast radius, ⊤ frontier, reaching tests, effects crossed, and findings
  on touched lines. Text / Markdown / JSON output. `--fail-on-new-findings` implements the R5
  ratchet and is off by default.
- NDJSON contract: optional `line_start` / `line_end` on `function` records, so a diff hunk maps
  to a function on the flat schema too. A **half** span aborts the load — it would mis-map every
  hunk, which is worse than no span.
- `arch-callgraph-go` emits source spans for every function that has syntax. Synthetic functions
  (wrappers, thunks, `init`) carry none by design.
- `arch-rules`: architecture fitness functions over the sound graph — layering, export-surface,
  effect and declared-dependency rules. Four verdicts (`VIOLATION` / `POSSIBLE` / `UNKNOWN` /
  `PASS`) instead of the pass-fail every declared-import checker reports; `PASS` is refused on an
  index that is not ⊤-marked, and a rule matching no code fails as VACUOUS.
- `arch-rules.txt`: arch-index's own layering rules, checked in CI.
- `lib/arch_tools`: the read model shared by every tool — schema detection, the graph (keyed
  by row id on the main schema, by name on the flat one), selectors, path resolution, the LCOV
  reader, the diff reader, and the sqlite3-compatible output formatter — so no two tools can
  drift on how the graph is keyed or which edges are in a closure. On Caqti, so a query's
  parameter arity and row shape are checked by the compiler.
- `arch-mutants`: mutation testing targeted by the call graph. `plan` decides what is worth
  mutating (test-reachable code, with the tests that must rerun for each target) and partitions
  every indexed function into exactly one bucket with a reconciliation count; `report` attributes
  each surviving mutant to the innermost enclosing function and the tests that failed to kill it.
  Generic NDJSON input plus a Mutaml adapter. No mutation engine of its own, and deliberately no
  mutation score.
- `arch-coverage`: reachability-weighted coverage from an LCOV tracefile — API-relative
  never-exercised functions, covered-but-only-⊤-reachable functions, and (with `--mutants`) the
  covered-yet-unkilled pairing that replaces a coverage percentage. `--write` finally populates
  the `coverage` table. LCOV in, so every ecosystem is covered by one parser.
- `arch_mcp`: an MCP server (stdio JSON-RPC) built on mcp-kit, exposing reachability, escapes,
  findings, change impact, architecture rules and the mutation plan to agents. Every result
  carries a `provenance` block — contract stamps, producing backend, and whether a negative is
  evidence at all. It SHELLS OUT to the command-line tools rather than reimplementing any
  verdict, so an agent and a reviewer cannot be told different things. Marked `(optional)` in
  dune because mcp-kit is not on opam yet; a dedicated `mcp` CI job pins it and asserts the
  binary was actually built rather than silently skipped.
- `selftest-impact.sh`, `selftest-rules.sh`, `selftest-mutants.sh`, `selftest-coverage.sh` and
  `selftest-mcp.sh`, wired into CI.
- `arch-impact --format json` / `arch-rules --format json`: a strict machine-output contract —
  `computed`, `contract_ok` and `verdict` fields that restate the exit-code decision for a
  stdout-only consumer (workflow gates, agents), int-only counts (`new_findings` on `arch-impact`;
  `failing`/`unknown`/`vacuous`/`not_computed` on `arch-rules`), and `findings.computed`/`reason`
  so an absent decision analysis is stated, not implied by a missing key. No floats, no `Intlit`,
  exactly one JSON object on stdout. Exit codes and text/md output are unchanged.

- `arch-serve`: the read-only HTTP browser over a flat index. A MAIN-schema index is declined at
  startup with exit 2 naming the schema, rather than reaching the first query and surfacing a raw
  `Sqlite3.Error` — that shape is not read yet, and saying so is the honest answer.

### Fixed
- **`arch-query effects-of`, `mutators-of` and `pure-fns` stopped at every module boundary too** —
  same root cause as `dead-code` below. On a two-module fixture where the mutation lives one module
  away from its caller: `effects-of` returned NOTHING, `mutators-of` lost the transitive caller,
  and `pure-fns` reported the caller as **pure** while it reaches a `Hashtbl.replace`. That last
  one is a claim consumers act on.

  The first fix moved only the join to `calls.callee_id` and left the recursion SET keyed by name
  — which made the closures cross module boundaries and then conflate homonyms on arrival:
  calling the pure namesake of a mutator read as reaching the mutation. An adversarial review
  proved it before it shipped anywhere. Both the join and the set are ids now. The endpoints
  touching `function_effects` cannot be id-keyed (that table has only `function_name, file_path`),
  so seeds and projections narrow same-named candidates by module path — and the first version of
  THAT narrowing was broken twice over, caught by a further review round before shipping: it
  compared paths with LIKE, where `_` in a filename matches `/` (so `foo_bar.ml` claimed an
  effect recorded in `foo/bar.ml`), and a basename-only match could suppress the fallback and
  DROP the true mutator entirely — an under-report, the one direction worse than conflation.
  The comparison is now substr arithmetic (no wildcards), prefers the longest matching path, keeps
  all same-named candidates when nothing matches, and effect rows with no `functions` row at all
  are listed as direct mutators instead of vanishing through the id join. `pure-fns` deliberately
  skips the narrowing — over-seeding withholds purity claims (for the namesake and its whole
  caller cone) rather than forging one, the only safe direction for that verdict. Residual,
  documented in the code: when extractor and indexer disagree about the source-relative root, a
  basename collision can still hand the row to the wrong homonym; the cure is resolving effects
  to ids at load time.
- **`arch-query dead-code` could still report the whole index as dead through its DEFAULT
  invocation.** The unmatched-root guard checked the name list, but the failure lives in the root
  SET: bare `dead-code` on an index where nothing is exported (a library with no `.mli`, a Go
  package with only lowercase names) rooted at nothing, reported every function dead, exited 0 —
  and stamped the report with the strongest soundness the index supports, since an empty reach
  cone touches no degrading edge. An empty root set now refuses with exit 2, as does `--roots`
  with a missing or empty value. On the flat schema both the guard and the root lookup now use
  functions ∪ callers — a legitimate root without a `functions` row was being refused, the exact
  mistake `arch-query`'s `known` had already documented and fixed. NOT callees: a first version
  included them, and a review showed `--roots '*TOP*'` or `--roots fmt.Println` then rooted at a
  leaf with no outgoing edges — every function dead, exit 0, stamped sound — resurrecting the
  precise report the guard exists to refuse.
- **`dead-code`'s `sound` verdict ignored unresolved callees.** "Unresolved" does not mean
  "outside the index", and the two shapes it covers land in different branches: module aliases
  are demoted to MAY_TOP by the CMT producer (observed, not assumed) and were already caught by
  the ⊤ degradation; qualified heads the resolver cannot place — `Stdlib.+`, cross-library names
  — carry MUST/MAY_ENUMERATED, the ⊤ branch never fires on them, and the callee may perfectly
  well be an indexed function. The verdict now degrades to
  `candidate (unresolved callees in the cone — the reach set is a lower bound)` for those. Stated
  cost: any cone that calls the stdlib degrades; `sound` remains reachable exactly for cones
  whose every edge resolves, and the corpus pins both directions.
- **`arch-query dead-code` stopped at every module boundary on the MAIN schema.** The reachability
  closure walked callee NAMES: a caller records its callee as dune spells it
  (`Arch_index__.Lsp_client.start`) while that function's own `functions.name` is `start`, so the
  chain broke at each cross-module call and everything reachable only across one was reported
  deletable. `calls.callee_id` already held the correct resolution — the query was not using it.
  The closure now walks ids on the main schema (the flat schema keeps names, where the name is
  the key). Walking names also *invented* edges through homonyms, since distinct functions
  sharing a short name in different modules were conflated; both directions are fixed. Found by
  running arch-index on its own test suite, which reported 129 of its own shared helpers dead;
  it now reports 3, all of them `let`-bound constants that are referenced but never applied.
- **`arch-query dead-code --roots` reported the entire index as dead.** The flag its own usage
  documents was never parsed: the raw argument became the roots list, so `--roots entry` searched
  for a function literally named `--roots`, matched nothing, and left the reachable set empty —
  every function in the index came back as deletable, for anyone following the documented
  interface. Both `--roots X` and `--roots=X` are parsed now (the bare positional form still
  works), and a root matching no function is refused with exit 2 instead of silently producing
  that report: an unmatched root makes every function unreachable, so a typo in a root name would
  otherwise read exactly like a correct answer.
- **The LSP indexing path forged must-reach paths.** `arch-index --language go|rust|typescript`
  wrote a `calls` table with no `kind` column, and a missing `kind` reads as the literal `'MUST'`
  in `Arch_db.kind_sql` — so every callHierarchy edge, including the deferred and conditional
  ones the protocol cannot distinguish, entered the MUST closure and `reaches` reported must-reach
  paths that path does not support. Every edge it writes is now tagged `MAY_ENUMERATED`, and the
  index deliberately does **not** stamp `callgraph_contract`: callHierarchy never reports the call
  sites it failed to resolve, so the ⊤ frontier is unknown rather than empty and
  `unreachable`/`escapes` must keep refusing.
- **A race against the language server's background indexing.** rust-analyzer answers
  `prepareCallHierarchy` with an empty list — not an error — while `cargo metadata` and the
  initial index are still running, so "still indexing" and "no calls" were indistinguishable and
  a cold checkout indexed to zero edges. The handshake now consumes `$/progress` and waits for
  the work-done tokens the server already reports. The wait reports which of four outcomes it
  reached, because they are not interchangeable: the indexing phase closing is authoritative,
  quiescence is a heuristic that can fire in an inter-phase gap (rust-analyzer runs startup as a
  sequence of tokens and closes each before opening the next), and no-progress and timed-out are
  neither. Only the first is a fact about the index; the rest fall back to the previous
  bounded-sweep behaviour, so a server that reports nothing is no worse off than before.
- A language-server request that timed out with its reply unread left the connection
  desynchronised, and every later call then failed with its own id-mismatch `Protocol_error` —
  N confusing errors, none of them naming the single event that caused them all. (Not a
  soundness bug: `Jsonrpc_client` stamps each request with a monotonic id and rejects a reply
  whose id does not match, so a desynced stream never returned a wrong answer.) The connection
  is now retired on the first such failure and every later call reports that reason, instead of
  the same refusal arriving by accident as an `Eio.Mutex.Poisoned` wrapped in
  `Connection_failed`.
- A legacy index with no `calls.kind` column crashed the closure queries — the column cannot be
  named in SQL when it does not exist. Every edge now reads as MUST there, as `arch-query` does.
- `arch-impact`'s `contract_ok`/`sound_reachability` used a weaker check (`t.contract <> None &&
  t.kinded`) than `arch-rules`'s (the full `require_contract` scan, which also rejects a
  NULL/invalid `kind` on a real edge — a flag set on a malformed index is worse than no flag at
  all: see `Arch_db.require_contract`'s doc comment). The same index could read `contract_ok:true`
  from one tool and `false` from the other. Both tools now derive it from one new shared helper,
  `Arch_db.contract_ok`, so they can never disagree. New selftest fixture (the same
  stamped-but-NULL-kind index `selftest-contract.sh` already uses) confirms both tools agree
  `contract_ok:false` on it. `arch-impact`'s text-mode output is unaffected — no existing fixture
  had a NULL-kind edge, so the stricter check changes nothing already covered, only what was
  previously miscategorized.
- `arch-rules --format json`: added `results[].detail_total`, the untruncated count each
  `detail` list (capped at 20) was cut from — previously a consumer could not tell "20 shown, 20
  total" from "20 of 200" without recounting from text output.
- `arch-coverage` and `arch-mutants` still computed `sound`/`sound_reachability` via the same
  weak `t.contract <> None && t.kinded` check `arch-impact` was just fixed to stop using
  (round-2 review, follow-up to the `contract_ok` unification above). Both now call the shared
  `Arch_db.contract_ok` helper too, so a NULL-kind edge reads `sound:false` consistently across
  all four tools instead of only the two that gate the `proof-carrying-change` workflow.

## [0.2.0] - 2026-06-25

### Added
- `arch-serve`: local HTTP server serving a D3 force-graph SPA from a SQLite DB
  - Neighborhood BFS view (depth 1/2/3), Module view, Reachability query
  - Function search and module filter sidebar
- CMT-based call graph extraction fallback for OCaml projects
  - Walks `_build/default/**/*.cmt` typed ASTs when LSP call hierarchy is unavailable
  - ocamllsp ≤1.23.1 does not implement `textDocument/prepareCallHierarchy`

### Fixed
- OCaml projects producing 0 functions — 5 root causes:
  - `language_id_of_uri` always returned `"typescript"` for `.ml` files
  - `scan_ts_files` used as fallback for OCaml (0 `.ts` files found)
  - `_opam/` local switch (~30k `.ml` files) not excluded from scan
  - `workspace/symbol` cold-start corruption on ocamllsp (stale response in read buffer)
  - `symbol_kind_of_int` table had kinds 6↔12 and 7↔13 swapped vs LSP spec
- LSP call hierarchy bugs: wrong method name, missing `callHierarchy` client capability, `character:0` pointing at `let` keyword instead of function name token
- Timeout in `runner.ml` discarded already-collected function rows

## [0.1.0] - 2026-06-25

### Added
- Initial release extracted from epure
- Sound ⊤-marked call-graph index for Go (go/ssa + CHA) and OCaml (cmt typedtree)
- `arch-index` CLI: build symbol + call-graph database from source
- `arch-query` CLI: query reachability (reaches/unreachable/callers-of/fan-in/exported/find/escapes)
- Three-verdict reachability: REACHABLE / UNKNOWN: MAY_TOP / UNREACHABLE: no path
- Standalone dune project + arch-index.opam
