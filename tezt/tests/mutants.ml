(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Call-graph-targeted mutation testing.

    arch-index mutates nothing; it decides what is WORTH mutating and who should
    have caught each survivor. So everything here is about the join being
    honest: every indexed function lands in exactly one bucket, a target carries
    the tests that must rerun for it, code no test reaches is a dead-code
    finding rather than a mutation target, a survivor is blamed on the innermost
    enclosing function, and a survivor that maps to nothing indexed is reported
    rather than dropped.

    The ⊤ cases are the sharp ones. An unreached list is only a proof while the
    test cone is closed; one ⊤ edge inside that cone and "no test reaches this"
    becomes "no test is KNOWN to reach this", which is a different claim. *)

open Arch_tezt

(* arch-mutants takes the subcommand FIRST and the database as its argument
   ("plan DB", "report DB REPORT"), unlike arch-query's "DB subcommand", so the
   database is part of [args] here rather than prepended. *)
let mutants args = run_command (arch_mutants ()) args

let mutants_json b ~what args =
  let code, output = mutants args in
  if code <> 0 then (
    Batch.note b "%s: arch-mutants exited %d:\n%s" what code output ;
    None)
  else
    (* [Batch.expect] is exactly this fold: Ok -> Some, Error -> note and None. *)
    Batch.expect b (Json.parse ~what output)

let expect = Batch.expect
let load_fixture name stream = Fixture.flat ~name stream

(* t_alpha -> covered(10-20) -> inner(14-16), and -> shared(30-40)
   t_beta  -> shared
   orphan(50-60) is reached by nobody
   dyn holds the only ⊤ edge and is OUTSIDE the test cone *)
let main_stream =
  {|{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"t_beta","file_path":"test/beta_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"inner","file_path":"lib/x.ml","line_start":14,"line_end":16}
{"type":"function","name":"shared","file_path":"lib/y.ml","line_start":30,"line_end":40}
{"type":"function","name":"orphan","file_path":"lib/z.ml","line_start":50,"line_end":60}
{"type":"function","name":"dyn","file_path":"lib/d.ml","line_start":1,"line_end":5}
{"type":"function","name":"shadowed","file_path":"lib/d.ml","line_start":7,"line_end":9}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"inner","callee_file":"lib/x.ml","call_site":"lib/x.ml:13","kind":"MUST"}
{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"shared","callee_file":"lib/y.ml","call_site":"lib/x.ml:12","kind":"MUST"}
{"type":"call","caller_name":"t_beta","caller_file":"test/beta_test.ml","callee_name":"shared","callee_file":"lib/y.ml","call_site":"test/beta_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/d.ml","callee_name":"shadowed","callee_file":"lib/d.ml","call_site":"lib/d.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/d.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/d.ml:3","kind":"MAY_TOP"}
|}

let sorted l = List.sort compare l

let register_plan () =
  Test.register ~__FILE__ ~title:"mutants: the plan partitions the index and carries its tests"
    ~tags:["mutants"; "plan"]
  @@ fun () ->
  let db = load_fixture "mutants" main_stream in
  Batch.run (fun b ->
      match mutants_json b ~what:"plan" ["plan"; db; "--tests"; "file:test/**"; "--format"; "json"] with
      | None -> ()
      | Some plan ->
          (* 1. nothing silently vanishes *)
          Option.iter
            (fun n ->
              Batch.eq_int b ~msg:"every indexed function must land in exactly one bucket" n 0)
            (expect b (Json.int ~what:"plan" "unaccounted" plan)) ;

          (* 2. targets are exactly the test-reachable functions, each with its tests *)
          (match expect b (Json.list ~what:"plan" "targets" plan) with
          | None -> ()
          | Some targets ->
              let names = sorted (Json.field_of_objects ~field:"function" targets) in
              Batch.eq_string b ~msg:"targets must be exactly the test-reachable functions"
                (String.concat "," names) "covered,inner,shared" ;
              let tests_of fn =
                List.find_map
                  (function
                    | `Assoc f when List.assoc_opt "function" f = Some (`String fn) -> (
                        match List.assoc_opt "reaching_tests" f with
                        | Some (`List l) ->
                            Some
                              (String.concat ","
                                 (List.filter_map
                                    (function `String s -> Some s | _ -> None)
                                    l))
                        | _ -> None)
                    | _ -> None)
                  targets
              in
              Batch.eq_string_opt b ~msg:"covered's reaching tests" (tests_of "covered")
                (Some "t_alpha") ;
              Batch.eq_string_opt b ~msg:"shared is reached by both tests" (tests_of "shared")
                (Some "t_alpha,t_beta")) ;

          (* 3. unreached code is a dead-code finding, and the ⊤ edge outside the
             cone must not weaken the proof. *)
          (match expect b (Json.strings ~what:"plan" "unreached" plan) with
          | None -> ()
          | Some unreached ->
              Batch.eq_string b ~msg:"unreached must list exactly the functions no test reaches"
                (String.concat "," (sorted unreached)) "dyn,orphan,shadowed") ;
          Option.iter
            (fun escapes ->
              Batch.eq_int b
                ~msg:"a ⊤ edge OUTSIDE the test cone must not appear as a cone escape"
                (List.length escapes) 0)
            (expect b (Json.list ~what:"plan" "test_cone_escapes" plan)) ;
          Option.iter
            (fun proof ->
              Batch.check b
                ~msg:"with a closed cone, the unreached list must be reported as a proof" proof)
            (expect b (Json.bool ~what:"plan" "unreached_is_proof" plan))) ;
  Lwt.return_unit

(* The mirror image: one ⊤ edge INSIDE the cone and the unreached list stops
   being a proof. Both the JSON flag and the human-readable report have to say
   so, because a reader who only sees the text is the one most likely to treat
   the list as exhaustive. *)
