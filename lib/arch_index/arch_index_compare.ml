(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Body comparison for duplicate-function detection.

    Extracts function bodies from source files using the line ranges stored in
    the architecture DB, normalises them, and groups occurrences by content hash
    so callers can determine whether named functions across modules are truly
    identical or merely share a name. *)

(* -------------------------------------------------------------------------- *)
(* Types                                                                      *)
(* -------------------------------------------------------------------------- *)

(** One occurrence of a named function in the index. *)
type occurrence = {
  path : string;  (** Source-relative path, e.g. [src/db/foo_store.ml] *)
  line_start : int;
  line_end : int;
  body : string;  (** Normalised body text *)
  digest : string;  (** Hex MD5 of [body] — used for grouping *)
}

(** Result of comparing all occurrences of a function name. *)
type result =
  | Not_found  (** No function with that name in the DB *)
  | Identical of occurrence list  (** All occurrences have the same body *)
  | Differs of (string * occurrence list) list
      (** [(digest, occurrences)] — at least two distinct bodies *)

(* -------------------------------------------------------------------------- *)
(* Source extraction                                                          *)
(* -------------------------------------------------------------------------- *)

(** Read lines [line_start..line_end] (1-based, inclusive) from [path].
    Returns an empty list when the file cannot be read or the range is out of
    bounds. *)
let read_lines path line_start line_end =
  if not (Sys.file_exists path) then []
  else
    let ic = open_in path in
    let lines = ref [] in
    let lnum = ref 1 in
    (try
       while !lnum <= line_end do
         let line = input_line ic in
         if !lnum >= line_start then lines := line :: !lines ;
         incr lnum
       done
     with End_of_file -> ()) ;
    close_in ic ;
    List.rev !lines

(** Strip leading/trailing whitespace from each line, drop blank lines, and
    rejoin.  This is intentionally lightweight — good enough to paper over
    indentation and trailing-space differences without requiring an external
    formatter process. *)
let normalise lines =
  lines |> List.map String.trim
  |> List.filter (fun s -> s <> "")
  |> String.concat "\n"

(* -------------------------------------------------------------------------- *)
(* DB query                                                                   *)
(* -------------------------------------------------------------------------- *)

let query_sql =
  {|
    SELECT m.path, f.line_start, f.line_end
    FROM   functions f
    JOIN   modules   m ON f.module_id = m.id
    WHERE  f.name = ?
    ORDER  BY m.path
  |}

(** Fetch all (path, line_start, line_end) rows for [fn_name] from [db].
    [project_root] is prepended to make paths absolute for file reading. *)
let fetch_rows db ~project_root fn_name =
  let stmt = Sqlite3.prepare db query_sql in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT fn_name)) ;
  let rows = ref [] in
  while Sqlite3.step stmt = Sqlite3.Rc.ROW do
    let rel_path =
      match Sqlite3.column stmt 0 with Sqlite3.Data.TEXT s -> s | _ -> ""
    in
    let line_start =
      match Sqlite3.column stmt 1 with
      | Sqlite3.Data.INT n -> Int64.to_int n
      | _ -> 0
    in
    let line_end =
      match Sqlite3.column stmt 2 with
      | Sqlite3.Data.INT n -> Int64.to_int n
      | _ -> 0
    in
    let abs_path =
      if project_root = "" then rel_path
      else Filename.concat project_root rel_path
    in
    rows := (abs_path, rel_path, line_start, line_end) :: !rows
  done ;
  ignore (Sqlite3.finalize stmt) ;
  List.rev !rows

(* -------------------------------------------------------------------------- *)
(* Public API                                                                 *)
(* -------------------------------------------------------------------------- *)

(** Compare all occurrences of [fn_name] in the architecture DB.

    @param db      Open SQLite handle to [docs/architecture.db].
    @param project_root  Absolute path to the repository root (prepended to
                         module paths when reading source files).
    @param fn_name  The function name to look up (exact match). *)
let compare_bodies db ~project_root fn_name =
  let rows = fetch_rows db ~project_root fn_name in
  match rows with
  | [] -> Not_found
  | _ ->
      let occurrences =
        List.map
          (fun (abs_path, rel_path, line_start, line_end) ->
            let lines = read_lines abs_path line_start line_end in
            let body = normalise lines in
            let digest = Digest.to_hex (Digest.string body) in
            {path = rel_path; line_start; line_end; body; digest})
          rows
      in
      (* Group by digest *)
      let tbl : (string, occurrence list) Hashtbl.t = Hashtbl.create 4 in
      List.iter
        (fun occ ->
          let existing =
            match Hashtbl.find_opt tbl occ.digest with
            | Some lst -> lst
            | None -> []
          in
          Hashtbl.replace tbl occ.digest (existing @ [occ]))
        occurrences ;
      if Hashtbl.length tbl = 1 then Identical occurrences
      else
        Differs
          (Hashtbl.fold (fun digest occs acc -> (digest, occs) :: acc) tbl [])
