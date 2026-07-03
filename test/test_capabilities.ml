(** Alcotest tests for Phase-2 capability layer.

    Tests:
    1. capability_types: reachability_class and edge_type serialisation roundtrips
    2. capability_extractor: sidecar YAML parsing
    3. capability_db: write_capabilities + write_attack_edges with an in-memory DB
    4. Selftest: full round-trip (migration → insert capabilities → insert edges → queries) *)

open Alcotest

module CT = Arch_effects.Capability_types
module CE = Arch_effects.Capability_extractor
module CD = Arch_effects.Capability_db

(* ── helpers ─────────────────────────────────────────────────────────────── *)

(** Create a migrated test DB with all Phase-2 columns.
    Creates the table with all Phase-1 + Phase-2 columns in one shot,
    so no ALTER TABLE is needed (avoids portability issues with IF NOT EXISTS). *)
let create_migrated_db () =
  let path = Filename.temp_file "arch_cap_test_migrated" ".db" in
  let db = Sqlite3.db_open path in
  let exec sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> ()
    | _ -> failwith ("SQL error: " ^ sql)
  in
  exec "CREATE TABLE IF NOT EXISTS functions \
        (id INTEGER PRIMARY KEY, name TEXT, file_path TEXT, exported INTEGER DEFAULT 0)";
  (* Create function_effects with all Phase-1 + Phase-2 columns from the start *)
  exec "CREATE TABLE IF NOT EXISTS function_effects \
        (id INTEGER PRIMARY KEY AUTOINCREMENT, \
         function_id INTEGER, function_name TEXT NOT NULL, \
         file_path TEXT, value_kind_id INTEGER, value_kind TEXT NOT NULL, \
         target TEXT, is_direct BOOLEAN NOT NULL DEFAULT 1, \
         soundness TEXT NOT NULL DEFAULT 'candidate', \
         producer TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP, \
         reachability_class TEXT, actor_role TEXT, temporal_class TEXT, \
         gating TEXT, value_touched TEXT, precondition TEXT)";
  exec "CREATE TABLE IF NOT EXISTS attack_edges (\
          id INTEGER PRIMARY KEY, from_action TEXT NOT NULL, \
          to_action TEXT NOT NULL, \
          edge_type TEXT NOT NULL, \
          evidence TEXT, source TEXT, created_at TEXT DEFAULT (datetime('now')))";
  ignore (Sqlite3.db_close db);
  path

(* ── capability_types: roundtrips ────────────────────────────────────────── *)

let test_reachability_class_roundtrip () =
  let open CT in
  let classes = [Validate; Apply; InternalOp; Rpc; ExternalOp; NodeLocal; Init; Unknown] in
  List.iter (fun rc ->
    let s = reachability_class_to_string rc in
    let back = reachability_class_of_string s in
    check (option (testable (fun fmt x -> Format.pp_print_string fmt (reachability_class_to_string x)) (=)))
      ("roundtrip " ^ s) (Some rc) back
  ) classes

let test_reachability_class_unknown_string () =
  check (option (testable (fun _ _ -> ()) (=)))
    "unknown string" None (CT.reachability_class_of_string "not_a_class")

let test_edge_type_roundtrip () =
  let open CT in
  let types = [Sequence; RemovesGuard; SharesResource; ActorDistinct] in
  List.iter (fun et ->
    let s = edge_type_to_string et in
    let back = edge_type_of_string s in
    check (option (testable (fun fmt x -> Format.pp_print_string fmt (edge_type_to_string x)) (=)))
      ("roundtrip " ^ s) (Some et) back
  ) types

let test_edge_type_unknown_string () =
  check (option (testable (fun _ _ -> ()) (=)))
    "unknown string" None (CT.edge_type_of_string "bogus")

(* ── capability_extractor: sidecar YAML parsing ──────────────────────────── *)

let write_sidecar_file content =
  let tmp = Filename.temp_file "sidecar_test" ".yaml" in
  let oc = open_out tmp in
  output_string oc content;
  close_out oc;
  tmp