let register_cone_escape () =
  Test.register ~__FILE__ ~title:"mutants: a ⊤ edge inside the test cone destroys the proof"
    ~tags:["mutants"; "plan"]
  @@ fun () ->
  let db =
    load_fixture "mutants_escape"
      {|{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"orphan","file_path":"lib/z.ml","line_start":50,"line_end":60}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/x.ml:12","kind":"MAY_TOP"}
|}
  in
  Batch.run (fun b ->
      (match mutants_json b ~what:"plan" ["plan"; db; "--tests"; "file:test/**"; "--format"; "json"] with
      | None -> ()
      | Some plan ->
          Option.iter
            (fun escapes ->
              Batch.eq_string b ~msg:"the escaping function must be named"
                (String.concat "," (Json.field_of_objects ~field:"function" escapes
                                   @ List.filter_map (function `String s -> Some s | _ -> None) escapes))
                "covered")
            (expect b (Json.list ~what:"plan" "test_cone_escapes" plan)) ;
          Option.iter
            (fun proof ->
              Batch.check b ~msg:"unreached_is_proof must drop to false when the cone escapes"
                (not proof))
            (expect b (Json.bool ~what:"plan" "unreached_is_proof" plan)) ;
          Option.iter
            (fun n -> Batch.eq_int b ~msg:"the buckets must still partition the index" n 0)
            (expect b (Json.int ~what:"plan" "unaccounted" plan))) ;
      let _, text = mutants ["plan"; db; "--tests"; "file:test/**"] in
      Batch.contains b
        ~msg:"the text report must say the unreached list is not a proof when the cone escapes"
        ~haystack:text "not a proof") ;
  Lwt.return_unit

let register_allowlist () =
  Test.register ~__FILE__ ~title:"mutants: the allowlist is engine-consumable and never empty by accident"
    ~tags:["mutants"; "plan"]
  @@ fun () ->
  let db = load_fixture "mutants_allow" main_stream in
  Batch.run (fun b ->
      let _, lines_out = mutants ["plan"; db; "--tests"; "file:test/**"; "--format"; "lines"] in
      let rows =
        String.split_on_char '\n' lines_out |> List.filter (fun l -> String.trim l <> "")
      in
      Batch.eq_int b ~msg:"the allowlist must have one range per spanned target"
        (List.length rows) 3 ;
      Batch.contains b ~msg:"allowlist rows must carry file:start-end ranges" ~haystack:lines_out
        "lib/x.ml:10-20" ;
      (* A selector that matches nothing would make every function read as
         unreached — a plan that mutates everything, justified by a typo. *)
      let code, output = mutants ["plan"; db; "--tests"; "file:nope/**"] in
      Batch.exit_code b ~msg:"a --tests selector matching nothing must abort" ~expected:2
        (code, output) ;

      (* `--tests` shares `Arch_sel.parse` with arch-rules, and `ext:` is meaningless as a TEST
         selector — an external leaf is not a function a test can be attributed to — so it must
         be refused the same way arch-rules refuses it: exit 2, naming the kind. Behaviour was
         already correct; only the test was missing. *)
      let ext_code, ext_out = mutants ["plan"; db; "--tests"; "ext:Stdlib.+"] in
      Batch.exit_code b ~msg:"ext: as --tests must abort, not silently match nothing" ~expected:2
        (ext_code, ext_out) ;
      Batch.contains b ~msg:"the ext: refusal on --tests must name the kind, not read as a typo"
        ~haystack:ext_out "not valid in this position") ;
  Lwt.return_unit

let survivors_report =
  {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"1","mutation":"a && b -> a || b"}
{"file":"lib/y.ml","line":35,"status":"SURVIVED","id":"2"}
{"file":"lib/x.ml","line":11,"status":"KILLED","id":"3"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"4"}
{"file":"lib/absent.ml","line":3,"status":"SURVIVED","id":"5"}
|}

let register_attribution () =
  Test.register ~__FILE__ ~title:"mutants: survivors are attributed to the innermost span"
    ~tags:["mutants"; "report"]
  @@ fun () ->
  let db = load_fixture "mutants_report" main_stream in
  let report = Temp.file "mutants_report.ndjson" in
  write_file report survivors_report ;
  Batch.run (fun b ->
      (match
         mutants_json b ~what:"report"
           ["report"; db; report; "--tests"; "file:test/**"; "--format"; "json"]
       with
      | None -> ()
      | Some r ->
          Option.iter (fun n -> Batch.eq_int b ~msg:"killed count" n 1)
            (expect b (Json.int ~what:"report" "killed" r)) ;
          Option.iter (fun n -> Batch.eq_int b ~msg:"total mutants seen" n 5)
            (expect b (Json.int ~what:"report" "total" r)) ;
          (match expect b (Json.list ~what:"report" "survivors" r) with
          | None -> ()
          | Some survivors ->
              let find id =
                List.find_map
                  (function
                    | `Assoc f when List.assoc_opt "id" f = Some (`String id) -> Some f
                    | _ -> None)
                  survivors
              in
              let field f key =
                match List.assoc_opt key f with
                | Some (`String s) -> Some s
                | Some (`List l) ->
                    Some
                      (String.concat ","
                         (List.filter_map (function `String s -> Some s | _ -> None) l))
                | _ -> None
              in
              (* Line 15 sits in BOTH covered(10-20) and inner(14-16). The
                 innermost span must win, or the developer is sent hunting
                 through an enclosing function. *)
              (match find "1" with
              | Some f ->
                  Batch.eq_string_opt b ~msg:"a survivor must be blamed on the innermost span"
                    (field f "function") (Some "inner")
              | None -> Batch.note b "survivor 1 missing from the report") ;
              (match find "2" with
              | Some f ->
                  Batch.eq_string_opt b ~msg:"a survivor must carry every test that reaches it"
                    (field f "reaching_tests") (Some "t_alpha,t_beta")
              | None -> Batch.note b "survivor 2 missing from the report") ;
              (* A survivor in code no test reaches is not a weak test — it is
                 untested code, and must be reported as such rather than as a
                 test failure. *)
              match find "4" with
              | Some f ->
                  Batch.eq_string_opt b ~msg:"an unreached survivor names its function"
                    (field f "function") (Some "orphan") ;
                  Batch.eq_string_opt b ~msg:"an unreached survivor has no reaching tests"
                    (field f "reaching_tests") (Some "")
              | None -> Batch.note b "survivor 4 missing from the report") ;
          match expect b (Json.list ~what:"report" "unmapped" r) with
          | None -> ()
          | Some unmapped ->
              Batch.eq_string b
                ~msg:"a survivor mapping to nothing indexed must be reported, never dropped"
                (String.concat "," (Json.field_of_objects ~field:"file" unmapped))
                "lib/absent.ml") ;

      Batch.exit_code b ~msg:"--fail-on-survivors must exit 1 when survivors exist" ~expected:1
        (mutants ["report"; db; report; "--tests"; "file:test/**"; "--fail-on-survivors"]) ;
      let clean = Temp.file "mutants_clean.ndjson" in
      write_file clean {|{"file":"lib/x.ml","line":11,"status":"KILLED","id":"9"}|} ;
      Batch.exit_code b ~msg:"--fail-on-survivors must exit 0 when every mutant was killed"
        ~expected:0
        (mutants ["report"; db; clean; "--tests"; "file:test/**"; "--fail-on-survivors"])) ;
  Lwt.return_unit

(* mutaml's own sources disagree about `status`: the type says int (an exit
   code), the runner maps exit codes to strings first. Both encodings must be
   read, and anything else must ABORT rather than be guessed — a mis-read status
   inverts the verdict and deletes a real defect from the report. *)
