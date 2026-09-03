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
  call_site TEXT,
  kind TEXT
);
|}

(* Every edge this backend produces is MAY_ENUMERATED, and the column exists so that it can say
   so. LSP callHierarchy answers "who does this function call", which pins the CALLEE but says
   nothing about whether the call runs on every execution — there is no CFG here and no
   post-dominance, so the dominance half of MUST is simply not computed.

   Leaving the column out was not neutral. `Arch_db.kind_sql` reads a missing column as the
   literal 'MUST' (COALESCE(kind,'MUST') on a kinded index, `'MUST'` on an unkinded one), so
   every conditional Go/Rust/TypeScript call was entering the graph as must-reach ground truth
   and `arch-query reaches` was printing "PATH EXISTS (must-reach)" over it.

   This does NOT earn `callgraph_contract = v1`, and the flag stays unset on purpose: the
   contract also requires that unknowable targets be recorded as MAY_TOP, and callHierarchy
   does not report the call sites it failed to resolve — interface dispatch, trait objects,
   function values. The ⊤ frontier is therefore unknown rather than empty, so `unreachable` and
   `escapes` must keep refusing on this schema. Downgrading MUST to MAY_ENUMERATED removes a
   false claim; it does not manufacture a sound index. *)
let lsp_edge_kind = "MAY_ENUMERATED"

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
       call_site, kind) VALUES (?, ?, ?, ?, ?, ?)"
  in
  List.iter
    (fun (row : Call_graph_extractor.call_row) ->
      ignore (Sqlite3.reset stmt) ;
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT row.caller_name)) ;
      ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT row.caller_file)) ;
      ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT row.callee_name)) ;
      bind_text stmt 4 row.callee_file ;
      ignore (Sqlite3.bind stmt 5 (Sqlite3.Data.TEXT row.call_site)) ;
      ignore (Sqlite3.bind stmt 6 (Sqlite3.Data.TEXT lsp_edge_kind)) ;
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
                (* A FRACTION of the pipeline timeout, never a constant: a fixed
                   wait longer than [timeout_s] would spend the entire run
                   waiting to start and report "0 functions, 0 calls" — the
                   readiness fix causing the very emptiness it exists to
                   prevent. Half leaves the other half for the work itself. *)
                ~ready_timeout:(timeout_s /. 2.)
                ~ready_grace:(Float.min 5.0 (timeout_s /. 6.))
                ()
            with
            | Error msg ->
                if verbose then
                  Arch_io.eprintf "arch_index_lsp: LSP start failed: %s\n%!" msg
            | Ok client ->
                let readiness = Lsp_client.readiness client in
                if verbose then
                  Arch_io.printf
                    "arch_index_lsp: server readiness: %s\n%!"
                    (Lsp_client.readiness_to_string readiness) ;
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
                  Call_graph_extractor.extract_calls
                    ~clock:(Eio.Stdenv.clock env)
                    client
                    ~project_dir
                    fn_rows
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
     set_meta db "schema_version" Arch_index_db.current_flat_schema_version ;
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

(* -------------------------------------------------------------------------- *)
(* Multi-language projects                                                    *)
(* -------------------------------------------------------------------------- *)

(* Each language is indexed relative to its own project file's directory, so a
   row says [src/index.ts] where the repository says [tsapp/src/index.ts].
   Re-root them on merge, otherwise two sub-projects with a [main.go] each are
   indistinguishable in the combined index. *)
let sub_prefix ~project_dir ~sub =
  let root = Filename.concat project_dir "" in
  let rlen = String.length root in
  if String.length sub >= rlen && String.sub sub 0 rlen = root then
    let rel = String.sub sub rlen (String.length sub - rlen) in
    if rel = "" then "" else rel ^ "/"
  else if sub = project_dir then ""
  else ""

(** [run_multi ~languages] indexes a project that holds several languages into a
    single database.

    [run] drives one language server and writes the database itself, so a
    polyglot repository could only ever be indexed one language at a time, each
    run replacing the previous file.  Rather than restructure that, each
    language is indexed into its own temporary database and the rows are merged
    afterwards -- which the schema makes safe, since [calls] refers to functions
    by name and file rather than by row id, so nothing has to be renumbered.

    The [language] meta key records every language that contributed, comma
    separated, instead of a single one. *)
