(* Tests for Arch_mcp (specs/arch-mcp-server.md FR-001..021). *)

let mk_db stmts =
  let db = Sqlite3.db_open ":memory:" in
  List.iter
    (fun s ->
      match Sqlite3.exec db s with
      | Sqlite3.Rc.OK -> ()
      | rc -> failwith (Sqlite3.Rc.to_string rc ^ ": " ^ s))
    stmts;
  db

let ctx_of db = {Arch_mcp.db; si = Arch_mcp.detect_schema db}

(* Flat ⊤-marked fixture: clean -> a (MUST), a -> ext (MAY_TOP), b isolated. *)
let flat_ctx () =
  ctx_of
    (mk_db
       [
         "CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT)";
         "INSERT INTO comment_db_meta VALUES('callgraph_contract','v1')";
         "CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0)";
         "INSERT INTO functions VALUES('clean','x.ml',1),('a','x.ml',0),('b','x.ml',1)";
         "CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file \
          TEXT, call_site TEXT, kind TEXT)";
         "INSERT INTO calls VALUES('clean','x.ml','a','x.ml','x.ml:1','MUST')";
         "INSERT INTO calls VALUES('a','x.ml','ext',NULL,'x.ml:2','MAY_TOP')";
       ])

(* Legacy fixture: no kind column, no meta. *)
let legacy_ctx () =
  ctx_of
    (mk_db
       [
         "CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0)";
         "INSERT INTO functions VALUES('f','x.ml',1),('g','x.ml',0)";
         "CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file \
          TEXT, call_site TEXT)";
         "INSERT INTO calls VALUES('f','x.ml','g','x.ml','x.ml:1')";
       ])

(* Malformed: contract flag set but one lowercase kind. *)
let malformed_ctx () =
  ctx_of
    (mk_db
       [
         "CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT)";
         "INSERT INTO comment_db_meta VALUES('callgraph_contract','v1')";
         "CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0)";
         "CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file \
          TEXT, call_site TEXT, kind TEXT)";
         "INSERT INTO calls VALUES('f','x','g','x','x:1','must')";
       ])

(* Main/FK-schema fixture with exposed + generated line_count. *)
let fk_ctx () =
  ctx_of
    (mk_db
       [
         "CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT)";
         "INSERT INTO comment_db_meta VALUES('callgraph_contract','v1')";
         "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT, lines INTEGER)";
         "INSERT INTO modules VALUES(1,'m.ml',600)";
         "CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT, \
          line_start INTEGER, line_end INTEGER, exposed INTEGER DEFAULT 0, \
          comment_quality_score INTEGER DEFAULT NULL, line_count INTEGER GENERATED ALWAYS AS \
          (line_end - line_start + 1) STORED)";
         "INSERT INTO functions(id,module_id,name,line_start,line_end,exposed,comment_quality_score) \
          VALUES(1,1,'main',1,100,1,80),(2,1,'helper',101,110,0,NULL)";
         "CREATE TABLE calls(id INTEGER PRIMARY KEY, caller_id INTEGER, callee_id INTEGER, \
          callee_name TEXT, call_site TEXT, kind TEXT)";
         "INSERT INTO calls(caller_id,callee_id,callee_name,call_site,kind) \
          VALUES(1,2,'helper','m.ml:5','MUST')";
       ])

(* ── helpers ─────────────────────────────────────────────────────────────── *)

let req ?(id = 1) meth params =
  `Assoc
    ([("jsonrpc", `String "2.0"); ("id", `Int id); ("method", `String meth)]
    @ match params with Some p -> [("params", p)] | None -> [])

let call ctx tool args =
  Arch_mcp.handle_message ctx
    (req "tools/call" (Some (`Assoc [("name", `String tool); ("arguments", args)])))

