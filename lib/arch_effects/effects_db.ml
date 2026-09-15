open Extractor_intf

exception Db_error of string

let db_error db what rc =
  raise (Db_error (Printf.sprintf "%s: %s (%s)" what (Sqlite3.errmsg db) (Sqlite3.Rc.to_string rc)))
let exec db what sql = match Sqlite3.exec db sql with Sqlite3.Rc.OK -> () | rc -> db_error db what rc
let bind db what st i data = match Sqlite3.bind st i data with Sqlite3.Rc.OK -> () | rc -> db_error db what rc
let text db st i s = bind db "bind text" st i (Sqlite3.Data.TEXT s)
let int db st i n = bind db "bind integer" st i (Sqlite3.Data.INT (Int64.of_int n))
let opt db st i = function None -> bind db "bind NULL" st i Sqlite3.Data.NULL | Some s -> text db st i s
let statement db sql f =
  let st = try Sqlite3.prepare db sql with Sqlite3.Error s -> raise (Db_error s) in
  Fun.protect ~finally:(fun () -> ignore (Sqlite3.finalize st)) (fun () -> f st)

let strip_comments sql =
  String.split_on_char '\n' sql |> List.map (fun line ->
    let quoted = ref false and stopped = ref false and b = Buffer.create (String.length line) in
    String.iteri (fun i c -> if not !stopped then
      if c = '\'' then (quoted := not !quoted; Buffer.add_char b c)
      else if not !quoted && c = '-' && i + 1 < String.length line && line.[i+1] = '-'
      then stopped := true else Buffer.add_char b c) line; Buffer.contents b)
  |> String.concat "\n"
let split_sql sql = strip_comments sql |> String.split_on_char ';' |> List.map String.trim |> List.filter ((<>) "")
let read_file path = let ic = open_in_bin path in Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () -> really_input_string ic (in_channel_length ic))

let migrate ~db_path ~migration_sql_path =
  if not (Sys.file_exists migration_sql_path) then Error ("migration SQL not found: " ^ migration_sql_path)
  else let db = Sqlite3.db_open db_path in
    Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> try
      exec db "begin migration" "BEGIN IMMEDIATE";
      (try List.iter (exec db "apply migration") (split_sql (read_file migration_sql_path)); exec db "commit migration" "COMMIT"; Ok ()
       with exn -> ignore (Sqlite3.exec db "ROLLBACK"); raise exn)
    with Db_error s | Sys_error s | Failure s -> Error s)

let columns db table = statement db ("PRAGMA table_info(" ^ table ^ ")") (fun st ->
  let xs = ref [] in let rec loop () = match Sqlite3.step st with
    | Sqlite3.Rc.ROW -> (match Sqlite3.column st 1 with Sqlite3.Data.TEXT s -> xs := s :: !xs | _ -> raise (Db_error "malformed table metadata")); loop ()
    | Sqlite3.Rc.DONE -> !xs | rc -> db_error db ("inspect " ^ table) rc in loop ())
let has xs x = List.mem x xs
type schema = Main | Alternative | Flat
let detect db =
  let f = columns db "functions" in
  if f = [] then Flat else if has f "module_id" then
    let m = columns db "modules" in
    if has f "id" && has f "name" && has m "id" && has m "path" then Main
    else raise (Db_error "malformed main schema: expected functions(id,module_id,name) and modules(id,path)")
  else if has f "id" then
    if has f "name" && has f "file_path" then Alternative
    else raise (Db_error "malformed alternative schema: expected functions(id,name,file_path)")
  else Flat

let normalize path =
  let absolute = not (Filename.is_relative path) in
  let rec fold acc = function
    | [] -> List.rev acc | (""|".")::tl -> fold acc tl
    | ".."::tl -> (match acc with
        | parent :: rest when parent <> ".." -> fold rest tl
        | _ -> if absolute then fold acc tl else fold (".." :: acc) tl)
    | x::tl -> fold (x::acc) tl in
  let body = String.concat "/" (fold [] (String.split_on_char '/' path)) in
  if absolute then "/" ^ body else if body = "" then "." else body

let ids db sql bind_values = statement db sql (fun st ->
  bind_values st; let found = ref [] in let rec loop () = match Sqlite3.step st with
    | Sqlite3.Rc.ROW -> (match Sqlite3.column st 0 with Sqlite3.Data.INT n -> found := Int64.to_int n :: !found | _ -> raise (Db_error "non-integer function id")); loop ()
    | Sqlite3.Rc.DONE -> List.rev !found | rc -> db_error db "resolve association" rc in loop ())
let ids_at_normalized_path db sql name wanted = statement db sql (fun st ->
  text db st 1 name; let found = ref [] in let rec loop () = match Sqlite3.step st with
    | Sqlite3.Rc.ROW ->
      let id = match Sqlite3.column st 0 with Sqlite3.Data.INT n -> Int64.to_int n | _ -> raise (Db_error "non-integer function id") in
      let path = match Sqlite3.column st 1 with Sqlite3.Data.TEXT p -> p | _ -> raise (Db_error "non-text function path") in
      if normalize path = normalize wanted then found := id :: !found; loop ()
    | Sqlite3.Rc.DONE -> List.rev !found | rc -> db_error db "resolve path association" rc in loop ())