let mutaml_entry status =
  Printf.sprintf
    {|[{"status":%s,"mutant":{"number":3,"repl":"true","loc":{"loc_start":{"pos_fname":"lib/x.ml","pos_lnum":15,"pos_bol":0,"pos_cnum":0},"loc_end":{"pos_fname":"lib/x.ml","pos_lnum":15,"pos_bol":0,"pos_cnum":9},"loc_ghost":false}}}]|}
    status

let register_mutaml () =
  Test.register ~__FILE__ ~title:"mutants: the mutaml adapter reads both encodings and refuses the rest"
    ~tags:["mutants"; "mutaml"]
  @@ fun () ->
  let db = load_fixture "mutants_mutaml" main_stream in
  Batch.run (fun b ->
      List.iter
        (fun (status, expected_survivors) ->
          let path = Temp.file ("mutaml_" ^ String.map (function '"' -> '_' | c -> c) status ^ ".json") in
          write_file path (mutaml_entry status) ;
          match
            mutants_json b ~what:("mutaml " ^ status)
              ["report"; db; path; "--from"; "mutaml"; "--tests"; "file:test/**"; "--format"; "json"]
          with
          | None -> ()
          | Some r ->
              Option.iter
                (fun l ->
                  Batch.eq_int b
                    ~msg:(Printf.sprintf "mutaml status %s must give %d survivor(s)" status
                            expected_survivors)
                    (List.length l) expected_survivors)
                (expect b (Json.list ~what:"report" "survivors" r)))
        [("0", 1); ({|"passed"|}, 1); ("1", 0); ({|"failed"|}, 0); ("124", 0); ({|"timeout"|}, 0)] ;

      let aborts ~msg contents =
        let path = Temp.file "mutaml_bad.json" in
        write_file path contents ;
        Batch.exit_code b ~msg ~expected:2
          (mutants ["report"; db; path; "--from"; "mutaml"; "--tests"; "file:test/**"])
      in
      aborts ~msg:"an unrecognised mutaml status must abort — guessing it inverts the verdict"
        (mutaml_entry {|"weird"|}) ;
      aborts ~msg:"a mutaml entry with no usable loc must abort, not be silently skipped"
        {|[{"status":0,"mutant":{"number":1,"repl":null,"loc":{}}}]|} ;
      aborts ~msg:"a mutaml report that is not a JSON array must abort" {|{"status":0}|} ;

      (* The adapter must land on the same answer as the generic path for the
         same location, or the two entry points disagree about who to blame. *)
      let path = Temp.file "mutaml_ok.json" in
      write_file path (mutaml_entry "0") ;
      match
        mutants_json b ~what:"mutaml"
          ["report"; db; path; "--from"; "mutaml"; "--tests"; "file:test/**"; "--format"; "json"]
      with
      | None -> ()
      | Some r -> (
          match expect b (Json.list ~what:"report" "survivors" r) with
          | Some (`Assoc f :: _) ->
              Batch.eq_string_opt b ~msg:"the mutaml adapter must attribute as the generic path does"
                (match List.assoc_opt "function" f with Some (`String s) -> Some s | _ -> None)
                (Some "inner") ;
              Batch.eq_string_opt b ~msg:"the mutaml adapter must carry the same reaching tests"
                (match List.assoc_opt "reaching_tests" f with
                | Some (`List l) ->
                    Some (String.concat "," (List.filter_map (function `String s -> Some s | _ -> None) l))
                | _ -> None)
                (Some "t_alpha")
          | _ -> Batch.note b "the mutaml adapter produced no survivor to attribute")) ;
  Lwt.return_unit

(* The same malformed-⊤-marked fixture the other tools are tested against: the
   flag is set and `kind` exists, but a real edge carries NULL. arch-mutants
   must reach the same verdict as arch-impact, arch-rules and arch-coverage,
   because they all read it from Arch_db.contract_ok. *)
let register_soundness_flag () =
  Test.register ~__FILE__ ~title:"mutants: a NULL-kind edge makes targeting unsound"
    ~tags:["mutants"; "contract"]
  @@ fun () ->
  (* The shared fixture, not a copy: arch-mutants must reach the same verdict as
     arch-query, arch-impact, arch-rules and arch-coverage on the same bytes. *)
  let db = Fixture.malformed_contract ~name:"mutants_malformed" in
  Batch.run (fun b ->
      match mutants_json b ~what:"plan" ["plan"; db; "--tests"; "fn:A"; "--format"; "json"] with
      | None -> ()
      | Some plan ->
          Option.iter
            (fun sound ->
              Batch.check b
                ~msg:"a NULL-kind edge on a flag-stamped index must report sound_targeting:false"
                (not sound))
            (expect b (Json.bool ~what:"plan" "sound_targeting" plan))) ;
  Lwt.return_unit

