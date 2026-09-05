(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Ratchet — whole-repository MUST-with-NULL-callee ceiling.

    Migrated from the standalone `checks/no-must-null-regression.js` script
    into the tezt suite (roadmap item 0.2's follow-up) so it runs under
    `dune test` like every other invariant here, rather than as a disconnected
    Node runtime invisible to `dune build`/`dune test`.

    Guards review finding arch_index.ml:359 (CRITICAL) at the scale the
    fixture-based [Nested_module_qualification] test cannot reach.

    A [calls] row with kind='MUST' and callee_id IS NULL is read downstream as
    a PROVEN external leaf: [arch_graph.ml] turns it into an "ext:" node and
    emits no TOP frontier marker. So every resolver miss that lands in that
    shape becomes a confident false UNREACHABLE for the real callee. Round 1
    of sound-qualified-name-resolution raised the count on this very
    repository from 1975 to 2557 — 582 previously-resolved edges dropped —
    and the whole tezt suite stayed green, because every fixture reference had
    the shape [Wrapper.File.value].

    [ceiling] is main's measured count plus [headroom]. The invariant is
    one-directional: the count may fall (that is a resolution gain), never
    rise past [ceiling]. When it falls a long way, lower [clean_measured] in
    the same commit so the ratchet keeps its teeth; a [Log.warn] below does
    that check automatically. [headroom] absorbs ordinary future growth of
    this shape without demanding a recalibration commit for every unrelated
    PR; it is not slack for a real regression — a rise that exceeds it still
    fails.

    Recalibrated three times, and once re-scoped, on 2026-09-01/02. First
    (item 0.2, wiring this ratchet into CI): the original baseline of 1975
    predated six commits' worth of ordinary growth on main (#37 fix, the
    dropped-node MAY_TOP fix, tools/, new tezt suites) — re-measured clean at
    2015 (a dirty working tree had first inflated this to 2024 — see review
    round 1 of wire-checks-into-ci). Second, migrating the ratchet itself
    from a standalone `checks/*.js` script into this tezt test: doing so adds
    this file and [nested_module_qualification.ml] to the very corpus the
    ratchet measures, raising the clean count again.

    Third — a re-scope, not just a recalibration (review cycle 2 round 1):
    the un-scoped [MUST]-with-NULL-callee count was ~87% calls into Stdlib
    (`Stdlib.Printf.sprintf`, `Stdlib.&&`, `Stdlib.ref`, …), which can never
    be anything BUT an external leaf — Stdlib is never part of this index, so
    its presence here carries zero signal about a resolver miss. Worse, that
    noise consumed nearly all of [headroom]: this migration's own two new
    files added 45 rows against a headroom of 25, entirely from ordinary
    Stdlib usage in test helper code, not from anything the ratchet exists to
    catch. Excluding `Stdlib.%%` callees turns the ceiling back into a signal:
    ~87% of the noise drops out, and the remaining rows are calls into other
    opam-dependency libraries (`Sqlite3.*`, `Yojson.*`, `Unix.*`,
    `Caqti_*`) that carry the same "never in this index" property, plus a
    genuinely interesting residual of in-repo cross-module references (e.g.
    `Arch_tezt.Temp.file`) that a future ratchet iteration could investigate
    — out of this task's scope; filed as a note here rather than pursued.

    Measured via, on the same clean checkout:

      git worktree add --detach /tmp/clean <sha> && cd /tmp/clean \
        && dune build && dune test --force
      => calls=9406  MUST-with-NULL-callee (unscoped)=2060
         MUST-with-NULL-callee (Stdlib excluded)=260

    The Stdlib-excluded count is diffuse, not a localized resolver
    regression: on the same checkout, the per-module breakdown spans 44
    modules, with no single module holding more than ~9% of the total
    (24 / 260). Reproducible via:

      SELECT m.path, count( * ) FROM calls c
      JOIN functions f ON f.id = c.caller_id
      JOIN modules m ON m.id = f.module_id
      WHERE c.kind = 'MUST' AND c.callee_id IS NULL AND c.callee_name NOT LIKE 'Stdlib.%'
      GROUP BY m.path ORDER BY 2 DESC;

    Runs against this repository's OWN [_build/default] — the widest, most
    varied OCaml index available without a network. *)

open Arch_tezt

(* Stdlib is never part of this index, so a MUST-with-NULL-callee row naming
   it carries zero signal about a resolver miss — see the recalibration note
   above. Excluding it is what makes [ceiling] a signal rather than noise. *)
let must_null_query =
  "SELECT count(*) FROM calls WHERE kind = 'MUST' AND callee_id IS NULL AND callee_name NOT \
   LIKE 'Stdlib.%'"

