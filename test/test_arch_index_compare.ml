(** Alcotest tests for Arch_index_compare — the first unit coverage of this module. It existed in
    the tree with no consumer at all before arch-body-compare; these pin the contract that CLI
    now relies on: Not_found on an unknown name, Identical when normalised bodies agree, Differs
    otherwise, and — the case a naive consumer would get wrong — two unreadable/empty bodies hash
    the same as each other and read as "Identical", which is exactly why a consumer must check
    for an empty body before treating that as proof. *)

open Alcotest

module C = Arch_index.Arch_index_compare

(* ── helpers ─────────────────────────────────────────────────────────────── *)

let create_db () =
  let path = Filename.temp_file "arch_body_compare_test" ".db" in
  let db = Sqlite3.db_open path in
  let exec sql =
    match Sqlite3.exec db sql with Sqlite3.Rc.OK -> () | _ -> failwith ("SQL error: " ^ sql)
  in
  exec "CREATE TABLE modules (id INTEGER PRIMARY KEY, path TEXT)" ;
  exec "CREATE TABLE functions (id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT, \
        line_start INTEGER, line_end INTEGER)" ;
  ignore (Sqlite3.db_close db) ;
  path

let insert_module db path =
  let stmt = Sqlite3.prepare db "INSERT INTO modules(path) VALUES(?)" in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT path)) ;
  ignore (Sqlite3.step stmt) ;
  ignore (Sqlite3.finalize stmt) ;
  Sqlite3.last_insert_rowid db

let insert_function db ~module_id ~name ~line_start ~line_end =
  let stmt =
    Sqlite3.prepare db "INSERT INTO functions(module_id,name,line_start,line_end) VALUES(?,?,?,?)"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT module_id)) ;
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT name)) ;
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.INT (Int64.of_int line_start))) ;
  ignore (Sqlite3.bind stmt 4 (Sqlite3.Data.INT (Int64.of_int line_end))) ;
  ignore (Sqlite3.step stmt) ;
  ignore (Sqlite3.finalize stmt)

(** Writes [lines] to a fresh temp file and returns its ABSOLUTE path — used directly as the
    `modules.path` row, with [project_root=""] in every test, so [compare_bodies] reads it as-is. *)
let write_source lines =
  let path = Filename.temp_file "arch_body_compare_src" ".ml" in
  let oc = open_out path in
  List.iter (fun l -> output_string oc (l ^ "\n")) lines ;
  close_out oc ;
  path

let result_testable =
  let pp fmt (r : C.result) =
    match r with
    | C.Not_found -> Format.pp_print_string fmt "Not_found"
    | C.Identical occs -> Format.fprintf fmt "Identical(%d)" (List.length occs)
    | C.Differs groups -> Format.fprintf fmt "Differs(%d groups)" (List.length groups)
  in
  let eq a b =
    match (a, b) with
    | C.Not_found, C.Not_found -> true
    | C.Identical o1, C.Identical o2 -> List.length o1 = List.length o2
    | C.Differs g1, C.Differs g2 -> List.length g1 = List.length g2
    | _ -> false
  in
  testable pp eq

(* ── tests ───────────────────────────────────────────────────────────────── *)

let test_not_found () =
  let path = create_db () in
  let db = Sqlite3.db_open path in
  check result_testable "unknown name" C.Not_found (C.compare_bodies db ~project_root:"" "nope") ;
  ignore (Sqlite3.db_close db)

let test_single_occurrence_is_identical () =
  let path = create_db () in
  let db = Sqlite3.db_open path in
  let src = write_source [ "let f x = x + 1" ] in
  let mid = insert_module db src in
  insert_function db ~module_id:mid ~name:"f" ~line_start:1 ~line_end:1 ;
  match C.compare_bodies db ~project_root:"" "f" with
  | C.Identical [ occ ] ->
      check int "line_start" 1 occ.line_start ;
      check string "body" "let f x = x + 1" occ.body
  | _ -> fail "expected a single-occurrence Identical result"