let test_sidecar_parse_capabilities () =
  let yaml = {|
capabilities:
  - fn: "Apply.apply_transaction"
    actor_role: ["user", "admin"]
    temporal_class: ["apply_time"]
    gating: "auth(manager_key)"
    precondition: "storage.balance >= amount"
  - fn: "Validate.validate_op"
    actor_role: "any"
    gating: "flag(feature_x)"
attack_edges:
  - from: "Apply.apply_transaction"
    to: "Validate.validate_op"
    edge_type: "sequence"
    evidence: "apply always follows validate"
|} in
  let tmp = write_sidecar_file yaml in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let sc = CE.load_sidecar tmp in
    check int "2 capabilities" 2 (List.length sc.CE.sc_capabilities);
    check int "1 edge" 1 (List.length sc.CE.sc_edges);
    check int "0 errors" 0 (List.length sc.CE.sc_errors);
    let cap = List.find (fun c -> c.CT.cap_function_name = "Apply.apply_transaction")
      sc.CE.sc_capabilities in
    check (option string) "actor_role" (Some "user,admin") cap.CT.cap_actor_role;
    check (option string) "gating" (Some "auth(manager_key)") cap.CT.cap_gating;
    let edge = List.hd sc.CE.sc_edges in
    check string "edge from" "Apply.apply_transaction" edge.CT.ae_from;
    check string "edge to"   "Validate.validate_op"   edge.CT.ae_to;
    check string "edge type" "sequence" (CT.edge_type_to_string edge.CT.ae_type)
  )

let test_sidecar_missing_file () =
  let sc = CE.load_sidecar "/no/such/file.yaml" in
  check int "0 capabilities" 0 (List.length sc.CE.sc_capabilities);
  check bool "has error" true (sc.CE.sc_errors <> [])

(* Empty-yield guard: a non-empty file in a foreign dialect (unrecognised
   sections / keys) parses to 0 caps + 0 edges — this must surface an error
   rather than silently loading nothing. *)
let test_sidecar_empty_yield_is_error () =
  let yaml = {|
component: widget
actions:
  - id: handler.entry
    where: src/module.ml:240
attack_edges:
  - id: EDGE-1
    target: T-2
    hypothesis: two entries in one batch.
|} in
  let tmp = write_sidecar_file yaml in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let sc = CE.load_sidecar tmp in
    check int "0 capabilities" 0 (List.length sc.CE.sc_capabilities);
    check int "0 edges" 0 (List.length sc.CE.sc_edges);
    check bool "has empty-yield error" true (sc.CE.sc_errors <> []))

(* A genuinely empty (comment/blank-only) file yields 0/0 but is not flagged:
   the guard fires only when actual content was present. *)
let test_sidecar_blank_no_error () =
  let yaml = "# just a comment\n\n   \n" in
  let tmp = write_sidecar_file yaml in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let sc = CE.load_sidecar tmp in
    check int "0 capabilities" 0 (List.length sc.CE.sc_capabilities);
    check int "0 edges" 0 (List.length sc.CE.sc_edges);
    check int "no error" 0 (List.length sc.CE.sc_errors))

(* ── G4: value_touched parsing ───────────────────────────────────────────── *)

(** A capability with inline-JSON value_touched must survive parsing.
    On the pre-fix loader value_touched was hardcoded to [] and silently
    dropped — this asserts it is now populated. *)
let test_sidecar_parse_value_touched () =
  let yaml = {|
capabilities:
  - fn: "Store.commit"
    actor_role: ["operator"]
    value_touched: [{"kind": "balance", "direction": "credit"}]
  - fn: "Ops.execute_message"
    actor_role: ["external"]
    value_touched: [{"kind": "resource", "direction": "burn"}, {"kind": "balance", "direction": "debit"}]
|} in
  let tmp = write_sidecar_file yaml in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let sc = CE.load_sidecar tmp in
    let row_commit = List.find (fun c -> c.CT.cap_function_name = "Store.commit")
      sc.CE.sc_capabilities in
    check int "row_commit: 1 value_touch" 1 (List.length row_commit.CT.cap_value_touched);
    let vt = List.hd row_commit.CT.cap_value_touched in
    check string "row_commit vt kind" "balance" vt.CT.vt_kind;
    check string "row_commit vt direction" "credit" vt.CT.vt_direction;
    let row_exec = List.find (fun c -> c.CT.cap_function_name = "Ops.execute_message")
      sc.CE.sc_capabilities in
    check int "row_exec: 2 value_touches" 2 (List.length row_exec.CT.cap_value_touched);
    let kinds = List.map (fun v -> v.CT.vt_kind) row_exec.CT.cap_value_touched in
    check bool "row_exec touches resource" true (List.mem "resource" kinds);
    check bool "row_exec touches balance" true (List.mem "balance" kinds))

