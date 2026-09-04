(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Runs [scripts/recalibrate.sh --self-test] as part of the suite.

    The script is a gate over two pinned constants — the self-index
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
    decisions is mutation-tested. Mutants are applied to the script and each is
    observed to turn this test RED — including, in round 7, the five that had
    survived round 6's battery (F9, R5, R6, F8, F10) and the anchor mutants on
    both halves of the pin reader. A green here is therefore evidence about the
    script, not about the harness.

    A COUNT IS NOT A HARNESS. An earlier version of this comment said "104
    cases at the time of writing" when the script reported 108, and nothing
    re-ran the claim — §10.3's shape exactly, in the test that exists to
    enforce §10.6. Numbers that decay are kept out of this comment now: the
    only case count that appears anywhere here is the FLOOR asserted below,
    which is machine-checked on every run. *)

open Arch_tezt

let register () =
  Test.register ~__FILE__ ~title:"recalibrate.sh --self-test passes"
    ~tags:["scripts"; "recalibrate"; "selftest"]
  @@ fun () ->
  let script = Filename.concat (repo_root ()) "scripts/recalibrate.sh" in
  if not (Sys.file_exists script) then
    Test.fail "%s does not exist — the recalibration gate has moved or been deleted" script ;
  let code, output, stderr = run_command_split "bash" [script; "--self-test"] in
  if code <> 0 then
    Test.fail "recalibrate.sh --self-test exited %d:\nstdout:\n%s\nstderr:\n%s" code output
      stderr ;
  (* STDERR MUST BE EMPTY, and this is not tidiness.

     The script's own oracle ([chk]) compares captured stdout and never looks at
     stderr, so a decision reached by a bash ERROR rather than by a guard passes
     every case and prints "all cases pass". That is not hypothetical: round 8's
     HIGH-2 is exactly it. Deleting [is_int] from [pinned_degraded]'s ratchet arm
     leaves `[ "$pinned" -ge 1 ]` to judge '' / 'abc' / '1_000'; `[` fails on all
     three with "integer expression expected", the function returns the RIGHT
     answer for the WRONG reason, and four assertions that were written to kill
     that mutant go quietly inert. With the mutant applied the self-test emitted
     191 bytes to stderr and still exited 0.

     Asserting the stream closes that whole family at once, rather than one
     leading-zero input at a time -- and it is why [run_command_split] is used
     here instead of [run_command], which merges the two. *)
  if String.trim stderr <> "" then
    Test.fail
      "recalibrate.sh --self-test wrote %d byte(s) to stderr while exiting 0. A self-test whose \
       cases pass because bash ERRORED is not a passing self-test: the script's own oracle \
       compares stdout only, so an assertion can go inert without any case turning red.\n\
       stderr:\n\
       %s\n\
       stdout:\n\
       %s"
      (String.length stderr) stderr output ;
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
  (* The floor is deliberately well below the number of cases the script
     actually reports, so ordinary additions do not demand an edit here, while
     a self-test that collapses to a handful of cases still fails. It is the
     one number in this file that is enforced rather than asserted in prose,
     which is why no "N cases at the time of writing" appears beside it. *)
  if cases < 100 then
    Test.fail
      "recalibrate.sh --self-test reported only %d passing cases (floor 100) — it looks like it \
       stopped running most of them rather than passing them:\n\
       %s"
      cases output ;
  Lwt.return_unit

(* L5 — keep [GOLDEN_RAW] a check against CI, not a check against history.

   The script measures the golden twice on purpose, and review confirmed the
   differential is real rather than two spellings of one query: [metric_value]
   builds three lines from three separate [q()] calls and a printf, while
   [GOLDEN_RAW] is a single [sqlite3] invocation with three concatenating
   SELECTs — character-for-character the one in ci.yml's "Self-index smoke
   test" step. Folding them together would turn the comparison into [diff x x].

   But that differential is only worth anything while the transcription is
   FAITHFUL. Nothing re-read ci.yml, so the day someone edits the smoke test's
   SQL the script goes on comparing against the old spelling and silently
   decays from "a check against what CI does" into "a check against what CI
   used to do" — a detector that still passes and no longer detects. This
   pins it. *)

let read_file path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic ; s

(* Collapse whitespace and shell line-continuations so the two files' identical
   SQL compares equal despite living at different indentation. *)
let normalise s =
  let b = Buffer.create (String.length s) in
  let sp = ref false in
  String.iter
    (fun c ->
      match c with
      | ' ' | '\t' | '\n' | '\r' | '\\' -> sp := true
      | c ->
          if !sp && Buffer.length b > 0 then Buffer.add_char b ' ' ;
          sp := false ;
          Buffer.add_char b c)
    s ;
  Buffer.contents b

let register_golden_sql_transcription () =
  Test.register ~__FILE__
    ~title:"recalibrate.sh's raw golden query matches the one CI runs"
    ~tags:["scripts"; "recalibrate"; "golden"; "ci"]
  @@ fun () ->
  let root = repo_root () in
  let script = normalise (read_file (Filename.concat root "scripts/recalibrate.sh")) in
  let ci = normalise (read_file (Filename.concat root ".github/workflows/ci.yml")) in
  let fragments =
    [ "SELECT 'modules: ' || count(*) FROM modules;";
      "SELECT 'functions: ' || count(*) FROM functions;";
      "SELECT 'calls: ' || count(*) FROM calls;";
      (* The refusal-class contract, which is the identical script<->CI shape
         and was left out of this list when it was introduced. The script
         prints this exact token on an implausibility refusal and ci.yml
         branches on it; a divergence sends a refusal that MAY be a property of
         the branch down the "the gate is broken, not your branch" arm, or the
         reverse -- and, like the SQL above, nothing else re-reads either file.

         Both greps in ci.yml spell the token in full, deliberately: this
         assertion is what keeps them spelled the same as the script's.

         BE HONEST ABOUT WHICH HALF IS LOAD-BEARING. [contains] over the whole
         file cannot tell code from a comment, so the SCRIPT half of this check
         would be satisfied by a comment mentioning the token even if
         [refusal_class]'s [implausible)] arm were deleted. That half is
         redundant here rather than false: --self-test asserts the emitted line
         character-for-character (mutant RC1, which renames the arm so it falls
         to the catch-all, turns it RED), so what this list adds on top is the
         CI half -- that ci.yml still greps for the string the script proves it
         prints. Same for the SQL above, and it was always so. *)
      "refusal-class=implausible" ]
  in
  List.iter
    (fun frag ->
      if not (contains ~needle:frag ci) then
        Test.fail
          "The self-index smoke test in .github/workflows/ci.yml no longer contains %S.\n\
           scripts/recalibrate.sh transcribes CI's golden query so that --check compares the\n\
           artifact CI compares. If CI's SQL changed, change the script's to match — otherwise\n\
           the script silently keeps checking against the OLD query."
          frag ;
      if not (contains ~needle:frag script) then
        Test.fail
          "scripts/recalibrate.sh no longer contains %S, which .github/workflows/ci.yml still\n\
           runs. GOLDEN_RAW exists to reproduce CI's query exactly; a divergence here makes the\n\
           script's golden comparison a check against history rather than against CI."
          frag)
    fragments ;
  Lwt.return_unit
