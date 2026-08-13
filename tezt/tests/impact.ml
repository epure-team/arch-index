(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Change-impact briefing.

    Every assertion here is about labelling an approximation in the right
    DIRECTION, because the answers are all bounds and a bound pointed the wrong
    way is worse than no answer:

    - a hunk maps to the function whose line span contains it, and to no other;
    - reverse reachability separates DEFINITE callers from ⊤-hidden MAY ones,
      and never counts a definite caller twice;
    - the forward radius is reported as a LOWER bound with its ⊤ frontier,
      never as a bound;
    - an index with no line spans degrades to FILE granularity loudly;
    - --fail-on-new-findings fires only when the diff actually touches a finding
      line, and REFUSES when the analysis was never computed at all. *)

open Arch_tezt

let impact args = run_command (arch_impact ()) args

(* Split streams for the JSON path: arch-impact legitimately writes diagnostics
   to stderr — the file-granularity WARNING is one of the things asserted below —
   and merged into stdout they make the object unparseable. *)
let impact_json b ~what args =
  let _, out, _err = run_command_split (arch_impact ()) args in
  match Json.strict_object ~what out with
  | Ok j -> Some j
  | Error e ->
      Batch.note b "%s" e ;
      None

(* Three functions at known, non-overlapping spans:
     1-3   entry     (exported)
     5-7   helper
     9-11  unrelated (exported) — must NEVER be touched by a hunk inside helper *)
let app_src =
  {|fn entry:
  call helper
  end

fn helper:
  compute
  end

fn unrelated:
  noop
  end
|}