let member k = function `Assoc l -> Option.value ~default:`Null (List.assoc_opt k l) | _ -> `Null

let tool_result resp =
  match resp with
  | Some r ->
      let res = member "result" r in
      let is_error = match member "isError" res with `Bool b -> b | _ -> false in
      let text =
        match member "content" res with
        | `List [c] -> (match member "text" c with `String s -> s | _ -> "")
        | _ -> ""
      in
      (is_error, text)
  | None -> Alcotest.fail "expected a response"

let tool_json resp =
  let is_error, text = tool_result resp in
  if is_error then Alcotest.fail ("unexpected isError: " ^ text);
  Yojson.Safe.from_string text

let check_bool = Alcotest.(check bool)

let check_str = Alcotest.(check string)

let contains hay needle =
  let nl = String.length needle and hl = String.length hay in
  let rec scan i = i + nl <= hl && (String.sub hay i nl = needle || scan (i + 1)) in
  scan 0

(* ── protocol (US-1) ─────────────────────────────────────────────────────── *)

let test_initialize () =
  let resp = Arch_mcp.handle_message (flat_ctx ()) (req "initialize" None) in
  match resp with
  | Some r ->
      check_str "protocol" "2024-11-05"
        (match member "protocolVersion" (member "result" r) with `String s -> s | _ -> "")
  | None -> Alcotest.fail "no response"

let test_tools_list () =
  let resp = Arch_mcp.handle_message (flat_ctx ()) (req "tools/list" None) in
  match resp with
  | Some r -> (
      match member "tools" (member "result" r) with
      | `List ts ->
          Alcotest.(check int) "11 tools" 11 (List.length ts);
          List.iter
            (fun t ->
              (match member "inputSchema" t with
              | `Assoc _ as s ->
                  check_bool "additionalProperties false" true
                    (member "additionalProperties" s = `Bool false)
              | _ -> Alcotest.fail "missing inputSchema"))
            ts
      | _ -> Alcotest.fail "no tools array")
  | None -> Alcotest.fail "no response"

let test_notification_silent () =
  let notif = `Assoc [("jsonrpc", `String "2.0"); ("method", `String "notifications/initialized")] in
  check_bool "no response" true (Arch_mcp.handle_message (flat_ctx ()) notif = None)

let test_unknown_method () =
  match Arch_mcp.handle_message (flat_ctx ()) (req "foo/bar" None) with
  | Some r ->
      Alcotest.(check int) "code" (-32601)
        (match member "code" (member "error" r) with `Int n -> n | _ -> 0)
  | None -> Alcotest.fail "no response"

let test_parse_error_line () =
  match Arch_mcp.handle_line (flat_ctx ()) "not json" with
  | Some r ->
      Alcotest.(check int) "code" (-32700)
        (match member "code" (member "error" r) with `Int n -> n | _ -> 0);
      check_bool "id null" true (member "id" r = `Null)
  | None -> Alcotest.fail "no response"

let test_blank_and_batch () =
  check_bool "blank skipped" true (Arch_mcp.handle_line (flat_ctx ()) "  " = None);
  match Arch_mcp.handle_message (flat_ctx ()) (`List []) with
  | Some r ->
      Alcotest.(check int) "batch -32600" (-32600)
        (match member "code" (member "error" r) with `Int n -> n | _ -> 0)
  | None -> Alcotest.fail "no response"

