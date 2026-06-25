(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Main orchestrator for the LSP-based arch_index extraction pipeline. *)

(* -------------------------------------------------------------------------- *)
(* SQLite helpers                                                              *)
(* -------------------------------------------------------------------------- *)

let schema_sql =
  {|
CREATE TABLE IF NOT EXISTS comment_db_meta (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS functions (
  id INTEGER PRIMARY KEY,
  name TEXT NOT NULL,
  file_path TEXT NOT NULL,
  line_start INTEGER NOT NULL DEFAULT 0,
  line_end INTEGER NOT NULL DEFAULT 0,
  exported INTEGER NOT NULL DEFAULT 0,
  signature TEXT,
  summary TEXT,
  comment_quality_score INTEGER,
  has_pre INTEGER NOT NULL DEFAULT 0,
  has_post INTEGER NOT NULL DEFAULT 0,
  has_violators INTEGER NOT NULL DEFAULT 0,
  has_violates INTEGER NOT NULL DEFAULT 0,
  violators_raw TEXT,
  violates_raw TEXT,
  tests_raw TEXT,
  quint_raw TEXT
);
CREATE TABLE IF NOT EXISTS calls (
  id INTEGER PRIMARY KEY,
  caller_name TEXT NOT NULL,
  caller_file TEXT NOT NULL,
  callee_name TEXT NOT NULL,
  callee_file TEXT,
  call_site TEXT
);
|}

let exec_exn db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc ->
      failwith
        (Printf.sprintf "SQLite error %s for: %s" (Sqlite3.Rc.to_string rc) sql)

let bind_text stmt pos = function
  | None -> ignore (Sqlite3.bind stmt pos Sqlite3.Data.NULL)
  | Some s -> ignore (Sqlite3.bind stmt pos (Sqlite3.Data.TEXT s))

let bind_int stmt pos n =
  ignore (Sqlite3.bind stmt pos (Sqlite3.Data.INT (Int64.of_int n)))

let bind_bool stmt pos b = bind_int stmt pos (if b then 1 else 0)

(* -------------------------------------------------------------------------- *)
(* Write functions and calls to SQLite                                         *)
(* -------------------------------------------------------------------------- *)

let write_functions db fn_rows =
  let stmt =
    Sqlite3.prepare
      db
      "INSERT INTO functions (name, file_path, line_start, line_end, exported, \
       signature, summary, comment_quality_score, has_pre, has_post, \
       has_violators, has_violates, violators_raw, violates_raw, tests_raw, \
       quint_raw) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)"
  in
  List.iter
    (fun (row : Lsp_extractor.fn_row) ->
      (* Extract doc comment and parse it *)
      let raw_comment =
        Doc_extractor.extract_comment
          ~file_path:row.file_path
          ~line_start:row.line_start
      in
      let parsed =
        match raw_comment with
        | None ->
            Comment_parser.
              {
                summary = None;
                pre = Absent;
                post = Absent;
                violators = Absent;
                violates = Absent;
                tests = Absent;
                quint = Absent;
                score = None;
              }
        | Some raw -> Comment_parser.parse raw
      in
      let score = parsed.score in
      let summary = parsed.summary in
      let has_pre =
        match parsed.pre with Comment_parser.Present _ -> true | _ -> false
      in
      let has_post =
        match parsed.post with Comment_parser.Present _ -> true | _ -> false
      in
      let has_violators =
        match parsed.violators with
        | Comment_parser.Present _ | Comment_parser.Present_none -> true
        | _ -> false
      in
      let has_violates =
        match parsed.violates with
        | Comment_parser.Present _ | Comment_parser.Present_none -> true
        | _ -> false
      in
      let violators_raw =
        match parsed.violators with
        | Comment_parser.Present s -> Comment_parser.parse_violators_json s
        | _ -> None
      in
      let violates_raw =
        match parsed.violates with
        | Comment_parser.Present s -> Comment_parser.parse_violators_json s
        | _ -> None
      in
      let tests_raw =
        match parsed.tests with Comment_parser.Present s -> Some s | _ -> None
      in
      let quint_raw =
        match parsed.quint with Comment_parser.Present s -> Some s | _ -> None
      in
      ignore (Sqlite3.reset stmt) ;
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT row.name)) ;
      ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT row.file_path)) ;
      bind_int stmt 3 row.line_start ;
      bind_int stmt 4 row.line_end ;
      bind_bool stmt 5 row.exported ;
      bind_text stmt 6 row.signature ;
      bind_text stmt 7 summary ;
      (match score with
      | None -> ignore (Sqlite3.bind stmt 8 Sqlite3.Data.NULL)
      | Some s -> bind_int stmt 8 s) ;
      bind_bool stmt 9 has_pre ;
      bind_bool stmt 10 has_post ;
      bind_bool stmt 11 has_violators ;
      bind_bool stmt 12 has_violates ;
      bind_text stmt 13 violators_raw ;
      bind_text stmt 14 violates_raw ;
      bind_text stmt 15 tests_raw ;
      bind_text stmt 16 quint_raw ;
      ignore (Sqlite3.step stmt))
    fn_rows ;
  ignore (Sqlite3.finalize stmt)

let write_calls db call_rows =
  let stmt =
    Sqlite3.prepare
      db
      "INSERT INTO calls (caller_name, caller_file, callee_name, callee_file, \
       call_site) VALUES (?, ?, ?, ?, ?)"
  in
  List.iter
    (fun (row : Call_graph_extractor.call_row) ->
      ignore (Sqlite3.reset stmt) ;
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT row.caller_name)) ;
      ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT row.caller_file)) ;
      ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT row.callee_name)) ;
      bind_text stmt 4 row.callee_file ;
      ignore (Sqlite3.bind stmt 5 (Sqlite3.Data.TEXT row.call_site)) ;
      ignore (Sqlite3.step stmt))
    call_rows ;
  ignore (Sqlite3.finalize stmt)

