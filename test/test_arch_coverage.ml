(* Tests for Arch_coverage (specs/arch-gardening-queries.md US-2). *)

let mk_db () =
  let db = Sqlite3.db_open ":memory:" in
  List.iter
    (fun s -> ignore (Sqlite3.exec db s))
    [
      "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT)";
      "INSERT INTO modules VALUES(1,'src/a.ml'),(2,'src/b.ml')";
      "CREATE TABLE functions(id INTEGER PRIMARY KEY, module_id INTEGER, name TEXT)";
      "INSERT INTO functions VALUES(1,1,'uniq'),(2,1,'dup'),(3,2,'dup')";
      "CREATE TABLE coverage(id INTEGER PRIMARY KEY AUTOINCREMENT, function_id INTEGER, \
       covered_lines INTEGER, total_lines INTEGER, \
       percentage REAL GENERATED ALWAYS AS (CASE WHEN total_lines > 0 THEN (covered_lines * \
       100.0 / total_lines) ELSE 0 END) STORED, \
       recorded_at TEXT, UNIQUE(function_id, recorded_at))";
    ];
  db

let count db =
  let stmt = Sqlite3.prepare db "SELECT count(*) FROM coverage" in
  ignore (Sqlite3.step stmt);
  let n = match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> Int64.to_int n | _ -> -1 in
  ignore (Sqlite3.finalize stmt);
  n

let no_warn _ = ()

let stamp = "2026-07-08T00:00:00Z"

let test_happy_and_idempotent () =
  let db = mk_db () in
  let lines =
    [
      {|{"type":"coverage","function":"uniq","covered_lines":8,"total_lines":10}|};
      {|{"type":"coverage","function":"dup","module":"src/b.ml","covered_lines":1,"total_lines":4}|};
    ]
  in
  (match Arch_coverage.load db ~stamp ~warn:no_warn lines with
  | Ok s ->
      Alcotest.(check int) "written" 2 s.written;
      Alcotest.(check int) "skipped" 0 s.skipped
  | Error e -> Alcotest.fail e);
  (* same stamp re-run → all ignored (FR-008) *)
  (match Arch_coverage.load db ~stamp ~warn:no_warn lines with
  | Ok s ->
      Alcotest.(check int) "rerun written" 0 s.written;
      Alcotest.(check int) "rerun ignored" 2 s.ignored
  | Error e -> Alcotest.fail e);
  Alcotest.(check int) "rows" 2 (count db)

let test_skips () =
  let db = mk_db () in
  let lines =
    [
      {|{"type":"coverage","function":"dup","covered_lines":1,"total_lines":2}|};
      (* ambiguous, no module *)
      {|{"type":"coverage","function":"nope","covered_lines":1,"total_lines":2}|};
      (* unknown *)
      {|{"type":"coverage","function":"uniq","module":"src/zzz.ml","covered_lines":1,"total_lines":2}|};
      (* unknown module *)
    ]
  in
  match Arch_coverage.load db ~stamp ~warn:no_warn lines with
  | Ok s ->
      Alcotest.(check int) "skipped" 3 s.skipped;
      Alcotest.(check int) "written" 0 s.written
  | Error e -> Alcotest.fail e

let test_malformed_rolls_back () =
  let db = mk_db () in
  let lines =
    [
      {|{"type":"coverage","function":"uniq","covered_lines":8,"total_lines":10}|};
      {|{"type":"coverage","function":"uniq","covered_lines":9,"total_lines":3}|};
      (* covered > total → malformed *)
    ]
  in
  (match Arch_coverage.load db ~stamp ~warn:no_warn lines with
  | Error msg -> Alcotest.(check bool) "line cited" true (String.length msg > 0)
  | Ok _ -> Alcotest.fail "expected malformed abort");
  Alcotest.(check int) "rolled back" 0 (count db)

let test_validation () =
  let bad l =
    match Arch_coverage.load (mk_db ()) ~stamp ~warn:no_warn [l] with
    | Error _ -> true
    | Ok _ -> false
  in
  Alcotest.(check bool) "bad json" true (bad "{nope");
  Alcotest.(check bool) "wrong type" true (bad {|{"type":"effect","function":"f","covered_lines":1,"total_lines":2}|});
  Alcotest.(check bool) "negative" true (bad {|{"type":"coverage","function":"f","covered_lines":-1,"total_lines":2}|});
  Alcotest.(check bool) "string int" true (bad {|{"type":"coverage","function":"f","covered_lines":"1","total_lines":2}|});
  (* total=0 is legal (generated pct = 0) *)
  match
    Arch_coverage.load (mk_db ()) ~stamp ~warn:no_warn
      [{|{"type":"coverage","function":"uniq","covered_lines":0,"total_lines":0}|}]
  with
  | Ok s -> Alcotest.(check int) "total=0 written" 1 s.written
  | Error e -> Alcotest.fail e

let test_stamp_validation () =
  Alcotest.(check bool) "valid" true (Arch_coverage.valid_stamp "2026-07-08T12:34:56Z");
  Alcotest.(check bool) "offset rejected" false (Arch_coverage.valid_stamp "2026-07-08T12:34:56+02:00");
  Alcotest.(check bool) "sloppy rejected" false (Arch_coverage.valid_stamp "2026-7-8");
  Alcotest.(check bool) "now_stamp valid" true (Arch_coverage.valid_stamp (Arch_coverage.now_stamp ()));
  (* codex review finding: impossible instants must be rejected, not just shape *)
  Alcotest.(check bool) "impossible month" false (Arch_coverage.valid_stamp "2026-99-99T99:99:99Z");
  Alcotest.(check bool) "hour 24" false (Arch_coverage.valid_stamp "2026-07-08T24:00:00Z")

let () =
  Alcotest.run "arch_coverage"
    [
      ( "load",
        [
          Alcotest.test_case "happy + idempotent rerun" `Quick test_happy_and_idempotent;
          Alcotest.test_case "skips (ambiguous/unknown)" `Quick test_skips;
          Alcotest.test_case "malformed rolls back all" `Quick test_malformed_rolls_back;
          Alcotest.test_case "record validation" `Quick test_validation;
          Alcotest.test_case "stamp validation" `Quick test_stamp_validation;
        ] );
    ]