(* ------------------------------------------------------------------------ *)
(* `arch-mutants run` — driving and persisting one campaign.                 *)
(*                                                                          *)
(* THE EXECUTION MODEL, because every assertion below depends on reading it  *)
(* the same way the driver does:                                             *)
(*                                                                          *)
(*   driver → engine (ONCE) → wrapper (ONCE PER MUTANT) → the selected tests *)
(*                                                                          *)
(* The stub engine here plays the part mutaml's runner plays: it loops over  *)
(* its own mutants and calls the wrapper once per mutant with MUTAML_MUTANT  *)
(* set. So nothing below asserts "the engine ran twice" — that would assert  *)
(* the wrong thing. The unit of observation is the WRAPPER's invocation,     *)
(* recorded in the trace file it appends to.                                 *)
(* ------------------------------------------------------------------------ *)

(* t_alpha and t_gamma share a FILE, which is what makes the group-granularity
   case observable: a `group` profile must widen {t_alpha} to {t_alpha,t_gamma}
   and say it did. t_beta lives elsewhere so a widening that swallowed the whole
   suite would be distinguishable from one that stopped at the group. *)
let campaign_stream =
  {|{"type":"function","name":"t_alpha","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"t_gamma","file_path":"test/alpha_test.ml","line_start":7,"line_end":9}
{"type":"function","name":"t_beta","file_path":"test/beta_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"function","name":"other","file_path":"lib/y.ml","line_start":30,"line_end":40}
{"type":"function","name":"shared","file_path":"lib/z.ml","line_start":50,"line_end":60}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
{"type":"call","caller_name":"t_gamma","caller_file":"test/alpha_test.ml","callee_name":"other","callee_file":"lib/y.ml","call_site":"test/alpha_test.ml:8","kind":"MUST"}
{"type":"call","caller_name":"t_beta","caller_file":"test/beta_test.ml","callee_name":"shared","callee_file":"lib/z.ml","call_site":"test/beta_test.ml:2","kind":"MUST"}
|}

(* The engine's own catalogue of what it will attempt: three mutants, one per
   target function, so each has a DIFFERENT intended test set. A wrapper that
   ignored MUTAML_MUTANT and always emitted one set would satisfy a
   single-mutant fixture perfectly. *)
let campaign_catalogue =
  {|{"id":"m1","file":"lib/x.ml","line":15,"col_start":3,"col_end":9,"replacement":"true"}
{"id":"m2","file":"lib/y.ml","line":35,"col_start":1,"col_end":4,"replacement":"false"}
{"id":"m3","file":"lib/z.ml","line":55,"col_start":2,"col_end":7,"replacement":"0"}
|}

let wrapper_path () = Filename.concat (repo_root ()) "scripts/mutaml-wrapper.sh"

(* One campaign harness: build the index, derive the plan through the real CLI,
   write the catalogue/report/engine, and hand back a runner plus the work
   directory the wrapper writes its trace into. *)
(* [db] and [tests] are parameters rather than constants because slice 2 replays ONE
   engine report over three DIFFERENT indexes — closed cone, ⊤ inside the cone, and no
   soundness contract at all — and the whole claim is that the same report publishes three
   different verdicts. A harness that could only build one index would make two of those
   three arms unreachable while the assertions still read as if they covered them. *)
let campaign_setup_on ~db ~tests ~name ~engine_body ~report =
  let dir = Temp.dir (name ^ "_campaign") in
  let plan_file = Filename.concat dir "plan.json" in
  let _, plan_out = mutants ["plan"; db; "--tests"; tests; "--format"; "json"] in
  write_file plan_file plan_out ;
  let catalogue = Filename.concat dir "catalogue.ndjson" in
  write_file catalogue campaign_catalogue ;
  let report_file = Filename.concat dir "report.ndjson" in
  write_file report_file report ;
  let engine = Filename.concat dir "engine.sh" in
  write_exec engine engine_body ;
  let work = Filename.concat dir "work" in
  let env =
    [("ARCH_MUTANTS_WORKDIR", work); ("ARCH_MUTANTS_WRAPPER", wrapper_path ())]
  in
  let argv extra =
    ["run"; db; "--plan"; plan_file; "--engine"; engine; "--test-cmd"; "true";
     "--catalogue"; catalogue; "--report"; report_file; "--tests"; tests]
    @ extra
  in
  let run extra = run_command ~env (arch_mutants ()) (argv extra) in
  (* The JSON surface is read through the SPLIT runner. The driver routes the
     engine's own chatter to stderr precisely so stdout stays one parseable
     object; merging the two back together here would undo that and make the
     assertion fail for a reason that has nothing to do with the code. *)
  let run_json extra = run_command_split ~env (arch_mutants ()) (argv extra) in
  (db, work, run, run_json)

let campaign_setup ~name ~engine_body ~report =
  campaign_setup_on ~db:(load_fixture name campaign_stream) ~tests:"file:test/**" ~name
    ~engine_body ~report

(* The wrapper's trace: one line per invocation, "<id>\t<n>\t<executed,…>\t<rc>". *)
let trace_rows work =
  let path = Filename.concat work "wrapper-trace.tsv" in
  if not (Sys.file_exists path) then []
  else
    String.split_on_char '\n' (read_file path)
    |> List.filter (fun l -> String.trim l <> "")
    |> List.map (fun l -> String.split_on_char '\t' l)

let executed_for work id =
  List.find_map
    (function id' :: _ :: executed :: _ when id' = id -> Some executed | _ -> None)
    (trace_rows work)

let stub_engine ids =
  "#!/bin/sh\n"
  ^ String.concat ""
      (List.map (fun m -> Printf.sprintf "MUTAML_MUTANT=%s \"$1\" || true\n" m) ids)
  ^ "exit 0\n"

let all_survived =
  {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"SURVIVED","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"m3"}
|}

(* CHECK-1 / AC-1. The claim is about the WRAPPER, not the engine, and it is
   asserted with counts and exact sets rather than by grepping the report for a
   word: a word survives a great many wrong implementations because it can be
   present for reasons unrelated to the branch that should have produced it. A
   count cannot. *)
let register_run_per_mutant () =
  Test.register ~__FILE__
    ~title:"mutants: run drives the wrapper once per mutant with the declared set"
    ~tags:["mutants"; "run"]
  @@ fun () ->
  let db, work, run, _ =
    campaign_setup ~name:"mutants_run" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"KILLED","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"m3"}
|}
  in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"a completed campaign must exit 0" ~expected:0 (run []) ;
      (* Three mutants, three wrapper invocations — not one, which is what the
         ENGINE got. *)
      Batch.eq_int b ~msg:"the wrapper must be invoked once per mutant"
        (List.length (trace_rows work)) 3 ;
      Batch.eq_string_opt b ~msg:"m1's executed set must be exactly covered's reaching tests"
        (executed_for work "m1") (Some "t_alpha") ;
      Batch.eq_string_opt b ~msg:"m2's executed set must be exactly other's reaching tests"
        (executed_for work "m2") (Some "t_gamma") ;
      Batch.eq_string_opt b ~msg:"m3's executed set must be exactly shared's reaching tests"
        (executed_for work "m3") (Some "t_beta") ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"one campaign row" (Db.int conn "SELECT count(*) FROM mutant_campaigns") 1 ;
          Batch.eq_int b ~msg:"one mutant site row per catalogued mutant"
            (Db.int conn "SELECT count(*) FROM mutants") 3 ;
          Batch.eq_int b ~msg:"one run row per attempted mutant"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 3 ;
          Batch.eq_int b
            ~msg:"a completed campaign must stamp completed_at"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL") 1 ;
          (* FR-013: a status is never stored without its provenance, and this
             fixture's cone is closed with a contract, so it is proved_superset. *)
          Batch.eq_int b ~msg:"every run row must carry a selection provenance"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs WHERE selection_provenance = 'proved_superset'")
            3 ;
          (* FR-007: m2 was killed under a SINGLETON executed set, so its
             attribution is known; nothing else is. *)
          Batch.eq_int b ~msg:"exactly one attribution is knowable here"
            (Db.int conn "SELECT count(*) FROM mutant_kills") 1 ;
          Batch.eq_string_opt b ~msg:"the attributed test must be the one that actually ran"
            (Db.string_opt conn "SELECT test_name FROM mutant_kills") (Some "t_gamma")) ;
      (* A second campaign over unchanged code adds campaign and run rows and NO
         mutant site rows (AC-5). *)
      Batch.exit_code b ~msg:"a re-run must succeed" ~expected:0 (run []) ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"a re-run inserts a new campaign, never updating the old one"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns") 2 ;
          Batch.eq_int b ~msg:"a re-run over unchanged code adds NO mutant site rows"
            (Db.int conn "SELECT count(*) FROM mutants") 3 ;
          Batch.eq_int b ~msg:"a re-run doubles the run rows"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 6)) ;
  Lwt.return_unit

(* CHECK-2 / AC-2. "Once per mutant with exactly the reaching tests" is
   unsatisfiable when the runner can only address a group, so the criterion is
   restated in terms of the EXECUTED set: it must be a superset, and both sizes
   must be recorded. Over-selection is sound; under-selection is not. *)
let register_run_group_superset () =
  Test.register ~__FILE__
    ~title:"mutants: a group-granularity profile executes a superset and says so"
    ~tags:["mutants"; "run"]
  @@ fun () ->
  let db, work, run, _ =
    campaign_setup ~name:"mutants_group" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:all_survived
  in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"the campaign must run" ~expected:0 (run ["--profile"; "alcotest"]) ;
      (* covered is reached by t_alpha alone, but t_gamma shares its FILE, so a
         group-addressing runner cannot avoid running it too. The executed set is
         that widened pair, in sorted order — and NOT the whole suite, which
         would also be a superset but a different (and needlessly expensive) one. *)
      Batch.eq_string_opt b ~msg:"a group profile must widen m1's set to its whole group"
        (executed_for work "m1") (Some "t_alpha,t_gamma") ;
      Batch.eq_string_opt b ~msg:"m3's group holds only itself, so its set must not widen"
        (executed_for work "m3") (Some "t_beta") ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"the campaign must record the declared granularity"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns WHERE granularity = 'group'") 1 ;
          (* The INTENDED set is preserved alongside the executed one: 1 and 2,
             worked out by hand from the fixture, not read back from the tool. *)
          Batch.eq_int b ~msg:"m1's run must record intended 1 and executed 2, flagged a superset"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id = r.mutant_id \
                WHERE m.file_path = 'lib/x.ml' AND r.intended_tests = 1 AND r.executed_tests = 2 \
                AND r.executed_superset = 1")
            1 ;
          (* Worked out by hand from the fixture, and it is NOT symmetric: m1
             (covered ← t_alpha) and m2 (other ← t_gamma) both widen, because
             t_alpha and t_gamma share alpha_test.ml. Only m3 (shared ← t_beta,
             alone in beta_test.ml) has a group of one and must stay unflagged.
             So 2 supersets and 1 not — a count the tool cannot satisfy by
             flagging everything, nor by flagging nothing. *)
          Batch.eq_int b ~msg:"exactly the two mutants whose group holds a second test widen"
            (Db.int conn "SELECT count(*) FROM mutant_runs WHERE executed_superset = 1") 2 ;
          Batch.eq_int b
            ~msg:"the mutant whose group holds only its own test must NOT be flagged a superset"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id = r.mutant_id \
                WHERE m.file_path = 'lib/z.ml' AND r.executed_superset = 0")
            1)) ;
  Lwt.return_unit

