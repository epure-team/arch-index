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
(* [?catalogue] and [?plan_tests] are WIDENINGS of this harness, not changes to it: both
   default to what every existing caller already got. The join between report entries and
   catalogued sites is only testable with two mutants on ONE line, which the shared
   catalogue deliberately does not have; and FR-003's subset prohibition is only reachable
   when the plan and the run were computed from DIFFERENT test selections. *)
let campaign_setup_on ?(extra_env = []) ?catalogue:(catalogue_text = campaign_catalogue)
    ?plan_tests ?(extra_argv = []) ~db ~tests ~name ~engine_body ~report () =
  let dir = Temp.dir (name ^ "_campaign") in
  let plan_file = Filename.concat dir "plan.json" in
  let _, plan_out =
    mutants
      ["plan"; db; "--tests"; Option.value ~default:tests plan_tests; "--format"; "json"]
  in
  write_file plan_file plan_out ;
  let catalogue = Filename.concat dir "catalogue.ndjson" in
  write_file catalogue catalogue_text ;
  let report_file = Filename.concat dir "report.ndjson" in
  write_file report_file report ;
  let engine = Filename.concat dir "engine.sh" in
  write_exec engine engine_body ;
  let work = Filename.concat dir "work" in
  let env =
    [("ARCH_MUTANTS_WORKDIR", work); ("ARCH_MUTANTS_WRAPPER", wrapper_path ())] @ extra_env
  in
  let argv extra =
    ["run"; db; "--plan"; plan_file; "--engine"; engine; "--test-cmd"; "true";
     "--catalogue"; catalogue; "--report"; report_file; "--tests"; tests]
    @ extra_argv @ extra
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
    ~engine_body ~report ()

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
(* CHECK-24 / FR-031. A wrapper REFUSAL is not an outcome, so it is not an
   attempt: no run row, no attribution, and the campaign stays open.

   The chain this closes is worth spelling out, because it crosses three
   programs. mutaml persists the RAW exit code of its test command rather than
   the label it prints (src/runner/runner.ml:109-110 saves `{ status = ret; … }`
   over a `status : int` in src/common/mutaml_common.ml:74), and the driver's
   adapter reads 0 as SURVIVED, 124 as TIMEOUT and every other code as KILLED.
   The wrapper used to refuse with `exit 2`, so a selection that was wholly
   broken produced a campaign of clean KILLS — the one outcome this design
   treats as self-certifying proof. The wrapper now refuses with 99 and the
   driver maps exactly that value.

   Asserted on counts and on table contents, never on a word in prose: the
   refusal already has legends in this tool's own output. *)
let register_run_wrapper_refusal_is_not_a_kill () =
  Test.register ~__FILE__
    ~title:"mutants: a wrapper refusal is never a kill and leaves the campaign open"
    ~tags:["mutants"; "run"; "refusal"]
  @@ fun () ->
  let db, work, _run, run_json =
    campaign_setup ~name:"mutants_refusal" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"REFUSED","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"KILLED","id":"m3"}
|}
  in
  Batch.run (fun b ->
      let code, out, _ = run_json ["--format"; "json"] in
      ignore code ;
      Batch.eq_int b ~msg:"the wrapper still ran once per mutant"
        (List.length (trace_rows work)) 3 ;
      (match Batch.expect b (Json.parse ~what:"refusal run" out) with
      | None -> ()
      | Some j ->
          List.iter
            (fun (key, expected) ->
              Option.iter
                (fun n -> Batch.eq_int b ~msg:("refusal run: " ^ key) n expected)
                (Batch.expect b (Json.int ~what:key key j)))
            [ (* m2 refused: counted apart, and in NONE of the four outcome buckets. *)
              ("mutants_refused_by_wrapper", 1);
              ("killed", 1); ("survived", 1); ("timed_out", 0); ("errored", 0);
              (* Two mutants were attempted, one was not, so one is PENDING. *)
              ("mutants_attempted", 2); ("mutants_pending", 1);
              (* m3 died under the singleton t_beta; m2 contributes nothing. *)
              ("attributions_recorded", 1) ] ;
          Option.iter
            (fun c -> Batch.eq_string b ~msg:"a refusal must leave the campaign incomplete"
                (string_of_bool c) "false")
            (Batch.expect b (Json.bool ~what:"completed" "completed" j))) ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"a refused mutant gets no run row"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 2 ;
          (* The decisive negative: nothing anywhere may record m2 as killed. *)
          Batch.eq_int b ~msg:"no run row may carry a KILLED status for the refused site"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id = r.mutant_id \
                WHERE m.file_path = 'lib/y.ml' AND r.engine_status = 'KILLED'")
            0 ;
          Batch.eq_string_opt b ~msg:"only m3's test may be named as a killer"
            (Db.string_opt conn "SELECT group_concat(test_name) FROM mutant_kills")
            (Some "t_beta") ;
          Batch.eq_int b ~msg:"completed_at must stay NULL while a mutant was refused"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL")
            0)) ;
  Lwt.return_unit

(* CHECK-25 / FR-007. A mutant for which the wrapper wrote NO trace line has an
   UNOBSERVED executed set, and an unobserved set is never an attribution.

   The old code read the trace with
   `Option.value ~default:sel.sel_executed (Hashtbl.find_opt …)`, so a missing
   line silently substituted the PLANNED set and recorded it as what ran. When
   that planned set was a singleton — which m2's is here, `other` being reached
   by t_gamma alone — it then wrote a `mutant_kills` row with
   `attribution = singleton_executed_set` naming a test nobody ever saw run: a
   fabricated attribution from the one table that exists to keep attribution
   honest.

   The fixture makes the buggy path REACHABLE rather than merely present: the
   engine skips m2 and only m2, and the report claims m2 was killed. *)