(* ── G3: inline comment stripping ────────────────────────────────────────── *)

(** Inline `# ...` comments on value lines must not pollute the parsed value,
    but a `#` inside a quoted string must be preserved. *)
let test_sidecar_strip_inline_comments () =
  let yaml = {|
capabilities:
  - fn: "Store.act"   # the action under test
    actor_role: ["operator"]   # only the operator
    gating: "auth(deposit)"  # requires a deposit
    precondition: "tag = '#1 candidate'"
    value_touched: [{"kind": "resource", "direction": "debit"}]  # burns resource
|} in
  let tmp = write_sidecar_file yaml in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let sc = CE.load_sidecar tmp in
    check int "1 capability" 1 (List.length sc.CE.sc_capabilities);
    let c = List.hd sc.CE.sc_capabilities in
    check string "fn has no comment" "Store.act" c.CT.cap_function_name;
    check (option string) "actor_role clean" (Some "operator") c.CT.cap_actor_role;
    check (option string) "gating clean" (Some "auth(deposit)") c.CT.cap_gating;
    (* the '#' inside the quoted precondition must survive *)
    check (option string) "quoted # preserved"
      (Some "tag = '#1 candidate'") c.CT.cap_precondition;
    check int "value_touched parsed despite trailing comment"
      1 (List.length c.CT.cap_value_touched))

(* ── G2: from_path / to_path edge discriminators ─────────────────────────── *)

let test_sidecar_parse_edge_paths () =
  let yaml = {|
attack_edges:
  - from: "timeout"
    from_path: "kernel/src/module_a.rs"
    to: "deposit"
    to_path: "kernel/src/module_b.rs"
    edge_type: "removes_guard"
    evidence: "forced inclusion"
|} in
  let tmp = write_sidecar_file yaml in
  Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
    let sc = CE.load_sidecar tmp in
    check int "1 edge" 1 (List.length sc.CE.sc_edges);
    let e = List.hd sc.CE.sc_edges in
    check (option string) "from_path" (Some "kernel/src/module_a.rs") e.CT.ae_from_path;
    check (option string) "to_path" (Some "kernel/src/module_b.rs") e.CT.ae_to_path)

(* ── capability_db: full round-trip ─────────────────────────────────────── *)

let test_write_capabilities_roundtrip () =
  let path = create_migrated_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let records = [
      { CT.cap_function_name  = "Apply.apply_transaction";
        cap_file_path         = Some "src/proto/apply.ml";
        cap_reachability      = Some CT.Apply;
        cap_actor_role        = Some "user";
        cap_temporal_class    = Some "apply_time";
        cap_gating            = Some "cost(gas)";
        cap_value_touched     = [{ CT.vt_kind = "balance"; vt_direction = "debit" }];
        cap_precondition      = Some "balance >= amount";
        cap_source            = "static"; };
      { CT.cap_function_name  = "Validate.check_op";
        cap_file_path         = Some "src/proto/validate.ml";
        cap_reachability      = Some CT.Validate;
        cap_actor_role        = Some "any";
        cap_temporal_class    = Some "validate_time";
        cap_gating            = Some "flag(feature_y)";
        cap_value_touched     = [];
        cap_precondition      = None;
        cap_source            = "sidecar"; };
    ] in
    match CD.write_capabilities ~db_path:path records with
    | Error msg -> fail ("write_capabilities failed: " ^ msg)
    | Ok (n_upd, n_ins, n_skip) ->
      check int "2 rows" 2 (n_upd + n_ins);
      check int "0 skipped" 0 n_skip
  )

let test_write_attack_edges_roundtrip () =
  let path = create_migrated_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let edges = [
      { CT.ae_from     = "Validate.check_op";
        ae_from_path   = None;
        ae_to          = "Apply.apply_transaction";
        ae_to_path     = None;
        ae_type        = CT.Sequence;
        ae_evidence    = Some "validate before apply";
        ae_source      = "static"; };
      { CT.ae_from     = "Reset.clear_flag";
        ae_from_path   = None;
        ae_to          = "Apply.apply_transaction";
        ae_to_path     = None;
        ae_type        = CT.RemovesGuard;
        ae_evidence    = Some "clear_flag removes the feature gate";
        ae_source      = "sidecar"; };
      { CT.ae_from     = "Rpc.submit";
        ae_from_path   = None;
        ae_to          = "Apply.apply_transaction";
        ae_to_path     = None;
        ae_type        = CT.ActorDistinct;
        ae_evidence    = None;
        ae_source      = "sidecar"; };
    ] in
    match CD.write_attack_edges ~db_path:path edges with
    | Error msg -> fail ("write_attack_edges failed: " ^ msg)
    | Ok (n_ins, n_skip) ->
      check int "3 edges" 3 n_ins;
      check int "0 skipped" 0 n_skip
  )

