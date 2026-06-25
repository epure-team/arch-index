(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** OCaml CMT-based enrichment. Uses arch_index_cmt internals to enrich an
    LSP-populated DB with module/type information. *)

(** [is_available ~project_dir] returns true if CMT files exist in
    _build/default/. *)
let is_available ~project_dir =
  let build_dir = Filename.concat project_dir "_build/default" in
  if not (Sys.file_exists build_dir) then false
  else begin
    let found = ref false in
    let rec scan dir =
      if !found then ()
      else begin
        try
          let entries = Sys.readdir dir in
          Array.iter
            (fun entry ->
              if !found then ()
              else begin
                let path = Filename.concat dir entry in
                if Filename.check_suffix path ".cmt" then found := true
                else if try Sys.is_directory path with _ -> false then scan path
              end)
            entries
        with _ -> ()
      end
    in
    scan build_dir ;
    !found
  end

(** [enrich ~project_dir ~db_path] enriches [db_path] with CMT-derived data.
    Returns [Ok ()] if CMT files absent (silently skips) or on success.
    Returns [Error msg] on CMT processing failure. *)
let enrich ~project_dir ~db_path =
  if not (is_available ~project_dir) then Ok ()
  else begin
    let build_dir = Filename.concat project_dir "_build/default" in
    let all_files = Arch_index_cmt.find_cmt_files build_dir in
    let cmti_files =
      List.filter (fun f -> Filename.check_suffix f ".cmti") all_files
    in
    let sigs =
      Arch_index_cmt.extract_signatures_from_cmti_files ~project_dir cmti_files
    in
    if sigs = [] then Ok ()
    else begin
      (* Open the LSP-populated DB and UPDATE signature column for matching
         rows.  No new rows are inserted; comment_db_meta is never touched.
         All UPDATEs are wrapped in a single transaction for atomicity. *)
      let result =
        try
          let db = Sqlite3.db_open db_path in
          let inner =
            try
              ignore (Sqlite3.exec db "BEGIN IMMEDIATE") ;
              (* Primary UPDATE: match on both name and file_path (relative) *)
              let stmt_exact =
                Sqlite3.prepare
                  db
                  "UPDATE functions SET signature = ?1 WHERE name = ?2 AND \
                   file_path = ?3"
              in
              (* Fallback UPDATE: name + parent-dir/basename LIKE match for
                 null-signature rows when the file_path prefix differs.
                 Uses parent/basename to avoid matching unrelated lib.ml files
                 in different directories. *)
              let stmt_fallback =
                Sqlite3.prepare
                  db
                  "UPDATE functions SET signature = ?1 WHERE name = ?2 AND \
                   file_path LIKE ?3 AND signature IS NULL"
              in
              List.iter
                (fun (src_rel, name, type_str) ->
                  (* Try exact relative-path match first *)
                  ignore (Sqlite3.reset stmt_exact) ;
                  ignore
                    (Sqlite3.bind stmt_exact 1 (Sqlite3.Data.TEXT type_str)) ;
                  ignore (Sqlite3.bind stmt_exact 2 (Sqlite3.Data.TEXT name)) ;
                  ignore (Sqlite3.bind stmt_exact 3 (Sqlite3.Data.TEXT src_rel)) ;
                  match Sqlite3.step stmt_exact with
                  | Sqlite3.Rc.DONE ->
                      if Sqlite3.changes db = 0 then begin
                        (* No exact hit — try parent/basename LIKE match *)
                        let base = Filename.basename src_rel in
                        let dir = Filename.dirname src_rel in
                        let like_pat =
                          if dir = "." then "%" ^ base
                          else "%" ^ Filename.basename dir ^ "/" ^ base
                        in
                        ignore (Sqlite3.reset stmt_fallback) ;
                        ignore
                          (Sqlite3.bind
                             stmt_fallback
                             1
                             (Sqlite3.Data.TEXT type_str)) ;
                        ignore
                          (Sqlite3.bind
                             stmt_fallback
                             2
                             (Sqlite3.Data.TEXT name)) ;
                        ignore
                          (Sqlite3.bind
                             stmt_fallback
                             3
                             (Sqlite3.Data.TEXT like_pat)) ;
                        ignore (Sqlite3.step stmt_fallback)
                      end
                  | _ -> ())
                sigs ;
              ignore (Sqlite3.finalize stmt_exact) ;
              ignore (Sqlite3.finalize stmt_fallback) ;
              ignore (Sqlite3.exec db "COMMIT") ;
              Ok ()
            with exn ->
              (try ignore (Sqlite3.exec db "ROLLBACK") with _ -> ()) ;
              Error (Printexc.to_string exn)
          in
          ignore (Sqlite3.db_close db) ;
          inner
        with exn -> Error (Printexc.to_string exn)
      in
      result
    end
  end