let register_run_unobserved_executed_set () =
  Test.register ~__FILE__
    ~title:"mutants: a mutant with no trace line is attributed to nobody"
    ~tags:["mutants"; "run"; "attribution"]
  @@ fun () ->
  let db, work, _run, run_json =
    campaign_setup ~name:"mutants_unobserved"
      (* m2 is deliberately absent: the engine never invokes the wrapper for it. *)
      ~engine_body:(stub_engine ["m1"; "m3"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/y.ml","line":35,"status":"KILLED","id":"m2"}
{"file":"lib/z.ml","line":55,"status":"SURVIVED","id":"m3"}
|}
  in
  Batch.run (fun b ->
      let code, out, _ = run_json ["--format"; "json"] in
      ignore code ;
      (* The premise, asserted rather than assumed: m2 really has no trace line,
         and m2's planned set really is the singleton the defect needed. *)
      Batch.eq_int b ~msg:"only two of the three mutants reached the wrapper"
        (List.length (trace_rows work)) 2 ;
      Batch.eq_string_opt b ~msg:"m2 must have written no trace line"
        (executed_for work "m2") None ;
      (match Batch.expect b (Json.parse ~what:"unobserved run" out) with
      | None -> ()
      | Some j ->
          List.iter
            (fun (key, expected) ->
              Option.iter
                (fun n -> Batch.eq_int b ~msg:("unobserved run: " ^ key) n expected)
                (Batch.expect b (Json.int ~what:key key j)))
            [ ("mutants_unobserved_executed_set", 1);
              ("mutants_attempted", 2); ("mutants_pending", 1);
              (* m2's KILLED is the only kill in the report, and it is unobserved,
                 so the campaign has none. *)
              ("killed", 0); ("survived", 2); ("attributions_recorded", 0) ] ;
          Option.iter
            (fun c ->
              Batch.eq_string b
                ~msg:"an unobserved executed set must leave the campaign incomplete"
                (string_of_bool c) "false")
            (Batch.expect b (Json.bool ~what:"completed" "completed" j))) ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"an unobserved mutant gets no run row"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 2 ;
          (* The one the pre-fix code invented. Named, not merely counted, so a
             regression is legible without re-deriving the fixture. *)
          Batch.eq_string_opt b ~msg:"t_gamma must never be named as a killer"
            (Db.string_opt conn
               "SELECT ifnull(group_concat(test_name), '(none)') FROM mutant_kills")
            (Some "(none)") ;
          Batch.eq_int b
            ~msg:"completed_at must stay NULL while an executed set was never observed"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL")
            0)) ;
  Lwt.return_unit

(* CHECK-26 / AC-24 / FR-030. The ancestor walk must not leave the working tree.

   `locate_wrapper` and `locate_impact` find their artefact by walking up from
   the working directory, so a checkout nested inside another one resolves the
   PARENT's wrapper — silently, with plausible output. The parent's binary is
   unmutated, every mutant survives, and the report becomes a page of false test
   gaps that reads exactly like a real finding. That is issue #77.

   Both polarities are asserted here, because only the second can tell a correct
   guard from one that refuses everything: the outer wrapper is refused, and the
   same fixture with an `ARCH_MUTANTS_WRAPPER` the operator named is honoured —
   the exemption FR-030 states, and the one this repo's own suite depends on. *)
let register_run_refuses_outside_tree () =
  Test.register ~__FILE__
    ~title:"mutants: run refuses a wrapper resolved outside the working tree"
    ~tags:["mutants"; "run"; "provenance"]
  @@ fun () ->
  let db = load_fixture "mutants_outside_tree" campaign_stream in
  let root = Temp.dir "mutants_outside_tree_nest" in
  let outer = Filename.concat root "outer" in
  let inner = Filename.concat outer "inner" in
  let outer_wrapper = Filename.concat outer "scripts/mutaml-wrapper.sh" in
  (* [write_exec] creates the file but not its directory, and the nesting IS the
     fixture, so the two levels are made explicitly. *)
  if Sys.command (Printf.sprintf "mkdir -p %s %s" (Filename.quote (Filename.concat outer "scripts")) (Filename.quote inner)) <> 0 then
    Test.fail "could not lay out the nested checkout fixture" ;
  write_exec outer_wrapper "#!/bin/sh\nexit 0\n" ;
  (* The inner directory must be its own working tree, or the boundary under test
     would be the enclosing one and the fixture would prove nothing. *)
  let git_code, git_out = run_command ~cwd:inner "git" ["init"; "-q"; "."] in
  if git_code <> 0 then Test.fail "could not make the inner tree a repository:\n%s" git_out ;
  let plan_file = Filename.concat inner "plan.json" in
  let _, plan_out = mutants ["plan"; db; "--tests"; "file:test/**"; "--format"; "json"] in
  write_file plan_file plan_out ;
  let catalogue = Filename.concat inner "catalogue.ndjson" in
  write_file catalogue campaign_catalogue ;
  let report_file = Filename.concat inner "report.ndjson" in
  write_file report_file all_survived ;
  let engine = Filename.concat inner "engine.sh" in
  write_exec engine "#!/bin/sh\nexit 0\n" ;
  let argv =
    ["run"; db; "--plan"; plan_file; "--engine"; engine; "--test-cmd"; "true";
     "--catalogue"; catalogue; "--report"; report_file; "--tests"; "file:test/**"]
  in
  (* `env -u` rather than an empty assignment: the driver REFUSES an override that
     names a path which does not exist, so blanking the variable would test a
     different refusal than the one under test. *)
  (* The assignments go into `env`'s OWN argument list, after the `-u`s. Passing
     them through [run_command]'s ~env would put them BEFORE the `env -u` that
     then strips them again — which is exactly what the second probe below
     caught on its first run. *)
  let invoke assignments =
    run_command ~cwd:inner "/usr/bin/env"
      (["-u"; "ARCH_MUTANTS_WRAPPER"; "-u"; "ARCH_IMPACT"; "-u"; "ARCH_MUTANTS"]
      @ assignments
      @ (arch_mutants () :: argv))
  in
  Batch.run (fun b ->
      let code, output = invoke [] in
      Batch.exit_code b
        ~msg:"a wrapper resolved outside the working tree must be REFUSED with exit 1"
        ~expected:1 (code, output) ;
      (* An exit code alone cannot tell a fired guard from an unrelated failure,
         so the message must name the artefact it declined to run. *)
      Batch.contains b ~msg:"the refusal must name the outside path" ~haystack:output
        outer_wrapper ;
      Db.with_db db (fun conn ->
          Batch.eq_int b
            ~msg:"a refused campaign must leave no campaign table behind"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0) ;
      (* The other polarity. Same nested fixture, same outside path — the only
         difference is that the operator named it, which FR-030 exempts. A guard
         that refuses here has broken every harness that points the driver at a
         built artefact outside its own tree on purpose. *)
      let code, output = invoke ["ARCH_MUTANTS_WRAPPER=" ^ outer_wrapper] in
      Batch.eq_string b
        ~msg:"an explicitly named wrapper outside the tree must NOT be refused"
        (string_of_bool (code = 1)) "false" ;
      Batch.not_contains b ~msg:"an operator-named override must not trip the boundary"
        ~haystack:output "OUTSIDE the working tree") ;
  Lwt.return_unit

(* The MEDIUM alongside FR-031. A test name is a function name harvested from the
   ANALYSED REPOSITORY'S OWN SOURCE, and it used to be spliced unquoted into the
   string the wrapper hands to `sh -c`, so a campaign over an untrusted checkout
   was arbitrary command execution. The wrapper now quotes; this asserts the
   second half of that fix, which is that a name carrying shell metacharacters is
   refused where selection.tsv is WRITTEN — at the point the bad name enters the
   pipeline, naming it, rather than where it would detonate. *)
let register_run_rejects_unsafe_test_name () =
  Test.register ~__FILE__
    ~title:"mutants: a test name carrying shell metacharacters is refused, not written"
    ~tags:["mutants"; "run"; "selection"]
  @@ fun () ->
  let evil = "t_evil;touch /tmp/arch-mutants-pwned" in
  let stream =
    Printf.sprintf
      {|{"type":"function","name":%S,"file_path":"test/evil_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":%S,"caller_file":"test/evil_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/evil_test.ml:2","kind":"MUST"}
|}
      evil evil
  in
  let db = load_fixture "mutants_unsafe_name" stream in
  let dir = Temp.dir "mutants_unsafe_name_campaign" in
  let plan_file = Filename.concat dir "plan.json" in
  let _, plan_out = mutants ["plan"; db; "--tests"; "file:test/**"; "--format"; "json"] in
  write_file plan_file plan_out ;
  let catalogue = Filename.concat dir "catalogue.ndjson" in
  write_file catalogue
    {|{"id":"m1","file":"lib/x.ml","line":15,"col_start":3,"col_end":9,"replacement":"true"}
|} ;
  let report_file = Filename.concat dir "report.ndjson" in
  write_file report_file
    {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
|} ;
  let engine = Filename.concat dir "engine.sh" in
  write_exec engine "#!/bin/sh\nexit 0\n" ;
  let work = Filename.concat dir "work" in
  Batch.run (fun b ->
      let code, output =
        run_command
          ~env:[("ARCH_MUTANTS_WORKDIR", work); ("ARCH_MUTANTS_WRAPPER", wrapper_path ())]
          (arch_mutants ())
          ["run"; db; "--plan"; plan_file; "--engine"; engine; "--test-cmd"; "true";
           "--catalogue"; catalogue; "--report"; report_file; "--tests"; "file:test/**"]
      in
      Batch.exit_code b ~msg:"an unsafe test name must abort the campaign" ~expected:2
        (code, output) ;
      Batch.contains b ~msg:"the refusal must name the offending test" ~haystack:output evil ;
      (* The verifiable half: the selection file the wrapper reads was never
         written, so the name never reached a command line at all. *)
      Batch.eq_string b ~msg:"selection.tsv must not exist after the refusal"
        (string_of_bool (Sys.file_exists (Filename.concat work "selection.tsv")))
        "false" ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"no campaign row may be written"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0)) ;
  Lwt.return_unit

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
        | None -> None
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
              [("killed", killed); ("survived", survived); ("errored", errored)] ;
            Some j
      in
      (* Mutants ran, none died: the picture an unmutated binary also produces. *)
      let survivors_json =
        check ~what:"all survivors" survivors_case ~tag:"uncertified_no_kill" ~killed:0
          ~survived:3 ~errored:0
      in
      (* Also zero kills, for an entirely different reason — nothing meaningfully
         ran — and it must NOT be reported in the same words. *)
      ignore
        (check ~what:"all errored" errors_case ~tag:"uncertified_all_errored" ~killed:0
           ~survived:0 ~errored:3) ;
      (* One kill is enough: a stale, unmutated binary cannot produce one. *)
      ignore
        (check ~what:"one kill" killed_case ~tag:"self_certifying" ~killed:1 ~survived:2
           ~errored:0) ;
      (* ---- AC-22 / FR-028: the campaign NAMES the binaries it resolved ----------------
         This is the half of CHECK-14 that was declared and never asserted. AC-21's
         certification tag alone does not close issue #77's failure mode: the all-survivor
         picture above is EXACTLY what an unmutated binary from an enclosing checkout
         produces, and the only thing that tells the two apart is which file actually ran.
         So the resolved paths are asserted against the fixture's OWN stub — not merely
         checked to be non-empty, which a hardcoded "/usr/bin/false" would satisfy — and
         the stored row is asserted to agree with the JSON, because a reader who opens the
         database gets the row and not the report. *)
      let db_of (db, _, _, _) = db in
      let stub_engine_path =
        Filename.concat (Temp.dir "mutants_uncert_surv_campaign") "engine.sh"
      in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "the fixture's engine stub must exist at %s, or the assertion below compares \
              two values neither of which is the binary that ran"
             stub_engine_path)
        (Sys.file_exists stub_engine_path) ;
      let json_string ~what key j =
        match Json.member key j with
        | Some (`String v) -> Some v
        | other ->
            Batch.note b "%s: %s is %s" what key (Json.show other) ;
            None
      in
      (match survivors_json with
      | None -> Batch.note b "all survivors: no JSON to read the resolved paths from"
      | Some j ->
          Option.iter
            (fun p ->
              Batch.eq_string b
                ~msg:"the report names the engine binary that actually ran" p
                stub_engine_path)
            (json_string ~what:"all survivors" "engine_path" j) ;
          Option.iter
            (fun p ->
              (* --test-cmd is `true`, and the claim is that the tool recorded what
                 RESOLUTION produced rather than echoing the operator's word back. So it
                 is compared against the answer this test resolves for itself, through
                 the same `command -v` the driver uses. On this machine `true` is a shell
                 builtin and that answer is the bare word — which is exactly why the
                 assertion is a comparison against an independently resolved value and
                 not "must look like a path": the latter would fail here for a reason
                 that has nothing to do with FR-028. *)
              Batch.eq_string b ~msg:"the report names the test runner AS RESOLVED"
                p (which "true"))
            (json_string ~what:"all survivors" "test_runner_path" j) ;
          (* And the STORED row, which is what a later reader of the database sees. *)
          Db.with_db (db_of survivors_case) (fun conn ->
              Batch.eq_string_opt b
                ~msg:"the stored campaign row carries the same engine_path as the report"
                (Db.string_opt conn "SELECT engine_path FROM mutant_campaigns ORDER BY id")
                (json_string ~what:"all survivors" "engine_path" j) ;
              Batch.eq_string_opt b
                ~msg:"the stored campaign row carries the same test_runner_path"
                (Db.string_opt conn
                   "SELECT test_runner_path FROM mutant_campaigns ORDER BY id")
                (json_string ~what:"all survivors" "test_runner_path" j)))) ;
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
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  let bounded =
    campaign_setup_on
      ~db:(load_fixture "mutants_verdict_top" campaign_stream_top)
      ~tests:"file:test/**" ~name:"mutants_verdict_top"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  (* The shared malformed-contract fixture, not a copy: arch-mutants must reach
     the same "no contract" verdict the other four tools reach on the same
     bytes, because they all read it through Arch_db.contract_ok. *)
  let no_contract =
    campaign_setup_on
      ~db:(Fixture.malformed_contract ~name:"mutants_verdict_nocontract")
      ~tests:"fn:A" ~name:"mutants_verdict_nocontract"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
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
      ()
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

(* ------------------------------------------------------------------------ *)
(* SLICE 3 — `--diff`: DIFF-SCOPED SELECTION.                                *)
(*                                                                          *)
(* The selected set is the UNION of three rules, and each fixture below is   *)
(* built so that exactly ONE of them can produce the answer being asserted.  *)
(* A fixture in which two rules would both select the same mutant proves     *)
(* nothing about either.                                                     *)
(*                                                                          *)
(* Every count here is worked out by hand from the fixture, never read back  *)
(* from the tool, and none of them is a `contains` on prose: a word survives *)
(* a great many wrong implementations because it can be present for a reason *)
(* unrelated to the branch that should have produced it. A count cannot.     *)
(* ------------------------------------------------------------------------ *)

(* Real files, long enough that every span in the index fixture exists in them:
   covered is lib/x.ml:10-20, other lib/y.ml:30-40, shared lib/z.ml:50-60,
   t_helper test/alpha_test.ml:11-13. The diff under test is produced by git
   from an edit to one of these lines, never written by the test. *)
let numbered n =
  String.concat "" (List.init n (fun i -> Printf.sprintf "line %d\n" (i + 1)))

let diff_files =
  [ ("lib/x.ml", numbered 25); ("lib/y.ml", numbered 45); ("lib/z.ml", numbered 65);
    ("test/alpha_test.ml", numbered 15); ("test/beta_test.ml", numbered 8);
    ("README.md", "readme\n") ]

let edit_line root rel n replacement =
  let path = Filename.concat root rel in
  let ls = String.split_on_char '\n' (read_file path) in
  write_file path
    (String.concat "\n" (List.mapi (fun i l -> if i = n - 1 then replacement else l) ls))

(* campaign_stream plus a SHARED TEST HELPER that both t_alpha and t_gamma call
   and that calls NOTHING. That leafness is the whole point of the fixture: a
   selection computed as "everything the touched helper reaches" would come out
   EMPTY, while the rule under test — "every case that traverses the helper, then
   everything those cases reach" — comes out as {covered, other}. The two are
   indistinguishable on any fixture whose helper calls production code. *)
let campaign_stream_helper =
  campaign_stream
  ^ {|{"type":"function","name":"t_helper","file_path":"test/alpha_test.ml","line_start":11,"line_end":13}
{"type":"call","caller_name":"t_alpha","caller_file":"test/alpha_test.ml","callee_name":"t_helper","callee_file":"test/alpha_test.ml","call_site":"test/alpha_test.ml:3","kind":"MUST"}
{"type":"call","caller_name":"t_gamma","caller_file":"test/alpha_test.ml","callee_name":"t_helper","callee_file":"test/alpha_test.ml","call_site":"test/alpha_test.ml:8","kind":"MUST"}
|}

let impact_env () = [("ARCH_IMPACT", arch_impact ())]

(* The `diff_scope` sub-object of `run --format json`. Returned as a pair with
   the whole document so a test can assert on both the scope and the run rows. *)
let scope_of b ~what run_json args =
  let _, out, _ = run_json (["--format"; "json"] @ args) in
  match Batch.expect b (Json.parse ~what out) with
  | None -> None
  | Some j -> (
      match Json.member "diff_scope" j with
      | Some ds -> Some (j, ds)
      | None ->
          Batch.note b "%s: the run output carries no diff_scope object" what ;
          None)

let run_files j =
  match Json.member "runs" j with
  | Some (`List l) ->
      String.concat ","
        (List.sort compare (Json.field_of_objects ~field:"file" l))
  | _ -> "<no runs>"

