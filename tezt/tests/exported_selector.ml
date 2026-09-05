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

    [exported:] does NOT carry the mirror of that hazard, and saying so precisely is half of
    what this file is for. Measured: admitted as a [forbid reach] TARGET, an [exported:] that
    matches something returns an EARNED proof, and one that matches nothing returns
    [1 vacuous], exit 1 — the framework already refuses to call it a proof. The refusal is a
    SCOPING decision: a kind is granted deliberately, per position, with tests, never inherited
    and never on borrowed soundness cover.

    The tests below therefore assert the REFUSAL as well as the result. A test that only
    exercises the position where a kind works cannot distinguish a granted kind from a kind
    granted everywhere.

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
    ("es_vuln.ml", "let danger n = n + 1\n\nlet danger2 n = n + 2\n");
    ( "es_api.ml",
      {|(* UNEXPORTED, and the only route to [danger]. *)
let hidden n = Es_vuln.danger n

(* EXPORTED and reaches nothing — the negative case. *)
let entry n = n * 2

(* EXPORTED and reaches [danger2] — the positive case. Without it every assertion about
   [exported:] in this file reads "0 violation", and a selector that matched the empty set
   would satisfy all of them. A feature needs one test where it CATCHES something. *)
let entry_bad n = Es_vuln.danger2 n
|} );
    ("es_api.mli", "val entry : int -> int\nval entry_bad : int -> int\n");
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
      Batch.eq_int b ~msg:"premise: exactly two functions are on the API surface" exposed_n 2 ;
      Batch.check b
        ~msg:(Printf.sprintf "premise: at least one function is NOT (got %d)" unexposed_n)
        (unexposed_n >= 1) ;
      (* PREMISE 2 — the target is reachable AT ALL, through a real CALL PATH.

         This used to read [from fn:** to fn:danger], and a review showed the violation came
         from SELECTOR OVERLAP rather than from any edge: [fn:**] contains [danger] itself, and
         [reach_verdict] unions [SS.inter src dst] into the MUST set, so the rule reports a
         violation on a graph with zero edges — precisely the situation this premise exists to
         rule out. [fn:hidden] is disjoint from the target, so the only way to a violation is
         the call [hidden] really makes. *)
      let _, wide =
        rules
          [ db;
            rule_file "es_wide"
              "rule \"reaches danger\"\n  forbid reach from fn:hidden to fn:danger\n" ]
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
      (* THE POSITIVE CASE, and the file had none. Every other assertion here is "0 violation":
         a selector matching the empty set satisfies all of them, so nothing showed the feature
         doing its job. [entry_bad] is exported and reaches [danger2] through a real call, so
         [exported:] must CATCH it. Green-to-red for the stated purpose, not only for the
         filter. *)
      let _, caught =
        rules
          [ db;
            rule_file "es_caught"
              "rule \"reaches danger\"\n  forbid reach from exported:** to fn:danger2\n" ]
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "an ENTRY POINT that really reaches the target must be caught through exported::\n%s"
             caught)
        (contains ~needle:"1 violation" (summary caught)) ;
      (* No unconditional [Batch.note] here. It is not an informational logger: it appends to
         the SAME failure list [check] does, so a note that always runs fails the test with its
         own text. It is for adding context inside an [if] that has already failed. Both
         assertions above therefore carry the full output in their own message instead. *)
      ()) ;
  Lwt.return_unit