let test_whitespace_is_preserved () =
  let path = create_db () in
  let db = Sqlite3.db_open path in
  let src_a = write_source [ "  let f x ="; "    x + 1  " ] in
  let src_b = write_source [ "let f x ="; "x + 1" ] in
  let ma = insert_module db src_a and mb = insert_module db src_b in
  insert_function db ~module_id:ma ~name:"dup" ~line_start:1 ~line_end:2 ;
  insert_function db ~module_id:mb ~name:"dup" ~line_start:1 ~line_end:2 ;
  match C.compare_bodies db ~project_root:"" "dup" with
  | C.Differs groups -> check int "two exact bodies" 2 (List.length groups)
  | C.Not_found -> fail "expected Differs, got Not_found"
  | C.Identical _ -> fail "language-independent whitespace folding is not a proof"

let test_digest_collision_is_not_identity () =
  let path = create_db () in
  let db = Sqlite3.db_open path in
  let src_a = write_source [ "let g x = x + 1" ] in
  let src_b = write_source [ "let g x = x - 1" ] in
  let ma = insert_module db src_a and mb = insert_module db src_b in
  insert_function db ~module_id:ma ~name:"g" ~line_start:1 ~line_end:1 ;
  insert_function db ~module_id:mb ~name:"g" ~line_start:1 ~line_end:1 ;
  match
    C.compare_bodies_with_digest
      ~digest_of_body:(fun _ -> "forced-collision")
      db
      ~project_root:""
      "g"
  with
  | C.Differs groups -> check int "bytes split collision" 2 (List.length groups)
  | _ -> fail "equal digests over unequal canonical bytes must differ"

let test_differing_bodies () =
  let path = create_db () in
  let db = Sqlite3.db_open path in
  let src_a = write_source [ "let g x = x + 1" ] in
  let src_b = write_source [ "let g x = x - 1" ] in
  let ma = insert_module db src_a and mb = insert_module db src_b in
  insert_function db ~module_id:ma ~name:"g" ~line_start:1 ~line_end:1 ;
  insert_function db ~module_id:mb ~name:"g" ~line_start:1 ~line_end:1 ;
  match C.compare_bodies db ~project_root:"" "g" with
  | C.Differs groups -> check int "two distinct bodies" 2 (List.length groups)
  | _ -> fail "expected Differs for two genuinely different bodies"

(** The trap a naive consumer falls into: two occurrences whose body could not be read (file
    missing) both normalise to "" and therefore hash identically — [compare_bodies] reports
    Identical, which is technically true of the EMPTY STRINGS but is not evidence the two
    functions are duplicates. A CLI consumer must special-case an empty body rather than report
    this as a proven duplicate. *)
let test_empty_bodies_are_identical_but_not_evidence () =
  let path = create_db () in
  let db = Sqlite3.db_open path in
  (* Neither module path exists on disk: read_lines returns [] for a missing file. *)
  let ma = insert_module db "/nonexistent/a.ml" and mb = insert_module db "/nonexistent/b.ml" in
  insert_function db ~module_id:ma ~name:"ghost" ~line_start:1 ~line_end:5 ;
  insert_function db ~module_id:mb ~name:"ghost" ~line_start:1 ~line_end:5 ;
  match C.compare_bodies db ~project_root:"" "ghost" with
  | C.Identical occs ->
      check int "two occurrences" 2 (List.length occs) ;
      List.iter (fun (o : C.occurrence) -> check string "unreadable body is empty" "" o.body) occs
  | _ -> fail "two equally-unreadable occurrences must still hash identically (Identical)"

(* ── test suite ──────────────────────────────────────────────────────────── *)

let () =
  run "arch_index_compare"
    [ ( "compare_bodies",
        [ test_case "not_found" `Quick test_not_found;
          test_case "single_occurrence_is_identical" `Quick test_single_occurrence_is_identical;
          test_case "whitespace_is_preserved" `Quick test_whitespace_is_preserved;
          test_case "digest_collision_is_not_identity" `Quick test_digest_collision_is_not_identity;
          test_case "differing_bodies" `Quick test_differing_bodies;
          test_case "empty_bodies_are_identical_but_not_evidence" `Quick
            test_empty_bodies_are_identical_but_not_evidence
        ] )
    ]