let main_stream =
  {|{"type":"function","name":"entry","file_path":"src/app.src","exported":true,"line_start":1,"line_end":3}
{"type":"function","name":"helper","file_path":"src/app.src","line_start":5,"line_end":7}
{"type":"function","name":"unrelated","file_path":"src/app.src","exported":true,"line_start":9,"line_end":11}
{"type":"function","name":"reflector","file_path":"src/dyn.src","exported":true,"line_start":1,"line_end":2}
{"type":"function","name":"test_helper","file_path":"test/app_test.src","line_start":1,"line_end":2}
{"type":"call","caller_name":"entry","caller_file":"src/app.src","callee_name":"helper","callee_file":"src/app.src","call_site":"src/app.src:2","kind":"MUST"}
{"type":"call","caller_name":"test_helper","caller_file":"test/app_test.src","callee_name":"helper","callee_file":"src/app.src","call_site":"test/app_test.src:1","kind":"MUST"}
{"type":"call","caller_name":"helper","caller_file":"src/app.src","callee_name":"unrelated","callee_file":"src/app.src","call_site":"src/app.src:6","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"reflector","caller_file":"src/dyn.src","callee_name":"*TOP*","callee_file":null,"call_site":"src/dyn.src:1","kind":"MAY_TOP"}
|}

(* Replace one line, 1-indexed, then commit: the diff under test is produced by
   git rather than written by the test. *)
let edit_line root rel n replacement =
  let path = Filename.concat root rel in
  let ls = String.split_on_char '\n' (read_file path) in
  let ls = List.mapi (fun i l -> if i = n - 1 then replacement else l) ls in
  write_file path (String.concat "\n" ls)

let names_of j key ~field =
  match Json.list ~what:"impact" key j with
  | Ok items -> Json.field_of_objects ~field items
  | Error _ -> []

let int_field b j key expected =
  match Json.int ~what:"impact" key j with
  | Ok n -> Batch.eq_int b ~msg:("impact." ^ key) n expected
  | Error e -> Batch.note b "%s" e

let register_granularity () =
  Test.register ~__FILE__ ~title:"impact: a hunk touches the span that contains it, and no other"
    ~tags:["impact"]
  @@ fun () ->
  Fixture.git_project ~name:"impact" ~files:[("src/app.src", app_src)] @@ fun root ->
  let db = Fixture.flat ~name:"impact" main_stream in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          (* Everything below depends on the spans surviving the load. *)
          Batch.eq_int b ~msg:"all five line spans must survive the load"
            (Db.int conn "SELECT count(*) FROM functions WHERE line_start IS NOT NULL")
            5) ;
      (* Edit ONLY line 6, inside helper. *)
      edit_line root "src/app.src" 6 "  compute_v2" ;
      Fixture.git_commit ~cwd:root "change helper" ;
      match
        impact_json b ~what:"impact"
          [db; "--diff"; "HEAD~1..HEAD"; "--repo"; root; "--format"; "json"]
      with
      | None -> ()
      | Some j ->
          Batch.eq_string b ~msg:"a hunk on line 6 must touch exactly 'helper'"
            (String.concat "," (List.sort compare (names_of j "touched" ~field:"name")))
            "helper" ;

          (* Reverse reachability: entry and test_helper definitely reach helper;
             reflector holds a ⊤ edge, so it only MAY. *)
          int_field b j "upstream_count" 2 ;
          int_field b j "may_upstream_count" 1 ;
          (match Json.strings ~what:"impact" "may_affected_exported" j with
          | Ok may ->
              let joined = String.concat "," may in
              Batch.contains b ~msg:"reflector must be a MAY-affected export" ~haystack:joined
                "reflector" ;
              (* Double counting would inflate the blast radius with functions
                 already reported as definite. *)
              Batch.not_contains b
                ~msg:"entry is a DEFINITE caller and must not be repeated in the may-reach set"
                ~haystack:joined "entry"
          | Error e -> Batch.note b "%s" e) ;
          (match Json.strings ~what:"impact" "tests_reaching" j with
          | Ok tests ->
              Batch.contains b ~msg:"test_helper must be listed as a reaching test"
                ~haystack:(String.concat "," tests) "test_helper"
          | Error e -> Batch.note b "%s" e) ;

          (* Forward radius: a lower bound, said out loud. *)
          int_field b j "downstream_count" 1 ;
          let _, text = impact [db; "--diff"; "HEAD~1..HEAD"; "--repo"; root] in
          Batch.contains b ~msg:"the forward radius must be labelled a lower bound, never a bound"
            ~haystack:text "lower bound" ;

          (* The sibling at lines 9-11 is not dragged in. *)
          Batch.not_contains b
            ~msg:"'unrelated' (lines 9-11) must not be touched by a hunk on line 6"
            ~haystack:(String.concat "," (names_of j "touched" ~field:"name"))
            "unrelated" ;

          (* An empty decisions table is NOT COMPUTED, which is a different claim
             from "nothing to report". *)
          (match Json.bool ~what:"impact" "decision_analysis_available" j with
          | Ok v ->
              Batch.check b
                ~msg:"an empty decisions table must read as NOT COMPUTED, never as 'nothing found'"
                (not v)
          | Error e -> Batch.note b "%s" e) ;

          (* The machine-output contract. strict_object already rejected floats
             and trailing data. *)
          (match Json.bool ~what:"impact" "computed" j with
          | Ok v -> Batch.check b ~msg:"impact.computed must be true" v
          | Error e -> Batch.note b "%s" e) ;
          Batch.eq_string_opt b ~msg:"impact.verdict without --fail-on-new-findings"
            (match Json.member "verdict" j with Some (`String s) -> Some s | _ -> None)
            (Some "pass")) ;
  Lwt.return_unit

let register_contract () =
  Test.register ~__FILE__ ~title:"impact: contract_ok is the strict check, not 'flag present'"
    ~tags:["impact"; "contract"]
  @@ fun () ->
  Fixture.git_project ~name:"impact_contract" ~files:[("src/app.src", app_src)] @@ fun root ->
  edit_line root "src/app.src" 6 "  compute_v2" ;
  Fixture.git_commit ~cwd:root "change helper" ;
  (* The shared fixture: arch-impact must reach the same verdict as arch-rules,
     arch-coverage and arch-mutants, which all read Arch_db.contract_ok. *)
  let db = Fixture.malformed_contract ~name:"impact_malformed" in
  Batch.run (fun b ->
      match
        impact_json b ~what:"impact"
          [db; "--diff"; "HEAD~1..HEAD"; "--repo"; root; "--format"; "json"]
      with
      | None -> ()
      | Some j ->
          List.iter
            (fun key ->
              match Json.bool ~what:"impact" key j with
              | Ok v ->
                  Batch.check b
                    ~msg:
                      (Printf.sprintf
                         "a NULL-kind edge on a flag-stamped index must report %s:false" key)
                    (not v)
              | Error e -> Batch.note b "%s" e)
            ["contract_ok"; "sound_reachability"]) ;
  Lwt.return_unit

let register_no_spans () =
  Test.register ~__FILE__ ~title:"impact: a span-less index degrades to file granularity, loudly"
    ~tags:["impact"]
  @@ fun () ->
  Fixture.git_project ~name:"impact_nospan" ~files:[("src/app.src", app_src)] @@ fun root ->
  edit_line root "src/app.src" 6 "  compute_v2" ;
  Fixture.git_commit ~cwd:root "change helper" ;
  let nospan =
    Fixture.flat ~name:"impact_nospan"
      {|{"type":"function","name":"entry","file_path":"src/app.src","exported":true}
{"type":"function","name":"helper","file_path":"src/app.src"}
{"type":"call","caller_name":"entry","caller_file":"src/app.src","callee_name":"helper","callee_file":"src/app.src","call_site":"src/app.src:2","kind":"MUST"}
|}
  in
  Batch.run (fun b ->
      (* The warning is the point: over-attributing silently would look like a
         precise answer. *)
      let _, _, err =
        run_command_split (arch_impact ()) [nospan; "--diff"; "HEAD~1..HEAD"; "--repo"; root]
      in
      Batch.contains b ~msg:"a span-less index must warn on stderr, not silently over-attribute"
        ~haystack:err "no function in this index has a line span" ;
      match
        impact_json b ~what:"impact"
          [nospan; "--diff"; "HEAD~1..HEAD"; "--repo"; root; "--format"; "json"]
      with
      | None -> ()
      | Some j ->
          Batch.eq_string b ~msg:"a span-less index maps the whole FILE, on purpose"
            (String.concat "," (List.sort compare (names_of j "touched" ~field:"name")))
            "entry,helper" ;
          Batch.eq_string b ~msg:"every touched row must say the mapping was file-granular"
            (String.concat ","
               (List.sort_uniq compare
                  (List.map
                     (fun h -> if has_prefix ~prefix:"file" h then "file" else h)
                     (names_of j "touched" ~field:"how"))))
            "file" ;
          (match Json.strings ~what:"impact" "files_file_granular" j with
          | Ok files ->
              Batch.eq_string b ~msg:"the file-granular list must name the file"
                (String.concat "," files) "src/app.src"
          | Error e -> Batch.note b "%s" e)) ;
  Lwt.return_unit

let register_findings_gate () =
  Test.register ~__FILE__ ~title:"impact: the findings gate fires on touched lines and refuses when uncomputed"
    ~tags:["impact"]
  @@ fun () ->
  Fixture.git_project ~name:"impact_gate" ~files:[("src/app.src", app_src)] @@ fun root ->
  edit_line root "src/app.src" 6 "  compute_v2" ;
  Fixture.git_commit ~cwd:root "change helper" ;
  let with_findings =
    Fixture.flat ~name:"impact_findings"
      {|{"type":"function","name":"helper","file_path":"src/app.src","line_start":5,"line_end":7}
{"type":"call","caller_name":"helper","caller_file":"src/app.src","callee_name":"x","callee_file":null,"call_site":"src/app.src:6","kind":"MUST"}
{"type":"decision","file_path":"src/app.src","line":6,"col":3,"form":"if","arity":2,"verdict":"DEAD_SUBTERM","decided_by":"enumeration","evidence":"e","snippet":"a && a"}
{"type":"decision","file_path":"src/app.src","line":10,"col":3,"form":"if","arity":2,"verdict":"DEAD_SUBTERM","decided_by":"enumeration","evidence":"e","snippet":"b && b"}
|}
  in
  let no_findings = Fixture.flat ~name:"impact_nofindings" main_stream in
  Batch.run (fun b ->
      let args db extra =
        [db; "--diff"; "HEAD~1..HEAD"; "--repo"; root] @ extra
      in
      Batch.exit_code b
        ~msg:"--fail-on-new-findings must exit 1: the diff touches line 6, which carries a finding"
        ~expected:1
        (impact (args with_findings ["--fail-on-new-findings"])) ;
      (match impact_json b ~what:"impact" (args with_findings ["--format"; "json"]) with
      | None -> ()
      | Some j -> (
          (* The `match Json.list "findings" … with | _ -> …` that used to wrap
             this discarded its own result: every branch fell through, so it
             read as a check and enforced nothing. Removed rather than
             repaired — `findings` is an OBJECT here, not a list, so the read it
             performed could never have succeeded anyway. *)
          (* Only the finding on a TOUCHED line may be reported: line 10 is
             not in the diff. *)
          match Json.member "findings" j with
              | Some (`Assoc f) -> (
                  match List.assoc_opt "decisions" f with
                  | Some (`List ds) ->
                      let ls =
                        List.filter_map
                          (function
                            | `Assoc d -> (
                                match List.assoc_opt "line" d with
                                | Some (`Int n) -> Some (string_of_int n)
                                | _ -> None)
                            | _ -> None)
                          ds
                      in
                      Batch.eq_string b
                        ~msg:"only the finding on a touched line may be reported"
                        (String.concat "," ls) "6"
                  | _ -> Batch.note b "impact.findings.decisions is missing or not a list")
          | _ -> Batch.note b "impact.findings is missing or not an object")) ;

      (* exit 1 <-> verdict "fail": a consumer with only stdout must reach the
         same conclusion as one with only the exit code. *)
      (match
         impact_json b ~what:"impact"
           (args with_findings ["--format"; "json"; "--fail-on-new-findings"])
       with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b ~msg:"verdict must read 'fail' exactly when the exit code is 1"
            (match Json.member "verdict" j with Some (`String s) -> Some s | _ -> None)
            (Some "fail") ;
          int_field b j "new_findings" 1) ;

      (* A diff that touches no finding line passes the gate. *)
      edit_line root "src/app.src" 2 "  call helper2" ;
      Fixture.git_commit ~cwd:root "change entry" ;
      Batch.exit_code b ~msg:"--fail-on-new-findings must PASS when no finding line is touched"
        ~expected:0
        (impact (args with_findings ["--fail-on-new-findings"])) ;
      (match
         impact_json b ~what:"impact"
           (args with_findings ["--format"; "json"; "--fail-on-new-findings"])
       with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b ~msg:"verdict must read 'pass' exactly when the exit code is 0"
            (match Json.member "verdict" j with Some (`String s) -> Some s | _ -> None)
            (Some "pass")) ;

      (* A gate whose input was never computed must REFUSE — never pass, never
         fail, and never be confused with a crash. *)
      Batch.exit_code b
        ~msg:"--fail-on-new-findings on an index with no decision analysis must REFUSE"
        ~expected:3
        (impact (args no_findings ["--fail-on-new-findings"])) ;
      match
        impact_json b ~what:"impact"
          (args no_findings ["--format"; "json"; "--fail-on-new-findings"])
      with
      | None -> ()
      | Some j ->
          Batch.eq_string_opt b
            ~msg:"verdict must read 'refused' exactly when the exit code is 3"
            (match Json.member "verdict" j with Some (`String s) -> Some s | _ -> None)
            (Some "refused")) ;
  Lwt.return_unit

(* A half span must be refused at LOAD time: a function with a start and no end
   cannot be matched against a hunk, and accepting it would silently drop that
   function from every future impact answer. *)
let register_half_span () =
  Test.register ~__FILE__ ~title:"impact: a half line span is refused at load time"
    ~tags:["impact"; "load"]
  @@ fun () ->
  let db = temp_db "impact_half" in
  if Sys.file_exists db then Sys.remove db ;
  let code, output =
    run_command
      ~stdin:
        {|{"type":"function","name":"f","file_path":"x","line_start":3}
{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"MUST"}
|}
      (arch_load ()) [db]
  in
  Batch.run (fun b ->
      Batch.check b
        ~msg:
          (Printf.sprintf
             "a function record with line_start but no line_end must ABORT the load:\n%s" output)
        (code <> 0)) ;
  Lwt.return_unit

(* Two parser failures that arise together, so they share one fixture.

   Under --unified=0 a removed line is written as "-" ^ content, so a deleted
   `-- comment` arrives as `--- comment` and was read as a file header —
   inventing a file named after the comment text, and clearing the current file
   so every later hunk was dropped. Separately, a pure-deletion hunk adds no new
   line, so the loop marked nothing and the deletion site vanished from a file
   otherwise reported as modified. *)
let register_diff_parsing () =
  Test.register ~__FILE__ ~title:"impact: a diff content line is not a file header"
    ~tags:["impact"; "diff"]
  @@ fun () ->
  Fixture.git_project ~name:"impact_diff"
    ~files:
      [
        ( "q.sql",
          "-- header comment\nSELECT 1;\n++ /dev/null\nSELECT 2;\nSELECT 3;\nSELECT 4;\nSELECT 5;\n"
        );
      ]
  @@ fun root ->
  (* Delete lines 1 and 3 AND edit the line that ends up at new line 3: a MIXED
     diff, so neither the deleted-file branch nor the deletion-only branch can
     rescue it. *)
  (* The last line is ADDED, so the diff renders it `+++ /dev/null` — the
     new-file header that means "this file was deleted". Deleting the `++ …`
     line above only ever produced `-++ /dev/null`, so the `+++` half of the
     trap was named in the assertion messages but never actually present in the
     input. Both halves are now genuinely in the diff:
       `--- header comment`   (deleted `-- …`, reads as an old-file header)
       `+++ /dev/null`        (added `++ …`, reads as "file deleted") *)
  write_file (Filename.concat root "q.sql")
    "SELECT 1;\nSELECT 2;\nSELECT 33;\nSELECT 4;\nSELECT 5;\n++ /dev/null\n" ;
  Fixture.git_commit ~cwd:root "edit" ;
  let db =
    Fixture.flat ~name:"impact_diff"
      {|{"type":"function","name":"top","file_path":"q.sql","exported":true,"line_start":1,"line_end":2}
{"type":"function","name":"mid","file_path":"q.sql","line_start":3,"line_end":4}
{"type":"function","name":"bot","file_path":"q.sql","line_start":5,"line_end":7}
{"type":"call","caller_name":"top","caller_file":"q.sql","callee_name":"mid","callee_file":"q.sql","call_site":"q.sql:1","kind":"MUST"}
|}
  in
  Batch.run (fun b ->
      match
        impact_json b ~what:"impact"
          [db; "--diff"; "HEAD~1..HEAD"; "--repo"; root; "--format"; "json"]
      with
      | None -> ()
      | Some j ->
          let touched = names_of j "touched" ~field:"name" in
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "the edit lands at new line 3 inside 'mid' — unless `--- header comment` was \
                  read as an old-file header, which restarted the parse and dropped every later \
                  hunk (touched: %s)"
                 (String.concat "," touched))
            (List.mem "mid" touched) ;
          Batch.check b
            ~msg:
              (Printf.sprintf
                 "the two deletions straddle 'top' — a pure-deletion hunk adds no new line to \
                  mark, so the site used to vanish (touched: %s)"
                 (String.concat "," touched))
            (List.mem "top" touched) ;
          let invented =
            Batch.list_or_empty b (Json.strings ~what:"impact" "files_unmatched" j)
            @ Batch.list_or_empty b
                (Json.strings ~what:"impact" "files_file_granular" j)
          in
          List.iter
            (fun ghost ->
              Batch.not_contains b
                ~msg:"a diff CONTENT line must never become a file"
                ~haystack:(String.concat "," invented) ghost)
            ["/dev/null"; "header comment"]) ;
  Lwt.return_unit
