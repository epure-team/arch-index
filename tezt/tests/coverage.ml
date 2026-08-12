(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Reachability-weighted coverage.

    Nearly every assertion here is about a distinction a naive coverage tool
    collapses, and collapsing them is exactly how a coverage number stops being
    worth anything:

    - "no instrumentation data" is not "0% covered";
    - covered but reachable only through a ⊤ edge is flagged, not counted as
      API-exercised;
    - covered AND mutants survive is the interesting pairing, and it is a set of
      functions rather than a percentage;
    - an empty or malformed tracefile ABORTS instead of reporting 0%;
    - merged LCOV records SUM rather than overwrite.

    The refusals matter as much as the numbers: an empty report reads as a clean
    one, so anything that would produce an empty report for the wrong reason has
    to fail loudly instead. *)

open Arch_tezt

let coverage args = run_command (arch_coverage ()) args
let mutants args = run_command (arch_mutants ()) args

let coverage_json b ~what args =
  let code, output = coverage args in
  if code <> 0 then (
    Batch.note b "%s: arch-coverage exited %d:\n%s" what code output ;
    None)
  else
    match Json.parse ~what output with
    | Ok j -> Some j
    | Error e ->
        Batch.note b "%s" e ;
        None

(* api (exported) --MUST--> hot, cold, nodata ; dyn --MUST--> hidden and --MAY_TOP--> ⊤,
   so `hidden` is covered but reachable only through the ⊤ cone. *)
let main_stream =
  {|{"type":"function","name":"api","file_path":"lib/api.ml","exported":true,"line_start":1,"line_end":8}
{"type":"function","name":"hot","file_path":"lib/hot.ml","line_start":10,"line_end":20}
{"type":"function","name":"cold","file_path":"lib/cold.ml","line_start":10,"line_end":20}
{"type":"function","name":"nodata","file_path":"lib/nodata.ml","line_start":10,"line_end":20}
{"type":"function","name":"dyn","file_path":"lib/dyn.ml","line_start":1,"line_end":5}
{"type":"function","name":"hidden","file_path":"lib/hidden.ml","line_start":1,"line_end":5}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"hot","callee_file":"lib/hot.ml","call_site":"lib/api.ml:2","kind":"MUST"}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"cold","callee_file":"lib/cold.ml","call_site":"lib/api.ml:3","kind":"MUST"}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"nodata","callee_file":"lib/nodata.ml","call_site":"lib/api.ml:4","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/dyn.ml","callee_name":"hidden","callee_file":"lib/hidden.ml","call_site":"lib/dyn.ml:2","kind":"MUST"}
{"type":"call","caller_name":"dyn","caller_file":"lib/dyn.ml","callee_name":"*TOP*","callee_file":null,"call_site":"lib/dyn.ml:3","kind":"MAY_TOP"}
|}

(* lib/nodata.ml is deliberately absent: no DA record at all is a different
   fact from every DA record reading zero. *)
let lcov =
  {|SF:lib/api.ml
DA:2,5
end_of_record
SF:lib/hot.ml
DA:11,7
DA:12,7
end_of_record
SF:lib/cold.ml
DA:11,0
DA:12,0
end_of_record
SF:lib/hidden.ml
DA:2,3
end_of_record
|}

let trace name contents =
  let path = Temp.file (name ^ ".lcov") in
  write_file path contents ;
  path

let strings_eq b ~msg j key expected =
  match Json.strings ~what:"coverage" key j with
  | Ok got -> Batch.eq_string b ~msg (String.concat "," got) (String.concat "," expected)
  | Error e -> Batch.note b "%s" e

let register_buckets () =
  Test.register ~__FILE__ ~title:"coverage: no data is not zero, and ⊤-only coverage is flagged apart"
    ~tags:["coverage"]
  @@ fun () ->
  let db = Fixture.flat ~name:"coverage" main_stream in
  let lc = trace "coverage" lcov in
  Batch.run (fun b ->
      match coverage_json b ~what:"coverage" [db; lc; "--format"; "json"] with
      | None -> ()
      | Some r ->
          strings_eq b ~msg:"cold has DA records and none were hit, so it was never exercised" r
            "api_never_exercised" ["cold"] ;
          (* The distinction the whole file exists for. *)
          strings_eq b
            ~msg:"nodata has NO DA record: that is 'not instrumented', never 'never exercised'" r
            "api_no_coverage_data" ["nodata"] ;
          (match Json.strings ~what:"coverage" "files_in_index_not_instrumented" r with
          | Ok files ->
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "lib/nodata.ml must be listed as an indexed file with no instrumentation \
                      (got: %s)"
                     (String.concat "," files))
                (List.mem "lib/nodata.ml" files)
          | Error e -> Batch.note b "%s" e) ;
          strings_eq b
            ~msg:"hidden is covered but reachable only through a ⊤ edge, so it is flagged apart" r
            "covered_via_top_only" ["hidden"]) ;
  Lwt.return_unit