let association db schema r =
  let found = match schema, r.er_file_path with
    | Flat, _ -> []
    | Main, Some p -> ids_at_normalized_path db "SELECT f.id,m.path FROM functions f JOIN modules m ON m.id=f.module_id WHERE f.name=?1" r.er_function_name p
    | Alternative, Some p -> ids_at_normalized_path db "SELECT id,file_path FROM functions WHERE name=?1" r.er_function_name p
    | Main, None -> ids db "SELECT f.id FROM functions f JOIN modules m ON m.id=f.module_id WHERE f.name=?1" (fun st -> text db st 1 r.er_function_name)
    | Alternative, None -> ids db "SELECT id FROM functions WHERE name=?1" (fun st -> text db st 1 r.er_function_name) in
  match found with [id] -> Some id | xs ->
    if schema <> Flat then Printf.eprintf "arch-effects-load: %s function %s%s; storing NULL association\n%!"
      (if xs=[] then "unmatched" else "ambiguous") r.er_function_name
      (match r.er_file_path with None -> "" | Some p -> " at " ^ p); None

let prepare db =
  exec db "create effects table" "CREATE TABLE IF NOT EXISTS function_effects(id INTEGER PRIMARY KEY AUTOINCREMENT,function_id INTEGER,function_name TEXT NOT NULL,file_path TEXT,value_kind_id INTEGER,value_kind TEXT NOT NULL,target TEXT,is_direct BOOLEAN NOT NULL DEFAULT 1,soundness TEXT NOT NULL DEFAULT 'candidate',producer TEXT,created_at TEXT DEFAULT CURRENT_TIMESTAMP)";
  exec db "create name index" "CREATE INDEX IF NOT EXISTS idx_fn_effects_fname ON function_effects(function_name)";
  exec db "create kind index" "CREATE INDEX IF NOT EXISTS idx_fn_effects_kind ON function_effects(value_kind)";
  exec db "replace obsolete identity index" "DROP INDEX IF EXISTS fn_effects_identity";
  exec db "create complete identity index" "CREATE UNIQUE INDEX fn_effects_identity ON function_effects(function_name,COALESCE(file_path,''),file_path IS NULL,value_kind,COALESCE(target,''),target IS NULL,COALESCE(producer,''),producer IS NULL,is_direct,soundness)"

let write_effects ~db_path records =
  if not (Sys.file_exists db_path) then Error ("database not found: " ^ db_path) else
  let db = Sqlite3.db_open db_path in Fun.protect ~finally:(fun () -> ignore (Sqlite3.db_close db)) (fun () -> try
    exec db "begin effects batch" "BEGIN IMMEDIATE";
    (try let schema = detect db in prepare db; let written = ref 0 and duplicates = ref 0 in
      List.iter (fun r ->
        let fnid = association db schema r and kind = value_kind_to_string r.er_value_kind and sound = soundness_to_string r.er_soundness in
        let old = statement db "SELECT id,function_id FROM function_effects WHERE function_name=?1 AND file_path IS ?2 AND value_kind=?3 AND target IS ?4 AND producer IS ?5 AND is_direct=1 AND soundness=?6" (fun st ->
          text db st 1 r.er_function_name; opt db st 2 r.er_file_path; text db st 3 kind; opt db st 4 r.er_target; text db st 5 r.er_producer; text db st 6 sound;
          match Sqlite3.step st with Sqlite3.Rc.DONE -> None | Sqlite3.Rc.ROW ->
            let id = match Sqlite3.column st 0 with Sqlite3.Data.INT n -> Int64.to_int n | _ -> raise (Db_error "non-integer effect id") in
            let assoc = match Sqlite3.column st 1 with Sqlite3.Data.NULL -> None | Sqlite3.Data.INT n -> Some (Int64.to_int n) | _ -> raise (Db_error "non-integer function id") in
            (match Sqlite3.step st with Sqlite3.Rc.DONE -> () | Sqlite3.Rc.ROW -> raise (Db_error "duplicate complete payloads prevent lossless migration") | rc -> db_error db "check duplicate" rc); Some(id,assoc)
          | rc -> db_error db "find effect" rc) in
        match old with
        | Some (_, assoc) when assoc = fnid -> incr duplicates
        | Some (id, _) -> statement db "UPDATE function_effects SET function_id=?1 WHERE id=?2" (fun st -> (match fnid with None -> bind db "bind NULL" st 1 Sqlite3.Data.NULL | Some n -> int db st 1 n); int db st 2 id; match Sqlite3.step st with Sqlite3.Rc.DONE when Sqlite3.changes db=1 -> () | Sqlite3.Rc.DONE -> raise (Db_error "association repair changed no row") | rc -> db_error db "repair association" rc); incr written
        | None -> statement db "INSERT INTO function_effects(function_id,function_name,file_path,value_kind,target,is_direct,soundness,producer) VALUES(?1,?2,?3,?4,?5,1,?6,?7)" (fun st ->
            (match fnid with None -> bind db "bind NULL" st 1 Sqlite3.Data.NULL | Some n -> int db st 1 n); text db st 2 r.er_function_name; opt db st 3 r.er_file_path; text db st 4 kind; opt db st 5 r.er_target; text db st 6 sound; text db st 7 r.er_producer;
            match Sqlite3.step st with Sqlite3.Rc.DONE when Sqlite3.changes db=1 -> () | Sqlite3.Rc.DONE -> raise (Db_error "effect insert changed no row") | rc -> db_error db "insert effect" rc); incr written) records;
      exec db "commit effects batch" "COMMIT"; Ok(!written,!duplicates)
    with exn -> ignore (Sqlite3.exec db "ROLLBACK"); raise exn)
  with Db_error s | Sqlite3.Error s | Failure s -> Error s)
