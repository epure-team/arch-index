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
   on the branch's clean tree (self-index: 20 modules / 527 functions). *)
let clean_measured = 289

let headroom = 25

(* A conservative floor on the TOTAL call count (not just the Stdlib-excluded
   ceiling metric): an under-built [_build/default] indexes fewer calls
   across the board, which would otherwise read as a comfortable pass on the
   ceiling rather than as "nothing was measured". Set well below the clean
   measurement (9406) to tolerate ordinary future growth without becoming its
   own recalibration treadmill. *)
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
