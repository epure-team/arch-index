(** Alcotest unit tests for the Capability A effects extractor (Phase 1).

    Tests the language-agnostic extractor interface types, value-kind
    serialisation, soundness labels, and the effects DB writer.

    Integration tests (CMT-based extraction) live in selftest-effects.sh. *)

open Alcotest

module EI = Arch_effects.Extractor_intf
module ED = Arch_effects.Effects_db

(* ── value_kind roundtrip ─────────────────────────────────────────────────── *)

let test_value_kind_to_string () =
  let open EI in
  check string "GlobalVar"    "GlobalVar"    (value_kind_to_string GlobalVar);
  check string "FieldAccess"  "FieldAccess"  (value_kind_to_string FieldAccess);
  check string "ArrayElem"    "ArrayElem"    (value_kind_to_string ArrayElem);
  check string "HashTbl"      "HashTbl"      (value_kind_to_string HashTbl);
  check string "BytesBuf"     "BytesBuf"     (value_kind_to_string BytesBuf);
  check string "HeapRef"      "HeapRef"      (value_kind_to_string HeapRef);
  check string "IoSideEffect" "IoSideEffect" (value_kind_to_string IoSideEffect);
  check string "EnvVar"       "EnvVar"       (value_kind_to_string EnvVar);
  check string "FileSystem"   "FileSystem"   (value_kind_to_string FileSystem);
  check string "Network"      "Network"      (value_kind_to_string Network);
  check string "UnknownMut"   "UnknownMut"   (value_kind_to_string UnknownMut)

let test_value_kind_of_string_roundtrip () =
  let open EI in
  let kinds = [GlobalVar; FieldAccess; ArrayElem; HashTbl; BytesBuf;
               HeapRef; IoSideEffect; EnvVar; FileSystem; Network; UnknownMut] in
  List.iter (fun k ->
    let s = value_kind_to_string k in
    check (option (testable (fun fmt x -> Format.pp_print_string fmt (value_kind_to_string x)) (=)))
      ("roundtrip " ^ s) (Some k) (value_kind_of_string s)
  ) kinds

let test_value_kind_of_string_unknown () =
  check (option (testable (fun _ _ -> ()) (=)))
    "unknown string" None (EI.value_kind_of_string "NotAKind")

(* ── soundness_to_string ─────────────────────────────────────────────────── *)

let test_soundness_strings () =
  let open EI in
  check string "sound"     "sound"     (soundness_to_string Sound);
  check string "candidate" "candidate" (soundness_to_string Candidate);
  check string "manual"    "manual"    (soundness_to_string Manual)

(* ── Effects_db.write_effects with an in-memory DB ──────────────────────── *)

(** Create a minimal in-memory SQLite DB with the function_effects table
    (as if the migration had been run).  Returns the path of a temp file DB. *)
let create_test_db () =
  let path = Filename.temp_file "arch_effects_test" ".db" in
  let db = Sqlite3.db_open path in
  let exec sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> ()
    | _ -> failwith ("SQL error: " ^ sql)
  in
  exec "CREATE TABLE IF NOT EXISTS functions \
        (id INTEGER PRIMARY KEY, name TEXT, file_path TEXT, exported INTEGER DEFAULT 0)";
  exec "CREATE TABLE IF NOT EXISTS function_effects \
        (id INTEGER PRIMARY KEY AUTOINCREMENT, \
         function_id INTEGER, function_name TEXT NOT NULL, \
         file_path TEXT, value_kind_id INTEGER, value_kind TEXT NOT NULL, \
         target TEXT, is_direct BOOLEAN NOT NULL DEFAULT 1, \
         soundness TEXT NOT NULL DEFAULT 'candidate', \
         producer TEXT, created_at TEXT DEFAULT CURRENT_TIMESTAMP)";
  ignore (Sqlite3.db_close db);
  path

let test_write_effects_happy () =
  let path = create_test_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let open EI in
    let records = [
      { er_function_name = "Foo.bar"; er_file_path = Some "foo.ml";
        er_value_kind = HashTbl; er_target = Some "myTable";
        er_soundness = Sound; er_producer = "test" };
      { er_function_name = "Foo.baz"; er_file_path = None;
        er_value_kind = HeapRef; er_target = None;
        er_soundness = Candidate; er_producer = "test" };
    ] in
    match ED.write_effects ~db_path:path records with
    | Error msg -> fail ("write_effects failed: " ^ msg)
    | Ok (n_inserted, n_skipped) ->
      check int "inserted 2" 2 n_inserted;
      check int "skipped 0"  0 n_skipped
  )

let test_write_effects_missing_db () =
  match ED.write_effects ~db_path:"/no/such/path/db.sqlite" [] with
  | Error _ -> ()   (* expected *)
  | Ok _    -> fail "should have failed on missing DB"

(* ── NDJSON loading ──────────────────────────────────────────────────────── *)

let test_effects_load_happy () =
  let path = create_test_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let ndjson =
      {|{"type":"effect","function_name":"pkg.Fn","file_path":"x.go","value_kind":"HashTbl","target":"myMap","soundness":"sound","producer":"test"}
{"type":"effect","function_name":"pkg.Gn","value_kind":"HeapRef","soundness":"candidate","producer":"test"}
|}
    in
    let ic = Scanf.Scanning.stdin in
    ignore ic;
    (* Use a string buffer as stdin substitute *)
    let tmp = Filename.temp_file "ndjson" ".ndjson" in
    Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
      let oc = open_out tmp in
      output_string oc ndjson;
      close_out oc;
      let ic = open_in tmp in
      Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
        match Arch_effects.Effects_load.load ~db_path:path ic with
        | Error msg -> fail ("load failed: " ^ msg)
        | Ok r ->
          check int "2 effects loaded" 2 r.Arch_effects.Effects_load.n_effects
      )
    )
  )

let test_effects_load_bad_json () =
  let path = create_test_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let ndjson = "this is not json\n" in
    let tmp = Filename.temp_file "ndjson_bad" ".ndjson" in
    Fun.protect ~finally:(fun () -> Sys.remove tmp) (fun () ->
      let oc = open_out tmp in
      output_string oc ndjson;
      close_out oc;
      let ic = open_in tmp in
      Fun.protect ~finally:(fun () -> close_in ic) (fun () ->
        match Arch_effects.Effects_load.load ~db_path:path ic with
        | Error _ -> ()  (* could fail *)
        | Ok r ->
          (* bad line skipped, 0 effects *)
          check int "0 effects on bad json" 0 r.Arch_effects.Effects_load.n_effects
      )
    )
  )

(* ── test suite ──────────────────────────────────────────────────────────── *)

let () =
  run "arch_effects" [
    "value_kind", [
      test_case "to_string"           `Quick test_value_kind_to_string;
      test_case "of_string_roundtrip" `Quick test_value_kind_of_string_roundtrip;
      test_case "of_string_unknown"   `Quick test_value_kind_of_string_unknown;
    ];
    "soundness", [
      test_case "to_string"           `Quick test_soundness_strings;
    ];
    "effects_db", [
      test_case "write_effects_happy"   `Quick test_write_effects_happy;
      test_case "write_effects_missing" `Quick test_write_effects_missing_db;
    ];
    "effects_load", [
      test_case "load_happy"   `Quick test_effects_load_happy;
      test_case "load_bad_json" `Quick test_effects_load_bad_json;
    ];
  ]