let register_tracefile_refusals () =
  Test.register ~__FILE__ ~title:"coverage: a malformed tracefile aborts instead of reporting 0%"
    ~tags:["coverage"; "lcov"]
  @@ fun () ->
  let db = Fixture.flat ~name:"coverage_refuse" main_stream in
  Batch.run (fun b ->
      let aborts ~msg contents =
        Batch.exit_code b ~msg ~expected:2 (coverage [db; trace "bad" contents])
      in
      aborts ~msg:"an LCOV file with no SF records must abort — 0% and 'never ran' differ" "" ;
      aborts ~msg:"a DA record before any SF must abort as malformed" "DA:3,1\n" ;
      aborts ~msg:"a non-integer DA hit count must abort, not be silently read as zero"
        "SF:lib/hot.ml\nDA:11,x\nend_of_record\n" ;
      aborts
        ~msg:"a negative DA hit count must abort — summed across records it can cancel a real hit"
        "SF:lib/hot.ml\nDA:11,-3\nend_of_record\n" ;
      (* A DA record after end_of_record belongs to no file. Crediting it to the
         previous one invents coverage: here it would mark lib/hot.ml:11 hit and
         hide that `hot` was never exercised. *)
      aborts ~msg:"a DA record after end_of_record must abort, not be credited to the previous file"
        "SF:lib/hot.ml\nDA:12,1\nend_of_record\nDA:11,9\n" ;

      (* A merged or sharded run emits the same file twice. Overwriting discards
         a shard's hits, so a line hit only in the SECOND record must still read
         as covered. *)
      let dup =
        trace "dup"
          "SF:lib/cold.ml\nDA:11,0\nDA:12,0\nend_of_record\nSF:lib/cold.ml\nDA:11,4\nDA:12,0\nend_of_record\n"
      in
      (match coverage_json b ~what:"dup" [db; dup; "--format"; "json"] with
      | None -> ()
      | Some r -> (
          match Json.strings ~what:"coverage" "api_never_exercised" r with
          | Ok never ->
              Batch.check b
                ~msg:
                  (Printf.sprintf
                     "duplicate SF records must SUM hit counts, not overwrite (never_exercised: \
                      %s)"
                     (String.concat "," never))
                (not (List.mem "cold" never))
          | Error e -> Batch.note b "%s" e)) ;

      (* An empty root set makes every list come back empty for want of a
         starting point, and an empty report is read as a clean one. *)
      Batch.exit_code b ~msg:"--roots matching nothing must abort, not report an empty API cone"
        ~expected:2
        (coverage [db; trace "roots" lcov; "--roots"; "file:nope/**"]) ;
      let no_exports =
        Fixture.flat ~name:"coverage_noexports"
          {|{"type":"function","name":"internal","file_path":"lib/hot.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"internal","caller_file":"lib/hot.ml","callee_name":"internal","callee_file":"lib/hot.ml","call_site":"lib/hot.ml:11","kind":"MUST"}
|}
      in
      Batch.exit_code b
        ~msg:
          "the DEFAULT roots on an index that marks no exports must abort too — same failure, \
           different clothes"
        ~expected:2
        (coverage [no_exports; trace "noexp" lcov])) ;
  Lwt.return_unit

(* Before the "outside the API cone" bucket existed, a covered function that was
   in neither the API cone nor the ⊤ cone appeared in no list at all: the report
   looked complete while dropping a function the tests demonstrably execute. *)
let register_every_covered_fn_lands_somewhere () =
  Test.register ~__FILE__ ~title:"coverage: a covered function always lands in some bucket"
    ~tags:["coverage"]
  @@ fun () ->
  let db =
    Fixture.flat ~name:"coverage_orphan"
      {|{"type":"function","name":"api","file_path":"lib/api.ml","exported":true,"line_start":1,"line_end":8}
{"type":"function","name":"orphan","file_path":"lib/hot.ml","line_start":10,"line_end":20}
{"type":"call","caller_name":"api","caller_file":"lib/api.ml","callee_name":"api","callee_file":"lib/api.ml","call_site":"lib/api.ml:2","kind":"MUST"}
|}
  in
  let lc = trace "orphan" lcov in
  Batch.run (fun b ->
      match coverage_json b ~what:"coverage" [db; lc; "--format"; "json"] with
      | None -> ()
      | Some r ->
          strings_eq b ~msg:"orphan is covered and outside the API cone, and must say so" r
            "covered_outside_api_cone" ["orphan"] ;
          let bucket key =
            match Json.strings ~what:"coverage" key r with Ok l -> l | Error _ -> []
          in
          let all =
            bucket "api_never_exercised" @ bucket "api_no_coverage_data"
            @ bucket "covered_via_top_only" @ bucket "covered_outside_api_cone"
          in
          Batch.check b
            ~msg:
              (Printf.sprintf "a covered function appears in no bucket at all (buckets: %s)"
                 (String.concat "," all))
            (List.mem "orphan" all)) ;
  Lwt.return_unit

let register_mutant_pairing () =
  Test.register ~__FILE__ ~title:"coverage: covered with surviving mutants is tested-by-nothing"
    ~tags:["coverage"; "mutants"]
  @@ fun () ->
  let db = Fixture.flat ~name:"coverage_pairing" main_stream in
  let lc = trace "pairing" lcov in
  let mr = Temp.file "pairing_report.ndjson" in
  write_file mr {|{"file":"lib/hot.ml","line":11,"status":"SURVIVED","id":"1"}|} ;
  let mj = Temp.file "pairing_mutants.json" in
  let code, out = mutants ["report"; db; mr; "--tests"; "fn:api"; "--format"; "json"] in
  if code <> 0 then Test.fail "arch-mutants report failed (exit %d):\n%s" code out ;
  write_file mj out ;
  Batch.run (fun b ->
      (match coverage_json b ~what:"pairing" [db; lc; "--mutants"; mj; "--format"; "json"] with
      | None -> ()
      | Some r ->
          (match Json.bool ~what:"coverage" "mutants_available" r with
          | Ok v -> Batch.check b ~msg:"mutants_available must be true when a report was supplied" v
          | Error e -> Batch.note b "%s" e) ;
          (match Json.list ~what:"coverage" "covered_but_mutants_survive" r with
          | Ok items ->
              let describe =
                List.map
                  (function
                    | `Assoc f ->
                        Printf.sprintf "%s:%s"
                          (match List.assoc_opt "function" f with
                          | Some (`String s) -> s
                          | _ -> "?")
                          (match List.assoc_opt "survivors" f with
                          | Some (`Int n) -> string_of_int n
                          | _ -> "?")
                    | _ -> "?")
                  items
              in
              Batch.eq_string b
                ~msg:"a covered function with a surviving mutant must be reported as tested by nothing"
                (String.concat "," describe) "hot:1"
          | Error e -> Batch.note b "%s" e)) ;

      (* Without a report the pairing is NOT COMPUTED, which is a different claim
         from "none survive". *)
      let _, text = coverage [db; lc] in
      Batch.contains b
        ~msg:"without --mutants the pairing must read 'not computed', never 'none'"
        ~haystack:(String.lowercase_ascii text) "not computed" ;
      let not_a_report = Temp.file "not_a_report.json" in
      write_file not_a_report "[]\n" ;
      Batch.exit_code b
        ~msg:"a --mutants file that is not an arch-mutants report must abort" ~expected:2
        (coverage [db; lc; "--mutants"; not_a_report])) ;
  Lwt.return_unit

(* `dup` exists twice and only one copy has coverage data. Counting duplicates
   among INSTRUMENTED functions sees one, stays silent, and blames the surviving
   mutant on whichever copy happens to be instrumented — which may be the other
   one. Built on the MAIN schema deliberately: the flat schema keys functions by
   name and so cannot represent two functions sharing one. *)
let register_ambiguity () =
  Test.register ~__FILE__ ~title:"coverage: a name shared with a non-instrumented function is ambiguous"
    ~tags:["coverage"; "mutants"]
  @@ fun () ->
  let db =
    Fixture.main ~name:"coverage_ambiguous"
      ~seed:
        {|
INSERT INTO modules(id,path) VALUES (1,'lib/api.ml'),(2,'lib/hot.ml'),(3,'lib/nodata.ml');
INSERT INTO functions(id,module_id,name,line_start,line_end,exposed)
  VALUES (1,1,'api',1,8,1),(2,2,'dup',10,20,0),(3,3,'dup',10,20,0);
INSERT INTO calls(caller_id,callee_id,callee_name,call_site,kind)
  VALUES (1,2,'dup','lib/api.ml:2','MUST'),(1,3,'dup','lib/api.ml:3','MUST');
INSERT INTO comment_db_meta(key,value) VALUES ('callgraph_contract','v1');
|}
      ()
  in
  let mr = Temp.file "ambiguous_report.ndjson" in
  write_file mr {|{"file":"lib/hot.ml","line":11,"status":"SURVIVED","id":"1"}|} ;
  let mj = Temp.file "ambiguous_mutants.json" in
  let code, out = mutants ["report"; db; mr; "--tests"; "fn:api"; "--format"; "json"] in
  if code <> 0 then Test.fail "arch-mutants report failed (exit %d):\n%s" code out ;
  write_file mj out ;
  let lc = trace "ambiguous" lcov in
  Batch.run (fun b ->
      match coverage_json b ~what:"ambiguity" [db; lc; "--mutants"; mj; "--format"; "json"] with
      | None -> ()
      | Some r ->
          (match Json.strings ~what:"coverage" "mutants_ambiguous_names" r with
          | Ok names ->
              Batch.check b
                ~msg:
                  (Printf.sprintf "the shared name must be reported ambiguous (got: %s)"
                     (String.concat "," names))
                (List.mem "dup" names)
          | Error e -> Batch.note b "%s" e) ;
          (match Json.list ~what:"coverage" "covered_but_mutants_survive" r with
          | Ok items ->
              Batch.eq_int b
                ~msg:"an ambiguous mutant must not be attributed to one of two same-named functions"
                (List.length items) 0
          | Error e -> Batch.note b "%s" e)) ;
  Lwt.return_unit

let register_write () =
  Test.register ~__FILE__ ~title:"coverage: --write replaces rather than accumulates"
    ~tags:["coverage"]
  @@ fun () ->
  let db = Fixture.flat ~name:"coverage_write" main_stream in
  let lc = trace "write" lcov in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"--write must succeed" ~expected:0 (coverage [db; lc; "--write"]) ;
      let count () = Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM coverage_by_name") in
      let n = count () in
      Batch.ge_int b ~msg:"--write must populate the coverage table" n 3 ;
      Db.with_db db (fun c ->
          Batch.eq_string_opt b ~msg:"hot has 2 instrumented lines, both hit"
            (Db.string_opt c
               "SELECT covered_lines||'/'||total_lines FROM coverage_by_name WHERE \
                function_name='hot'")
            (Some "2/2") ;
          Batch.eq_string_opt b ~msg:"cold has 2 instrumented lines, neither hit"
            (Db.string_opt c
               "SELECT covered_lines||'/'||total_lines FROM coverage_by_name WHERE \
                function_name='cold'")
            (Some "0/2")) ;
      Batch.exit_code b ~msg:"a second --write must succeed" ~expected:0
        (coverage [db; lc; "--write"]) ;
      Batch.eq_int b ~msg:"--write must replace, not accumulate rows" (count ()) n) ;
  Lwt.return_unit

let register_soundness_flag () =
  Test.register ~__FILE__ ~title:"coverage: a NULL-kind edge makes reachability unsound"
    ~tags:["coverage"; "contract"]
  @@ fun () ->
  (* The shared fixture: arch-coverage must agree with arch-impact, arch-rules
     and arch-mutants, which all read this through Arch_db.contract_ok. *)
  let db = Fixture.malformed_contract ~name:"coverage_malformed" in
  let lc = trace "malformed" "SF:x\nDA:1,1\nend_of_record\n" in
  Batch.run (fun b ->
      match coverage_json b ~what:"coverage" [db; lc; "--format"; "json"] with
      | None -> ()
      | Some r -> (
          match Json.bool ~what:"coverage" "sound_reachability" r with
          | Ok v ->
              Batch.check b
                ~msg:"a NULL-kind edge on a flag-stamped index must report sound_reachability:false"
                (not v)
          | Error e -> Batch.note b "%s" e)) ;
  Lwt.return_unit
