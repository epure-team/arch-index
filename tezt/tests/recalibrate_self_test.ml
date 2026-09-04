(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Runs [scripts/recalibrate.sh --self-test] as part of the suite.

    The script is an 875-line gate over two pinned constants — the self-index
    golden and [must_null_ceiling]'s [clean_measured] — and until this test it
    was wired to NOTHING: no CI step invoked it, no dune rule ran it, and
    `grep -rn recalibrate --include=*.yml --include=dune --include=Makefile`
    returned no hit outside the script itself. A gate nobody invokes cannot
    gate anything, and it is why six rounds of review on that file moved no
    existing test: there was no test to move.

    [--self-test] is the half that needs neither a build nor repository state —
    it drives the script's pure decisions (the pin readers, the 2x2
    classification, the well-formedness, adequacy and plausibility gates, the
    ratchet band, the write-verification) against temp fixtures, in well under
    a second. The measuring half needs two pristine worktrees and four indexing
    runs, which belongs in CI's [--check] step, not here.

    Why this is a real check and not decoration: every one of the script's pure
    decisions is mutation-tested. Fourteen mutants — including all seven that
    survived review round 6 — were applied to the script and each was observed
    to turn this test RED. A green here is therefore evidence about the script,
    not about the harness. *)

open Arch_tezt

let register () =
  Test.register ~__FILE__ ~title:"recalibrate.sh --self-test passes"
    ~tags:["scripts"; "recalibrate"; "selftest"]
  @@ fun () ->
  let script = Filename.concat (repo_root ()) "scripts/recalibrate.sh" in
  if not (Sys.file_exists script) then
    Test.fail "%s does not exist — the recalibration gate has moved or been deleted" script ;
  let code, output = run_command "bash" [script; "--self-test"] in
  if code <> 0 then
    Test.fail "recalibrate.sh --self-test exited %d:\n%s" code output ;
  (* Exit 0 alone is not enough. The script reports per-case results and returns
     1 on any failure, but a --self-test that silently stopped running cases
     would also exit 0 — the shape §10.6 calls "a check that looks like a
     check", and the shape this very script shipped when metric_well_formed had
     no coverage and stubbing it to `return 0` still printed "all cases pass".
     So assert the summary line AND a floor on the number of cases actually
     reported, so a self-test that degrades to running nothing fails here. *)
  if not (contains ~needle:"self-test: all cases pass" output) then
    Test.fail "recalibrate.sh --self-test did not report 'all cases pass':\n%s" output ;
  let cases =
    String.split_on_char '\n' output
    |> List.filter (fun l ->
           String.length l > 6 && String.sub l 0 7 = "  ok   ")
    |> List.length
  in
  (* 104 cases at the time of writing. The floor is deliberately well below it,
     so ordinary additions do not demand an edit here, while a self-test that
     collapses to a handful of cases still fails. *)
  if cases < 80 then
    Test.fail
      "recalibrate.sh --self-test reported only %d passing cases (floor 80) — it looks like it \
       stopped running most of them rather than passing them:\n\
       %s"
      cases output ;
  Lwt.return_unit