(* CHECK-3 / AC-3. Exit 2 is asserted TOGETHER with a fact no message can
   simulate: the database must hold no campaign table at all. An empty campaign
   row would read as "nothing survived", which is the whole reason this refuses. *)
let register_run_missing_engine () =
  Test.register ~__FILE__ ~title:"mutants: run with no engine exits 2 and writes no campaign"
    ~tags:["mutants"; "run"]
  @@ fun () ->
  let db = load_fixture "mutants_no_engine" campaign_stream in
  let dir = Temp.dir "mutants_no_engine_campaign" in
  let plan_file = Filename.concat dir "plan.json" in
  let _, plan_out = mutants ["plan"; db; "--tests"; "file:test/**"; "--format"; "json"] in
  write_file plan_file plan_out ;
  let catalogue = Filename.concat dir "catalogue.ndjson" in
  write_file catalogue campaign_catalogue ;
  let report_file = Filename.concat dir "report.ndjson" in
  write_file report_file all_survived ;
  Batch.run (fun b ->
      let code, output =
        run_command
          ~env:[("ARCH_MUTANTS_WORKDIR", Filename.concat dir "work");
                ("ARCH_MUTANTS_WRAPPER", wrapper_path ())]
          (arch_mutants ())
          ["run"; db; "--plan"; plan_file; "--engine"; "arch-mutants-no-such-engine";
           "--test-cmd"; "true"; "--catalogue"; catalogue; "--report"; report_file;
           "--tests"; "file:test/**"]
      in
      Batch.exit_code b ~msg:"an unresolvable engine must abort with exit 2" ~expected:2
        (code, output) ;
      (* The verifiable half. The driver opens the database for writing only
         AFTER the engine resolves, so an aborted run leaves it without the
         campaign tables entirely — a fact no wording can fake. *)
      Db.with_db db (fun conn ->
          Batch.eq_int b
            ~msg:"a refused campaign must not create the campaign table, let alone a row in it"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0)) ;
  Lwt.return_unit

(* CHECK-5 / AC-11. The engine dies after one of three mutants. The campaign
   stays OPEN and the two it never reached have no run row — PENDING by that
   absence. Reporting them as SURVIVED would be a false accusation against two
   tests that were never given the chance. *)
let register_run_interrupted () =
  Test.register ~__FILE__ ~title:"mutants: an interrupted campaign reports PENDING, never SURVIVED"
    ~tags:["mutants"; "run"]
  @@ fun () ->
  let db, work, run, _ =
    campaign_setup ~name:"mutants_interrupted"
      ~engine_body:"#!/bin/sh\nMUTAML_MUTANT=m1 \"$1\" || true\nexit 1\n"
      ~report:{|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
|}
  in
  Batch.run (fun b ->
      let code, output = run [] in
      ignore code ;
      Batch.eq_int b ~msg:"only the mutant the engine reached invoked the wrapper"
        (List.length (trace_rows work)) 1 ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"an interrupted campaign must leave completed_at NULL"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NULL") 1 ;
          (* All three sites are catalogued and persisted; only one was
             attempted. The other two are PENDING by the ABSENCE of a run row,
             which is why the count is 1 and not 3. *)
          Batch.eq_int b ~msg:"every catalogued mutant is still persisted as a site"
            (Db.int conn "SELECT count(*) FROM mutants") 3 ;
          Batch.eq_int b ~msg:"only the attempted mutant gets a run row"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 1 ;
          Batch.eq_int b
            ~msg:"the two unattempted mutants must not appear as SURVIVED"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id = r.mutant_id \
                WHERE m.file_path IN ('lib/y.ml','lib/z.ml')")
            0) ;
      ignore output) ;
  Lwt.return_unit