let joined b ~what k ds =
  match Json.strings ~what k ds with
  | Ok l -> String.concat "," (List.sort compare l)
  | Error e ->
      Batch.note b "%s" e ;
      "<unreadable>"

let sites b ~what k ds =
  match Json.list ~what k ds with
  | Ok l ->
      String.concat ","
        (List.sort compare
           (List.filter_map
              (function
                | `Assoc f -> (
                    match (List.assoc_opt "file" f, List.assoc_opt "line" f) with
                    | Some (`String p), Some (`Int n) -> Some (Printf.sprintf "%s:%d" p n)
                    | _ -> None)
                | _ -> None)
              l))
  | Error e ->
      Batch.note b "%s" e ;
      "<unreadable>"

let int_of b ~what k j expected =
  match Json.int ~what k j with
  | Ok n -> Batch.eq_int b ~msg:(what ^ ": " ^ k) n expected
  | Error e -> Batch.note b "%s" e

(* AC-13 / FR-016 rule 1. Selection is by FUNCTION, and the fixture proves it is
   not by line: the edited line is 12 and the only mutant in that function sits
   at line 15, so a line-granular selection would select NOTHING. The edit is a
   comment, so a change-intent heuristic would also select nothing. *)
let register_diff_touched_function () =
  Test.register ~__FILE__
    ~title:"mutants: --diff selects a touched function's mutants, by function and not by line"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  Fixture.git_project ~name:"mutants_diff_fn" ~files:diff_files @@ fun root ->
  let db, work, _, run_json =
    campaign_setup_on ~extra_env:(impact_env ())
      ~db:(load_fixture "mutants_diff_fn" campaign_stream)
      ~tests:"file:test/**" ~name:"mutants_diff_fn"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  (* Line 12 is inside covered (10-20) and is NOT the mutant's line (15). *)
  edit_line root "lib/x.ml" 12 "(* a comment, and nothing else *)" ;
  Fixture.git_commit ~cwd:root "comment inside covered" ;
  let scoped = ["--repo"; root; "--diff"; "HEAD~1..HEAD"] in
  Batch.run (fun b ->
      (match scope_of b ~what:"diff by function" run_json scoped with
      | None -> ()
      | Some (j, ds) ->
          Batch.eq_string b ~msg:"a hunk on line 12 must touch exactly 'covered'"
            (joined b ~what:"scope" "touched_functions" ds) "covered" ;
          (* Three catalogued, one selected: the two counts together cannot be
             satisfied by selecting everything nor by selecting nothing. *)
          int_of b ~what:"diff by function" "mutants_catalogued_before_scoping" j 3 ;
          int_of b ~what:"diff by function" "mutants_excluded_by_scope" j 2 ;
          Batch.eq_string b ~msg:"only the touched function's mutant may run" (run_files j)
            "lib/x.ml" ;
          (match Json.bool ~what:"scope" "whole_index" ds with
          | Ok v ->
              Batch.check b ~msg:"a scoped campaign must not report itself whole-index" (not v)
          | Error e -> Batch.note b "%s" e)) ;
      (* The wrapper was invoked for the selected mutant and refused for the other
         two, which never reach the trace. 1, not 3. *)
      Batch.eq_int b ~msg:"the wrapper must run only for the selected mutant"
        (List.length (trace_rows work)) 1 ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"only the selected mutant is persisted as a site"
            (Db.int conn "SELECT count(*) FROM mutants") 1 ;
          Batch.eq_int b ~msg:"only the selected mutant gets a run row"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 1) ;
      (* The same catalogue with NO --diff is whole-index selection, said so. The
         second campaign adds the two sites the scope had excluded: 1 -> 3 sites
         and 1 -> 4 runs, both hand-counted, and neither reachable if the first
         campaign had quietly catalogued all three. *)
      (* The SAME repo argument, so the only difference between the two campaigns
         is the --diff flag itself. *)
      (match scope_of b ~what:"whole index" run_json ["--repo"; root] with
      | None -> ()
      | Some (j, ds) -> (
          int_of b ~what:"whole index" "mutants_excluded_by_scope" j 0 ;
          Batch.eq_string b ~msg:"the whole-index run must publish no range"
            (match Json.member "range" ds with Some `Null -> "null" | other -> Json.show other)
            "null" ;
          match Json.bool ~what:"scope" "whole_index" ds with
          | Ok v ->
              Batch.check b ~msg:"an absent --diff must be reported as whole-index selection" v
          | Error e -> Batch.note b "%s" e)) ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"the unscoped re-run catalogues the two sites the scope excluded"
            (Db.int conn "SELECT count(*) FROM mutants") 3 ;
          Batch.eq_int b ~msg:"one run row from the scoped campaign, three from the unscoped one"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 4)) ;
  Lwt.return_unit

(* CHECK-16 / AC-12 / FR-016 rule 2. A diff touching ONLY a test helper selects
   mutants in the code that helper's tests reach. t_helper calls nothing, so the
   answer can only come from walking BACKWARD to the cases that traverse it and
   then forward from those. m3 (shared, reached only by t_beta) must stay out. *)
let register_diff_test_helper () =
  Test.register ~__FILE__
    ~title:
      "mutants: a diff touching only a test helper selects mutants in the code that helper's \
       tests reach"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  Fixture.git_project ~name:"mutants_diff_helper" ~files:diff_files @@ fun root ->
  let db, work, _, run_json =
    campaign_setup_on ~extra_env:(impact_env ())
      ~db:(load_fixture "mutants_diff_helper" campaign_stream_helper)
      ~tests:"file:test/**" ~name:"mutants_diff_helper"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  (* Line 12 is inside t_helper (11-13) and inside no production function. *)
  edit_line root "test/alpha_test.ml" 12 "  assert_shared_thing ()" ;
  Fixture.git_commit ~cwd:root "change the shared helper" ;
  Batch.run (fun b ->
      (match
         scope_of b ~what:"diff helper" run_json ["--repo"; root; "--diff"; "HEAD~1..HEAD"]
       with
      | None -> ()
      | Some (j, ds) ->
          Batch.eq_string b ~msg:"the diff must touch exactly the helper"
            (joined b ~what:"scope" "touched_functions" ds) "t_helper" ;
          Batch.eq_string b ~msg:"the helper must be recognised as a test, not as product code"
            (joined b ~what:"scope" "touched_tests" ds) "t_helper" ;
          (* The discriminating assertion. Forward from the helper alone is EMPTY
             because it calls nothing; the two cases that traverse it reach
             covered and other, and nothing reaches shared. *)
          Batch.eq_string b
            ~msg:"every case traversing the helper must contribute what IT reaches"
            (joined b ~what:"scope" "functions_reached_by_touched_tests" ds) "covered,other" ;
          Batch.eq_string b ~msg:"the mutants of both reached functions run, and no other"
            (run_files j) "lib/x.ml,lib/y.ml" ;
          int_of b ~what:"diff helper" "mutants_excluded_by_scope" j 1) ;
      Batch.eq_int b ~msg:"the wrapper runs for the two selected mutants and no more"
        (List.length (trace_rows work)) 2 ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"two run rows, one per selected mutant"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 2 ;
          Batch.eq_int b
            ~msg:"the mutant of the function no traversing case reaches must not run"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id = r.mutant_id \
                WHERE m.file_path = 'lib/z.ml'")
            0)) ;
  Lwt.return_unit

(* A prior campaign, seeded so that the deleted-test rule has BOTH arms present:
     lib/z.ml:55 — killed, exactly ONE kill row, naming a test the index no
                   longer carries. Re-selectable.
     lib/y.ml:35 — killed, NO kill row at all. Attribution was never known, so
                   nothing can say whether the deleted test was the only one
                   catching it: UN-RECHECKABLE.
     lib/x.ml:15 — killed, one kill row naming t_alpha, which is STILL in the
                   index. Not deleted, therefore not re-selected.
   Without the second row the un-recheckable half is asserted against nothing;
   without the third, "selects what a deleted test killed alone" is
   indistinguishable from "selects everything a prior campaign killed alone". *)
