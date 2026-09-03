(** NDJSON call-edge stream → ⊤-marked SQLite database (PR-B write side).

    This is the enforcement point for the edge-kind contract: every call edge must
    carry a valid [kind] before [callgraph_contract=v1] is stamped in the DB. *)

(* ── types ──────────────────────────────────────────────────────────────── *)

type func_rec = {
  f_name     : string;
  f_file     : string option;
  f_exported : bool;
}

type call_rec = {
  c_caller      : string;
  c_caller_file : string option;
  c_callee      : string;
  c_callee_file : string option;
  c_site        : string option;
  c_kind        : string;
}

type load_result = {
  n_functions : int;
  n_calls     : int;
  n_must      : int;
  n_may_enum  : int;
  n_may_top   : int;
}

let valid_kinds = ["MUST"; "MAY_ENUMERATED"; "MAY_TOP"]

(* ── NDJSON parsing ──────────────────────────────────────────────────────── *)

(** Parse one non-empty NDJSON line.  Raises [Failure] with a diagnostic on any error. *)
let parse_line line_num line =
  let j =
    match Yojson.Safe.from_string line with
    | exception Yojson.Json_error msg ->
      failwith (Printf.sprintf "invalid JSON (line %d): %s" line_num msg)
    | v -> v
  in
  let obj =
    match j with
    | `Assoc o -> o
    | _ -> failwith (Printf.sprintf "not a JSON object (line %d)" line_num)
  in
  let get_str k =
    match List.assoc_opt k obj with Some (`String s) -> Some s | _ -> None
  in
  let get_bool k =
    match List.assoc_opt k obj with Some (`Bool b) -> b | _ -> false
  in
  let has_callee  = List.mem_assoc "callee_name" obj in
  let typ         = get_str "type" in
  let is_call     = typ = Some "call" || (has_callee && typ <> Some "function") in
  if is_call then begin
    let kind =
      match get_str "kind" with
      | Some k when List.mem k valid_kinds -> k
      | Some k ->
        failwith (Printf.sprintf
          "call edge has invalid kind %S; must be MUST, MAY_ENUMERATED, or MAY_TOP (line %d)" k line_num)
      | None ->
        failwith (Printf.sprintf
          "call edge missing kind; must be MUST, MAY_ENUMERATED, or MAY_TOP (line %d)" line_num)
    in
    let caller =
      match get_str "caller_name" with
      | Some n -> n
      | None -> failwith (Printf.sprintf "call edge missing caller_name (line %d)" line_num)
    in
    let callee =
      match get_str "callee_name" with
      | Some n -> n
      | None -> failwith (Printf.sprintf "call edge missing callee_name (line %d)" line_num)
    in
    `Call {
      c_caller = caller; c_caller_file = get_str "caller_file";
      c_callee = callee; c_callee_file = get_str "callee_file";
      c_site   = get_str "call_site";  c_kind    = kind;
    }
  end else begin
    let name =
      match get_str "name" with
      | Some n -> n
      | None -> failwith (Printf.sprintf "function record missing name (line %d)" line_num)
    in
    `Func { f_name = name; f_file = get_str "file_path"; f_exported = get_bool "exported" }
  end

(* ── SQLite writer ───────────────────────────────────────────────────────── *)

let schema_ddl = [
  "DROP TABLE IF EXISTS comment_db_meta";
  "DROP TABLE IF EXISTS functions";
  "DROP TABLE IF EXISTS calls";
  "CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT)";
  "CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0)";
  "CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, \
   callee_file TEXT, call_site TEXT, kind TEXT)";
  "CREATE INDEX idx_calls_caller ON calls(caller_name)";
  "CREATE INDEX idx_calls_callee ON calls(callee_name)";
]

let exec_exn db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> failwith (Printf.sprintf "SQL error (%s): %s" (Sqlite3.Rc.to_string rc) sql)

let write_db ~output ~funcs ~calls =
  let db = Sqlite3.db_open output in
  List.iter (exec_exn db) schema_ddl;
  exec_exn db "BEGIN";
  exec_exn db "INSERT INTO comment_db_meta(key,value) VALUES('callgraph_contract','v1')";
  exec_exn db "INSERT INTO comment_db_meta(key,value) VALUES('built_by','arch-load')";
  let st_fn = Sqlite3.prepare db
    "INSERT INTO functions(name,file_path,exported) VALUES(?,?,?)" in
  Hashtbl.iter (fun name (fp, exp) ->
    Sqlite3.reset st_fn |> ignore;
    Sqlite3.bind_text st_fn 1 name |> ignore;
    (match fp with
     | Some s -> Sqlite3.bind_text st_fn 2 s |> ignore
     | None   -> Sqlite3.bind st_fn 2 Sqlite3.Data.NULL |> ignore);
    Sqlite3.bind_int st_fn 3 (if exp then 1 else 0) |> ignore;
    Sqlite3.step st_fn |> ignore
  ) funcs;
  Sqlite3.finalize st_fn |> ignore;
  let st_c = Sqlite3.prepare db
    "INSERT INTO calls(caller_name,caller_file,callee_name,callee_file,call_site,kind) \
     VALUES(?,?,?,?,?,?)" in
  let bind_opt st i = function
    | Some s -> Sqlite3.bind_text st i s |> ignore
    | None   -> Sqlite3.bind st i Sqlite3.Data.NULL |> ignore
  in
  List.iter (fun c ->
    Sqlite3.reset st_c |> ignore;
    Sqlite3.bind_text st_c 1 c.c_caller |> ignore;
    bind_opt st_c 2 c.c_caller_file;
    Sqlite3.bind_text st_c 3 c.c_callee |> ignore;
    bind_opt st_c 4 c.c_callee_file;
    bind_opt st_c 5 c.c_site;
    Sqlite3.bind_text st_c 6 c.c_kind |> ignore;
    Sqlite3.step st_c |> ignore
  ) calls;
  Sqlite3.finalize st_c |> ignore;
  exec_exn db "COMMIT";
  Sqlite3.db_close db |> ignore

(* ── main entry point ───────────────────────────────────────────────────── *)

(** Read NDJSON from [ic] and write a ⊤-marked SQLite DB to [output].

    Returns [Error `Empty_calls] (without writing anything) when 0 call edges
    are found and [allow_empty] is false — false-confidence guard: a producer
    that silently failed emits nothing, yet the resulting ⊤-marked DB would
    report EVERYTHING as UNREACHABLE. *)