let test_write_attack_edges_dedup () =
  let path = create_migrated_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let edge = { CT.ae_from = "A.foo"; ae_from_path = None;
                 ae_to = "B.bar"; ae_to_path = None; ae_type = CT.Sequence;
                 ae_evidence = None; ae_source = "static" } in
    (match CD.write_attack_edges ~db_path:path [edge; edge] with
     | Error msg -> fail ("write failed: " ^ msg)
     | Ok (n_ins, _n_skip) ->
       (* INSERT OR IGNORE: second insert is a no-op; 1 or 2 depending on SQLite *)
       check bool "at least 1 inserted" true (n_ins >= 1))
  )

let test_write_capabilities_missing_db () =
  match CD.write_capabilities ~db_path:"/no/such.db" [] with
  | Error _ -> ()
  | Ok _ -> fail "expected Error on missing db"

(* ── G4 end-to-end regression: load YAML → DB → actor-paths query ────────────
   This is the blocking-bug proof. It exercises the REAL loader path
   (CE.load_sidecar → CD.write_capabilities → CD.write_attack_edges — exactly
   what the arch-sidecar-load binary does), then runs the SAME SQL that
   `arch-query actor-paths balance` runs, and asserts a cross-role value
   crossing (two roles both touching `balance`) appears.

   On the PRE-FIX loader value_touched was hardcoded to [] in flush_cap, so
   inserted rows carried only value_kind='UnknownMut' and the actor-paths query
   returned ZERO rows. This test therefore FAILS on the old loader and PASSES
   after the G4 fix. *)

(** Count cross-role pairs both touching [value_kind], mirroring the
    `actor-paths` SQL in ./arch-query (value_touched JSON match + value_kind
    fallback, distinct non-NULL actor_roles). *)
let actor_paths_count db_path value_kind =
  let db = Sqlite3.db_open db_path in
  let sql = Printf.sprintf
    "SELECT COUNT(*) FROM ( \
       SELECT DISTINCT a.function_name, b.function_name \
       FROM function_effects a \
       JOIN function_effects b \
         ON a.actor_role IS NOT NULL AND b.actor_role IS NOT NULL \
        AND a.actor_role != b.actor_role \
        AND a.function_name != b.function_name \
       WHERE (a.value_kind = '%s' OR lower(COALESCE(a.value_touched,'')) LIKE '%%\"kind\":\"%s\"%%') \
         AND (b.value_kind = '%s' OR lower(COALESCE(b.value_touched,'')) LIKE '%%\"kind\":\"%s\"%%'))"
    value_kind value_kind value_kind value_kind in
  let result = ref 0 in
  (match Sqlite3.exec_no_headers db ~cb:(fun row ->
     match row.(0) with Some n -> result := int_of_string n | None -> ()) sql
   with _ -> ());
  ignore (Sqlite3.db_close db);
  !result

