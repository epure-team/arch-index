(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** TypeScript enrichment via bundled ts-morph Node.js shim.

    The shim is embedded at compile time via [ppx_blob].  At runtime the
    enricher writes it to a temp file, invokes [node <shim> <project_dir>],
    reads newline-delimited JSON from stdout, and merges [signature] and
    [exported] fields into the [functions] table of the arch DB.

    Falls back gracefully: returns [Error msg] when Node is unavailable,
    the shim exits non-zero, or the DB update fails — callers are expected
    to log and continue. *)

let shim_content : string = [%blob "ts_shim.js"]

(** [is_available ()] returns true if [node] is on PATH.
    Uses PATH walking — no subprocess is spawned. *)
let is_available () =
  match Sys.getenv_opt "PATH" with
  | None -> false
  | Some path_var ->
      let dirs = String.split_on_char ':' path_var in
      List.exists (fun dir -> Sys.file_exists (Filename.concat dir "node")) dirs

(* Parse a single NDJSON line into name, file_path, type_sig, exported fields. *)
let parse_record line =
  try
    match Yojson.Safe.from_string line with
    | `Assoc fields -> (
        let get_str k =
          match List.assoc_opt k fields with
          | Some (`String s) -> Some s
          | _ -> None
        in
        let get_bool k =
          match List.assoc_opt k fields with Some (`Bool b) -> b | _ -> false
        in
        match (get_str "name", get_str "file_path") with
        | Some name, Some file_path ->
            Some (name, file_path, get_str "type_sig", get_bool "exported")
        | _ -> None)
    | _ -> None
  with _ -> None

(* ts-morph reports absolute paths while the LSP rows store paths relative to
   the project, so an update keyed on the raw path matches nothing -- and an
   UPDATE that matches no row still returns DONE, so the mismatch was silent.
   Strip the project prefix before looking the row up. *)
let relative_to ~project_dir path =
  let prefix = if project_dir = "" then "" else project_dir ^ "/" in
  let plen = String.length prefix in
  if plen > 0 && String.length path >= plen && String.sub path 0 plen = prefix
  then String.sub path plen (String.length path - plen)
  else path

(* Update signature and exported for a function row matching name + file_path. *)
let update_row db name file_path type_sig exported =
  let open Sqlite3 in
  let sql =
    (* The column is [exported] in the schema Runner.run creates, which is the
       only database this enricher ever runs against. *)
    "UPDATE functions SET signature = ?, exported = ? WHERE name = ? AND \
     file_path = ?"
  in
  let stmt = prepare db sql in
  (match type_sig with
  | Some s -> ignore (bind stmt 1 (Data.TEXT s))
  | None -> ignore (bind stmt 1 Data.NULL)) ;
  ignore (bind stmt 2 (Data.INT (if exported then 1L else 0L))) ;
  ignore (bind stmt 3 (Data.TEXT name)) ;
  ignore (bind stmt 4 (Data.TEXT file_path)) ;
  let rc = step stmt in
  ignore (finalize stmt) ;
  match rc with
  | Rc.DONE ->
      if Sqlite3.changes db = 0 then
        Arch_io.warnf
          "ts_enricher: no indexed function %s in %s to enrich"
          name
          file_path
  | _ ->
      Arch_io.warnf
        "ts_enricher: update failed for %s in %s"
        name
        file_path

(** [enrich ~project_dir ~db_path] attempts TypeScript enrichment.

    Writes the bundled shim to a temp file, invokes [node <shim> <project_dir>],
    parses newline-delimited JSON records from stdout, and updates [signature]
    and [exported] in the functions table of [db_path].

    Returns [Error msg] when Node is unavailable, the shim exits non-zero, or
    the DB cannot be opened.  Returns [Ok ()] on success or when the project
    has no TypeScript files to process. *)
let enrich ~sw ~env ~project_dir ~db_path =
  if not (is_available ()) then Error "ts_enricher: node not found on PATH"
  else begin
    (* Write shim to a temp file. *)
    let tmp_shim = Filename.temp_file "ts_shim_" ".js" in
    (try
       let oc = open_out tmp_shim in
       output_string oc shim_content ;
       close_out oc
     with e ->
       Unix.unlink tmp_shim ;
       raise e) ;
    (* Run the shim and collect stdout via Eio process. *)
    let run_result =
      try
        let proc_mgr = Eio.Stdenv.process_mgr env in
        let stdout_r, stdout_w = Eio.Process.pipe ~sw proc_mgr in
        let proc =
          Eio.Process.spawn
            ~sw
            proc_mgr
            ~stdout:(stdout_w :> _ Eio.Flow.sink)
            ["node"; tmp_shim; project_dir]
        in
        Eio.Flow.close stdout_w ;
        let buf = Buffer.create 4096 in
        let reader =
          Eio.Buf_read.of_flow ~max_size:(64 * 1024 * 1024) stdout_r
        in
        (try
           while true do
             Buffer.add_string buf (Eio.Buf_read.line reader) ;
             Buffer.add_char buf '\n'
           done
         with End_of_file -> ()) ;
        Eio.Flow.close stdout_r ;
        match Eio.Process.await proc with
        | `Exited 0 -> Ok (Buffer.contents buf)
        | `Exited n -> Error (Printf.sprintf "ts_shim exited %d" n)
        | `Signaled _ -> Error "ts_shim killed by signal"
      with e -> Error (Printexc.to_string e)
    in
    Unix.unlink tmp_shim ;
    match run_result with
    | Error msg ->
        Arch_io.warnf "ts_enricher: %s — LSP-only enrichment" msg ;
        Error msg
    | Ok ndjson -> (
        (* Open the arch DB and update rows. *)
        match
          try Ok (Sqlite3.db_open db_path)
          with e -> Error (Printexc.to_string e)
        with
        | Error msg -> Error msg
        | Ok db ->
            let lines = String.split_on_char '\n' ndjson in
            List.iter
              (fun line ->
                if String.length line > 0 then
                  match parse_record line with
                  | Some (name, file_path, type_sig, exported) ->
                      update_row
                        db
                        name
                        (relative_to ~project_dir file_path)
                        type_sig
                        exported
                  | None ->
                      Arch_io.warnf
                        "ts_enricher: unparseable record: %s"
                        line)
              lines ;
            ignore (Sqlite3.db_close db) ;
            Ok ())
  end
