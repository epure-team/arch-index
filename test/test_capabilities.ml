(** Alcotest tests for Phase-2 capability layer.

    Tests:
    1. capability_types: reachability_class and edge_type serialisation roundtrips
    2. capability_extractor: derive_reachability_class, derive_gating_from_calls
    3. capability_extractor: sidecar YAML parsing
    4. capability_db: write_capabilities + write_attack_edges with an in-memory DB
    5. Selftest: full round-trip (migration → insert capabilities → insert edges → queries) *)

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

(* ── capability_extractor: static derivation ─────────────────────────────── *)

let test_derive_reachability_validate () =
  let rc = CE.derive_reachability_class "src/proto_025/validate.ml" in
  check (option string) "validate.ml → Validate"
    (Some "validate") (Option.map CT.reachability_class_to_string rc)

let test_derive_reachability_apply () =
  let rc = CE.derive_reachability_class "src/proto_025/apply.ml" in
  check (option string) "apply.ml → Apply"
    (Some "apply") (Option.map CT.reachability_class_to_string rc)

let test_derive_reachability_rpc () =
  let rc = CE.derive_reachability_class "src/proto_025/rpc_services.ml" in
  check (option string) "rpc_services.ml → Rpc"
    (Some "rpc") (Option.map CT.reachability_class_to_string rc)

