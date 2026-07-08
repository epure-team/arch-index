(* arch_coverage — NDJSON coverage loader core (specs/arch-gardening-queries.md US-2).
   Loads coverage snapshots into an EXISTING main-schema DB. Transactional:
   any malformed record rolls back the whole run (FR-007). Lossy resolution
   contract: exactly one (name [+ module path]) candidate, else skip (FR-006). *)

type record = {
  fn : string;
  module_ : string option;
  covered : int;
  total : int;
}

type outcome = Written | Ignored (* INSERT OR IGNORE hit: same fn + stamp *) | Skipped of string

type summary = {written : int; skipped : int; ignored : int}

exception Malformed of string

(* strict UTC stamp (YYYY-MM-DDTHH:MM:SSZ) — lexicographically sortable, so
   MAX(recorded_at) is sound. Checked positionally: OCaml's Str lacks {n}. *)
let valid_stamp s =
  String.length s = 20
  && (let ok = ref true in
      String.iteri
        (fun i c ->
          let want =
            match i with
            | 4 | 7 -> c = '-'
            | 10 -> c = 'T'
            | 13 | 16 -> c = ':'
            | 19 -> c = 'Z'
            | _ -> c >= '0' && c <= '9'
          in
          if not want then ok := false)
        s;
      !ok)
  && (* field ranges — 2026-99-99T99:99:99Z must not sort as "latest" forever *)
  (let f a b = int_of_string (String.sub s a b) in
   let mo = f 5 2 and d = f 8 2 and h = f 11 2 and mi = f 14 2 and sec = f 17 2 in
   mo >= 1 && mo <= 12 && d >= 1 && d <= 31 && h <= 23 && mi <= 59 && sec <= 59)

let now_stamp () =
  let t = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02dZ" (t.Unix.tm_year + 1900)
    (t.Unix.tm_mon + 1) t.Unix.tm_mday t.Unix.tm_hour t.Unix.tm_min t.Unix.tm_sec

let parse_record line : record =
  let module U = Yojson.Safe.Util in
  let json =
    try Yojson.Safe.from_string line
    with Yojson.Json_error m -> raise (Malformed ("invalid JSON: " ^ m))
  in
  let str k = match U.member k json with `String s -> Some s | `Null -> None | _ -> raise (Malformed (k ^ " must be a string")) in
  let int k =
    match U.member k json with
    | `Int n -> n
    | _ -> raise (Malformed (k ^ " must be an integer"))
  in
  (match str "type" with
  | Some "coverage" -> ()
  | _ -> raise (Malformed "type must be \"coverage\""));
  let fn = match str "function" with Some s when s <> "" -> s | _ -> raise (Malformed "function required") in
  let covered = int "covered_lines" and total = int "total_lines" in
  if covered < 0 || total < 0 then raise (Malformed "covered_lines/total_lines must be >= 0");
  if covered > total then raise (Malformed "covered_lines > total_lines");
  {fn; module_ = str "module"; covered; total}

(* exactly-one candidate or skip (plan objection #3: explicitly lossy) *)
let resolve db (r : record) : (int, string) result =
  let sql =
    match r.module_ with
    | Some _ ->
        "SELECT f.id FROM functions f JOIN modules m ON f.module_id = m.id WHERE f.name = ? AND m.path = ?"
    | None -> "SELECT f.id FROM functions f WHERE f.name = ?"
  in
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind_text stmt 1 r.fn);
      (match r.module_ with Some m -> ignore (Sqlite3.bind_text stmt 2 m) | None -> ());
      let ids = ref [] in
      while Sqlite3.step stmt = Sqlite3.Rc.ROW do
        (match Sqlite3.column stmt 0 with
        | Sqlite3.Data.INT n -> ids := Int64.to_int n :: !ids
        | _ -> ())
      done;
      match !ids with
      | [id] -> Ok id
      | [] -> Error (Printf.sprintf "no function %S%s" r.fn
                       (match r.module_ with Some m -> " in " ^ m | None -> ""))
      | _ -> Error (Printf.sprintf "ambiguous function %S (give \"module\")" r.fn))

let insert db ~stamp ~fn_id (r : record) : outcome =
  let stmt =
    Sqlite3.prepare db
      "INSERT OR IGNORE INTO coverage(function_id, covered_lines, total_lines, recorded_at) \
       VALUES(?,?,?,?)"
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT (Int64.of_int fn_id)));
      ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.INT (Int64.of_int r.covered)));
      ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.INT (Int64.of_int r.total)));
      ignore (Sqlite3.bind_text stmt 4 stamp);
      match Sqlite3.step stmt with
      | Sqlite3.Rc.DONE -> if Sqlite3.changes db = 0 then Ignored else Written
      | rc -> raise (Malformed ("insert failed: " ^ Sqlite3.Rc.to_string rc)))

let exec db sql =
  match Sqlite3.exec db sql with Sqlite3.Rc.OK -> () | rc -> failwith (Sqlite3.Rc.to_string rc)

(* Load all lines. Malformed anywhere → ROLLBACK (nothing persists) and
   [Error msg]; resolution failures are per-line skips, run still succeeds. *)
let load db ~stamp ~(warn : string -> unit) (lines : string list) : (summary, string) result =
  exec db "BEGIN";
  let s = ref {written = 0; skipped = 0; ignored = 0} in
  match
    List.iteri
      (fun i line ->
        if String.trim line <> "" then
          let r =
            try parse_record line
            with Malformed m -> raise (Malformed (Printf.sprintf "line %d: %s" (i + 1) m))
          in
          match resolve db r with
          | Error why ->
              warn (Printf.sprintf "line %d skipped: %s" (i + 1) why);
              s := {!s with skipped = !s.skipped + 1}
          | Ok fn_id -> (
              match insert db ~stamp ~fn_id r with
              | Written -> s := {!s with written = !s.written + 1}
              | Ignored -> s := {!s with ignored = !s.ignored + 1}
              | Skipped _ -> assert false))
      lines
  with
  | () ->
      exec db "COMMIT";
      Ok !s
  | exception Malformed m ->
      exec db "ROLLBACK";
      Error m
  | exception e ->
      (* SQLite/schema failures must not escape with the transaction open *)
      (try exec db "ROLLBACK" with _ -> ());
      Error ("internal: " ^ Printexc.to_string e)
