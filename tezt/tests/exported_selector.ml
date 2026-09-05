(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [exported:<glob>] — the API-surface selector, and the position it may not occupy.

    {1 Why the kind exists}

    [forbid reach] has always had a [from] nobody can write correctly at repository scale.
    "Does any entry point reach this function" is the question a reachability gate is for —
    it is what vulnerability triage asks of a CVE symbol, and what a blast-radius review asks
    of a refactor — and until now the only way to spell it was to enumerate file globs by
    hand and hope the list stayed complete. [functions.exposed] has carried the answer since
    the beginning, with its own index, read by nothing that selects.

    {1 The hazard this file is really about}

    A selector answerable in ONE position, accepted in another, does not fail loudly. It
    matches a population that position never ranges over, comes back empty, and the empty
    result is reported as a PROOF rather than as vacuity. [ext:]'s own comment in
    {!module:Arch_sel} documents this against itself, and it was MEASURED on this repository:
    [forbid dep from module:src/** to file:bar] printed "1 proved".

    [exported:] carries the mirror of that hazard, so the tests below assert the REFUSAL as
    well as the result. A test that only exercises the position where a kind works cannot
    distinguish a granted kind from a kind granted everywhere.

    {1 Red-capability, verified by hand rather than asserted here}

    Widening [dep_allow] to include [Exported] makes the refused rule parse and report a
    verdict — so {!register_refused_in_dep} is red-capable, and its green means the grant is
    per-position rather than global. That mutation is recorded in the commit message; it is
    not performed here, because a test that edits the tool it tests measures the edit. *)

open Arch_tezt

let rules args = run_command (arch_rules ()) args

let rule_file name contents =
  let path = Temp.file (name ^ ".rules") in
  write_file path contents ;
  path

(* [es_api.mli] is what makes this fixture discriminate: [entry] appears in it and is
   therefore [exposed = 1]; [hidden] does not and is [exposed = 0].

   The reachability is deliberately INVERTED against the exposure — the UNEXPORTED function
   is the one that reaches the target. A fixture where the exported function reaches it
   cannot tell [exported:**] from [fn:**]: both would report VIOLATION and the filter would
   be unobservable. *)
let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name es_fixture)\n\
      \ (wrapped false)\n\
      \ (modules es_api es_vuln)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ("es_vuln.ml", "let danger n = n + 1\n");
    ( "es_api.ml",
      {|let hidden n = Es_vuln.danger n

let entry n = n * 2
|} );
    ("es_api.mli", "val entry : int -> int\n");
  ]

let with_indexed name f =
  with_fixture ~name ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db name in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  f db

(* Assert on the SUMMARY COUNTS, not on a verdict word.

   The first version of this file checked [contains "VIOLATION"], and its premise failed
   against correct behaviour: [arch-rules] prints [[ FAIL  ]] per rule and counts them
   lowercase in the summary — the token [VIOLATION] appears in the source and never in the
   output. A needle that cannot occur turns every "the bad thing is absent" assertion into a
   tautology, which is the same instrument-never-switched-on failure this suite has hit
   before. The summary line is the tool's own tally and cannot be satisfied by accident. *)
let summary out =
  String.split_on_char '\n' out
  |> List.find_opt (fun l -> contains ~needle:"rule(s):" l)
  |> Option.value ~default:"(no summary line in output)"

let register_filters () =
  Test.register ~__FILE__
    ~title:"exported selector: exported:** is fn:** restricted to the API surface"
    ~tags:["rules"; "reach"; "selector"; "exported"]
  @@ fun () ->
  with_indexed "es_filter" @@ fun db ->
  Batch.run (fun b ->
      (* PREMISE 1 — the fixture really splits the population. Without both numbers the
         assertions below cannot distinguish a working filter from a selector that matches
         everything, or from one that matches nothing. *)
      let exposed_n =
        Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM functions WHERE exposed = 1")
      in
      let unexposed_n =
        Db.with_db db (fun c ->
            Db.int c "SELECT count(*) FROM functions WHERE COALESCE(exposed,0) = 0")
      in
      Batch.eq_int b ~msg:"premise: exactly one function is on the API surface" exposed_n 1 ;
      Batch.check b
        ~msg:(Printf.sprintf "premise: at least one function is NOT (got %d)" unexposed_n)
        (unexposed_n >= 1) ;
      (* PREMISE 2 — the target is reachable AT ALL. This is what stops the assertion below
         from being the vacuous kind: a rule reporting "not reached" over a graph where
         nothing reaches anything is a statement about the fixture, not about the filter. *)
      let _, wide =
        rules
          [ db;
            rule_file "es_wide"
              "rule \"reaches danger\"\n  forbid reach from fn:** to fn:danger\n" ]
      in
      Batch.check b
        ~msg:(Printf.sprintf "premise: SOME function reaches danger — from fn:**:\n%s" wide)
        (contains ~needle:"1 violation" (summary wide)) ;
      (* THE ASSERTION. The one exported function does NOT reach danger; the unexported one
         does. So restricting the source to the API surface must change the verdict. If
         [exported:] silently selected every node this would read VIOLATION, identically to
         the premise above. *)
      let _, narrow =
        rules
          [ db;
            rule_file "es_narrow"
              "rule \"reaches danger\"\n  forbid reach from exported:** to fn:danger\n" ]
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "no ENTRY POINT reaches danger, so the rule must not be violated:\n%s" narrow)
        (contains ~needle:"0 violation" (summary narrow)) ;
      (* And it must not be the OTHER kind of empty answer either: a selector matching
         nothing reports NO_SOURCE, which is vacuity, not a filtered result. The two are
         indistinguishable from "not VIOLATION" alone. *)
      (* …and it is a real cone, not an empty selector. An [exported:] that matched nothing
         would also report "0 violation" — as VACUOUS, which is the tool's word for "this rule
         quantified over nothing". Without this line the assertion above passes for a selector
         that is simply broken. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and it is not vacuous — the source cone is non-empty:\n%s" narrow)
        (contains ~needle:"0 vacuous" (summary narrow)) ;
      (* No unconditional [Batch.note] here. It is not an informational logger: it appends to
         the SAME failure list [check] does, so a note that always runs fails the test with its
         own text. It is for adding context inside an [if] that has already failed. Both
         assertions above therefore carry the full output in their own message instead. *)
      ()) ;
  Lwt.return_unit

let register_refused_in_dep () =
  Test.register ~__FILE__
    ~title:"exported selector: refused in a position that cannot answer it"
    ~tags:["rules"; "reach"; "selector"; "exported"; "vacuity"]
  @@ fun () ->
  with_indexed "es_refuse" @@ fun db ->
  (* [forbid dep] reads DECLARED MODULE PATHS from a table, not the call graph, so a
     function-level selector ranges over a population it never sees. The refusal must be at
     PARSE time and fatal — a verdict computed over an empty match is the false green this
     kind is guarded against. *)
  let code, out =
    rules
      [ db;
        rule_file "es_dep"
          "rule \"dep\"\n  forbid dep from exported:** to module:Es_vuln\n" ]
  in
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:(Printf.sprintf "an exported: operand in forbid dep must ABORT, not be evaluated:\n%s" out)
        code 2 ;
      (* The message must name the POSITION, not report an unknown kind: `exported:` IS a
         selector kind, and "expected module" would send the author hunting a typo that is
         not there. Same distinction Arch_sel already draws for `ext:`. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and says the kind is not valid HERE, not that it is unknown:\n%s" out)
        (contains ~needle:"not valid in this position" out) ;
      (* No verdict may be printed for a rule that was refused. A parse that aborts but still
         emits a line is how a refused rule ends up counted as a pass by a consumer reading
         the summary rather than the exit code. *)
      (* No verdict tally may be printed for a refused rule. A parse that aborts but still
         emits a summary is how a refused rule gets counted as a pass by a consumer reading
         the summary rather than the exit code. *)
      Batch.check b
        ~msg:(Printf.sprintf "…and prints no verdict summary for the refused rule:\n%s" out)
        (not (contains ~needle:"rule(s):" out))) ;
  Lwt.return_unit

(* EVERY POSITION THE PARSER HAS, not just the one that works and the one I thought of.

   A review pointed out that the refusal evidence covered ONE direction. [ext:] is answerable
   only as a TARGET and proves nothing as a source; [exported:] has the mirror symmetry, so a
   TARGET-position [exported:] is the same hazard on the side nobody was watching. "I only
   granted it in one place" is a statement about the code I wrote, not about the parser — six
   other operand positions exist and each reads its own allow-list.

   Each row carries a CONTROL: the same rule body with [fn:] substituted. Without it an exit 2
   is not evidence about the selector at all. Measured while writing this: my first sweep
   scored [forbid origin from exported:**] as a refusal, and the control showed BOTH spellings
   failing with "unrecognised rule body" — the probe had omitted the mandatory [allow-file:]
   clause, so the rule never reached selector parsing. An exit code for the wrong reason looks
   exactly like an exit code for the right one. *)
let positions =
  [
    ("reach TARGET", "forbid reach from fn:** to %s");
    ("dep source", "forbid dep from %s to module:Es_vuln");
    ("dep TARGET", "forbid dep from module:Es_api to %s");
    ("exported-outside operand", "forbid exported outside %s");
    ("effect source", "forbid effect from %s kind:GlobalVar");
  ]

let register_position_sweep () =
  Test.register ~__FILE__
    ~title:"exported selector: accepted in exactly ONE position, refused in every other"
    ~tags:["rules"; "reach"; "selector"; "exported"; "vacuity"]
  @@ fun () ->
  with_indexed "es_sweep" @@ fun db ->
  let allow = Temp.file "es_sweep.allow" in
  write_file allow "" ;
  let origin_body sel =
    Printf.sprintf "forbid origin from %s form:division allow-file:%s" sel allow
  in
  let run body =
    rules [ db; rule_file "es_sweep" (Printf.sprintf "rule \"p\"\n  %s\n" body) ]
  in
  Batch.run (fun b ->
      let check_position (label, tmpl) =
        let body sel = Printf.sprintf (Scanf.format_from_string tmpl "%s") sel in
        (* CONTROL FIRST. If the `fn:` spelling does not parse, the rule FORM is malformed and
           the refusal below says nothing about the selector kind. *)
        let _, ctrl = run (body "fn:**") in
        Batch.check b
          ~msg:
            (Printf.sprintf "control [%s]: the same body with fn: must parse, or the refusal \
                             below is about the rule form:\n%s" label ctrl)
          (not (contains ~needle:"unrecognised rule body" ctrl)) ;
        let code, out = run (body "exported:**") in
        Batch.eq_int b
          ~msg:(Printf.sprintf "[%s] must ABORT on exported:\n%s" label out) code 2 ;
        Batch.check b
          ~msg:
            (Printf.sprintf "[%s] must refuse for the POSITION, not as an unknown kind or a \
                             malformed body:\n%s" label out)
          (contains ~needle:"not valid in this position" out) ;
        Batch.check b
          ~msg:(Printf.sprintf "[%s] must print no verdict summary:\n%s" label out)
          (not (contains ~needle:"rule(s):" out))
      in
      List.iter check_position positions ;
      (* `forbid origin` is spelled out rather than templated because its body carries a
         mandatory allow-file: clause — the very thing whose omission made my first probe
         wrong. *)
      let _, octrl = run (origin_body "fn:**") in
      Batch.check b
        ~msg:(Printf.sprintf "control [origin source]: the fn: spelling must parse:\n%s" octrl)
        (not (contains ~needle:"unrecognised rule body" octrl)) ;
      let ocode, oout = run (origin_body "exported:**") in
      Batch.eq_int b ~msg:(Printf.sprintf "[origin source] must ABORT:\n%s" oout) ocode 2 ;
      Batch.check b
        ~msg:(Printf.sprintf "[origin source] must refuse for the POSITION:\n%s" oout)
        (contains ~needle:"not valid in this position" oout) ;
      (* THE OTHER HALF, and the reason this is one test rather than six: the sweep must also
         show that SOME position accepts the kind. Six refusals alone are equally consistent
         with a selector nothing accepts anywhere — which would refuse in every position and
         pass this test while being useless. *)
      let acode, aout = run "forbid reach from exported:** to fn:danger" in
      Batch.eq_int b
        ~msg:(Printf.sprintf "the granted position must still work — exit 0:\n%s" aout) acode 0 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and produce a real verdict, not a refusal:\n%s" aout)
        (contains ~needle:"rule(s):" aout)) ;
  Lwt.return_unit

let register () =
  register_filters () ;
  register_refused_in_dep () ;
  register_position_sweep ()
