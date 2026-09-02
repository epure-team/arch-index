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

    Recalibrated twice on 2026-09-01/02. First (item 0.2, wiring this ratchet
    into CI): the original baseline of 1975 predated six commits' worth of
    ordinary growth on main (#37 fix, the dropped-node MAY_TOP fix, tools/,
    new tezt suites) — re-measured clean at 2015 (a dirty working tree had
    first inflated this to 2024 — see review round 1 of wire-checks-into-ci).
    Second, migrating the ratchet itself from a standalone `checks/*.js`
    script into this tezt test: doing so adds this file and
    [nested_module_qualification.ml] to the very corpus the ratchet measures,
    which raised the clean count again. Measured via:

      git worktree add --detach /tmp/clean <sha> && cd /tmp/clean \
        && dune build && dune test --force
      => calls=9406  MUST-with-NULL-callee=2060  (before headroom)

    The clean-checkout count is diffuse, not a localized resolver regression:
    on the same checkout, the per-module breakdown spans 71 modules, with no
    single module holding more than ~7% of the total (144 / 2060).
    Reproducible via:

      SELECT m.path, count( * ) FROM calls c
      JOIN functions f ON f.id = c.caller_id
      JOIN modules m ON m.id = f.module_id
      WHERE c.kind = 'MUST' AND c.callee_id IS NULL
      GROUP BY m.path ORDER BY 2 DESC;

    Runs against this repository's OWN [_build/default] — the widest, most
    varied OCaml index available without a network. *)

open Arch_tezt

let clean_measured = 2060

let headroom = 25

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
   [<repo-build-default>] without introducing a second search. *)
let repo_build_default () =
  Filename.dirname (Filename.dirname (Filename.dirname (callgraph_ocaml ())))

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
      let must_null =
        Db.int conn "SELECT count(*) FROM calls WHERE kind = 'MUST' AND callee_id IS NULL"
      in
      Log.info "calls=%d  MUST-with-NULL-callee=%d  ceiling=%d" total must_null ceiling ;
      if must_null > ceiling then
        Test.fail
          "%d calls rows are kind=MUST with callee_id IS NULL, above the ceiling of %d (+%d). \
           Each one is a resolver miss stamped as a proven external leaf: arch_graph.ml emits no \
           TOP marker for it, so the real callee is reported UNREACHABLE with confidence. Either \
           resolve those references or emit them as MAY_TOP so the TOP frontier survives."
          must_null ceiling (must_null - ceiling) ;
      (* Enforce the tightening half of the one-directional invariant: advisory
         only, never a failure. *)
      if must_null < clean_measured - headroom then
        Log.warn
          "MUST-with-NULL-callee (%d) has fallen well below clean_measured (%d). Consider \
           lowering clean_measured in this commit so the ratchet keeps its teeth."
          must_null clean_measured) ;
  Lwt.return_unit