let seed_prior_campaign ~name =
  let db = load_fixture name campaign_stream in
  let migration = read_file (Filename.concat (repo_root ()) "mutants-schema-migration.sql") in
  Db.with_db_rw db (fun conn ->
      Db.exec conn migration ;
      Db.exec conn
        {|INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
            VALUES ('lib/x.ml',15,3,9,'true','prior-x','covered'),
                   ('lib/y.ml',35,1,4,'false','prior-y','other'),
                   ('lib/z.ml',55,2,7,'0','prior-z','shared');
          INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
            VALUES ('stub','/bin/true','/bin/true','case','2026-09-05T00:00:00Z');
          INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                                  intended_tests,executed_tests)
            SELECT 1, id, 'KILLED', 'proved_superset', 1, 1 FROM mutants;
          INSERT INTO mutant_kills(campaign_id,mutant_id,test_name,attribution)
            SELECT 1, id, 't_alpha', 'singleton_executed_set' FROM mutants
             WHERE file_path = 'lib/x.ml';
          INSERT INTO mutant_kills(campaign_id,mutant_id,test_name,attribution)
            SELECT 1, id, 't_deleted', 'singleton_executed_set' FROM mutants
             WHERE file_path = 'lib/z.ml';|}) ;
  db

(* FR-017 / EC-8. The range edits only README.md, so rules 1 and 2 select
   NOTHING and every mutant that runs got there through the deleted-test rule
   alone. That isolation is what makes the assertion mean something. *)
let register_diff_deleted_test () =
  Test.register ~__FILE__
    ~title:
      "mutants: a deleted test re-selects what it alone killed and names what cannot be \
       re-checked"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  Fixture.git_project ~name:"mutants_diff_deleted" ~files:diff_files @@ fun root ->
  let db, _, _, run_json =
    campaign_setup_on ~extra_env:(impact_env ())
      ~db:(seed_prior_campaign ~name:"mutants_diff_deleted")
      ~tests:"file:test/**" ~name:"mutants_diff_deleted"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  write_file (Filename.concat root "README.md") "readme, revised\n" ;
  Fixture.git_commit ~cwd:root "documentation only" ;
  Batch.run (fun b ->
      (match
         scope_of b ~what:"deleted test" run_json ["--repo"; root; "--diff"; "HEAD~1..HEAD"]
       with
      | None -> ()
      | Some (j, ds) ->
          (* Rules 1 and 2 contribute nothing, so nothing below can come from them. *)
          Batch.eq_string b ~msg:"a documentation-only range must touch no indexed function"
            (joined b ~what:"scope" "touched_functions" ds) "" ;
          Batch.eq_string b
            ~msg:"only the test absent from the current index counts as deleted"
            (joined b ~what:"scope" "deleted_tests" ds) "t_deleted" ;
          Batch.eq_string b ~msg:"the mutant the deleted test killed ALONE is re-selected"
            (sites b ~what:"scope" "rechecked_for_deleted_tests" ds) "lib/z.ml:55" ;
          (* The honest half. The killed mutant with no kill row cannot be shown
             safe from the deletion, so it is named rather than skipped. *)
          Batch.eq_string b
            ~msg:"a killed mutant whose attribution was never known is UN-RECHECKABLE"
            (sites b ~what:"scope" "unrecheckable" ds) "lib/y.ml:35" ;
          Batch.eq_string b ~msg:"only the re-checked mutant runs" (run_files j) "lib/z.ml" ;
          int_of b ~what:"deleted test" "mutants_excluded_by_scope" j 2) ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"the new campaign holds exactly the one re-checked mutant"
            (Db.int conn "SELECT count(*) FROM mutant_runs WHERE campaign_id = 2") 1 ;
          Batch.eq_int b
            ~msg:"the mutant attributed to a test that still exists must not be re-checked"
            (Db.int conn
               "SELECT count(*) FROM mutant_runs r JOIN mutants m ON m.id = r.mutant_id \
                WHERE r.campaign_id = 2 AND m.file_path = 'lib/x.ml'")
            0)) ;
  Lwt.return_unit

(* FR-032. Exit 3 from the scoping subprocess means REFUSED — the callee declined
   to answer — and must not be folded into a failure or into an empty result. An
   empty touched set selects nothing and reads as "nothing to test", which is the
   single worst way for this distinction to be lost.
   Asserted on the EXIT CODE together with a fact no wording can simulate: the
   database must carry no campaign table at all. *)
let register_diff_impact_refuses () =
  Test.register ~__FILE__
    ~title:"mutants: arch-impact exiting 3 is REFUSED, distinct from a failure and from an \
            empty scope"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  Fixture.git_project ~name:"mutants_diff_refuse" ~files:diff_files @@ fun root ->
  edit_line root "lib/x.ml" 12 "(* a comment *)" ;
  Fixture.git_commit ~cwd:root "comment inside covered" ;
  let dir = Temp.dir "mutants_diff_refuse_stubs" in
  let stub code =
    let p = Filename.concat dir (Printf.sprintf "impact-%d.sh" code) in
    write_exec p (Printf.sprintf "#!/bin/sh\nexit %d\n" code) ;
    p
  in
  let case ~name ~impact_exit ~expected =
    let db, _, run, _ =
      campaign_setup_on
        ~extra_env:[("ARCH_IMPACT", stub impact_exit)]
        ~db:(load_fixture name campaign_stream) ~tests:"file:test/**" ~name
        ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
    in
    (db, expected, run ["--repo"; root; "--diff"; "HEAD~1..HEAD"])
  in
  let refused = case ~name:"mutants_diff_refused" ~impact_exit:3 ~expected:3 in
  let failed = case ~name:"mutants_diff_failed" ~impact_exit:1 ~expected:2 in
  Batch.run (fun b ->
      List.iter
        (fun (what, (db, expected, outcome)) ->
          Batch.exit_code b ~msg:(what ^ ": the driver's own exit code") ~expected outcome ;
          (* The verifiable half: the driver opens the database for writing only
             after scoping succeeds, so neither path may leave a campaign table —
             an empty campaign would read as "no survivors". *)
          Db.with_db db (fun conn ->
              Batch.eq_int b ~msg:(what ^ ": no campaign table may exist")
                (Db.int conn
                   "SELECT count(*) FROM sqlite_master WHERE type='table' AND \
                    name='mutant_campaigns'")
                0))
        [("a refusal (3) stays a refusal", refused); ("a failure (1) is not a refusal", failed)]) ;
  Lwt.return_unit