let set_meta db key value =
  let stmt =
    Sqlite3.prepare
      db
      "INSERT OR REPLACE INTO comment_db_meta (key, value) VALUES (?, ?)"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT key)) ;
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT value)) ;
  ignore (Sqlite3.step stmt) ;
  ignore (Sqlite3.finalize stmt)

(* -------------------------------------------------------------------------- *)
(* Timeout helper                                                              *)
(* -------------------------------------------------------------------------- *)

let default_timeout_s = 30.0

let get_timeout_s () =
  match Sys.getenv_opt "EPURE_ARCH_INDEX_TIMEOUT_S" with
  | None -> default_timeout_s
  | Some s -> ( try float_of_string s with Failure _ -> default_timeout_s)

(* -------------------------------------------------------------------------- *)
(* Main run function                                                           *)
(* -------------------------------------------------------------------------- *)

let run ~sw ~env ~project_dir ~language ~output ?(no_enrich = false)
    ?(verbose = false) () =
  let timeout_s = get_timeout_s () in
  let registry = Language_registry.default () in
  (* Step 1: Detect language if "auto" *)
  let language =
    if language = "auto" then
      match Language_registry.detect_language ~project_dir with
      | Some lang -> lang
      | None -> "ocaml" (* default fallback *)
    else language
  in
  if verbose then
    Arch_io.printf "arch_index_lsp: language=%s\n%!" language ;
  (* Step 2: Lookup LSP server — degrade gracefully if not found *)
  let cfg_opt =
    match Language_registry.lookup registry ~language ~project_dir with
    | Ok cfg -> Some cfg
    | Error msg ->
        if verbose then
          Arch_io.eprintf
            "arch_index_lsp: LSP lookup failed: %s\n%!"
            msg ;
        None
  in
  (* Temporary output path *)
  let tmp_output = output ^ ".tmp" in
  (* Step 3-7: Run pipeline with timeout *)
  (* Mutable refs capture partial results so a timeout during call extraction
     still preserves the already-collected function rows. *)
  let fn_rows_ref   = ref [] in
  let call_rows_ref = ref [] in
  (match cfg_opt with
   | None -> ()
   | Some cfg ->
     (try
        Eio.Time.with_timeout_exn (Eio.Stdenv.clock env) timeout_s (fun () ->
            match
              Lsp_client.start
                ~sw
                ~env
                ~command:cfg.command
                ~args:cfg.args
                ~project_dir
                ?init_options:cfg.init_options
                ()
            with
            | Error msg ->
                if verbose then
                  Arch_io.eprintf "arch_index_lsp: LSP start failed: %s\n%!" msg
            | Ok client ->
                if verbose then
                  Arch_io.printf "arch_index_lsp: extracting symbols...\n%!" ;
                let fn_rows =
                  Lsp_extractor.extract_symbols client ~project_dir ~language
                in
                fn_rows_ref := fn_rows ;
                if verbose then
                  Arch_io.printf
                    "arch_index_lsp: found %d functions\n%!"
                    (List.length fn_rows) ;
                let call_rows =
                  Call_graph_extractor.extract_calls client ~project_dir fn_rows
                in
                call_rows_ref := call_rows ;
                if verbose then
                  Arch_io.printf
                    "arch_index_lsp: found %d calls\n%!"
                    (List.length call_rows) ;
                Lsp_client.shutdown client)
      with
      | Eio.Time.Timeout ->
          if verbose then
            Arch_io.eprintf
              "arch_index_lsp: timeout after %.0fs — using partial results \
               (%d functions, %d calls)\n%!"
              timeout_s
              (List.length !fn_rows_ref)
              (List.length !call_rows_ref)
      | exn ->
          if verbose then
            Arch_io.eprintf
              "arch_index_lsp: unexpected error: %s\n%!"
              (Printexc.to_string exn))) ;
  let fn_rows, call_rows = !fn_rows_ref, !call_rows_ref in
  (* Step 8: Write SQLite DB atomically *)
  (try Sys.remove tmp_output with _ -> ()) ;
  let db = Sqlite3.db_open tmp_output in
  ignore (Sqlite3.exec db "PRAGMA journal_mode = WAL") ;
  (try
     exec_exn db schema_sql ;
     exec_exn db "BEGIN TRANSACTION" ;
     write_functions db fn_rows ;
     write_calls db call_rows ;
     exec_exn db "COMMIT" ;
     set_meta db "schema_version" "1" ;
     set_meta db "language" language
   with exn ->
     ignore (Sqlite3.db_close db) ;
     (try Sys.remove tmp_output with _ -> ()) ;
     raise exn) ;
  ignore (Sqlite3.db_close db) ;
  (* Atomic rename *)
  Sys.rename tmp_output output ;
  if verbose then
    Arch_io.printf "arch_index_lsp: wrote %s\n%!" output ;
  (* Step 7: Enrichment (optional) *)
  if not no_enrich then begin
    let enrich_result =
      match language with
      | "ocaml" -> Ocaml_enricher.enrich ~project_dir ~db_path:output
      | "typescript" -> Ts_enricher.enrich ~sw ~env ~project_dir ~db_path:output
      | _ -> Ok ()
    in
    match enrich_result with
    | Ok () -> ()
    | Error msg ->
        if verbose then
          Arch_io.eprintf
            "arch_index_lsp: enricher warning: %s\n%!"
            msg
  end ;
  Ok ()