(* FR-027/FR-029 / AC-21, AC-23. A campaign with no kills is SELF-UNCERTIFIED,
   and the three ways of having no kill are three different facts.

   Asserted on the TAG the driver computes and on hand-counted per-status
   numbers, never by grepping the rendered report for the word
   "self-uncertified". A word survives a great many wrong implementations,
   because it can be present for a reason that has nothing to do with the branch
   that should have produced it — a legend, a header, a help line. A tag whose
   value distinguishes `uncertified_no_kill` from `uncertified_all_errored`
   cannot. *)
let register_run_self_uncertified () =
  Test.register ~__FILE__
    ~title:"mutants: a campaign with no kills is self-uncertified, and says WHY it has none"
    ~tags:["mutants"; "run"]
  @@ fun () ->
  let survivors_case =
    campaign_setup ~name:"mutants_uncert_surv"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived
  in
  let errors_case =
    campaign_setup ~name:"mutants_uncert_err" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"ERROR","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"ERROR","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"ERROR","id":"m3"}
|}
  in
  let killed_case =
    campaign_setup ~name:"mutants_uncert_kill" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"KILLED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"SURVIVED","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"m3"}
|}
  in
  let tag_and_counts b ~what (_, _, _, run_json) =
    match Batch.expect b (Json.parse ~what (let _, out, _ = run_json ["--format"; "json"] in out)) with
    | None -> None
    | Some j -> Some j
  in
  Batch.run (fun b ->
      let check ~what case ~tag ~killed ~survived ~errored =
        match tag_and_counts b ~what case with
        | None -> ()
        | Some j ->
            Option.iter
              (fun s ->
                Batch.eq_string b ~msg:(what ^ ": certification tag") s tag)
              (Batch.expect b
                 (match Json.member "certification" j with
                 | Some (`String s) -> Ok s
                 | other -> Error (what ^ ": certification is " ^ Json.show other))) ;
            List.iter
              (fun (key, expected) ->
                Option.iter
                  (fun n -> Batch.eq_int b ~msg:(what ^ ": " ^ key) n expected)
                  (Batch.expect b (Json.int ~what key j)))
              [("killed", killed); ("survived", survived); ("errored", errored)]
      in
      (* Mutants ran, none died: the picture an unmutated binary also produces. *)
      check ~what:"all survivors" survivors_case ~tag:"uncertified_no_kill" ~killed:0
        ~survived:3 ~errored:0 ;
      (* Also zero kills, for an entirely different reason — nothing meaningfully
         ran — and it must NOT be reported in the same words. *)
      check ~what:"all errored" errors_case ~tag:"uncertified_all_errored" ~killed:0
        ~survived:0 ~errored:3 ;
      (* One kill is enough: a stale, unmutated binary cannot produce one. *)
      check ~what:"one kill" killed_case ~tag:"self_certifying" ~killed:1 ~survived:2
        ~errored:0) ;
  Lwt.return_unit

(* ------------------------------------------------------------------------ *)
(* SLICE 2 — `arch-mutants verdict`: the PUBLISHED verdict.                  *)
(*                                                                          *)
(* The stored fact is the engine's status. The published verdict is DERIVED  *)
(* from that status together with the selection provenance OF THE SAME RUN   *)
(* ROW, and never stored — PENDING least of all, which is the ABSENCE of a   *)
(* run row inside a campaign whose completion is NULL.                       *)
(*                                                                          *)
(* Everything below asserts on the computed verdict string and on            *)
(* hand-counted numbers rather than on words in prose. A word survives a     *)
(* great many wrong implementations because it can be present for a reason   *)
(* unrelated to the branch that should have produced it; "UNKNOWN" in        *)
(* particular appears in this tool's own legends. A count cannot.            *)
(* ------------------------------------------------------------------------ *)

(* The same index as [campaign_stream], plus ONE ⊤ edge held by `covered`,
   which t_alpha reaches — so the escape is INSIDE the test cone and every
   selection over this index is a lower bound. Without this fixture the
   `top_bounded` arm is unreachable, and an assertion about a branch no fixture
   can reach passes while checking nothing. *)
let campaign_stream_top =
  campaign_stream
  ^ {|{"type":"call","caller_name":"covered","caller_file":"lib/x.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/x.ml:12","kind":"MAY_TOP"}
|}

let verdict_of b ~what ?(args = []) db =
  match mutants_json b ~what (["verdict"; db; "--format"; "json"] @ args) with
  | None -> None
  | Some j -> (
      match expect b (Json.list ~what "campaigns" j) with
      | Some (c :: _) -> (
          match expect b (Json.list ~what:"campaign" "findings" c) with
          | Some fs -> Some (c, fs)
          | None -> None)
      | _ ->
          Batch.note b "%s: the verdict output carries no campaign" what ;
          None)

(* One field of the finding for [file]. "<absent>" and "null" are kept apart on
   purpose: FR-033 requires an unlinked finding to carry an explicit null rather
   than a borrowed value, and a MISSING key would satisfy a laxer assertion
   while telling a reader nothing. *)
let finding_field fs ~file key =
  List.find_map
    (function
      | `Assoc f when List.assoc_opt "file" f = Some (`String file) ->
          Some
            (match List.assoc_opt key f with
            | Some (`String s) -> s
            | Some `Null -> "null"
            | Some other -> Yojson.Safe.to_string other
            | None -> "<absent>")
      | _ -> None)
    fs

let verdict_count b ~what c verdict expected =
  match Json.member "verdict_counts" c with
  | Some counts ->
      Option.iter
        (fun n -> Batch.eq_int b ~msg:(what ^ ": " ^ verdict ^ " count") n expected)
        (expect b (Json.int ~what verdict counts))
  | None -> Batch.note b "%s: no verdict_counts in the campaign record" what

(* CHECK-4 / AC-7, AC-8, AC-9. ONE engine report — every mutant SURVIVED —
   replayed over THREE indexes, publishing three different verdicts while the
   STORED status stays SURVIVED in all three.

   Each arm has its own fixture, because a three-arm assertion over a fixture
   that can only produce one arm passes while checking a third of what it
   claims. The three fixtures differ in exactly the two facts the rule reads:
   whether the test cone escapes, and whether the index carries a soundness
   contract at all. *)
let register_verdict_three_indexes () =
  Test.register ~__FILE__
    ~title:"mutants: one engine report, three indexes, three published verdicts"
    ~tags:["mutants"; "verdict"]
  @@ fun () ->
  let closed =
    campaign_setup_on
      ~db:(load_fixture "mutants_verdict_closed" campaign_stream)
      ~tests:"file:test/**" ~name:"mutants_verdict_closed"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived
  in
  let bounded =
    campaign_setup_on
      ~db:(load_fixture "mutants_verdict_top" campaign_stream_top)
      ~tests:"file:test/**" ~name:"mutants_verdict_top"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived
  in
  (* The shared malformed-contract fixture, not a copy: arch-mutants must reach
     the same "no contract" verdict the other four tools reach on the same
     bytes, because they all read it through Arch_db.contract_ok. *)
  let no_contract =
    campaign_setup_on
      ~db:(Fixture.malformed_contract ~name:"mutants_verdict_nocontract")
      ~tests:"fn:A" ~name:"mutants_verdict_nocontract"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived
  in
  Batch.run (fun b ->
      let arm ~what (db, _, run, _) ~provenance ~verdict =
        Batch.exit_code b ~msg:(what ^ ": the campaign must run") ~expected:0 (run []) ;
        (* The STORED fact is SURVIVED in all three arms. Asserted as a count of
           rows, which no rendering can imitate. *)
        Db.with_db db (fun conn ->
            Batch.eq_int b ~msg:(what ^ ": all three mutants are stored SURVIVED")
              (Db.int conn "SELECT count(*) FROM mutant_runs WHERE engine_status = 'SURVIVED'")
              3 ;
            Batch.eq_int b
              ~msg:(what ^ ": the published verdict must not be stored in any column")
              (Db.int conn
                 "SELECT count(*) FROM pragma_table_info('mutant_runs') WHERE name LIKE \
                  '%verdict%'")
              0) ;
        match verdict_of b ~what db with
        | None -> ()
        | Some (c, fs) ->
            Batch.eq_string_opt b ~msg:(what ^ ": the run's own selection provenance")
              (finding_field fs ~file:"lib/x.ml" "selection_provenance")
              (Some provenance) ;
            Batch.eq_string_opt b ~msg:(what ^ ": the engine status stays SURVIVED")
              (finding_field fs ~file:"lib/x.ml" "engine_status")
              (Some "SURVIVED") ;
            Batch.eq_string_opt b ~msg:(what ^ ": the PUBLISHED verdict")
              (finding_field fs ~file:"lib/x.ml" "published_verdict")
              (Some verdict) ;
            (* Three mutants, all with the same provenance in this campaign, so
               the count is 3 — worked out from the fixture, not read back. *)
            verdict_count b ~what c verdict 3
      in
      arm ~what:"closed cone + contract" closed ~provenance:"proved_superset"
        ~verdict:"SURVIVED" ;
      arm ~what:"⊤ inside the test cone" bounded ~provenance:"top_bounded" ~verdict:"UNKNOWN" ;
      arm ~what:"no soundness contract" no_contract ~provenance:"no_contract"
        ~verdict:"UNKNOWN_NO_CONTRACT") ;
  Lwt.return_unit

(* AC-9 / EC-6. A kill is a PROOF: a wider selection could only have killed the
   mutant too, so a bounded selection cannot weaken it. The provenance is
   asserted in the SAME record, which is what stops this passing vacuously on a
   closed-cone fixture where every kill is trivially unbounded. *)
let register_verdict_killed_under_top () =
  Test.register ~__FILE__ ~title:"mutants: a KILLED under a bounded selection still publishes KILLED"
    ~tags:["mutants"; "verdict"]
  @@ fun () ->
  let db, _, run, _ =
    campaign_setup_on
      ~db:(load_fixture "mutants_verdict_kill_top" campaign_stream_top)
      ~tests:"file:test/**" ~name:"mutants_verdict_kill_top"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"KILLED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"TIMEOUT","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"m3"}
|}
  in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"the campaign must run" ~expected:0 (run []) ;
      match verdict_of b ~what:"killed under top" db with
      | None -> ()
      | Some (c, fs) ->
          Batch.eq_string_opt b ~msg:"the fixture must really be the bounded one"
            (finding_field fs ~file:"lib/x.ml" "selection_provenance")
            (Some "top_bounded") ;
          Batch.eq_string_opt b ~msg:"KILLED under top_bounded still publishes KILLED"
            (finding_field fs ~file:"lib/x.ml" "published_verdict")
            (Some "KILLED") ;
          Batch.eq_string_opt b ~msg:"TIMEOUT under top_bounded also publishes KILLED"
            (finding_field fs ~file:"lib/y.ml" "published_verdict")
            (Some "KILLED") ;
          (* And the survivor beside them does NOT: the same provenance weakens
             the negative claim and leaves the positive one alone. Two kills and
             one UNKNOWN — hand-counted from the report above. *)
          Batch.eq_string_opt b ~msg:"a SURVIVED under the same provenance publishes UNKNOWN"
            (finding_field fs ~file:"lib/z.ml" "published_verdict")
            (Some "UNKNOWN") ;
          verdict_count b ~what:"killed under top" c "KILLED" 2 ;
          verdict_count b ~what:"killed under top" c "UNKNOWN" 1 ;
          verdict_count b ~what:"killed under top" c "SURVIVED" 0) ;
  Lwt.return_unit

(* CHECK-5 / AC-11, FR-014. The engine dies after one of three mutants. The two
   it never reached have no run row, and that ABSENCE publishes PENDING. Calling
   them SURVIVED would accuse two tests that were never given the chance. *)
let register_verdict_pending () =
  Test.register ~__FILE__
    ~title:"mutants: an unattempted mutant publishes PENDING, never SURVIVED"
    ~tags:["mutants"; "verdict"]
  @@ fun () ->
  let db, _, run, _ =
    campaign_setup ~name:"mutants_verdict_pending"
      ~engine_body:"#!/bin/sh\nMUTAML_MUTANT=m1 \"$1\" || true\nexit 1\n"
      ~report:{|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
|}
  in
  Batch.run (fun b ->
      (* An index no campaign has ever touched REFUSES (exit 3) rather than publishing an
         empty verdict list. FR-032's distinction, at the surface a caller reads: "nothing
         ran" and "ran and found nothing" are different facts, and 3 is the code that
         carries the first across a process boundary. *)
      let virgin = load_fixture "mutants_verdict_virgin" campaign_stream in
      Batch.exit_code b
        ~msg:"an index with no campaign tables must REFUSE, not publish an empty verdict"
        ~expected:3
        (mutants ["verdict"; virgin; "--format"; "json"]) ;
      ignore (run [] : int * string) ;
      match verdict_of b ~what:"interrupted" db with
      | None -> ()
      | Some (c, fs) ->
          Option.iter
            (fun partial ->
              Batch.check b ~msg:"an interrupted campaign must report itself partial" partial)
            (expect b (Json.bool ~what:"campaign" "partial" c)) ;
          (* One attempted, two never reached. Hand-counted from the engine body
             above, which stops after m1. *)
          verdict_count b ~what:"interrupted" c "PENDING" 2 ;
          verdict_count b ~what:"interrupted" c "SURVIVED" 1 ;
          List.iter
            (fun file ->
              Batch.eq_string_opt b
                ~msg:("an unattempted mutant in " ^ file ^ " publishes PENDING")
                (finding_field fs ~file "published_verdict")
                (Some "PENDING") ;
              (* FR-033: no run row means no provenance to carry, and the honest
                 answer is an explicit null — never the provenance of the one run
                 that did happen. *)
              Batch.eq_string_opt b
                ~msg:("a PENDING finding in " ^ file ^ " borrows no provenance")
                (finding_field fs ~file "selection_provenance")
                (Some "null") ;
              Batch.eq_string_opt b
                ~msg:("a PENDING finding in " ^ file ^ " borrows no engine status")
                (finding_field fs ~file "engine_status")
                (Some "null"))
            ["lib/y.ml"; "lib/z.ml"]) ;
  Lwt.return_unit

(* CHECK-18 / AC-27, FR-033. Two runs, DIFFERING provenance, in one campaign —
   and the same two runs written in the opposite order in a second database.

   A single-run fixture cannot tell positional attribution from correct
   attribution, which is exactly how a peer's `match producers with p :: _`
   survived review: it labelled every finding with the FIRST run's class. So the
   fixture holds two, the two disagree, and the test asserts BOTH that the
   collection order really did reverse and that no label moved with it. *)
let seed_two_provenances ~name ~x_first =
  let db = load_fixture name campaign_stream in
  let migration = read_file (Filename.concat (repo_root ()) "mutants-schema-migration.sql") in
  Db.with_db_rw db (fun conn ->
      (* The migration text itself, not a hand-copied CREATE TABLE: a copy keeps
         working while the real schema moves under it. *)
      Db.exec conn migration ;
      Db.exec conn
        {|INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
            VALUES ('lib/x.ml',15,3,9,'true','hash-x','covered'),
                   ('lib/y.ml',35,1,4,'false','hash-y','other');
          INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
            VALUES ('stub','/bin/true','/bin/true','case','2026-09-05T00:00:00Z');|} ;
      let insert file provenance =
        Db.exec conn
          (Printf.sprintf
             "INSERT INTO mutant_runs(campaign_id,mutant_id,engine_mutant_id,engine_status,\
              selection_provenance,intended_tests,executed_tests) SELECT 1, id, 'e-'||id, \
              'SURVIVED', '%s', 1, 1 FROM mutants WHERE file_path = '%s'"
             provenance file)
      in
      (* Insertion order IS the order the reporter walks, because it reads
         ORDER BY r.id. That is what makes the swap observable. *)
      if x_first then (
        insert "lib/x.ml" "top_bounded" ;
        insert "lib/y.ml" "proved_superset")
      else (
        insert "lib/y.ml" "proved_superset" ;
        insert "lib/x.ml" "top_bounded")) ;
  db

let register_verdict_provenance_follows_run () =
  Test.register ~__FILE__
    ~title:"mutants: provenance follows the run, not the collection order"
    ~tags:["mutants"; "verdict"]
  @@ fun () ->
  let x_first = seed_two_provenances ~name:"mutants_fr033_x" ~x_first:true in
  let y_first = seed_two_provenances ~name:"mutants_fr033_y" ~x_first:false in
  Batch.run (fun b ->
      let labels ~what db =
        match verdict_of b ~what db with
        | None -> None
        | Some (_, fs) ->
            (* The order actually reversed — asserted, not assumed. Without this
               the "reversing changes no label" claim could hold because nothing
               reversed. *)
            Some
              ( List.hd (Json.field_of_objects ~field:"file" fs),
                finding_field fs ~file:"lib/x.ml" "published_verdict",
                finding_field fs ~file:"lib/y.ml" "published_verdict",
                finding_field fs ~file:"lib/x.ml" "selection_provenance",
                finding_field fs ~file:"lib/y.ml" "selection_provenance" )
      in
      match (labels ~what:"x first" x_first, labels ~what:"y first" y_first) with
      | Some (head_x, vx1, vy1, px1, py1), Some (head_y, vx2, vy2, px2, py2) ->
          Batch.eq_string b ~msg:"the first database must list the ⊤-bounded run first" head_x
            "lib/x.ml" ;
          Batch.eq_string b
            ~msg:"the second database must list the proved run first — otherwise nothing swapped"
            head_y "lib/y.ml" ;
          (* The bounded run is UNKNOWN and the proved run is SURVIVED, in BOTH
             orders. A first-element attribution would label both runs alike and
             so would disagree with itself between the two databases. *)
          List.iter
            (fun (msg, got, expected) -> Batch.eq_string_opt b ~msg got (Some expected))
            [ ("x-first: the ⊤-bounded run publishes UNKNOWN", vx1, "UNKNOWN");
              ("x-first: the proved run publishes SURVIVED", vy1, "SURVIVED");
              ("y-first: the ⊤-bounded run still publishes UNKNOWN", vx2, "UNKNOWN");
              ("y-first: the proved run still publishes SURVIVED", vy2, "SURVIVED");
              ("x-first: lib/x.ml carries its OWN provenance", px1, "top_bounded");
              ("x-first: lib/y.ml carries its OWN provenance", py1, "proved_superset");
              ("y-first: lib/x.ml still carries its own provenance", px2, "top_bounded");
              ("y-first: lib/y.ml still carries its own provenance", py2, "proved_superset") ]
      | _ -> Batch.note b "one of the two orderings produced no verdict output") ;
  Lwt.return_unit
