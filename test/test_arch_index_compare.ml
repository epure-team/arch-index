(* Tests for Arch_index.Arch_index_compare (specs/arch-health-queries.md US-3).
   First coverage for this module (epure lineage, previously untested here). *)

module Compare = Arch_index.Arch_index_compare

let write_file path contents =
  let oc = open_out path in
  output_string oc contents;
  close_out oc

(* tmpdir project with a main-schema-ish DB (modules + functions with ranges). *)
let fixture () =
  let root = Filename.temp_file "archcmp" "" in
  Sys.remove root;
  Unix.mkdir root 0o700;
  write_file (Filename.concat root "a.ml")
    "let dup_fn x =\n  x + 1\n\nlet solo x = x\n";
  write_file (Filename.concat root "b.ml")
    "let dup_fn x =\n    x + 1\n";
  (* same body modulo indentation -> identical after normalization *)
  write_file (Filename.concat root "c.ml") "let dup_fn x =\n  x + 2\n";
  let db = Sqlite3.db_open ":memory:" in
  List.iter
    (fun s -> ignore (Sqlite3.exec db s))
    [
      "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT)";
      "INSERT INTO modules VALUES(1,'a.ml'),(2,'b.ml'),(3,'c.ml')";
      "CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT, \
       line_start INTEGER, line_end INTEGER)";
      "INSERT INTO functions VALUES(1,1,'dup_fn',1,2),(2,2,'dup_fn',1,2),(3,3,'dup_fn',1,2)";
      "INSERT INTO functions VALUES(4,1,'solo',4,4)";
      "INSERT INTO functions VALUES(5,1,'ghost',1,2)";
      "UPDATE functions SET module_id=99 WHERE name='ghost'";
      (* ghost points at a module id with no row -> excluded by the JOIN *)
      "INSERT INTO modules VALUES(99,'missing.ml')";
    ];
  (root, db)

let test_differs_and_sorted () =
  let root, db = fixture () in
  match Compare.compare_bodies db ~project_root:root "dup_fn" with
  | Compare.Differs groups ->
      Alcotest.(check int) "two distinct bodies" 2 (List.length groups);
      let sizes = List.map (fun (_, occs) -> List.length occs) groups in
      Alcotest.(check int) "three occurrences total" 3 (List.fold_left ( + ) 0 sizes)
  | _ -> Alcotest.fail "expected Differs"

let test_identical_normalization () =
  let root, db = fixture () in
  (* restrict to a.ml/b.ml copies by renaming c.ml's function *)
  ignore (Sqlite3.exec db "UPDATE functions SET name='other' WHERE module_id=3");
  match Compare.compare_bodies db ~project_root:root "dup_fn" with
  | Compare.Identical occs ->
      Alcotest.(check int) "both occurrences" 2 (List.length occs);
      let dgs = List.map (fun (o : Compare.occurrence) -> o.digest) occs in
      Alcotest.(check bool) "same digest" true (List.for_all (( = ) (List.hd dgs)) dgs)
  | _ -> Alcotest.fail "expected Identical (indentation-insensitive)"

let test_not_found () =
  let root, db = fixture () in
  Alcotest.(check bool) "not found" true
    (Compare.compare_bodies db ~project_root:root "nope" = Compare.Not_found)

let test_missing_file_empty_body () =
  let root, db = fixture () in
  match Compare.compare_bodies db ~project_root:root "ghost" with
  | Compare.Identical [o] ->
      Alcotest.(check string) "empty body" "" o.body;
      Alcotest.(check string) "path" "missing.ml" o.path
  | _ -> Alcotest.fail "expected single empty-body occurrence"

let () =
  Alcotest.run "arch_index_compare"
    [
      ( "compare_bodies",
        [
          Alcotest.test_case "differs + total occurrences" `Quick test_differs_and_sorted;
          Alcotest.test_case "identical modulo indentation" `Quick test_identical_normalization;
          Alcotest.test_case "not found" `Quick test_not_found;
          Alcotest.test_case "missing file = empty body" `Quick test_missing_file_empty_body;
        ] );
    ]
