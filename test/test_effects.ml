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

let sqlite_exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> fail (Printf.sprintf "SQL %s: %s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))

let query_ints path sql =
  let db = Sqlite3.db_open path in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () ->
    let values = ref [] in
    let rc = Sqlite3.exec_no_headers db sql ~cb:(function
      | [| Some value |] -> values := int_of_string value :: !values
      | _ -> fail "unexpected query shape")
    in
    if rc <> Sqlite3.Rc.OK then fail (Sqlite3.errmsg db);
    List.rev !values)

let test_source_aware_main_schema () =
  let path = Filename.temp_file "arch_effects_main" ".db" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let db = Sqlite3.db_open path in
    sqlite_exec db "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT NOT NULL)";
    sqlite_exec db "CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT NOT NULL)";
    sqlite_exec db "INSERT INTO modules VALUES(1,'src/dir/../a.ml'),(2,'src/b.ml')";
    sqlite_exec db "INSERT INTO functions VALUES(11,1,'f'),(22,2,'f')";
    ignore (Sqlite3.db_close db);
    let open EI in
    let mk file kind =
      { er_function_name = "f"; er_file_path = Some file;
        er_value_kind = kind; er_target = None; er_soundness = Sound;
        er_producer = "test" }
    in
    (match ED.write_effects ~db_path:path [mk "src/./a.ml" HeapRef; mk "src/b.ml" HashTbl] with
     | Error msg -> fail msg | Ok (2, 0) -> () | Ok _ -> fail "wrong counts");
    check (list int) "exact path selects each homonym" [11; 22]
      (query_ints path "SELECT function_id FROM function_effects ORDER BY id"))

let test_complete_payload_identity () =
  let path = create_test_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let open EI in
    let mk soundness target =
      { er_function_name = "f"; er_file_path = None; er_value_kind = HeapRef;
        er_target = target; er_soundness = soundness; er_producer = "test" }
    in
    (match ED.write_effects ~db_path:path
       [mk Sound None; mk Candidate None; mk Sound (Some "")] with
     | Error msg -> fail msg | Ok (3, 0) -> () | Ok _ -> fail "distinct payloads collapsed");
    (match ED.write_effects ~db_path:path [mk Sound None] with
     | Error msg -> fail msg | Ok (0, 1) -> () | Ok _ -> fail "exact reload not duplicate");
    check (list int) "three payloads survive" [3]
      (query_ints path "SELECT count(*) FROM function_effects"))

let test_alternative_flat_and_stale_repair () =
  let path = Filename.temp_file "arch_effects_alt" ".db" in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let db = Sqlite3.db_open path in
    sqlite_exec db "CREATE TABLE functions(id INTEGER PRIMARY KEY,name TEXT,file_path TEXT)";
    sqlite_exec db "INSERT INTO functions VALUES(7,'f','a.ml')";
    sqlite_exec db "CREATE TABLE function_effects(id INTEGER PRIMARY KEY,function_id INTEGER,function_name TEXT NOT NULL,file_path TEXT,value_kind TEXT NOT NULL,target TEXT,is_direct INTEGER NOT NULL,soundness TEXT NOT NULL,producer TEXT)";
    sqlite_exec db "INSERT INTO function_effects VALUES(41,999,'f','a.ml','HeapRef',NULL,1,'sound','test')";
    ignore (Sqlite3.db_close db);
    let open EI in
    let r = { er_function_name="f"; er_file_path=Some "./a.ml"; er_value_kind=HeapRef; er_target=None; er_soundness=Sound; er_producer="test" } in
    (* Lexically equivalent path finds the payload row only when payload storage
       itself is canonicalized by the producer. Test stale repair with exact input. *)
    let r = { r with er_file_path=Some "a.ml" } in
    (match ED.write_effects ~db_path:path [r] with Error s -> fail s | Ok (1,0) -> () | Ok _ -> fail "repair count");
    check (list int) "row id retained and association repaired" [41;7]
      (query_ints path "SELECT id FROM function_effects UNION ALL SELECT function_id FROM function_effects");
    (match ED.write_effects ~db_path:path [r] with Error s -> fail s | Ok (0,1) -> () | Ok _ -> fail "reload count"));
  let ambiguous = Filename.temp_file "arch_effects_ambiguous" ".db" in
  Fun.protect ~finally:(fun () -> Sys.remove ambiguous) (fun () ->
    let db = Sqlite3.db_open ambiguous in
    sqlite_exec db "CREATE TABLE functions(id INTEGER PRIMARY KEY,name TEXT,file_path TEXT)";
    sqlite_exec db "INSERT INTO functions VALUES(7,'f','a.ml')";
    ignore (Sqlite3.db_close db);
    let open EI in
    let r = { er_function_name="f"; er_file_path=None; er_value_kind=HeapRef; er_target=None; er_soundness=Sound; er_producer="test" } in
    (match ED.write_effects ~db_path:ambiguous [r] with Error s -> fail s | Ok (1,0) -> () | Ok _ -> fail "initial association");
    let db = Sqlite3.db_open ambiguous in
    sqlite_exec db "INSERT INTO functions VALUES(8,'f','b.ml')";
    ignore (Sqlite3.db_close db);
    (match ED.write_effects ~db_path:ambiguous [r] with Error s -> fail s | Ok (1,0) -> () | Ok _ -> fail "ambiguity repair count");
    check (list int) "new ambiguity clears obsolete association" [1]
      (query_ints ambiguous "SELECT function_id IS NULL FROM function_effects"));
  let flat = create_test_db () in
  Fun.protect ~finally:(fun () -> Sys.remove flat) (fun () ->
    let open EI in
    let r = { er_function_name="missing"; er_file_path=Some "x.ml"; er_value_kind=HeapRef; er_target=None; er_soundness=Sound; er_producer="test" } in
    (match ED.write_effects ~db_path:flat [r] with Error s -> fail s | Ok (1,0) -> () | Ok _ -> fail "flat count");
    check (list int) "flat association remains NULL" [1]
      (query_ints flat "SELECT function_id IS NULL FROM function_effects"))