let test_unknown_tool () =
  let is_error, text = tool_result (call (flat_ctx ()) "nope" `Null) in
  check_bool "isError" true is_error;
  check_bool "message" true (contains text "Unknown tool: nope")

let test_string_id_echoed () =
  let r =
    Arch_mcp.handle_message (flat_ctx ())
      (`Assoc [("jsonrpc", `String "2.0"); ("id", `String "abc"); ("method", `String "initialize")])
  in
  match r with
  | Some r -> check_bool "id echoed" true (member "id" r = `String "abc")
  | None -> Alcotest.fail "no response"

(* ── core tools (US-2) ───────────────────────────────────────────────────── *)

let test_stats_flat () =
  let j = tool_json (call (flat_ctx ()) "arch_stats" `Null) in
  check_bool "functions" true (member "functions" j = `Int 3);
  check_bool "call_edges" true (member "call_edges" j = `Int 2);
  check_bool "contract" true (member "contract" j = `String "v1")

let test_find_escaping () =
  let ctx = flat_ctx () in
  ignore
    (Sqlite3.exec ctx.db "INSERT INTO functions VALUES('pct100%','y.ml',0)");
  let j = tool_json (call ctx "arch_find" (`Assoc [("substr", `String "100%")])) in
  match member "matches" j with
  | `List [m] -> check_bool "literal %" true (member "name" m = `String "pct100%")
  | `List l -> Alcotest.fail (Printf.sprintf "expected 1 match, got %d" (List.length l))
  | _ -> Alcotest.fail "no matches array"

let test_find_empty_substr_rejected () =
  let is_error, text = tool_result (call (flat_ctx ()) "arch_find" (`Assoc [("substr", `String "")])) in
  check_bool "isError" true is_error;
  check_bool "msg" true (contains text "non-empty")

let test_fan_in_bad_n () =
  let is_error, _ = tool_result (call (flat_ctx ()) "arch_fan_in" (`Assoc [("n", `Int 0)])) in
  check_bool "n=0 rejected" true is_error;
  let is_error2, _ = tool_result (call (flat_ctx ()) "arch_fan_in" (`Assoc [("n", `String "25")])) in
  check_bool "string n rejected" true is_error2

let test_unknown_arg_rejected () =
  let is_error, text =
    tool_result (call (flat_ctx ()) "arch_stats" (`Assoc [("bogus", `Int 1)]))
  in
  check_bool "isError" true is_error;
  check_bool "msg" true (contains text "unknown argument")

let test_reachable_from_truncation () =
  let j =
    tool_json
      (call (flat_ctx ()) "arch_reachable_from"
         (`Assoc [("name", `String "clean"); ("limit", `Int 1)]))
  in
  (match member "reachable" j with
  | `List l -> Alcotest.(check int) "1 row" 1 (List.length l)
  | _ -> Alcotest.fail "no reachable array");
  check_bool "truncated" true (member "truncated" j = `Bool true)

let test_callers_callees_flat () =
  let j = tool_json (call (flat_ctx ()) "arch_callers_of" (`Assoc [("name", `String "a")])) in
  check_bool "clean calls a" true (member "callers" j = `List [`String "clean"]);
  let j2 = tool_json (call (flat_ctx ()) "arch_callees_of" (`Assoc [("name", `String "a")])) in
  check_bool "a calls ext" true (member "callees" j2 = `List [`String "ext"])