(* Recalibrated 2026-09-03 (feat/exn-raise-sets): 260 → 289. The +29 rows are
   the new [lib/arch_index/arch_index_exn.ml]'s calls into compiler-libs
   ([Ident.*], [Path.*], [Types.get_desc], [Predef.*]) and [Tast_iterator] —
   genuine external leaves of the same class as the existing rows, measured
   on the branch's clean tree (self-index: 20 modules / 527 functions).

   Recalibrated again 2026-09-03 (feat/coverage-matrix): 289 → 321. The +32
   rows are calls from the new [lib/arch_index/coverage_matrix.ml] (roadmap
   1.3) into [Sys.*]/[Filename.*]/[Unix.*]/[Sqlite3.*] plus the intervening
   provenance-columns and language-universe tasks' own additions since the
   prior recalibration — genuine external leaves of the same class, not a
   new unsound edge kind. *)
(* Recalibrated 2026-09-04 (feat/coverage-error-channels): 321 -> 345, in two
   attributable parts.

   +19 is DRIFT ALREADY ON MAIN. Error channels (#60) landed without
   recalibrating this constant, so main at 7fcf3c0 measures 340 against a
   constant of 321. The gate still passed, which is exactly why it went
   unnoticed: the change quietly spent 19 of the 25 headroom and left 6 for
   everyone after it, and this ratchet's own note above says headroom "is not
   slack for a real regression". Caught by the roadmap session while measuring
   main to attribute its own delta; recorded here rather than absorbed
   silently, because a ratchet that swallows one change's drift into the next
   one's baseline has stopped ratcheting.

   +5 is this branch: three Sqlite3.prepare/step/finalize calls from
   coverage_matrix.ml's read-only contract probe, and two Arch_tezt.Check.option
   calls from its tezt. Verified to be the same class as the existing rows and
   not a new unsound edge kind — the 340 on main are dominated by Sqlite3 (117),
   Arch_tezt (80), Eio (31) and Unix (24), all genuine external leaves.

   Measured on the whole repo _build/default, which is what this test indexes —
   not lib/arch_index alone, which reads 142 and is a different metric. *)
(* Recalibrated 2026-09-05 (fix/coverage-matrix-root-boundary, PR #83): 347 ->
   367, in three separately-sourced parts. Three, not one total: a single
   number here would make this branch look like a 20-row change, and the
   largest part of it is not this branch's at all.

   +11 is DRIFT ALREADY ON MAIN, and this is the SECOND documented occurrence
   — see the 2026-09-04 entry directly above, which caught the same miss and
   said in its own words why it must not be absorbed: "a ratchet that swallows
   one change's drift into the next one's baseline has stopped ratcheting".
   Main at ba2804a measures 358 against a constant of 347. Measured twice
   independently: once by the roadmap session on a clean detached worktree with
   a completed full build, and once here, where scripts/recalibrate.sh --check
   reports 358 in BOTH base-source cells (A = base bin/base src, B = new
   bin/base src) of its 2x2. The gate passed throughout, which is again exactly
   why it went unnoticed: the intervening work spent 11 of the 25 headroom and
   left 14. Recorded as MAIN's, not as this PR's.

   +6 is this branch's production change: the dune-project sentinel added to
   find_upwards and find_repo_root_from in lib/arch_index/coverage_matrix.ml
   (358 -> 364, measured at 77ff462). Two Filename.concat + Sys.file_exists
   pairs, external leaves of the same class as every other row here, not a new
   unsound edge kind.

   +3 is this branch's new tezt test
   (register_find_sibling_tool_stops_at_dune_project_build_candidate, 364 ->
   367): Arch_tezt/Sys calls from one more boundary fixture.

   367 is what main will measure once this PR lands, which is the only value
   this constant is allowed to take — it is main's measured count by this
   file's own opening sentence, so it may not include work that is not in this
   branch. It deliberately does NOT account for dev-13's in-flight
   feat/mutation-campaign-313, which measures 373 on its own tree; that branch
   is inside 367 + 25 = 392 and needs no adjustment here, but a later reader
   comparing the two numbers should not have to re-derive why they differ.

   Measured on the whole repo _build/default, the same corpus as every entry
   above. *)
(* Recalibrated 2026-09-05, later the same day: 367 -> 382. THE WHOLE OF IT IS
   MAIN'S OWN UNDECLARED DRIFT, and this is the THIRD documented occurrence.
   Nothing in this commit changes a line of production code.

   Five PRs merged after #83 set the pin at 367 — #81 (sarif ingest), #79
   (schema-drift refusal), #82 (option phantom origins), #85 (the exported:
   selector), and #83 itself — and not one of them re-ran the ceiling check
   afterwards. The deletion checks were run before and after every merge; this
   one was not run at all. So the constant read 367 while main climbed to 382,
   and the gate spent 15 of its 25 headroom in an afternoon, leaving 10 for
   whoever came next. That is precisely the failure the 2026-09-04 entry
   describes, committed by the session that quoted that entry at two other
   sessions the same morning.

   Measured twice, independently, on main at 8260ad9: once by dev-13 while
   attributing their own branch's delta, and once here on a clean detached
   worktree with a completed full build, where scripts/recalibrate.sh --check
   reports 382 in ALL FOUR cells of its 2x2 (A = B = C = D), so it is not a
   tooling artefact.

   NOT attributed per merge. The aggregate is measured; which of the five
   contributed what is not, and a bisect was not run. The likeliest single
   source is #79, whose four top-level handlers add Arch_db calls in four
   binaries, but that is a guess and this comment does not claim it.

   382 is main's measured count at 8260ad9 and this commit contains nothing
   else, so the constant may take it. It deliberately does NOT account for
   dev-13's feat/mutation-campaign-313, which measures 399 on its own tree:
   that branch is inside 382 + 25 = 407 with 8 to spare and needs no
   recalibration of its own. Its own +17 decomposes as 12 inert Sqlite3.* rows
   from a new file and 5 Arch_tezt.Temp.* rows that DO carry signal — that
   separation belongs in that branch's ledger and must not be hidden behind
   this recalibration. *)

(* 382 -> 383, and the +1 is ONE NAMED ROW, not a delta:

     tezt/tests/flat_exported_selector.ml:rule_file -> Arch_tezt.Temp.file

   That file is new in this branch; its [rule_file] helper calls [Temp.file], which lives in a
   different library and so resolves to no [callee_id] — a MUST edge with a NULL callee, which
   is exactly what this metric counts. Inert: it is a test helper writing a temp file, carrying
   no signal about the indexed code.

   Attributed by DIFFING THE ROW SETS between main and this branch, not by subtracting counts.
   The first attempt used a baseline tree one commit behind main and showed TWO differences —
   this row, plus [must_null_ceiling.ml:register.<fun:224:6>] appearing as [<fun:257:6>]. The
   second is not a row at all: it is the same edge renamed, because a lambda's identity encodes
   its LINE, and the recalibration above moved every line in this file. Counting would have
   netted the two to +1 and looked right for the wrong reason; re-measured against the tree that
   exists, there is one difference and it is the new one. *)
(* NOT recalibrated by feat/escaping-origins-exported (PR #88): the delta is ZERO,
   and this note exists so that zero can be told apart from "nobody measured".

   383 is unchanged from the entry directly above. Evidence, in the order that
   makes the zero decidable:

   - [scripts/recalibrate.sh --explain] against merge-base 4e74c72 reports 383 in
     ALL FOUR cells (A = B = C = D), so both the source delta (C - A) and the
     behaviour delta (B - A) are 0 — this branch changes production code in
     [bin/arch_query/arch_query.ml], so B = A is a claim worth having, not a
     formality.
   - ROW-SET diff, not a count. Against 4e74c72 the branch adds zero rows and removes
     zero. The one textual difference in the whole 383 is a RENAME, and it is this
     note's own doing: the [Arch_tezt.Log.info] call inside [register]'s nested
     lambda below carries a position-encoded name, so inserting prose above it
     changes its identity without changing anything about the code. A count alone
     would have read +0 whether that line were a rename or a real addition
     cancelling a real deletion — which is why the diff is over the row SET.
     Deliberately cited by BINDING rather than by [<fun:LINE:COL>]: quoting the
     coordinates would put a number here that this very comment's length decides,
     and it would be wrong again after the next word added above it.

   The PRESENCE PREMISE, because a metric that never saw the new code reports zero
   exactly like a metric that saw it and found nothing: [escaping_origins_exported.ml]
   IS in the index (18 functions, 73 calls). It contributes 13 MUST-with-NULL rows
   and every one is excluded by name — [Stdlib.Printf.sprintf] x7, [Stdlib.>=] x3,
   [Stdlib.not] x2, [Stdlib.<>] x1.

   The CONTROL that proves a new test file's row would have been counted: the row
   this metric gained from #87's new file — [flat_exported_selector.ml:rule_file ->
   Arch_tezt.Temp.file] — is present in this branch's own measurement. The
   difference between the two files is mechanical, not lucky: #87's helper reaches
   a cross-library [Temp.file], this branch's fixture never leaves [Stdlib]. *)
let clean_measured = 383

let headroom = 25

(* A conservative floor on the TOTAL call count (not just the Stdlib-excluded
   ceiling metric): an under-built [_build/default] indexes fewer calls
   across the board, which would otherwise read as a comfortable pass on the
   ceiling rather than as "nothing was measured". Set well below the clean
   measurement to tolerate ordinary future growth without becoming its own
   recalibration treadmill.

   The clean total was 9406 when this floor was set and is 12980 today — a
   pre-existing drift, corrected here rather than left standing. A number in a
   comment is a measurement with no harness: nothing fails when it goes stale,
   so it is asserted once by someone who had just measured it and then read as
   evidence by people who cannot check it. Reproduce by counting every row of
   [calls] in a database indexed over this repository's own [_build/default]. *)
let min_total_calls = 8000

(* A merely positive headroom (e.g. 1) would satisfy a naive "> 0" check while
   still reproducing the exact failure mode this ratchet guards: the gate
   firing on the very next unrelated call site. Require a floor proportional
   to [clean_measured] instead of a bare positivity check. *)
let min_headroom_fraction = 0.01

let ceiling = clean_measured + headroom

(* The repo's own [_build/default] — not a per-test throwaway fixture. Mirrors
   how [callgraph_ocaml ()] itself is located: it resolves to
   [<repo-build-default>/bin/arch_callgraph_ocaml/arch_callgraph_ocaml.exe],
   so stripping the same three path components off it gives
   [<repo-build-default>] without introducing a second search.

   This derivation follows [ARCH_CALLGRAPH_OCAML] when it is set, same as
   [callgraph_ocaml ()] itself — an override pointing at a binary outside this
   tree would otherwise silently measure an unrelated directory. Guard against
   that: [clean_measured]/[ceiling] are meaningful only for THIS repository,
   so assert the derived directory actually looks like this repository's own
   build output before indexing it. *)
let repo_build_default () =
  let dir = Filename.dirname (Filename.dirname (Filename.dirname (callgraph_ocaml ()))) in
  let marker = Filename.concat dir "lib/arch_index/.arch_index.objs/byte/arch_index.cmi" in
  if not (Sys.file_exists marker) then
    Test.fail
      "repo_build_default resolved to %s, which does not look like this repository's own \
       _build/default (missing %s) — is ARCH_CALLGRAPH_OCAML pointing outside this tree?"
      dir marker ;
  dir

let index_repo () =
  let db = temp_db "must-null-ceiling" in
  let code, output =
    run_command (callgraph_ocaml ())
      ["--build-dir"; repo_build_default (); "--db-path"; db; "--schema-path"; schema ()]
  in
  if code <> 0 then Test.fail "indexing %s failed (exit %d):\n%s" (repo_build_default ()) code output ;
  db

let register () =
  Test.register ~__FILE__
    ~title:"cmt: the whole-repo MUST-with-NULL-callee count stays under its ceiling"
    ~tags:["cmt"; "soundness"; "ratchet"]
  @@ fun () ->
  let min_headroom = int_of_float (ceil (float_of_int clean_measured *. min_headroom_fraction)) in
  if headroom < min_headroom then
    Test.fail
      "ratchet headroom (%d) is below the minimum meaningful floor (%d = %.0f%% of \
       clean_measured=%d) — a headroom this small still fires on the next unrelated call site, \
       which is exactly the bug this ratchet guards against"
      headroom min_headroom (min_headroom_fraction *. 100.) clean_measured ;
  let db = index_repo () in
  Db.with_db db (fun conn ->
      let total = Db.int conn "SELECT count(*) FROM calls" in
      if total = 0 then Test.fail "the index has no calls at all — nothing was measured" ;
      if total < min_total_calls then
        Test.fail
          "only %d calls were indexed, below the floor of %d — _build/default looks under-built \
           (run `dune build` for the whole project, not a partial target) rather than genuinely \
           reflecting a shrunk codebase"
          total min_total_calls ;
      let must_null = Db.int conn must_null_query in
      Log.info "calls=%d  MUST-with-NULL-callee(Stdlib excluded)=%d  ceiling=%d" total must_null
        ceiling ;
      if must_null > ceiling then
        Test.fail
          "%d calls rows are kind=MUST with callee_id IS NULL (Stdlib excluded), above the \
           ceiling of %d (+%d). Each one is a resolver miss stamped as a proven external leaf: \
           arch_graph.ml emits no TOP marker for it, so the real callee is reported UNREACHABLE \
           with confidence. Either resolve those references or emit them as MAY_TOP so the TOP \
           frontier survives."
          must_null ceiling (must_null - ceiling) ;
      (* Enforce the tightening half of the one-directional invariant: advisory
         only, never a failure. *)
      if must_null < clean_measured - headroom then
        Log.warn
          "MUST-with-NULL-callee (%d) has fallen well below clean_measured (%d). Consider \
           lowering clean_measured in this commit so the ratchet keeps its teeth."
          must_null clean_measured) ;
  Lwt.return_unit