let load ~output ~allow_empty ic =
  let funcs : (string, string option * bool) Hashtbl.t = Hashtbl.create 512 in
  let calls = ref [] in
  (* names_in_calls: names seen in call edges (for deriving minimal function rows) *)
  let names_in_calls : (string, string option) Hashtbl.t = Hashtbl.create 512 in
  let line_num = ref 0 in
  (try
    while true do
      let raw  = input_line ic in
      incr line_num;
      let line = String.trim raw in
      if line <> "" then
        match parse_line !line_num line with
        | `Func f ->
          if f.f_name <> "*TOP*" then
            Hashtbl.replace funcs f.f_name (f.f_file, f.f_exported)
        | `Call c ->
          calls := c :: !calls;
          Hashtbl.replace names_in_calls c.c_caller c.c_caller_file;
          if c.c_callee <> "*TOP*" then
            Hashtbl.replace names_in_calls c.c_callee c.c_callee_file
    done
  with End_of_file -> ());
  (* Derive minimal function rows for names seen only in call edges *)
  Hashtbl.iter (fun name fp ->
    if not (Hashtbl.mem funcs name) then
      Hashtbl.add funcs name (fp, false)
  ) names_in_calls;
  let calls = List.rev !calls in
  if calls = [] && not allow_empty then
    Error `Empty_calls
  else begin
    write_db ~output ~funcs ~calls;
    let kc k = List.length (List.filter (fun c -> c.c_kind = k) calls) in
    Ok {
      n_functions = Hashtbl.length funcs;
      n_calls     = List.length calls;
      n_must      = kc "MUST";
      n_may_enum  = kc "MAY_ENUMERATED";
      n_may_top   = kc "MAY_TOP";
    }
  end