(* ------------------------------------------------------------------------ *)
(* FR-034 / AC-28 / CHECK-19 — the verdict surface REFUSES what it cannot    *)
(* scope.                                                                   *)
(*                                                                          *)
(* PENDING is "a catalogued mutant site with no run row in this campaign",   *)
(* and NO TABLE records which sites a campaign catalogued. The only universe *)
(* the schema can derive is the global `mutants` site table — the database's *)
(* sites, not the campaign's. One campaign: the two coincide, the answer is  *)
(* right. Two campaigns over different sets: an open campaign reports the    *)
(* OTHER campaign's sites as PENDING, which is a WRONG answer, not a missing *)
(* one, and it is indistinguishable from a right one to its reader.          *)
(*                                                                          *)
(* So the fixture holds TWO campaigns over DISJOINT mutant sets, one of them *)
(* open. A single-campaign fixture would pass whether or not the refusal     *)
(* exists, because there the derivation is correct. And the single-campaign  *)
(* control below is what stops an implementation that refuses               *)
(* UNCONDITIONALLY from passing, together with the completed-campaign arm on *)
(* the two-campaign database itself.                                        *)
(* ------------------------------------------------------------------------ *)

(* Seed campaigns directly. The driver cannot produce this shape: `run` always
   catalogues the whole index, so two campaigns it writes share one site set and
   the ambiguity never arises. The mis-scoping is a property of the SCHEMA, so
   the fixture is written at the schema. *)
let seed_campaign_scoping ~name ~two_campaigns =
  let db = load_fixture name campaign_stream in
  let migration = read_file (Filename.concat (repo_root ()) "mutants-schema-migration.sql") in
  Db.with_db_rw db (fun conn ->
      Db.exec conn migration ;
      (* Set A — lib/x.ml, lib/y.ml — is campaign 1's. Set B — lib/z.ml, lib/d.ml —
         exists only when there is a second campaign to own it, so the one-campaign
         control really does have ONE site set and not a truncated two. *)
      Db.exec conn
        {|INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
            VALUES ('lib/x.ml',15,3,9,'true','hash-x','covered'),
                   ('lib/y.ml',35,1,4,'false','hash-y','shared');|} ;
      if two_campaigns then
        Db.exec conn
          {|INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
              VALUES ('lib/z.ml',55,2,6,'0','hash-z','orphan'),
                     ('lib/d.ml',3,1,2,'()','hash-d','dyn');|} ;
      let run campaign file status =
        Db.exec conn
          (Printf.sprintf
             "INSERT INTO mutant_runs(campaign_id,mutant_id,engine_mutant_id,engine_status,\
              selection_provenance,intended_tests,executed_tests) SELECT %d, id, 'e-'||id, \
              '%s', 'proved_superset', 1, 1 FROM mutants WHERE file_path = '%s'"
             campaign status file)
      in
      if two_campaigns then (
        (* Campaign 1 — COMPLETED, and it attempted BOTH of its own sites, so it has
           no pending set of its own to be wrong about. *)
        Db.exec conn
          {|INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
              VALUES ('stub','/bin/true','/bin/true','case','2026-09-05T00:00:00Z');|} ;
        run 1 "lib/x.ml" "KILLED" ;
        run 1 "lib/y.ml" "SURVIVED" ;
        (* Campaign 2 — OPEN, over the OTHER site set, one of its two sites attempted.
           Its true pending set is lib/d.ml alone: ONE site. Derived from the global
           site table it would be THREE — lib/d.ml plus both of campaign 1's. *)
        Db.exec conn
          {|INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
              VALUES ('stub','/bin/true','/bin/true','case',NULL);|} ;
        run 2 "lib/z.ml" "SURVIVED")
      else (
        (* The control: ONE campaign, OPEN, over the only site set there is. Here the
           global site table IS the campaign's catalogue, so PENDING is derivable and
           must be answered — lib/y.ml, one site. *)
        Db.exec conn
          {|INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
              VALUES ('stub','/bin/true','/bin/true','case',NULL);|} ;
        run 1 "lib/x.ml" "SURVIVED")) ;
  db

(* The refusal's own numbers, read back out of it. Asserting on a COUNT rather than
   on a word: "REFUSED" and "campaign" survive a great many wrong refusals — a
   refusal that fired for the wrong reason, or on the wrong campaign, still prints
   both — while `campaigns_in_db=2` is produced by the query whose answer decides
   the branch, so it cannot be right by accident. *)
let tagged_int output key =
  let key = key ^ "=" in
  let n = String.length output and k = String.length key in
  let rec find i =
    if i + k > n then None
    else if String.sub output i k = key then (
      let j = ref (i + k) in
      while !j < n && output.[!j] >= '0' && output.[!j] <= '9' do
        incr j
      done ;
      if !j = i + k then None else Some (int_of_string (String.sub output (i + k) (!j - i - k))))
    else find (i + 1)
  in
  find 0

let register_verdict_refuses_unscopable_pending () =
  Test.register ~__FILE__ ~title:"mutants: the verdict refuses an open campaign it cannot scope"
    ~tags:["mutants"; "verdict"]
  @@ fun () ->
  let two = seed_campaign_scoping ~name:"mutants_fr034_two" ~two_campaigns:true in
  let one = seed_campaign_scoping ~name:"mutants_fr034_one" ~two_campaigns:false in
  Batch.run (fun b ->
      (* The fixture is really the ambiguous one — asserted at the schema, not
         assumed. Without this, every assertion below could hold on a database that
         never had two campaigns or two site sets. *)
      Db.with_db two (fun conn ->
          Batch.eq_int b ~msg:"the fixture must hold two campaigns"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns") 2 ;
          Batch.eq_int b ~msg:"exactly one of them must be open"
            (Db.int conn "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NULL") 1 ;
          (* Disjoint: no mutant site carries a run row from both campaigns. A shared
             site would make the two campaigns' universes coincide and the ambiguity
             disappear. *)
          Batch.eq_int b ~msg:"the two campaigns must cover DIFFERENT mutant sets"
            (Db.int conn
               "SELECT count(*) FROM mutants m WHERE EXISTS (SELECT 1 FROM mutant_runs r \
                WHERE r.mutant_id = m.id AND r.campaign_id = 1) AND EXISTS (SELECT 1 FROM \
                mutant_runs r WHERE r.mutant_id = m.id AND r.campaign_id = 2)")
            0) ;

      (* 1. The open campaign in the two-campaign database: REFUSED, exit 3. *)
      let code, output = mutants ["verdict"; two; "--campaign"; "2"; "--format"; "json"] in
      Batch.exit_code b
        ~msg:"an open campaign in a two-campaign database must be REFUSED (3), not answered"
        ~expected:3 (code, output) ;
      (* Refused, not failed: 2 is this tool's failure code and would be a different
         fact about the same run. *)
      Batch.check b ~msg:"the refusal must not be reported as a failure (2)" (code <> 2) ;
      Batch.eq_int b ~msg:"the refusal must name how many campaigns the database holds"
        (Option.value ~default:(-1) (tagged_int output "campaigns_in_db"))
        2 ;
      Batch.eq_int b ~msg:"the refusal must name how many requested campaigns are open"
        (Option.value ~default:(-1) (tagged_int output "open_campaigns_requested"))
        1 ;
      (* The unscopable universe itself: four sites in the database, of which only
         two are campaign 2's. This number is the whole reason for the refusal. *)
      Batch.eq_int b ~msg:"the refusal must name the site universe it could not scope"
        (Option.value ~default:(-1) (tagged_int output "mutant_sites_in_db"))
        4 ;

      (* And with no --campaign at all, the open campaign is still in the requested
         set, so the same refusal applies. *)
      let code_all, out_all = mutants ["verdict"; two; "--format"; "json"] in
      Batch.exit_code b ~msg:"no --campaign still includes the open one, so it still refuses"
        ~expected:3 (code_all, out_all) ;
      Batch.eq_int b ~msg:"the unscoped request names the same open-campaign count"
        (Option.value ~default:(-1) (tagged_int out_all "open_campaigns_requested"))
        1 ;

      (* 2. The COMPLETED campaign in the SAME database answers normally: it has no
         pending set to get wrong. This is half of what stops an unconditional
         refusal passing — it fires on a two-campaign database and must not. *)
      (match verdict_of b ~what:"completed campaign" ~args:["--campaign"; "1"] two with
      | None -> Batch.note b "the completed campaign in a two-campaign database must be answered"
      | Some (c, fs) ->
          Batch.eq_int b ~msg:"the completed campaign reports its own two runs and nothing else"
            (List.length fs) 2 ;
          verdict_count b ~what:"completed campaign" c "PENDING" 0 ;
          verdict_count b ~what:"completed campaign" c "KILLED" 1 ;
          verdict_count b ~what:"completed campaign" c "SURVIVED" 1 ;
          (* Campaign 2's sites must not appear at all — neither as findings nor,
             above, as PENDING. *)
          Batch.eq_string_opt b ~msg:"the other campaign's site is absent, not PENDING"
            (finding_field fs ~file:"lib/z.ml" "published_verdict")
            None) ;

      (* 3. The single-campaign control: an OPEN campaign, and it is answered. The
         other half of the negative arm — a refusal that fired here would be refusing
         a question it can answer correctly. *)
      match verdict_of b ~what:"single campaign" ~args:["--campaign"; "1"] one with
      | None -> Batch.note b "a single-campaign database with an open campaign must be answered"
      | Some (c, fs) ->
          Batch.eq_int b ~msg:"one attempted site and one pending, both reported"
            (List.length fs) 2 ;
          (* Hand-counted from the fixture: lib/x.ml ran, lib/y.ml did not. *)
          verdict_count b ~what:"single campaign" c "PENDING" 1 ;
          verdict_count b ~what:"single campaign" c "SURVIVED" 1 ;
          Batch.eq_string_opt b ~msg:"the unattempted site is PENDING on a scopable database"
            (finding_field fs ~file:"lib/y.ml" "published_verdict")
            (Some "PENDING")) ;
  Lwt.return_unit

(* ------------------------------------------------------------------------ *)
(* `report` — the OTHER surface a status is published on.                    *)
(*                                                                          *)
(* `run` and `verdict` were built around FR-011 and FR-013; `report` was     *)
(* not, and it is the subcommand a CI pipeline actually invokes. It answers  *)
(* about an engine's own report file with no campaign row behind it, but a   *)
(* backward test-closure is a LOWER BOUND there too — MAY_TOP edges are      *)
(* never traversed — so the same rule holds: SURVIVED publishes as SURVIVED  *)
(* only under `proved_superset`.                                            *)
(* ------------------------------------------------------------------------ *)

(* One SURVIVED inside `covered` (lib/x.ml:10-20), replayed over two indexes that
   differ in exactly one edge. The engine's report is BYTE-IDENTICAL in both arms,
   so any difference below is the index's and nothing else's. *)
let one_survivor_report =
  {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1","mutation":"a && b -> a || b"}
|}

let register_report_provenance () =
  Test.register ~__FILE__
    ~title:"mutants: report publishes no survivor without its provenance, and its gate \
            follows the verdict"
    ~tags:["mutants"; "report"]
  @@ fun () ->
  let closed = load_fixture "mutants_report_closed" campaign_stream in
  let bounded = load_fixture "mutants_report_bounded" campaign_stream_top in
  let report = Temp.file "mutants_report_provenance.ndjson" in
  write_file report one_survivor_report ;
  Batch.run (fun b ->
      let arm ~what db ~provenance ~verdict ~gate =
        (match
           mutants_json b ~what
             ["report"; db; report; "--tests"; "file:test/**"; "--format"; "json"]
         with
        | None -> ()
        | Some j ->
            let str key =
              match Json.member key j with
              | Some (`String v) -> Some v
              | other ->
                  Batch.note b "%s: %s is %s" what key (Json.show other) ;
                  None
            in
            Batch.eq_string_opt b ~msg:(what ^ ": the document names its provenance")
              (str "selection_provenance") (Some provenance) ;
            (* And on the SURVIVOR RECORD itself, which is the line a reader copies
               out of the report. A provenance living only at the top of the document
               does not travel with it. *)
            (match expect b (Json.list ~what "survivors" j) with
            | None -> ()
            | Some [ `Assoc f ] ->
                Batch.eq_string_opt b
                  ~msg:(what ^ ": the survivor record carries its own provenance")
                  (match List.assoc_opt "selection_provenance" f with
                  | Some (`String v) -> Some v
                  | _ -> None)
                  (Some provenance) ;
                Batch.eq_string_opt b
                  ~msg:(what ^ ": the survivor record publishes the DERIVED verdict")
                  (match List.assoc_opt "verdict" f with
                  | Some (`String v) -> Some v
                  | _ -> None)
                  (Some verdict)
            | Some l ->
                Batch.note b "%s: expected exactly one survivor, got %d" what
                  (List.length l))) ;
        (* The gate. A defect list is a list of things genuinely SURVIVED; a mutant
           whose reaching tests may never have run is not one, and failing a build
           on it is a false accusation against a real test. *)
        Batch.exit_code b ~msg:(what ^ ": --fail-on-survivors") ~expected:gate
          (mutants ["report"; db; report; "--tests"; "file:test/**"; "--fail-on-survivors"])
      in
      (* The ⊤-free index: the closure is complete, so the survivor is a real gap and
         the gate must fire. Without this arm, "never fail" would satisfy the other. *)
      arm ~what:"closed cone" closed ~provenance:"proved_superset" ~verdict:"SURVIVED"
        ~gate:1 ;
      (* One ⊤ edge inside the test cone, and the same engine report: UNKNOWN, and the
         gate must NOT fire. *)
      arm ~what:"⊤ inside the cone" bounded ~provenance:"top_bounded" ~verdict:"UNKNOWN"
        ~gate:0) ;
  Lwt.return_unit

(* FR-031. `load_mutaml` has always died on an unrecognised status; `load_generic`
   read the field as a bare string and `report`'s bucketing ended in a catch-all,
   so a misspelled status was counted as an ENGINE ERROR — a defect removed from the
   defect list with no crash and no log, and a gate that still exits 0.
   Asserted on the EXIT CODE and on the offending string being NAMED, plus the
   negative control that the five legal values still load: without the latter,
   refusing every report would pass. *)
let register_report_status_vocabulary () =
  Test.register ~__FILE__
    ~title:"mutants: report refuses a status outside the closed vocabulary, never counts it"
    ~tags:["mutants"; "report"]
  @@ fun () ->
  let db = load_fixture "mutants_report_vocab" campaign_stream in
  let write name body = let p = Temp.file name in write_file p body ; p in
  let typo = write "mutants_vocab_typo.ndjson"
      {|{"file":"lib/x.ml","line":15,"status":"SURVIVE","id":"m1"}
|}
  in
  let future = write "mutants_vocab_future.ndjson"
      {|{"file":"lib/x.ml","line":15,"status":"SKIPPED","id":"m1"}
|}
  in
  let legal = write "mutants_vocab_legal.ndjson"
      {|{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1"}
{"file":"lib/x.ml","line":16,"status":"KILLED","id":"m2"}
{"file":"lib/x.ml","line":17,"status":"TIMEOUT","id":"m3"}
{"file":"lib/x.ml","line":18,"status":"ERROR","id":"m4"}
{"file":"lib/x.ml","line":19,"status":"REFUSED","id":"m5"}
|}
  in
  Batch.run (fun b ->
      let code, out =
        mutants ["report"; db; typo; "--tests"; "file:test/**"; "--format"; "json"]
      in
      Batch.eq_int b ~msg:"a misspelled status aborts rather than being bucketed" code 2 ;
      Batch.contains b ~msg:"the refusal names the offending string" ~haystack:out "SURVIVE" ;
      Batch.not_contains b
        ~msg:"nothing was counted on the way out — no report was printed at all"
        ~haystack:out "\"errored\"" ;
      Batch.exit_code b ~msg:"the gate cannot pass on a report it did not understand"
        ~expected:2
        (mutants ["report"; db; typo; "--tests"; "file:test/**"; "--fail-on-survivors"]) ;
      Batch.exit_code b
        ~msg:"a value added to the vocabulary elsewhere aborts here too" ~expected:2
        (mutants ["report"; db; future; "--tests"; "file:test/**"; "--format"; "json"]) ;
      (* NEGATIVE CONTROL. Without it, a `report` that refused every input would
         satisfy every assertion above. *)
      (* Read through the SPLIT runner. `report` writes its errored-mutant NOTE to
         stderr precisely so stdout stays one parseable object; merging them back
         together here would break the parse for a reason unrelated to the code. *)
      let json_stdout ~what args =
        let code, out, err = run_command_split (arch_mutants ()) args in
        if code <> 0 then (
          Batch.note b "%s: arch-mutants exited %d:\n%s" what code err ;
          None)
        else Batch.expect b (Json.parse ~what out)
      in
      match
        json_stdout ~what:"legal vocabulary"
          ["report"; db; legal; "--tests"; "file:test/**"; "--format"; "json"]
      with
      | None -> ()
      | Some j ->
          List.iter
            (fun (key, expected) ->
              Option.iter
                (fun n -> Batch.eq_int b ~msg:("legal vocabulary: " ^ key) n expected)
                (expect b (Json.int ~what:"legal vocabulary" key j)))
            [("killed", 2); ("errored", 1); ("refused_by_wrapper", 1); ("total", 5)] ;
          Option.iter
            (fun l ->
              Batch.eq_int b ~msg:"SURVIVED is the only survivor" (List.length l) 1)
            (expect b (Json.list ~what:"legal vocabulary" "survivors" j))) ;
  Lwt.return_unit

(* FR-013 / FR-018. `prior_mutants` read `engine_status` with no
   `selection_provenance` beside it and collapsed the row to a boolean, so a
   SURVIVED recorded under a ⊤-BOUNDED selection — UNKNOWN everywhere else in this
   tool — was treated here as a PROVEN non-kill and dropped from the un-recheckable
   list.

   The seed carries all three polarities under one completed campaign:
     lib/x.ml:15  KILLED / proved_superset, ONE kill row naming a test the index no
                  longer carries → re-checked, and the reason `deleted_tests` is
                  non-empty at all;
     lib/y.ml:35  SURVIVED / top_bounded, no kill row → UN-RECHECKABLE;
     lib/z.ml:55  SURVIVED / proved_superset, no kill row → NOT un-recheckable, the
                  negative control without which "call every survivor un-recheckable"
                  would pass. *)
let seed_prior_bounded_survivor ~name =
  let db = load_fixture name campaign_stream in
  let migration = read_file (Filename.concat (repo_root ()) "mutants-schema-migration.sql") in
  Db.with_db_rw db (fun conn ->
      Db.exec conn migration ;
      Db.exec conn
        {|INSERT INTO mutants(file_path,line,col_start,col_end,replacement,source_hash,function_name)
            VALUES ('lib/x.ml',15,3,9,'true','prior-x','covered'),
                   ('lib/y.ml',35,1,4,'false','prior-y','other'),
                   ('lib/z.ml',55,2,7,'0','prior-z','shared');
          INSERT INTO mutant_campaigns(engine,engine_path,test_runner_path,granularity,completed_at)
            VALUES ('stub','/bin/true','/bin/true','case','2026-09-05T00:00:00Z');
          INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                                  intended_tests,executed_tests)
            SELECT 1, id, 'KILLED', 'proved_superset', 1, 1 FROM mutants WHERE file_path='lib/x.ml';
          INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                                  intended_tests,executed_tests)
            SELECT 1, id, 'SURVIVED', 'top_bounded', 1, 1 FROM mutants WHERE file_path='lib/y.ml';
          INSERT INTO mutant_runs(campaign_id,mutant_id,engine_status,selection_provenance,
                                  intended_tests,executed_tests)
            SELECT 1, id, 'SURVIVED', 'proved_superset', 1, 1 FROM mutants WHERE file_path='lib/z.ml';
          INSERT INTO mutant_kills(campaign_id,mutant_id,test_name,attribution)
            SELECT 1, id, 't_deleted', 'singleton_executed_set' FROM mutants
             WHERE file_path = 'lib/x.ml';|}) ;
  db

let register_diff_bounded_survivor_unrecheckable () =
  Test.register ~__FILE__
    ~title:
      "mutants: a ⊤-bounded prior SURVIVED is un-recheckable, never a proven non-kill"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  Fixture.git_project ~name:"mutants_diff_bounded" ~files:diff_files @@ fun root ->
  let db = seed_prior_bounded_survivor ~name:"mutants_diff_bounded" in
  let _, _, _, run_json =
    campaign_setup_on ~extra_env:(impact_env ()) ~db ~tests:"file:test/**"
      ~name:"mutants_diff_bounded" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:all_survived ()
  in
  write_file (Filename.concat root "README.md") "readme, revised\n" ;
  Fixture.git_commit ~cwd:root "documentation only" ;
  Batch.run (fun b ->
      (* PRECONDITION, read off the database rather than off the tool under test: the two
         SURVIVED rows must really differ in provenance and neither may carry a kill row.
         Without that contrast every assertion below would pass vacuously. *)
      Db.with_db db (fun conn ->
          Batch.eq_string b ~msg:"the seed holds one bounded and one proved survivor"
            (String.concat "|"
               (Db.strings conn
                  "SELECT r.selection_provenance FROM mutant_runs r JOIN mutants m ON \
                   m.id = r.mutant_id WHERE r.engine_status = 'SURVIVED' ORDER BY \
                   m.file_path"))
            "top_bounded|proved_superset" ;
          Batch.eq_int b ~msg:"neither survivor carries a kill row"
            (Db.int conn
               "SELECT count(*) FROM mutant_kills k JOIN mutant_runs r ON r.mutant_id = \
                k.mutant_id WHERE r.engine_status = 'SURVIVED'")
            0) ;
      match
        scope_of b ~what:"bounded survivor" run_json
          ["--repo"; root; "--diff"; "HEAD~1..HEAD"]
      with
      | None -> ()
      | Some (_, ds) ->
          (* Rules 1 and 2 contribute nothing, so nothing below can have come from them. *)
          Batch.eq_string b ~msg:"a documentation-only range touches no indexed function"
            (joined b ~what:"scope" "touched_functions" ds) "" ;
          Batch.eq_string b ~msg:"only the absent test counts as deleted"
            (joined b ~what:"scope" "deleted_tests" ds) "t_deleted" ;
          Batch.eq_string b ~msg:"the mutant a deleted test killed ALONE is re-selected"
            (sites b ~what:"scope" "rechecked_for_deleted_tests" ds) "lib/x.ml:15" ;
          (* THE FINDING, together with its negative control in one assertion: the
             ⊤-bounded survivor is named, the proved one is not. *)
          Batch.eq_string b
            ~msg:"a ⊤-bounded SURVIVED is un-recheckable; a proved one is not"
            (sites b ~what:"scope" "unrecheckable" ds) "lib/y.ml:35") ;
  Lwt.return_unit

(* ------------------------------------------------------------------------ *)
(* ROUND 3 — the driver and the wrapper                                     *)
(* ------------------------------------------------------------------------ *)

(* THE JOIN. Engine outcomes were matched to catalogued sites by
   `Filename.basename file` plus LINE alone, consuming duplicates in list order
   and never refusing — so two mutants on one line had their KILLED/SURVIVED
   verdicts stored against EACH OTHER, and a `mutant_kills` row landed on a file
   that merely shared a basename, under `attribution = singleton_executed_set`,
   the one attribution that claims to name a killer.

   Both discriminators were present and discarded: the schema's key is
   UNIQUE(file_path, line, col_start, col_end, replacement, source_hash), and
   the engine's own id is carried by the catalogue record AND by the report
   entry.

   Asserted on the DATABASE keyed by COLUMN, never on a rendered line: the
   inversion is invisible in any rendering that groups by file and line, which
   is why it survived two review rounds. *)
let two_on_one_line_catalogue =
  {|{"id":"m1","file":"lib/x.ml","line":15,"col_start":3,"col_end":9,"replacement":"true"}
{"id":"m2","file":"lib/x.ml","line":15,"col_start":11,"col_end":15,"replacement":"false"}
|}

let register_run_join_is_site_identity () =
  Test.register ~__FILE__
    ~title:"mutants: two mutants on one line keep their own verdicts, and an ambiguous \
            entry is refused"
    ~tags:["mutants"; "run"; "join"]
  @@ fun () ->
  let db, _, _, run_json =
    campaign_setup_on ~db:(load_fixture "mutants_join" campaign_stream)
      ~tests:"file:test/**" ~name:"mutants_join" ~catalogue:two_on_one_line_catalogue
      ~engine_body:(stub_engine ["m1"; "m2"])
        (* The engine reports the SECOND mutant first. A join that consumes
           duplicates in list order pairs each outcome with the other site. *)
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"KILLED","id":"m2","col_start":11,"col_end":15,"replacement":"false"}
{"file":"lib/x.ml","line":15,"status":"SURVIVED","id":"m1","col_start":3,"col_end":9,"replacement":"true"}
|}
      ()
  in
  (* The AMBIGUOUS case, on its own database: a report entry naming an id the
     catalogue does not know and carrying neither a column span nor a
     replacement matches BOTH sites and can be told apart from neither. *)
  let db2, _, run2, _ =
    campaign_setup_on ~db:(load_fixture "mutants_join_ambiguous" campaign_stream)
      ~tests:"file:test/**" ~name:"mutants_join_ambiguous"
      ~catalogue:two_on_one_line_catalogue ~engine_body:(stub_engine ["m1"; "m2"])
      ~report:{|{"file":"lib/x.ml","line":15,"status":"KILLED","id":"zz"}
|}
      ()
  in
  Batch.run (fun b ->
      let _ = run_json ["--format"; "json"] in
      Db.with_db db (fun conn ->
          Batch.eq_string_opt b
            ~msg:"the mutant at columns 3-9 keeps the SURVIVED the engine gave IT"
            (Db.string_opt conn
               "SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id = \
                r.mutant_id WHERE m.col_start = 3")
            (Some "SURVIVED") ;
          Batch.eq_string_opt b
            ~msg:"the mutant at columns 11-15 keeps the KILLED the engine gave IT"
            (Db.string_opt conn
               "SELECT r.engine_status FROM mutant_runs r JOIN mutants m ON m.id = \
                r.mutant_id WHERE m.col_start = 11")
            (Some "KILLED") ;
          (* The traceability column must travel with the site it belongs to,
             or a mispairing leaves no trace even in the column that exists to
             record one. *)
          Batch.eq_string_opt b ~msg:"the engine id travels with its own site"
            (Db.string_opt conn
               "SELECT r.engine_mutant_id FROM mutant_runs r JOIN mutants m ON m.id = \
                r.mutant_id WHERE m.col_start = 3")
            (Some "m1")) ;
      let code, output = run2 [] in
      Batch.exit_code b
        ~msg:"two indistinguishable candidates must be REFUSED, not resolved by list order"
        ~expected:1 (code, output) ;
      Batch.contains b ~msg:"the refusal must say the sites could not be told apart"
        ~haystack:output "INDISTINGUISHABLE" ;
      Db.with_db db2 (fun conn ->
          Batch.eq_int b ~msg:"no kill row may be written on a coin flip"
            (Db.int conn "SELECT count(*) FROM mutant_kills") 0 ;
          Batch.eq_int b ~msg:"a refused join leaves the campaign incomplete"
            (Db.int conn
               "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL")
            0)) ;
  Lwt.return_unit

(* A --diff whose narrowing leaves ZERO mutants used to produce a COMPLETED
   campaign with no run rows, which `verdict` published as all-zero counts —
   an empty read reported in the same words as a clean one. And
   `report_entries_unmatched`, a total join failure when it equals the report's
   size, was published in the JSON and left out of the `complete` conjunction.

   The impact stub names a function this index does not carry, so rules 1 and 2
   select nothing and there is no prior campaign for rule 3 to draw on. *)
let register_run_empty_scope_and_unmatched () =
  Test.register ~__FILE__
    ~title:"mutants: a --diff narrowed to zero is refused, and an unmatched report entry \
            blocks completion"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  let dir = Temp.dir "mutants_empty_scope_stub" in
  let impact = Filename.concat dir "impact.sh" in
  write_exec impact
    "#!/bin/sh\ncat <<'J'\n{\"touched\": [{\"name\":\"no_such_function\",\"how\":\"line\"}]}\nJ\n" ;
  let db, _, run, _ =
    campaign_setup_on ~extra_env:[("ARCH_IMPACT", impact)]
      ~db:(load_fixture "mutants_empty_scope" campaign_stream) ~tests:"file:test/**"
      ~name:"mutants_empty_scope" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:all_survived ()
  in
  (* The other half, on its own database and with no --diff at all: every report
     entry names a site the catalogue does not hold. *)
  let db2, _, _, run2_json =
    campaign_setup_on ~db:(load_fixture "mutants_unmatched" campaign_stream)
      ~tests:"file:test/**" ~name:"mutants_unmatched"
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:
        {|{"file":"lib/nowhere.ml","line":99,"status":"KILLED","id":"ghost1"}
{"file":"lib/nowhere.ml","line":98,"status":"KILLED","id":"ghost2"}
|}
      ()
  in
  Batch.run (fun b ->
      let code, output = run ["--diff"; "HEAD~1..HEAD"] in
      Batch.exit_code b
        ~msg:"a --diff that narrows the catalogue to zero must be REFUSED with exit 1"
        ~expected:1 (code, output) ;
      Batch.contains b ~msg:"the refusal must name the conflation it is preventing"
        ~haystack:output "nothing to test" ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"a refused scope must leave no campaign table behind"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0) ;
      (match Batch.expect b (Json.parse ~what:"unmatched run"
                               (let _, out, _ = run2_json ["--format"; "json"] in out))
       with
      | None -> ()
      | Some j ->
          int_of b ~what:"unmatched run" "report_entries_unmatched" j 2 ;
          Option.iter
            (fun c ->
              Batch.eq_string b
                ~msg:"a total join failure must leave the campaign incomplete"
                (string_of_bool c) "false")
            (Batch.expect b (Json.bool ~what:"completed" "completed" j))) ;
      Db.with_db db2 (fun conn ->
          Batch.eq_int b
            ~msg:"completed_at must stay NULL when no report entry matched a site"
            (Db.int conn
               "SELECT count(*) FROM mutant_campaigns WHERE completed_at IS NOT NULL")
            0)) ;
  Lwt.return_unit

(* An `arch-impact` answer whose entries the reader cannot understand — a
   renamed `name` field — was dropped by `List.filter_map` with NO count, so a
   touched set silently shrunk from twelve to three was indistinguishable from a
   correct set of three, and every mutant outside it published as "not at risk"
   rather than "not looked at". *)
let register_run_impact_entries_counted () =
  Test.register ~__FILE__
    ~title:"mutants: arch-impact entries the reader cannot understand are counted, never \
            dropped"
    ~tags:["mutants"; "run"; "diff"]
  @@ fun () ->
  let dir = Temp.dir "mutants_impact_renamed_stub" in
  let impact = Filename.concat dir "impact.sh" in
  write_exec impact
    "#!/bin/sh\ncat <<'J'\n{\"touched\": [{\"fn\":\"covered\",\"how\":\"line\"},{\"fn\":\"other\",\"how\":\"line\"}]}\nJ\n" ;
  let db, _, run, _ =
    campaign_setup_on ~extra_env:[("ARCH_IMPACT", impact)]
      ~db:(load_fixture "mutants_impact_renamed" campaign_stream) ~tests:"file:test/**"
      ~name:"mutants_impact_renamed" ~engine_body:(stub_engine ["m1"; "m2"; "m3"])
      ~report:all_survived ()
  in
  Batch.run (fun b ->
      let code, output = run ["--diff"; "HEAD~1..HEAD"] in
      Batch.exit_code b ~msg:"unreadable touched entries must abort the campaign"
        ~expected:2 (code, output) ;
      (* The COUNT, not the word: "2 of them" is a number worked out from the
         stub's own two entries, and a message that merely mentions the field
         name would satisfy a grep while counting nothing. *)
      Batch.contains b ~msg:"the refusal must say HOW MANY entries it could not read"
        ~haystack:output "2 of them carry no string `name` field" ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"nothing is written when the scope could not be read"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0)) ;
  Lwt.return_unit