let test_fk_schema_tools () =
  let ctx = fk_ctx () in
  let j = tool_json (call ctx "arch_callers_of" (`Assoc [("name", `String "helper")])) in
  check_bool "FK caller join" true (member "callers" j = `List [`String "main"]);
  let j2 = tool_json (call ctx "arch_exported" `Null) in
  (match member "exported" j2 with
  | `List [m] -> check_bool "exposed col" true (member "name" m = `String "main")
  | _ -> Alcotest.fail "expected 1 exported");
  let j3 = tool_json (call ctx "arch_stats" `Null) in
  check_bool "exported count" true (member "exported" j3 = `Int 1)

let test_find_exported_flag () =
  let j = tool_json (call (flat_ctx ()) "arch_find" (`Assoc [("substr", `String "clean")])) in
  match member "matches" j with
  | `List [m] -> check_bool "exported flag" true (member "exported" m = `Bool true)
  | _ -> Alcotest.fail "expected 1 match"

(* Codex review finding: FK schemas store qualified callee display names
   ("M.helper") while functions.name is unqualified — the closure must resolve
   through callee_id or resolved multi-hop paths silently disappear. *)
let test_fk_qualified_callee_closure () =
  let ctx =
    ctx_of
      (mk_db
         [
           "CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT)";
           "INSERT INTO comment_db_meta VALUES('callgraph_contract','v1')";
           "CREATE TABLE functions(id INTEGER PRIMARY KEY, name TEXT, exposed INTEGER DEFAULT 0)";
           "INSERT INTO functions VALUES(1,'entry',1),(2,'helper',0),(3,'leaf',0)";
           "CREATE TABLE calls(id INTEGER PRIMARY KEY, caller_id INTEGER, callee_id INTEGER, \
            callee_name TEXT, call_site TEXT, kind TEXT)";
           (* qualified display name, resolved via callee_id *)
           "INSERT INTO calls(caller_id,callee_id,callee_name,call_site,kind) \
            VALUES(1,2,'M.helper','m:1','MUST'),(2,3,'M.leaf','m:2','MUST')";
         ])
  in
  let j =
    tool_json (call ctx "arch_reaches" (`Assoc [("from", `String "entry"); ("to", `String "leaf")]))
  in
  check_bool "resolved 2-hop path found" true (member "result" j = `String "PATH_EXISTS")

(* ── sound tools (US-3) ──────────────────────────────────────────────────── *)

let test_reaches_must_only () =
  let j =
    tool_json (call (flat_ctx ()) "arch_reaches" (`Assoc [("from", `String "clean"); ("to", `String "a")]))
  in
  check_bool "PATH_EXISTS" true (member "result" j = `String "PATH_EXISTS");
  (* ext only via MAY_TOP → no MUST path *)
  let j2 =
    tool_json (call (flat_ctx ()) "arch_reaches" (`Assoc [("from", `String "clean"); ("to", `String "ext")]))
  in
  check_bool "NO_MUST_PATH" true (member "result" j2 = `String "NO_MUST_PATH")

let test_reaches_legacy_flag () =
  let j =
    tool_json (call (legacy_ctx ()) "arch_reaches" (`Assoc [("from", `String "f"); ("to", `String "g")]))
  in
  check_bool "legacy" true (member "legacy" j = `Bool true);
  check_bool "PATH_EXISTS" true (member "result" j = `String "PATH_EXISTS")