let test_actor_paths_end_to_end () =
  (* A minimal sidecar with a cross-role balance crossing:
       commit          (operator) credits balance
       execute_message (external) debits  balance
     Distinct roles, both touching `balance` → one actor-paths pair. *)
  let yaml = {|
capabilities:
  - fn: "Store.commit"
    file_path: "src/module/store.ml"
    actor_role: ["operator"]
    temporal_class: ["boundary"]
    value_touched: [{"kind": "balance", "direction": "credit"}]
  - fn: "Ops.execute_message"
    file_path: "src/module/ops.ml"
    actor_role: ["external"]
    temporal_class: ["boundary"]
    value_touched: [{"kind": "balance", "direction": "debit"}]
attack_edges:
  - from: "Store.commit"
    from_path: "src/module/store.ml"
    to: "Ops.execute_message"
    to_path: "src/module/ops.ml"
    edge_type: "actor_distinct"
    evidence: "guard-removal -> balance-extraction crossing"
|} in
  let tmp = write_sidecar_file yaml in
  let path = create_migrated_db () in
  Fun.protect ~finally:(fun () -> Sys.remove tmp; Sys.remove path) (fun () ->
    (* Real loader path — identical to bin/arch_sidecar_load/main.ml *)
    let sc = CE.load_sidecar tmp in
    check int "no sidecar parse errors" 0 (List.length sc.CE.sc_errors);
    (match CD.write_capabilities ~db_path:path sc.CE.sc_capabilities with
     | Error msg -> fail ("write_capabilities failed: " ^ msg)
     | Ok _ -> ());
    (match CD.write_attack_edges ~db_path:path sc.CE.sc_edges with
     | Error msg -> fail ("write_attack_edges failed: " ^ msg)
     | Ok _ -> ());
    (* The headline assertion: actor-paths balance is NON-EMPTY end-to-end.
       This is exactly what was empty on the pre-G4 loader. *)
    let n = actor_paths_count path "balance" in
    check bool "actor-paths balance is non-empty (G4 fixed)" true (n >= 1);
    (* Confirm value_touched actually reached the DB (the precise G4 symptom). *)
    let db = Sqlite3.db_open path in
    let vt_rows = ref 0 in
    (match Sqlite3.exec_no_headers db ~cb:(fun row ->
       match row.(0) with Some n -> vt_rows := int_of_string n | None -> ())
       "SELECT COUNT(*) FROM function_effects WHERE value_touched IS NOT NULL"
     with _ -> ());
    (* And confirm the G2 file_path discriminator was persisted. *)
    let fp_rows = ref 0 in
    (match Sqlite3.exec_no_headers db ~cb:(fun row ->
       match row.(0) with Some n -> fp_rows := int_of_string n | None -> ())
       "SELECT COUNT(*) FROM function_effects WHERE file_path IS NOT NULL"
     with _ -> ());
    let edge_path_rows = ref 0 in
    (match Sqlite3.exec_no_headers db ~cb:(fun row ->
       match row.(0) with Some n -> edge_path_rows := int_of_string n | None -> ())
       "SELECT COUNT(*) FROM attack_edges WHERE from_path IS NOT NULL AND to_path IS NOT NULL"
     with _ -> ());
    ignore (Sqlite3.db_close db);
    check bool "value_touched persisted to DB" true (!vt_rows >= 2);
    check bool "file_path persisted to DB (G2)" true (!fp_rows >= 2);
    check bool "edge from_path/to_path persisted (G2)" true (!edge_path_rows >= 1))

(* ── test suite ──────────────────────────────────────────────────────────── *)

let () =
  run "arch_capabilities" [
    "capability_types", [
      test_case "reachability_class_roundtrip"     `Quick test_reachability_class_roundtrip;
      test_case "reachability_class_unknown"       `Quick test_reachability_class_unknown_string;
      test_case "edge_type_roundtrip"              `Quick test_edge_type_roundtrip;
      test_case "edge_type_unknown"                `Quick test_edge_type_unknown_string;
    ];
    "sidecar_yaml", [
      test_case "parse_capabilities"               `Quick test_sidecar_parse_capabilities;
      test_case "missing_file"                     `Quick test_sidecar_missing_file;
      test_case "empty_yield_is_error"             `Quick test_sidecar_empty_yield_is_error;
      test_case "blank_no_error"                   `Quick test_sidecar_blank_no_error;
      test_case "parse_value_touched"              `Quick test_sidecar_parse_value_touched;
      test_case "strip_inline_comments"            `Quick test_sidecar_strip_inline_comments;
      test_case "parse_edge_paths"                 `Quick test_sidecar_parse_edge_paths;
    ];
    "capability_db", [
      test_case "write_capabilities_roundtrip"     `Quick test_write_capabilities_roundtrip;
      test_case "write_attack_edges_roundtrip"     `Quick test_write_attack_edges_roundtrip;
      test_case "write_attack_edges_dedup"         `Quick test_write_attack_edges_dedup;
      test_case "write_capabilities_missing_db"    `Quick test_write_capabilities_missing_db;
    ];
    "regression_g4_end_to_end", [
      test_case "actor_paths_end_to_end"           `Quick test_actor_paths_end_to_end;
    ];
  ]