(* A survivor the index maps to no function was published as
   {file, line, status, id, mutation} — a naked engine status — inside a document
   whose own top-level key said survivors publish as UNKNOWN. And the headline
   counted `List.length survivors`, which excludes the unmapped, so a report
   holding one surviving mutant read "0 survived" while `--fail-on-survivors`
   counted it. *)
let register_report_unmapped_survivor_carries_verdict () =
  Test.register ~__FILE__
    ~title:"mutants: an unmapped survivor carries its verdict and is counted in the headline"
    ~tags:["mutants"; "report"]
  @@ fun () ->
  (* campaign_stream_top holds one ⊤ edge INSIDE the test cone, so the published
     verdict is UNKNOWN and not SURVIVED — which is what makes a naked
     "SURVIVED" on the record visibly the wrong answer rather than a shorthand
     for the right one. *)
  let db = load_fixture "mutants_unmapped_survivor" campaign_stream_top in
  let dir = Temp.dir "mutants_unmapped_survivor_report" in
  let report_file = Filename.concat dir "report.ndjson" in
  write_file report_file
    {|{"file":"lib/zzz_unmapped.ml","line":999,"status":"SURVIVED","id":"u1","mutation":"a && b -> a || b"}
|} ;
  Batch.run (fun b ->
      (match
         mutants_json b ~what:"unmapped survivor"
           ["report"; db; report_file; "--tests"; "file:test/**"; "--format"; "json"]
       with
      | None -> ()
      | Some j -> (
          (* The premise, asserted rather than assumed: if the fixture stopped
             producing a ⊤-bounded selection the assertions below would still
             pass while checking nothing. *)
          Batch.eq_string b ~msg:"the fixture really is ⊤-bounded"
            (match Json.member "survivors_publish_as" j with
            | Some (`String v) -> v
            | other -> Json.show other)
            "UNKNOWN" ;
          match expect b (Json.list ~what:"report" "unmapped" j) with
          | None -> ()
          | Some [ `Assoc f ] ->
              let field k =
                match List.assoc_opt k f with Some (`String v) -> Some v | _ -> None
              in
              Batch.eq_string_opt b
                ~msg:"the unmapped record carries a VERDICT, not a naked status"
                (field "verdict") (Some "UNKNOWN") ;
              Batch.eq_string_opt b
                ~msg:"and its selection provenance travels with it (FR-013)"
                (field "selection_provenance") (Some "top_bounded") ;
              Batch.eq_string_opt b
                ~msg:"the engine status is kept BESIDE the verdict, never instead of it"
                (field "status") (Some "SURVIVED") ;
              Batch.eq_int b ~msg:"the basis the verdict was derived from is present"
                (match field "verdict_basis" with
                | Some s when String.length s > 0 -> 1
                | _ -> 0)
                1
          | Some l ->
              Batch.note b "expected exactly one unmapped record, got %d" (List.length l))) ;
      let code, text =
        mutants ["report"; db; report_file; "--tests"; "file:test/**"]
      in
      Batch.exit_code b ~msg:"the text rendering must succeed" ~expected:0 (code, text) ;
      (* The headline is what a reader acts on, and it contradicted the gate on
         the same run: one surviving mutant, "0 survived". *)
      Batch.contains b ~msg:"the headline counts the unmapped survivor" ~haystack:text
        "1 mutant(s) in the report: 1 survived" ;
      Batch.contains b ~msg:"and names the unmapped share inline" ~haystack:text
        "1 of them unmapped to any indexed function" ;
      Batch.contains b ~msg:"the unmapped survivor's own line carries its verdict"
        ~haystack:text "UNKNOWN lib/zzz_unmapped.ml:999") ;
  Lwt.return_unit

(* The shell-injection allowlist excluded the apostrophe — an ordinary OCaml
   identifier character (`aux'`, `loop'`, `test_foo'`) — so ONE such name
   anywhere in the reaching set aborted the WHOLE campaign at exit 2 with no
   campaign row. It is also the one excluded character the wrapper demonstrably
   handles: every name is POSIX-quoted before substitution.

   The negative control travels with it: comma, tab and newline stay refused,
   because they are the separators the refusal message itself argues for. *)
let prime_stream =
  {|{"type":"function","name":"test_alpha'","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"test_alpha'","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
|}

let comma_stream =
  {|{"type":"function","name":"test_a,b","file_path":"test/alpha_test.ml","line_start":1,"line_end":5}
{"type":"function","name":"covered","file_path":"lib/x.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"test_a,b","caller_file":"test/alpha_test.ml","callee_name":"covered","callee_file":"lib/x.ml","call_site":"test/alpha_test.ml:2","kind":"MUST"}
|}

let one_mutant_catalogue =
  {|{"id":"m1","file":"lib/x.ml","line":15,"col_start":3,"col_end":9,"replacement":"true"}
|}

let register_run_accepts_prime_suffixed_test_name () =
  Test.register ~__FILE__
    ~title:"mutants: a prime-suffixed test name runs to completion; a comma is still refused"
    ~tags:["mutants"; "run"; "names"]
  @@ fun () ->
  let db, work, _, run_json =
    campaign_setup_on ~db:(load_fixture "mutants_prime" prime_stream)
      ~tests:"file:test/**" ~name:"mutants_prime" ~catalogue:one_mutant_catalogue
      ~engine_body:(stub_engine ["m1"])
      ~report:
        {|{"file":"lib/x.ml","line":15,"status":"KILLED","id":"m1","col_start":3,"col_end":9,"replacement":"true"}
|}
      ()
  in
  let db2, _, run2, _ =
    campaign_setup_on ~db:(load_fixture "mutants_comma" comma_stream) ~tests:"file:test/**"
      ~name:"mutants_comma" ~catalogue:one_mutant_catalogue
      ~engine_body:(stub_engine ["m1"]) ~report:all_survived ()
  in
  Batch.run (fun b ->
      let code, out, _ = run_json ["--format"; "json"] in
      Batch.exit_code b ~msg:"a prime-suffixed name must not abort the campaign" ~expected:0
        (code, out) ;
      (* The name really did reach the wrapper: the trace line is what proves the
         campaign RAN rather than merely exiting 0. *)
      Batch.eq_string_opt b ~msg:"the wrapper executed the prime-suffixed test"
        (executed_for work "m1") (Some "test_alpha'") ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"the campaign wrote its run row" 
            (Db.int conn "SELECT count(*) FROM mutant_runs") 1) ;
      (* The negative control. A comma is a TSV separator and would silently
         split one test into two, so it stays refused. *)
      let code2, out2 = run2 [] in
      Batch.exit_code b ~msg:"a comma in a test name is still refused" ~expected:2
        (code2, out2) ;
      Db.with_db db2 (fun conn ->
          Batch.eq_int b ~msg:"and still writes no campaign table"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0)) ;
  Lwt.return_unit

(* FR-003 — the engine is NEVER invoked with a SUBSET of the intended set. The
   only relation computed anywhere was a cardinality comparison, which an
   executed set of EQUAL size with a member substituted satisfies while
   violating the requirement outright.

   The fixture makes the violation real rather than hypothetical: the plan is
   computed over `file:test/**` (so lib/z.ml's mutant intends t_beta), the run
   is scoped to `test/alpha_test.ml` alone, and a `suite`-granularity profile
   then replaces the executed set with the run's own test list — which does not
   contain t_beta. *)
let register_run_refuses_subset_executed_set () =
  Test.register ~__FILE__
    ~title:"mutants: an executed set that is not a superset of the intended set is refused"
    ~tags:["mutants"; "run"; "fr003"]
  @@ fun () ->
  let db, _, run, _ =
    campaign_setup_on ~db:(load_fixture "mutants_subset" campaign_stream)
      ~tests:"file:test/alpha_test.ml" ~plan_tests:"file:test/**" ~name:"mutants_subset"
      ~extra_argv:["--profile"; "cargo-mutants"]
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  (* The negative control: the SAME profile and the same index with plan and run
     agreeing on the selection must run to completion. Without it, "refuse every
     suite-granularity campaign" would pass the assertion above. *)
  let db2, _, run2, _ =
    campaign_setup_on ~db:(load_fixture "mutants_subset_ok" campaign_stream)
      ~tests:"file:test/**" ~name:"mutants_subset_ok"
      ~extra_argv:["--profile"; "cargo-mutants"]
      ~engine_body:(stub_engine ["m1"; "m2"; "m3"]) ~report:all_survived ()
  in
  Batch.run (fun b ->
      let code, output = run [] in
      Batch.exit_code b ~msg:"a subset executed set must abort before the engine runs"
        ~expected:2 (code, output) ;
      Batch.contains b ~msg:"the refusal must cite FR-003" ~haystack:output "FR-003" ;
      Batch.contains b ~msg:"and NAME the test that would not have run" ~haystack:output
        "t_beta" ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"no campaign table is left behind"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0) ;
      let code2, output2 = run2 [] in
      Batch.exit_code b
        ~msg:"a genuine superset under the same profile still runs to completion"
        ~expected:0 (code2, output2) ;
      Db.with_db db2 (fun conn ->
          Batch.eq_int b ~msg:"and writes its three run rows"
            (Db.int conn "SELECT count(*) FROM mutant_runs") 3)) ;
  Lwt.return_unit

(* FR-030's boundary was `git rev-parse --show-toplevel` ALONE, so `git init` —
   not the layout — decided whether the guard fired at all. A checkout that is
   NOT itself a repository but sits inside one resolves its toplevel to the OUTER
   repo, the boundary spans both trees, and the outer tree's wrapper is handed to
   the engine: issue #77, unrefused.

   The boundary is now the NEARER of the git toplevel and the checkout's own
   `dune-project`, and the sibling test above covers the git-initialised
   polarity: this one covers the case `git init` used to flip. *)
let register_run_refuses_outside_non_git_tree () =
  Test.register ~__FILE__
    ~title:"mutants: a checkout that is not itself a repository still refuses the outer \
            wrapper"
    ~tags:["mutants"; "run"; "provenance"]
  @@ fun () ->
  let db = load_fixture "mutants_outside_nongit" campaign_stream in
  let root = Temp.dir "mutants_outside_nongit_nest" in
  let outer = Filename.concat root "outer" in
  let inner = Filename.concat outer "inner" in
  let outer_wrapper = Filename.concat outer "scripts/mutaml-wrapper.sh" in
  if
    Sys.command
      (Printf.sprintf "mkdir -p %s %s"
         (Filename.quote (Filename.concat outer "scripts"))
         (Filename.quote inner))
    <> 0
  then Test.fail "could not lay out the nested checkout fixture" ;
  write_exec outer_wrapper "#!/bin/sh\nexit 0\n" ;
  (* The OUTER tree is the repository; the inner one deliberately is NOT. That is
     the whole fixture: `git rev-parse` inside `inner` answers with `outer`. *)
  let git_code, git_out = run_command ~cwd:outer "git" ["init"; "-q"; "."] in
  if git_code <> 0 then Test.fail "could not make the outer tree a repository:\n%s" git_out ;
  (* The inner checkout's own root marker — what says "the campaign belongs to
     THIS tree" where git cannot. *)
  write_file (Filename.concat inner "dune-project") "(lang dune 3.0)\n" ;
  let plan_file = Filename.concat inner "plan.json" in
  let _, plan_out = mutants ["plan"; db; "--tests"; "file:test/**"; "--format"; "json"] in
  write_file plan_file plan_out ;
  let catalogue = Filename.concat inner "catalogue.ndjson" in
  write_file catalogue campaign_catalogue ;
  let report_file = Filename.concat inner "report.ndjson" in
  write_file report_file all_survived ;
  let engine = Filename.concat inner "engine.sh" in
  write_exec engine "#!/bin/sh\nexit 0\n" ;
  let invoke cwd =
    run_command ~cwd "/usr/bin/env"
      (["-u"; "ARCH_MUTANTS_WRAPPER"; "-u"; "ARCH_IMPACT"; "-u"; "ARCH_MUTANTS"]
      @ (arch_mutants ()
        :: ["run"; db; "--plan"; plan_file; "--engine"; engine; "--test-cmd"; "true";
            "--catalogue"; catalogue; "--report"; report_file; "--tests"; "file:test/**"]))
  in
  Batch.run (fun b ->
      let code, output = invoke inner in
      Batch.exit_code b
        ~msg:"a NON-git inner checkout must still refuse the outer tree's wrapper"
        ~expected:1 (code, output) ;
      Batch.contains b ~msg:"the refusal must name the outside path" ~haystack:output
        outer_wrapper ;
      Db.with_db db (fun conn ->
          Batch.eq_int b ~msg:"and leave no campaign table behind"
            (Db.int conn
               "SELECT count(*) FROM sqlite_master WHERE type='table' AND name='mutant_campaigns'")
            0) ;
      (* The other polarity, and the reason the fix is not simply "refuse more":
         the inner tree's OWN wrapper must be accepted. Without this, a guard
         that refused everything would pass the assertion above. *)
      if
        Sys.command
          (Printf.sprintf "mkdir -p %s"
             (Filename.quote (Filename.concat inner "scripts")))
        <> 0
      then Test.fail "could not lay out the inner tree's own wrapper" ;
      write_exec (Filename.concat inner "scripts/mutaml-wrapper.sh")
        (read_file (wrapper_path ())) ;
      let code2, output2 = invoke inner in
      Batch.exit_code b ~msg:"the inner tree's OWN wrapper is accepted" ~expected:0
        (code2, output2)) ;
  Lwt.return_unit