let test_unreachable_verdicts () =
  let ctx = flat_ctx () in
  let verdict from_ to_ =
    let j = tool_json (call ctx "arch_unreachable" (`Assoc [("from", `String from_); ("to", `String to_)])) in
    match member "verdict" j with `String s -> s | _ -> "?"
  in
  check_str "in closure" "REACHABLE" (verdict "clean" "a");
  (* clean reaches a which has a MAY_TOP edge → UNKNOWN for unrelated target *)
  check_str "top reachable" "UNKNOWN" (verdict "clean" "zzz");
  (* b has no outgoing edges at all → sound UNREACHABLE *)
  check_str "sound negative" "UNREACHABLE" (verdict "b" "a");
  check_str "self" "REACHABLE" (verdict "b" "b")

let test_refusals () =
  let is_error, text =
    tool_result (call (legacy_ctx ()) "arch_unreachable" (`Assoc [("from", `String "f"); ("to", `String "g")]))
  in
  check_bool "legacy refused" true is_error;
  (* spec C-21: refusal payload is structured JSON *)
  let rj = Yojson.Safe.from_string text in
  check_bool "REFUSED json" true (member "error" rj = `String "REFUSED");
  check_bool "reason present" true (match member "reason" rj with `String _ -> true | _ -> false);
  let is_error2, text2 =
    tool_result (call (malformed_ctx ()) "arch_escapes" (`Assoc [("from", `String "f")]))
  in
  check_bool "lowercase kind refused" true is_error2;
  check_bool "invalid kind wording" true (contains text2 "NULL/invalid kind")

let test_escapes () =
  let j = tool_json (call (flat_ctx ()) "arch_escapes" (`Assoc [("from", `String "clean")])) in
  (match member "escapes" j with
  | `List [e] ->
      check_bool "escaping fn" true (member "escaping_fn" e = `String "a");
      check_bool "kind" true (member "kind" e = `String "MAY_TOP")
  | _ -> Alcotest.fail "expected 1 escape");
  (* b reaches no ⊤ → empty array, not an error (EC-16) *)
  let j2 = tool_json (call (flat_ctx ()) "arch_escapes" (`Assoc [("from", `String "b")])) in
  check_bool "empty" true (member "escapes" j2 = `List [])

(* ── metrics (US-4) ──────────────────────────────────────────────────────── *)

let test_metrics_flat_omissions () =
  let j = tool_json (call (flat_ctx ()) "arch_metrics" `Null) in
  check_bool "exported_functions" true (member "exported_functions" j = `Int 2);
  check_bool "no doc_coverage_pct" true (member "doc_coverage_pct" j = `Null);
  check_bool "may_top_edges" true (member "may_top_edges" j = `Int 1)

let test_metrics_fk () =
  let j = tool_json (call (fk_ctx ()) "arch_metrics" `Null) in
  check_bool "large_files" true (member "large_files" j = `Int 1);
  check_bool "large_functions (generated col)" true (member "large_functions" j = `Int 1);
  check_bool "undocumented_exposed" true (member "undocumented_exposed" j = `Int 0);
  check_bool "doc_coverage_pct" true (member "doc_coverage_pct" j = `Float 100.0)

let test_no_functions_table () =
  let ctx = ctx_of (mk_db ["CREATE TABLE t(x)"]) in
  let is_error, text = tool_result (call ctx "arch_stats" `Null) in
  check_bool "isError" true is_error;
  check_bool "wording" true (contains text "not an arch-index index")

let () =
  Alcotest.run "arch_mcp"
    [
      ( "protocol",
        [
          Alcotest.test_case "initialize" `Quick test_initialize;
          Alcotest.test_case "tools/list" `Quick test_tools_list;
          Alcotest.test_case "notification silent" `Quick test_notification_silent;
          Alcotest.test_case "unknown method" `Quick test_unknown_method;
          Alcotest.test_case "parse error line" `Quick test_parse_error_line;
          Alcotest.test_case "blank + batch" `Quick test_blank_and_batch;
          Alcotest.test_case "unknown tool" `Quick test_unknown_tool;
          Alcotest.test_case "string id echoed" `Quick test_string_id_echoed;
        ] );
      ( "core-tools",
        [
          Alcotest.test_case "stats flat" `Quick test_stats_flat;
          Alcotest.test_case "find escapes wildcards" `Quick test_find_escaping;
          Alcotest.test_case "find empty substr" `Quick test_find_empty_substr_rejected;
          Alcotest.test_case "fan_in bad n" `Quick test_fan_in_bad_n;
          Alcotest.test_case "unknown arg" `Quick test_unknown_arg_rejected;
          Alcotest.test_case "reachable_from truncation" `Quick test_reachable_from_truncation;
          Alcotest.test_case "callers/callees flat" `Quick test_callers_callees_flat;
          Alcotest.test_case "FK schema tools" `Quick test_fk_schema_tools;
          Alcotest.test_case "find carries exported flag" `Quick test_find_exported_flag;
          Alcotest.test_case "FK qualified-callee closure" `Quick test_fk_qualified_callee_closure;
        ] );
      ( "sound-tools",
        [
          Alcotest.test_case "reaches MUST-only" `Quick test_reaches_must_only;
          Alcotest.test_case "reaches legacy flag" `Quick test_reaches_legacy_flag;
          Alcotest.test_case "unreachable verdicts" `Quick test_unreachable_verdicts;
          Alcotest.test_case "refusals" `Quick test_refusals;
          Alcotest.test_case "escapes" `Quick test_escapes;
        ] );
      ( "metrics",
        [
          Alcotest.test_case "flat omissions" `Quick test_metrics_flat_omissions;
          Alcotest.test_case "FK schema incl. generated col" `Quick test_metrics_fk;
          Alcotest.test_case "no functions table" `Quick test_no_functions_table;
        ] );
    ]