let register_refused_in_dep () =
  Test.register ~__FILE__
    ~title:"exported selector: refused where it is not granted, before it can answer wrongly"
    ~tags:["rules"; "reach"; "selector"; "exported"; "vacuity"]
  @@ fun () ->
  with_indexed "es_refuse" @@ fun db ->
  (* [forbid dep] reads DECLARED MODULE PATHS from a table, not the call graph. The refusal
     must be at PARSE time and fatal, and the reason measured rather than assumed:

     - [Dep]'s evaluator never calls {!Arch_sel.select} AT ALL — it globs the pattern against
       [module_deps] rows, so the selector KIND is discarded and only the pattern survives.
     - Widening [dep_allow] to admit [Exported] and running this very fixture returns
       [1 proved], exit 0. The position does not fail to answer; it answers WRONGLY, over a
       rule that policed nothing.

     An earlier revision of this comment called it "a verdict computed over an empty match".
     The match is not empty — [source_size] is 2. The assertions below were right and
     red-capable throughout; only this rationale was invented. *)
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

   A review pointed out that the refusal evidence covered ONE direction, and the sweep it
   prompted refuted the reason it was asked for: a TARGET-position [exported:] is NOT the
   mirror of [ext:]'s source hazard (see this file's header). What survives is the reason that
   does not depend on it — "I only granted it in one place" is a statement about the code I
   wrote, not about the parser, and eight other operand positions exist, each reading its own
   allow-list.

   NINE positions, enumerated from the parser rather than from my own table — [arch-rules]'s
   seven operand positions plus [arch-coverage --roots] and [arch-mutants --tests], which call
   {!Arch_sel.parse} with their own allow-lists. The first version of this sweep listed seven,
   and a sweep that omits a position looks exactly like one that covers it.

   Each rules-file row carries a CONTROL: the same rule body with [fn:] substituted. Without it an exit 2
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
  let lcov = Temp.file "es_sweep.lcov" in
  write_file lcov "SF:es_api.ml\nDA:1,1\nDA:3,1\nend_of_record\n" ;
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
      (* TWO POSITIONS LIVE OUTSIDE arch-rules, and the first version of this sweep missed them
         because it enumerated from my own table instead of from the parser: `arch-mutants
         --tests` and `arch-coverage --roots` both call Arch_sel.parse with their own
         allow-list. A sweep that omits a position looks exactly like one that covers it.

         They land differently, and the difference is the point. `--roots` GRANTS the kind: the
         flag already computes this very set under the bare keyword `exported`, so refusing the
         selector spelling would have been two names for one set disagreeing inside one flag.
         `--tests` refuses it: that flag's population is test roots, not the API surface, and a
         kind is granted deliberately. *)
      let cov = run_command (arch_coverage ()) [ db; lcov; "--roots"; "exported:**" ] in
      let cov_code, cov_out = cov in
      Batch.eq_int b
        ~msg:(Printf.sprintf "arch-coverage --roots accepts exported: (it computes that set already):\n%s" cov_out)
        cov_code 0 ;
      let kw_code, kw_out = run_command (arch_coverage ()) [ db; lcov; "--roots"; "exported" ] in
      Batch.eq_int b ~msg:"the bare keyword still works" kw_code 0 ;
      (* Compare the two spellings to EACH OTHER rather than to a literal. A hard-coded cone
         size would have to be re-derived whenever the fixture grows — and the property under
         test is agreement, not any particular number. The non-vacuity check is separate: a
         cone of zero would make the two agree trivially. *)
      (* Extract the TAIL from "function(s)" onward, not "everything after the arrow": the
         arrow is U+2192, three bytes, and [String.index_opt l '>'] finds no ASCII '>' at all —
         so the first version compared whole lines that legitimately differ in their `roots:`
         label while agreeing on the number. It failed against correct behaviour. *)
      let cone_count out =
        let line =
          String.split_on_char '\n' out
          |> List.find_opt (fun l -> contains ~needle:"in the API cone" l)
          |> Option.value ~default:"(no cone line)"
        in
        let rec find i =
          if i + 11 > String.length line then line
          else if String.sub line i 11 = "function(s)" then
            (* walk back over the count's digits and the space before them *)
            let rec back j = if j > 0 && line.[j - 1] <> ' ' then back (j - 1) else j in
            String.trim (String.sub line (back (i - 1)) (String.length line - back (i - 1)))
          else find (i + 1)
        in
        find 0
      in
      Batch.eq_string b
        ~msg:"the two spellings of one set must not disagree"
        (cone_count cov_out) (cone_count kw_out) ;
      Batch.check b
        ~msg:(Printf.sprintf "…on a non-empty cone, or they agree vacuously: %s" (cone_count kw_out))
        (not (contains ~needle:"0 function(s)" (cone_count kw_out))) ;
      (* `plan` is mandatory. The first version omitted it and got exit 2 with a usage banner —
         a refusal for the wrong reason, which is the third time today this exact trap has
         caught me. Hence the control below: if the `fn:` spelling does not run, the refusal
         says nothing about the selector kind. *)
      let mctrl_code, mctrl_out =
        run_command (arch_mutants ()) [ "plan"; db; "--tests"; "fn:**" ]
      in
      Batch.eq_int b
        ~msg:(Printf.sprintf "control: arch-mutants plan --tests fn:** must RUN:\n%s" mctrl_out)
        mctrl_code 0 ;
      let mut_code, mut_out =
        run_command (arch_mutants ()) [ "plan"; db; "--tests"; "exported:**" ]
      in
      Batch.eq_int b
        ~msg:(Printf.sprintf "arch-mutants --tests refuses exported: (test roots, not the API surface):\n%s" mut_out)
        mut_code 2 ;
      Batch.check b
        ~msg:(Printf.sprintf "…and names the position, not the usage banner:\n%s" mut_out)
        (contains ~needle:"not valid in this position" mut_out) ;
      (* THE OTHER HALF, and the reason this is one test rather than nine: the sweep must also
         show that SOME position accepts the kind. Refusals alone are equally consistent
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