let run_multi ~sw ~env ~project_dir ~languages ~output ?(no_enrich = false)
    ?(verbose = false) () =
  let tmp_dbs =
    List.filter_map
      (fun (language, project_dir_of_lang) ->
        let tmp = Filename.temp_file "arch_index_lang_" ".db" in
        (try Sys.remove tmp with _ -> ()) ;
        match
          run
            ~sw
            ~env
            ~project_dir:project_dir_of_lang
            ~language
            ~output:tmp
            ~no_enrich
            ~verbose
            ()
        with
        | Ok () -> Some (language, tmp, sub_prefix ~project_dir ~sub:project_dir_of_lang)
        | Error msg ->
            if verbose then
              Arch_io.eprintf
                "arch_index_lsp: %s failed: %s\n%!"
                language
                msg ;
            (try Sys.remove tmp with _ -> ()) ;
            None
        | exception exn ->
            if verbose then
              Arch_io.eprintf
                "arch_index_lsp: %s raised: %s\n%!"
                language
                (Printexc.to_string exn) ;
            (try Sys.remove tmp with _ -> ()) ;
            None)
      languages
  in
  match tmp_dbs with
  | [] -> Error "run_multi: no language could be indexed"
  | _ :: _ ->
      let merged = Filename.temp_file "arch_index_merged_" ".db" in
      (try Sys.remove merged with _ -> ()) ;
      let db = Sqlite3.db_open merged in
      ignore (Sqlite3.exec db "PRAGMA journal_mode = WAL") ;
      let ok =
        try
          exec_exn db schema_sql ;
          List.iter
            (fun (_, path, prefix) ->
              let q = Printf.sprintf "'%s' || " (String.escaped prefix) in
              let q = if prefix = "" then "" else q in
              exec_exn db (Printf.sprintf "ATTACH DATABASE '%s' AS src" path) ;
              exec_exn
                db
                (Printf.sprintf
                   "INSERT INTO functions (name, file_path, line_start, \
                    line_end, exported, signature, summary) SELECT name, %sfile_path, \
                    line_start, line_end, exported, signature, summary FROM \
                    src.functions"
                   q) ;
              exec_exn
                db
                (Printf.sprintf
                   (* `kind` is carried through rather than re-defaulted: a merge that dropped
                      it would silently re-promote every edge to MUST (see [lsp_edge_kind]),
                      which is exactly the bug this column exists to prevent — and it would
                      only show up on polyglot repositories. *)
                   "INSERT INTO calls (caller_name, caller_file, callee_name, \
                    callee_file, call_site, kind) SELECT caller_name, %scaller_file, \
                    callee_name, %scallee_file, %scall_site, kind FROM src.calls"
                   q
                   q
                   q) ;
              exec_exn db "DETACH DATABASE src")
            tmp_dbs ;
          set_meta db "schema_version" Arch_index_db.current_flat_schema_version ;
          set_meta
            db
            "language"
            (String.concat "," (List.map (fun (l, _, _) -> l) tmp_dbs)) ;
          true
        with exn ->
          if verbose then
            Arch_io.eprintf
              "arch_index_lsp: merge failed: %s\n%!"
              (Printexc.to_string exn) ;
          false
      in
      ignore (Sqlite3.db_close db) ;
      List.iter (fun (_, p, _) -> try Sys.remove p with _ -> ()) tmp_dbs ;
      if ok then begin
        (try Sys.remove output with _ -> ()) ;
        Sys.rename merged output ;
        if verbose then
          Arch_io.printf
            "arch_index_lsp: wrote %s (%s)\n%!"
            output
            (String.concat ", " (List.map (fun (l, _, _) -> l) tmp_dbs)) ;
        Ok ()
      end
      else begin
        (try Sys.remove merged with _ -> ()) ;
        Error "run_multi: merge failed"
      end
