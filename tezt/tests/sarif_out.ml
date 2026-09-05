(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-rules --format sarif] — roadmap 2.1.

    {1 The validator decision}

    The SARIF 2.1.0 schema
    (https://raw.githubusercontent.com/oasis-tcs/sarif-spec/main/sarif-2.1/schema/sarif-schema-2.1.0.json,
    vendored at [vendor/sarif/sarif-schema-2.1.0.json]) declares itself
    ["$schema": "http://json-schema.org/draft-04/schema#"] — JSON Schema draft-04, the
    least-supported draft in modern validators. This is CHECK-4's whole difficulty.

    The opam package [jsonschema] (0.1.0) claims draft-4 support and was tried first — but an
    experiment (not this file; done once, by hand, while designing this test, and recorded here
    so the decision is not re-litigated by a future reader) found it silently accepts a SARIF
    document MISSING its required top-level ["version"] field and a [driver] missing its
    required ["name"]: it reported the whole document VALID. A validator that cannot reject an
    invalid document is not a validator — CHECK-4 needs a tool that can go RED, and this one
    could not be shown to. python3's [jsonschema] library (4.26.0, locally confirmed available)
    correctly rejects both defects via its [Draft4Validator]. That is the tool this file shells
    out to.

    Declared, not assumed present (per this repo's own PR #69 lesson — a tool assumed present and
    declared nowhere): [.github/workflows/ci.yml] installs it with an explicit
    [pip install 'jsonschema==4.26.0'] step, named so its absence reads as "the install step
    rotted", not "the machine is bare". [validate_sarif] below never skips: an absent python3 or
    an absent [jsonschema] module both {!Tezt.Test.fail}, loudly, naming what is missing — the
    "validation must never silently skip" rule from this item's brief. *)

open Arch_tezt

let rules args = run_command (arch_rules ()) args

let rule_file name contents =
  let path = Temp.file (name ^ ".rules") in
  write_file path contents ;
  path

(* Same shape as rules.ml's `layered_stream`, kept local and self-contained rather than shared:
   this file's fixture needs one more thing rules.ml's does not carry by default — a `top_reason`
   on the MAY_TOP edge, which is what lets the UNKNOWN case assert
   `properties.top_reason` end to end.

   ui.handle  --MUST-->      db.write            a definite layering violation      -> VIOLATION
   api.serve  --MAY_ENUM-->  db.write            possible: dispatch could land there -> POSSIBLE
   job.run    --MUST--> util.helper --MAY_TOP--> ⊤ (top_reason=reflection)           -> UNKNOWN
   pure.calc  --MUST-->      pure.inner          a closed cone: a real proof         -> PASS *)