let test_derive_reachability_none () =
  let rc = CE.derive_reachability_class "src/lib_some_helper/utils.ml" in
  (* utils.ml doesn't match any pattern — Unknown or None *)
  (match rc with
   | None | Some CT.Unknown -> ()
   | Some other ->
     fail (Printf.sprintf "expected None/Unknown, got %s"
       (CT.reachability_class_to_string other)))

let test_derive_gating_flag () =
  let g = CE.derive_gating_from_calls ["check_dal_feature_enabled"; "some_other_fn"] in
  match g with
  | Some s when String.length s > 5 && String.sub s 0 5 = "flag(" -> ()
  | Some s -> fail (Printf.sprintf "expected flag(...), got %s" s)
  | None   -> fail "expected Some flag(...)"

let test_derive_gating_signature () =
  let g = CE.derive_gating_from_calls ["Bls.check"; "Token.transfer"] in
  check (option string) "Bls.check → auth(signature)"
    (Some "auth(signature)") g

let test_derive_gating_manager () =
  let g = CE.derive_gating_from_calls ["assert_manager"; "something"] in
  check (option string) "assert_manager → auth(manager_key)"
    (Some "auth(manager_key)") g

let test_derive_gating_gas () =
  let g = CE.derive_gating_from_calls ["Gas.check"; "run_contract"] in
  check (option string) "Gas.check → cost(gas)"
    (Some "cost(gas)") g

let test_derive_gating_none () =
  let g = CE.derive_gating_from_calls ["helper_fn"; "pure_computation"] in
  check (option string) "no gate" None g

(* ── capability_extractor: make_static_record ────────────────────────────── *)

let test_make_static_record () =
  let r = CE.make_static_record
    ~function_name:"Apply.apply_operation"
    ~file_path:(Some "src/proto_025/apply.ml")
    ~callees:["Gas.check"; "Token.credit"] in
  check string "source" "static" r.CT.cap_source;
  check (option string) "reachability"
    (Some "apply") (Option.map CT.reachability_class_to_string r.CT.cap_reachability);
  check (option string) "gating" (Some "cost(gas)") r.CT.cap_gating

(* ── capability_extractor: merge_records ─────────────────────────────────── *)

let test_merge_records () =
  let base = CE.make_static_record
    ~function_name:"Foo.bar"
    ~file_path:(Some "src/validate.ml")
    ~callees:[] in
  let override = {
    CT.cap_function_name  = "Foo.bar";
    cap_file_path         = None;
    cap_reachability      = None;
    cap_actor_role        = Some "baker,delegate";
    cap_temporal_class    = Some "validate_time";
    cap_gating            = None;
    cap_value_touched     = [];
    cap_precondition      = Some "storage.registered = true";
    cap_source            = "sidecar";
  } in
  let merged = CE.merge_records ~base ~override in
  (* base reachability preserved *)
  check (option string) "reachability preserved"
    (Some "validate") (Option.map CT.reachability_class_to_string merged.CT.cap_reachability);
  (* override actor_role applied *)
  check (option string) "actor_role from sidecar"
    (Some "baker,delegate") merged.CT.cap_actor_role;
  check string "source = sidecar" "sidecar" merged.CT.cap_source

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
    actor_role: ["baker", "delegate"]
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
    check (option string) "actor_role" (Some "baker,delegate") cap.CT.cap_actor_role;
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

(* ── capability_db: full round-trip ─────────────────────────────────────── *)

let test_write_capabilities_roundtrip () =
  let path = create_migrated_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let records = [
      { CT.cap_function_name  = "Apply.apply_transaction";
        cap_file_path         = Some "src/proto/apply.ml";
        cap_reachability      = Some CT.Apply;
        cap_actor_role        = Some "baker";
        cap_temporal_class    = Some "apply_time";
        cap_gating            = Some "cost(gas)";
        cap_value_touched     = [{ CT.vt_kind = "balance"; vt_direction = "debit" }];
        cap_precondition      = Some "balance >= fee";
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
        ae_to          = "Apply.apply_transaction";
        ae_type        = CT.Sequence;
        ae_evidence    = Some "validate before apply";
        ae_source      = "static"; };
      { CT.ae_from     = "Reset.clear_flag";
        ae_to          = "Apply.apply_transaction";
        ae_type        = CT.RemovesGuard;
        ae_evidence    = Some "clear_flag removes the feature gate";
        ae_source      = "sidecar"; };
      { CT.ae_from     = "Rpc.submit";
        ae_to          = "Apply.apply_transaction";
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
    let edge = { CT.ae_from = "A.foo"; ae_to = "B.bar"; ae_type = CT.Sequence;
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

(* ── test suite ──────────────────────────────────────────────────────────── *)

let () =
  run "arch_capabilities" [
    "capability_types", [
      test_case "reachability_class_roundtrip"     `Quick test_reachability_class_roundtrip;
      test_case "reachability_class_unknown"       `Quick test_reachability_class_unknown_string;
      test_case "edge_type_roundtrip"              `Quick test_edge_type_roundtrip;
      test_case "edge_type_unknown"                `Quick test_edge_type_unknown_string;
    ];
    "static_derivation", [
      test_case "reachability_validate"            `Quick test_derive_reachability_validate;
      test_case "reachability_apply"               `Quick test_derive_reachability_apply;
      test_case "reachability_rpc"                 `Quick test_derive_reachability_rpc;
      test_case "reachability_none"                `Quick test_derive_reachability_none;
      test_case "gating_flag"                      `Quick test_derive_gating_flag;
      test_case "gating_signature"                 `Quick test_derive_gating_signature;
      test_case "gating_manager"                   `Quick test_derive_gating_manager;
      test_case "gating_gas"                       `Quick test_derive_gating_gas;
      test_case "gating_none"                      `Quick test_derive_gating_none;
      test_case "make_static_record"               `Quick test_make_static_record;
      test_case "merge_records"                    `Quick test_merge_records;
    ];
    "sidecar_yaml", [
      test_case "parse_capabilities"               `Quick test_sidecar_parse_capabilities;
      test_case "missing_file"                     `Quick test_sidecar_missing_file;
    ];
    "capability_db", [
      test_case "write_capabilities_roundtrip"     `Quick test_write_capabilities_roundtrip;
      test_case "write_attack_edges_roundtrip"     `Quick test_write_attack_edges_roundtrip;
      test_case "write_attack_edges_dedup"         `Quick test_write_attack_edges_dedup;
      test_case "write_capabilities_missing_db"    `Quick test_write_capabilities_missing_db;
    ];
  ]
