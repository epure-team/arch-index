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
    match Json.parse ~what output with
    | Ok j -> Some j
    | Error e ->
        Batch.note b "%s" e ;
        None

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
        (code, output)) ;
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