let layered_stream =
  {|{"type":"function","name":"ui.handle","file_path":"src/ui/handler.ts","exported":true}
{"type":"function","name":"api.serve","file_path":"src/api/serve.ts","exported":true}
{"type":"function","name":"job.run","file_path":"src/job/run.ts"}
{"type":"function","name":"util.helper","file_path":"src/util/helper.ts"}
{"type":"function","name":"pure.calc","file_path":"src/pure/calc.ts"}
{"type":"function","name":"pure.inner","file_path":"src/pure/inner.ts"}
{"type":"function","name":"db.write","file_path":"lib/db/write.ts"}
{"type":"call","caller_name":"ui.handle","caller_file":"src/ui/handler.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/ui/handler.ts:5","kind":"MUST"}
{"type":"call","caller_name":"api.serve","caller_file":"src/api/serve.ts","callee_name":"db.write","callee_file":"lib/db/write.ts","call_site":"src/api/serve.ts:9","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"job.run","caller_file":"src/job/run.ts","callee_name":"util.helper","callee_file":"src/util/helper.ts","call_site":"src/job/run.ts:3","kind":"MUST"}
{"type":"call","caller_name":"util.helper","caller_file":"src/util/helper.ts","callee_name":"*TOP*","callee_file":null,"call_site":"src/util/helper.ts:7","kind":"MAY_TOP","top_reason":"reflection"}
{"type":"call","caller_name":"pure.calc","caller_file":"src/pure/calc.ts","callee_name":"pure.inner","callee_file":"src/pure/inner.ts","call_site":"src/pure/calc.ts:2","kind":"MUST"}
|}

let four_rules =
  {|rule "ui must not reach persistence"
  forbid reach from file:src/ui/** to file:lib/db/**
rule "api must not reach persistence"
  forbid reach from file:src/api/** to file:lib/db/**
rule "jobs must not reach persistence"
  forbid reach from file:src/job/** to file:lib/db/**
rule "pure code must not reach persistence"
  forbid reach from file:src/pure/** to file:lib/db/**
|}

let fixture_db () = Fixture.flat ~name:"sarif_out" layered_stream

let sarif_schema_path () =
  let p = Filename.concat (repo_root ()) "vendor/sarif/sarif-schema-2.1.0.json" in
  if not (Sys.file_exists p) then Test.fail "vendored SARIF schema not found at %s" p ;
  p

(* Shells out to python3's jsonschema (Draft4Validator) — see the module header for why. Returns
   [(valid, message)]. Never returns [(true, _)] on a missing interpreter or module: both cases
   {!Test.fail} directly, which is what "must never silently skip" means operationally. *)
let validate_sarif ~what json_text =
  let py =
    let code, out = run_command "sh" ["-c"; "command -v python3"] in
    let path = String.trim out in
    if code <> 0 || path = "" then
      Test.fail
        "%s: python3 is required to validate SARIF output against the draft-04 schema (CHECK-4) \
         and was not found on PATH"
        what ;
    path
  in
  let script =
    {|
import sys, json
try:
    from jsonschema import Draft4Validator
except ImportError as e:
    print("JSONSCHEMA_MODULE_MISSING: " + str(e))
    sys.exit(3)
schema = json.load(open(sys.argv[1]))
doc = json.load(open(sys.argv[2]))
errors = list(Draft4Validator(schema).iter_errors(doc))
if errors:
    print("INVALID")
    for e in errors[:20]:
        print(" - " + e.message)
    sys.exit(1)
print("VALID")
|}
  in
  let script_path = Temp.file "validate_sarif.py" in
  write_file script_path script ;
  let doc_path = Temp.file (what ^ ".sarif.json") in
  write_file doc_path json_text ;
  let code, output = run_command py [script_path; sarif_schema_path (); doc_path] in
  if code = 3 then
    Test.fail
      "%s: python3's `jsonschema` module is not installed — install it with `pip install \
       jsonschema` (see .github/workflows/ci.yml for the declared CI step). Output:\n\
       %s"
      what output ;
  (code = 0, output)

let sarif_json b ~what output =
  match Json.strict_object ~what output with
  | Ok j -> Some j
  | Error e ->
      Batch.note b "%s" e ;
      None

(* Every rule's [ruleId] -> its `results[]` entries, in document order. *)
let results_by_rule j =
  match Json.member "runs" j with
  | Some (`List [ run ]) -> (
      match Json.member "results" run with
      | Some (`List rs) ->
          List.filter_map
            (function
              | `Assoc _ as r -> ( match Json.member "ruleId" r with Some (`String id) -> Some (id, r) | _ -> None)
              | _ -> None)
            rs
      | _ -> [])
  | _ -> []

let find_result j ~rule_id = List.assoc_opt rule_id (results_by_rule j)

(* -------------------------------------------------------------------- *)

let register_schema_valid () =
  Test.register ~__FILE__ ~title:"sarif: --format sarif validates against the SARIF 2.1.0 schema"
    ~tags:["sarif"; "rules"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_valid" four_rules in
  let code, output = rules [db; rf; "--format"; "sarif"] in
  ignore code ;
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some _j ->
          let valid, msg = validate_sarif ~what:"sarif output" output in
          Batch.check b ~msg:(Printf.sprintf "SARIF output must validate against the 2.1.0 schema:\n%s" msg) valid) ;
  Lwt.return_unit

let register_pass_excluded () =
  Test.register ~__FILE__ ~title:"sarif: a PASS verdict never becomes a result — only non-PASS verdicts do"
    ~tags:["sarif"; "rules"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_pass" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j ->
          let ids = List.map fst (results_by_rule j) in
          Batch.check b
            ~msg:(Printf.sprintf "a PASS rule ('pure code must not reach persistence') must not appear \
                                   in results, got: [%s]" (String.concat "; " ids))
            (not (List.mem "pure code must not reach persistence" ids)) ;
          (* The other three ARE non-PASS and must all be present — a mutant that dropped every
             result (not just PASS) would still make the assertion above pass vacuously, so this
             is the assertion that catches THAT mutant. *)
          List.iter
            (fun name ->
              Batch.check b ~msg:(Printf.sprintf "%S must appear in results" name) (List.mem name ids))
            ["ui must not reach persistence"; "api must not reach persistence";
             "jobs must not reach persistence"]) ;
  Lwt.return_unit

let register_level_mapping () =
  Test.register ~__FILE__ ~title:"sarif: VIOLATION/POSSIBLE/UNKNOWN map to error/warning/note"
    ~tags:["sarif"; "rules"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_levels" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j ->
          let level_of rule_id =
            match find_result j ~rule_id with
            | Some r -> ( match Json.member "level" r with Some (`String s) -> Some s | _ -> None)
            | None -> None
          in
          Batch.eq_string_opt b ~msg:"VIOLATION -> level=error"
            (level_of "ui must not reach persistence") (Some "error") ;
          Batch.eq_string_opt b ~msg:"POSSIBLE -> level=warning"
            (level_of "api must not reach persistence") (Some "warning") ;
          Batch.eq_string_opt b ~msg:"UNKNOWN -> level=note"
            (level_of "jobs must not reach persistence") (Some "note")) ;
  Lwt.return_unit

let register_unknown_carries_soundness_and_top_reason () =
  Test.register ~__FILE__
    ~title:"sarif: an UNKNOWN result carries properties.soundness=unknown_top and its top_reason"
    ~tags:["sarif"; "rules"; "top_reason"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_unknown" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"jobs must not reach persistence" with
          | None -> Batch.note b "the UNKNOWN rule has no SARIF result at all"
          | Some r -> (
              match Json.member "properties" r with
              | None -> Batch.note b "UNKNOWN result has no properties bag at all"
              | Some props ->
                  Batch.eq_string_opt b ~msg:"properties.soundness"
                    (match Json.member "soundness" props with Some (`String s) -> Some s | _ -> None)
                    (Some "unknown_top") ;
                  (match Json.member "top_reason" props with
                  | Some (`List [ `String r ]) ->
                      Batch.eq_string b ~msg:"properties.top_reason[0]" r "reflection"
                  | other -> Batch.note b "properties.top_reason is not a singleton list: %s" (Json.show other))))) ;
  Lwt.return_unit

let register_witness_becomes_code_flow () =
  Test.register ~__FILE__ ~title:"sarif: a rule's witness path becomes a codeFlow with one location per step"
    ~tags:["sarif"; "rules"; "witness"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_codeflow" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match find_result j ~rule_id:"ui must not reach persistence" with
          | None -> Batch.note b "the VIOLATION rule has no SARIF result at all"
          | Some r -> (
              match Json.member "codeFlows" r with
              | Some (`List [ flow ]) -> (
                  match Json.member "threadFlows" flow with
                  | Some (`List [ tf ]) -> (
                      match Json.member "locations" tf with
                      | Some (`List locs) ->
                          (* ui.handle -> db.write: exactly two steps. A mutant that emitted the
                             witness as a single collapsed string (rather than per-step
                             locations) would make this 1, not 2. *)
                          Batch.eq_int b ~msg:"codeFlow location count" (List.length locs) 2
                      | other -> Batch.note b "threadFlow has no locations list: %s" (Json.show other))
                  | other -> Batch.note b "codeFlow has no singleton threadFlows: %s" (Json.show other))
              | other -> Batch.note b "VIOLATION result has no singleton codeFlows: %s" (Json.show other)))) ;
  Lwt.return_unit

let register_run_shape_and_category () =
  Test.register ~__FILE__
    ~title:"sarif: driver name/category/automationDetails are set, and the ⊤ frontier is a count, not results"
    ~tags:["sarif"; "rules"; "category"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_shape" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match Json.member "runs" j with
          | Some (`List [ run ]) ->
              let driver =
                match Json.member "tool" run with Some t -> Json.member "driver" t | None -> None
              in
              (match driver with
              | Some d ->
                  Batch.eq_string_opt b ~msg:"tool.driver.name"
                    (match Json.member "name" d with Some (`String s) -> Some s | _ -> None)
                    (Some "arch-index")
              | None -> Batch.note b "run has no tool.driver at all") ;
              let props = Json.member "properties" run in
              (match props with
              | Some p ->
                  Batch.eq_string_opt b ~msg:"run.properties.category"
                    (match Json.member "category" p with Some (`String s) -> Some s | _ -> None)
                    (Some "arch-index/rules") ;
                  (* The ⊤ frontier (roadmap 1.4/1.5's escaping edge on util.helper) must be a
                     COUNT in run.properties, never a member of `results` — GitHub caps a run at
                     25 000 results and a real corpus's frontier is orders of magnitude past
                     that. A mutant that turned this into a results-list entry would still pass
                     every OTHER assertion in this file, which is why it gets its own check. *)
                  (match Json.member "top_frontier" p with
                  | Some (`Int n) -> Batch.check b ~msg:"top_frontier must be >= 1" (n >= 1)
                  | other -> Batch.note b "run.properties.top_frontier missing or not an int: %s" (Json.show other))
              | None -> Batch.note b "run has no properties bag at all") ;
              (match Json.member "automationDetails" run with
              | Some ad ->
                  Batch.eq_string_opt b ~msg:"automationDetails.id"
                    (match Json.member "id" ad with Some (`String s) -> Some s | _ -> None)
                    (Some "arch-index/rules")
              | None -> Batch.note b "run has no automationDetails at all")
          | other -> Batch.note b "sarif output does not have exactly one run: %s" (Json.show other))) ;
  Lwt.return_unit

(* CHECK-5's round-trip, in spirit: every non-PASS verdict `--format json` reports must be
   traceable in `--format sarif` too, with a level consistent with that same verdict. An
   asymmetry here is exactly PR #70's defect class (the JSON channel honest, another channel
   not) reproduced for the JSON/SARIF pair instead of JSON/text. *)
let register_json_sarif_round_trip () =
  Test.register ~__FILE__ ~title:"sarif: every non-PASS verdict in --format json appears in --format sarif"
    ~tags:["sarif"; "rules"; "round_trip"]
  @@ fun () ->
  let db = fixture_db () in
  let rf = rule_file "sarif_roundtrip" four_rules in
  let _, json_output = rules [db; rf; "--format"; "json"] in
  let _, sarif_output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match (Json.strict_object ~what:"json output" json_output, sarif_json b ~what:"sarif output" sarif_output) with
      | Error e, _ ->
          Batch.note b "%s" e
      | _, None -> ()
      | Ok jj, Some sj -> (
          match Json.list ~what:"json" "results" jj with
          | Error e -> Batch.note b "%s" e
          | Ok rs ->
              let sarif_rule_ids = List.map fst (results_by_rule sj) in
              List.iter
                (fun r ->
                  match (Json.member "rule" r, Json.member "verdict" r) with
                  | Some (`String rule), Some (`String verdict) when verdict <> "PASS" ->
                      Batch.check b
                        ~msg:(Printf.sprintf "non-PASS rule %S (verdict %s) must appear in sarif results, got [%s]"
                                rule verdict (String.concat "; " sarif_rule_ids))
                        (List.mem rule sarif_rule_ids)
                  | Some (`String rule), Some (`String "PASS") ->
                      Batch.check b ~msg:(Printf.sprintf "PASS rule %S must NOT appear in sarif results" rule)
                        (not (List.mem rule sarif_rule_ids))
                  | _ -> Batch.note b "a json result is missing rule/verdict")
                rs)) ;
  Lwt.return_unit

let register_not_analysed_becomes_notification () =
  Test.register ~__FILE__
    ~title:"sarif: an analysis_coverage row with status=not_analysed becomes a toolExecutionNotification, never silence"
    ~tags:["sarif"; "rules"; "coverage"]
  @@ fun () ->
  let db = fixture_db () in
  (* analysis_coverage (roadmap 1.3) is not part of arch-load's flat schema — added here the way
     a coverage-writing producer (arch-coverage-matrix) would, so the SARIF writer's read path is
     exercised the same way it would be on a real polyglot index. *)
  Db.with_db_rw db (fun conn ->
      Db.exec conn
        "CREATE TABLE analysis_coverage(id INTEGER PRIMARY KEY, language TEXT, analysis TEXT NOT \
         NULL, status TEXT NOT NULL, detail TEXT);
         INSERT INTO analysis_coverage(language, analysis, status, detail) VALUES \
         ('rust', 'callgraph', 'not_analysed', 'no rust producer configured');") ;
  let rf = rule_file "sarif_notanalysed" four_rules in
  let _, output = rules [db; rf; "--format"; "sarif"] in
  Batch.run (fun b ->
      match sarif_json b ~what:"sarif output" output with
      | None -> ()
      | Some j -> (
          match Json.member "runs" j with
          | Some (`List [ run ]) -> (
              match Json.member "invocations" run with
              | Some (`List [ inv ]) -> (
                  match Json.member "toolExecutionNotifications" inv with
                  | Some (`List notifs) ->
                      let texts =
                        List.filter_map
                          (fun n ->
                            match Json.member "message" n with
                            | Some m -> ( match Json.member "text" m with Some (`String s) -> Some s | _ -> None)
                            | None -> None)
                          notifs
                      in
                      Batch.check b
                        ~msg:(Printf.sprintf "a not_analysed notification mentioning 'rust' must be present, got: [%s]"
                                (String.concat "; " texts))
                        (List.exists (fun t -> contains ~needle:"rust" t) texts)
                  | other -> Batch.note b "invocation has no toolExecutionNotifications: %s" (Json.show other))
              | other -> Batch.note b "run has no singleton invocations: %s" (Json.show other))
          | other -> Batch.note b "sarif output does not have exactly one run: %s" (Json.show other))) ;
  Lwt.return_unit

(* Roadmap 2.1's amendment: two analyses from ONE producer must carry distinct
   `properties.category`/`automationDetails.id`, or a second GitHub upload overwrites the first
   rather than merging (GitHub stopped combining same-category runs in July 2025). Exercised
   directly against {!Arch_tools.Arch_sarif}, the shared writer, since a single `arch-rules`
   invocation only ever emits one run — this is 2.2 (`arch-report`, several runs per log)'s
   contract, checked here so it cannot regress before that item exists to exercise it end to end. *)
let register_two_runs_distinct_categories () =
  Test.register ~__FILE__
    ~title:"sarif: two runs from one producer must carry distinct category/automationDetails.id"
    ~tags:["sarif"; "category"]
  @@ fun () ->
  let open Arch_tools in
  let finding rule_id : Arch_sarif.finding =
    { rule_id; level = Arch_sarif.Error; message = "x"; soundness_class = None;
      soundness_unknown_top = false; top_reasons = []; locations = []; code_flow = [] }
  in
  let run1 : Arch_sarif.run =
    { producer = "arch-index"; producer_version = Some "1.0"; category = "arch-index/callgraph";
      findings = [ finding "r1" ]; coverage = []; top_frontier = None; notifications = [] }
  in
  let run2 : Arch_sarif.run =
    { producer = "arch-index"; producer_version = Some "1.0"; category = "arch-index/effects";
      findings = [ finding "r2" ]; coverage = []; top_frontier = None; notifications = [] }
  in
  let log_text = Arch_sarif.to_string [ run1; run2 ] in
  Batch.run (fun b ->
      match Json.strict_object ~what:"combined sarif log" log_text with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match Json.member "runs" j with
          | Some (`List [ a; b_run ]) ->
              let category r =
                match Json.member "properties" r with
                | Some p -> ( match Json.member "category" p with Some (`String s) -> Some s | _ -> None)
                | None -> None
              in
              let automation_id r =
                match Json.member "automationDetails" r with
                | Some ad -> ( match Json.member "id" ad with Some (`String s) -> Some s | _ -> None)
                | None -> None
              in
              let show_opt = function None -> "<none>" | Some s -> Printf.sprintf "%S" s in
              Batch.check b
                ~msg:(Printf.sprintf "the two runs' categories must differ, got %s and %s"
                        (show_opt (category a)) (show_opt (category b_run)))
                (category a <> category b_run && category a <> None) ;
              Batch.check b
                ~msg:(Printf.sprintf "the two runs' automationDetails.id must differ, got %s and %s"
                        (show_opt (automation_id a)) (show_opt (automation_id b_run)))
                (automation_id a <> automation_id b_run && automation_id a <> None) ;
              let valid, msg = validate_sarif ~what:"combined two-run sarif log" log_text in
              Batch.check b ~msg:(Printf.sprintf "the two-run log must still validate:\n%s" msg) valid
          | other -> Batch.note b "expected exactly two runs, got: %s" (Json.show other))) ;
  Lwt.return_unit

(* A future SARIF-in adapter (roadmap 2.3) constructs {!Arch_tools.Arch_sarif.finding} values
   with [soundness_class = Some "heuristic"] directly — this is the writer-level guarantee that
   the field round-trips into `properties.soundness_class` (spec FR-022: "a heuristic fact
   carries that in its properties bag so a consumer can filter"), checked once here rather than
   only implicitly through arch-rules, which never sets this field itself. *)
let register_heuristic_soundness_class () =
  Test.register ~__FILE__ ~title:"sarif: a finding's soundness_class=heuristic round-trips into properties"
    ~tags:["sarif"; "heuristic"]
  @@ fun () ->
  let open Arch_tools in
  let finding : Arch_sarif.finding =
    { rule_id = "semgrep.some-rule"; level = Arch_sarif.Warning; message = "heuristic finding";
      soundness_class = Some "heuristic"; soundness_unknown_top = false; top_reasons = [];
      locations = []; code_flow = [] }
  in
  let run : Arch_sarif.run =
    { producer = "semgrep"; producer_version = Some "1.2.3"; category = "semgrep/oss";
      findings = [ finding ]; coverage = []; top_frontier = None; notifications = [] }
  in
  let text = Arch_sarif.to_string [ run ] in
  Batch.run (fun b ->
      match Json.strict_object ~what:"heuristic sarif log" text with
      | Error e -> Batch.note b "%s" e
      | Ok j -> (
          match find_result j ~rule_id:"semgrep.some-rule" with
          | None -> Batch.note b "the finding has no SARIF result at all"
          | Some r -> (
              match Json.member "properties" r with
              | Some props ->
                  Batch.eq_string_opt b ~msg:"properties.soundness_class"
                    (match Json.member "soundness_class" props with Some (`String s) -> Some s | _ -> None)
                    (Some "heuristic")
              | None -> Batch.note b "result has no properties bag at all"))) ;
  Lwt.return_unit

let register () =
  register_schema_valid () ;
  register_pass_excluded () ;
  register_level_mapping () ;
  register_unknown_carries_soundness_and_top_reason () ;
  register_witness_becomes_code_flow () ;
  register_run_shape_and_category () ;
  register_json_sarif_round_trip () ;
  register_not_analysed_becomes_notification () ;
  register_two_runs_distinct_categories () ;
  register_heuristic_soundness_class ()