let test_batch_failure_rolls_back () =
  let path = create_test_db () in
  Fun.protect ~finally:(fun () -> Sys.remove path) (fun () ->
    let db = Sqlite3.db_open path in
    sqlite_exec db "CREATE TRIGGER reject_second BEFORE INSERT ON function_effects WHEN NEW.function_name='bad' BEGIN SELECT RAISE(ABORT,'injected failure'); END";
    ignore (Sqlite3.db_close db);
    let open EI in
    let mk name = { er_function_name=name; er_file_path=None; er_value_kind=HeapRef; er_target=None; er_soundness=Sound; er_producer="test" } in
    (match ED.write_effects ~db_path:path [mk "good"; mk "bad"] with Error _ -> () | Ok _ -> fail "injected SQL error reported success");
    check (list int) "earlier row rolled back" [0]
      (query_ints path "SELECT count(*) FROM function_effects"))

let test_producer_explicit_root_and_shadowing () =
  let root = Filename.temp_file "arch_effects_producer" "" in
  Sys.remove root;
  let q = Filename.quote in
  let run command = if Sys.command command <> 0 then fail ("command failed: " ^ command) in
  run ("mkdir -p " ^ q (Filename.concat root "src") ^ " " ^ q (Filename.concat root "obj/deep"));
  Fun.protect ~finally:(fun () -> ignore (Sys.command ("rm -rf -- " ^ q root))) (fun () ->
    let source = Filename.concat root "src/effect.ml" in
    let oc = open_out source in
    output_string oc "let f t = Hashtbl.replace t 1 2\nlet f t = Hashtbl.replace t 3 4\n";
    close_out oc;
    let before = Sys.getcwd () in
    Fun.protect ~finally:(fun () -> Sys.chdir before) (fun () ->
      Sys.chdir root;
      run "ocamlc -w -32 -bin-annot -c src/effect.ml -o obj/deep/effect.cmo");
    let records = Arch_effects.Ocaml_effects_extractor.extract_effects
      ~source_root:root ~build_dir:(Some (Filename.concat root "obj")) in
    let names = List.map (fun r -> r.EI.er_function_name) records in
    let paths = List.map (fun r -> r.EI.er_file_path) records in
    check (list string) "typedtree order numbers earlier shadow" ["f#1"; "f"] names;
    check (list (option string)) "relative metadata uses explicit root"
      [Some "src/effect.ml"; Some "src/effect.ml"] paths)

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
      test_case "source_aware_main_schema" `Quick test_source_aware_main_schema;
      test_case "complete_payload_identity" `Quick test_complete_payload_identity;
      test_case "alternative_flat_stale_repair" `Quick test_alternative_flat_and_stale_repair;
      test_case "batch_failure_rolls_back" `Quick test_batch_failure_rolls_back;
    ];
    "effects_load", [
      test_case "load_happy"   `Quick test_effects_load_happy;
      test_case "load_bad_json" `Quick test_effects_load_bad_json;
    ];
    "ocaml_producer", [
      test_case "explicit_root_and_shadowing" `Quick test_producer_explicit_root_and_shadowing;
    ];
  ]
