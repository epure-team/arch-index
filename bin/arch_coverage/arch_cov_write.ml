(** Writing coverage back into the index.

    Split out because it is the only part of arch-coverage that opens the database read-WRITE,
    and because it needs a second Caqti connection: {!Arch_db.open_ro} is read-only by design, so
    that a query tool cannot mutate the index it is reporting on. *)

module C = Caqti_blocking
module Ty = Caqti_type.Std
open Caqti_request.Infix

let exec conn sql =
  let module Db = (val conn : C.CONNECTION) in
  let req = Caqti_request.create ~oneshot:true Ty.unit Ty.unit Caqti_mult.zero (fun _ ->
      Caqti_query.of_string_exn sql)
  in
  match Db.exec req () with
  | Ok () -> ()
  | Error e ->
      prerr_endline ("arch-coverage: " ^ Caqti_error.show e) ;
      exit 2

(** [write ~db_path ~flat per_fn] replaces the coverage rows and returns how many were written.

    REPLACES rather than accumulates: rerunning must not grow the table. *)
let write ~db_path ~flat per_fn =
  let conn =
    match C.connect (Uri.make ~scheme:"sqlite3" ~path:db_path ()) with
    | Ok c -> c
    | Error e ->
        prerr_endline ("arch-coverage: cannot open for writing: " ^ Caqti_error.show e) ;
        exit 2
  in
  let module Db = (val conn : C.CONNECTION) in
  exec conn
    "CREATE TABLE IF NOT EXISTS coverage (id INTEGER PRIMARY KEY AUTOINCREMENT, function_id \
     INTEGER NOT NULL, covered_lines INTEGER NOT NULL DEFAULT 0, total_lines INTEGER NOT NULL \
     DEFAULT 0, recorded_at TEXT DEFAULT CURRENT_TIMESTAMP)" ;
  let n = ref 0 in
  if flat then (
    (* The flat schema has no function ids; store the name in its own table rather than invent
       ids that would join to nothing. *)
    exec conn
      "CREATE TABLE IF NOT EXISTS coverage_by_name (function_name TEXT PRIMARY KEY, covered_lines \
       INTEGER, total_lines INTEGER, recorded_at TEXT DEFAULT CURRENT_TIMESTAMP)" ;
    exec conn "DELETE FROM coverage_by_name" ;
    let ins =
      Ty.(t3 string int int) -->. Ty.unit
      @:- "INSERT INTO coverage_by_name(function_name,covered_lines,total_lines) VALUES(?,?,?)"
    in
    Hashtbl.iter
      (fun _ ((node : Arch_tools.Arch_graph.node), _, total, covered) ->
        match Db.exec ins (node.name, covered, total) with
        | Ok () -> incr n
        | Error e ->
            prerr_endline ("arch-coverage: " ^ Caqti_error.show e) ;
            exit 2)
      per_fn)
  else (
    exec conn "DELETE FROM coverage" ;
    let ins =
      Ty.(t3 int int int) -->. Ty.unit
      @:- "INSERT INTO coverage(function_id,covered_lines,total_lines) VALUES(?,?,?)"
    in
    Hashtbl.iter
      (fun key ((_ : Arch_tools.Arch_graph.node), _, total, covered) ->
        (* Main-schema keys are "#<rowid>". *)
        if String.length key > 1 && key.[0] = '#' then
          match int_of_string_opt (String.sub key 1 (String.length key - 1)) with
          | Some id -> (
              match Db.exec ins (id, covered, total) with
              | Ok () -> incr n
              | Error e ->
                  prerr_endline ("arch-coverage: " ^ Caqti_error.show e) ;
                  exit 2)
          | None -> ())
      per_fn) ;
  !n
