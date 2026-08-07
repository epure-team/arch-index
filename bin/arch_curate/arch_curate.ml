(** arch-curate — the human-judgement WRITE surface for the curation ledgers.

    A2's measures and A3's duplicates can only ever hand back a fact or a proof; what to DO about
    a big module, an unfixed string param, or a proven duplicate is a human call. This tool is
    where that call gets RECORDED, with provenance, rather than left as a vibe: open a gardening
    task against a GitHub issue, mark (or record) a string-typed param that should have a proper
    type, and append to the gardening log.

    [gardening_log] is APPEND-ONLY by construction here: every subcommand below either INSERTs a
    new row or UPDATEs a [fixed]/[fixed_at] flag on an existing [unsafe_params] row — nothing in
    this tool issues a DELETE or an UPDATE against [gardening_log], and there is no subcommand
    that would let one. Every write is one transaction: it lands, or (on a constraint violation or
    unexpected SQL error) none of it does. *)

let usage =
  {|arch-curate — record a human curation decision, with provenance.

Usage: arch-curate <db> <subcommand> --flag value ...

Subcommands:
  open-task --issue N --category C --title T [--module PATH | --function NAME]
      Open a gardening task (gardening_tasks), linked to a GitHub issue. At most one of
      --module/--function may be given as the target; omit both for a task with no single target.

  mark-fixed --function NAME --param PARAM
      Mark an EXISTING unsafe_params row fixed=1 (stamps fixed_at). Errors if the row does not
      exist yet — record it first with add-unsafe-param.

  add-unsafe-param --function NAME --param PARAM --current TYPE [--target TYPE] [--issue N]
      Record a new string-typed parameter that should have a proper type (unsafe_params).

  log --contributor NAME --category C --description TEXT --pr N [--issue N] [--date YYYY-MM-DD]
      Append one entry to gardening_log (APPEND-ONLY — there is no edit/delete subcommand).
      --contributor and --pr are REQUIRED: this ledger's whole point is recorded provenance, not
      an unattributed note. --date defaults to today (UTC).

Every write is transactional. github_issue is UNIQUE in gardening_tasks and
(function,param_name) is UNIQUE in unsafe_params — re-using either is refused with a clear
message rather than a raw SQL error.|}

let die code msg =
  prerr_endline msg ;
  exit code

(* ------------------------------------------------------------------ *)
(* flag parsing: --name value pairs only, unknown/missing flags refuse  *)
(* ------------------------------------------------------------------ *)

let is_flag s = String.length s > 2 && String.sub s 0 2 = "--"
let flag_name s = String.sub s 2 (String.length s - 2)

let rec parse_flags acc = function
  | [] -> List.rev acc
  | f :: v :: tl when is_flag f && not (is_flag v) ->
      let name = flag_name f in
      if List.mem_assoc name acc then die 2 (Printf.sprintf "arch-curate: duplicate flag --%s" name) ;
      parse_flags ((name, v) :: acc) tl
  | [ f ] when is_flag f -> die 2 (Printf.sprintf "arch-curate: flag --%s needs a value" (flag_name f))
  | f :: _ -> die 2 (Printf.sprintf "arch-curate: unexpected argument %S (expected --flag value pairs)" f)

let need flags name =
  match List.assoc_opt name flags with
  | Some v when v <> "" -> v
  | _ -> die 2 (Printf.sprintf "arch-curate: --%s is required" name)

let check_allowed flags allowed =
  List.iter
    (fun (k, _) ->
      if not (List.mem k allowed) then
        die 2
          (Printf.sprintf "arch-curate: unknown flag --%s for this subcommand (allowed: %s)" k
             (String.concat ", " (List.map (fun n -> "--" ^ n) allowed))))
    flags

(* ------------------------------------------------------------------ *)
(* DB helpers                                                          *)
(* ------------------------------------------------------------------ *)

let has_table db name =
  let stmt = Sqlite3.prepare db "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name=?" in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT name)) ;
  let r =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW -> ( match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> n > 0L | _ -> false)
    | _ -> false
  in
  ignore (Sqlite3.finalize stmt) ;
  r

(** Every id matching [col=name] in [table]. Exactly-one resolution: the caller decides
    not-found/ambiguous/use from the shape of the list, matching arch-coverage-load's discipline —
    never guess between candidates. *)
let resolve_ids db ~table ~col name =
  let stmt = Sqlite3.prepare db (Printf.sprintf "SELECT id FROM %s WHERE %s=?" table col) in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT name)) ;
  let ids = ref [] in
  let rec loop () =
    match Sqlite3.step stmt with
    | Sqlite3.Rc.ROW ->
        (match Sqlite3.column stmt 0 with Sqlite3.Data.INT n -> ids := n :: !ids | _ -> ()) ;
        loop ()
    | _ -> ()
  in
  loop () ;
  ignore (Sqlite3.finalize stmt) ;
  !ids

let resolve_one_exn db ~table ~col ~what name =
  match resolve_ids db ~table ~col name with
  | [ id ] -> id
  | [] -> die 2 (Printf.sprintf "arch-curate: no %s named %S in this index" what name)
  | _ ->
      die 2
        (Printf.sprintf
           "arch-curate: %S resolves to more than one %s in this index — ambiguous, cannot pick \
            one"
           name what)

let bind_opt stmt i = function
  | Some s -> ignore (Sqlite3.bind stmt i (Sqlite3.Data.TEXT s))
  | None -> ignore (Sqlite3.bind stmt i Sqlite3.Data.NULL)

let bind_int_opt stmt i = function
  | Some n -> ignore (Sqlite3.bind stmt i (Sqlite3.Data.INT n))
  | None -> ignore (Sqlite3.bind stmt i Sqlite3.Data.NULL)

let opt_int_flag flags name =
  match List.assoc_opt name flags with
  | None -> None
  | Some v -> (
      match int_of_string_opt v with
      | Some n -> Some n
      | None -> die 2 (Printf.sprintf "arch-curate: --%s must be an integer, got %S" name v))

let int_flag flags name =
  match opt_int_flag flags name with
  | Some n -> n
  | None -> die 2 (Printf.sprintf "arch-curate: --%s is required" name)

let utc_date () =
  let tm = Unix.gmtime (Unix.time ()) in
  Printf.sprintf "%04d-%02d-%02d" (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday

(** A minimal YYYY-MM-DD shape check — enough to catch an obviously wrong format (a timestamp, a
    US-order date) without pulling in a date-parsing library for one field. *)
let valid_date_shape s =
  String.length s = 10 && s.[4] = '-' && s.[7] = '-'
  && String.for_all (fun c -> (c >= '0' && c <= '9') || c = '-') s

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> die 2 (Printf.sprintf "arch-curate: SQL error (%s) running %s: %s" (Sqlite3.Rc.to_string rc) sql (Sqlite3.errmsg db))

(* ------------------------------------------------------------------ *)
(* subcommands                                                         *)
(* ------------------------------------------------------------------ *)

let cmd_open_task db flags =
  check_allowed flags [ "issue"; "category"; "title"; "module"; "function" ] ;
  let issue = int_flag flags "issue" in
  let category = need flags "category" and title = need flags "title" in
  (match (List.assoc_opt "module" flags, List.assoc_opt "function" flags) with
  | Some _, Some _ -> die 2 "arch-curate: open-task: give at most one of --module / --function"
  | _ -> ()) ;
  let module_id = Option.map (resolve_one_exn db ~table:"modules" ~col:"path" ~what:"module") (List.assoc_opt "module" flags) in
  let function_id = Option.map (resolve_one_exn db ~table:"functions" ~col:"name" ~what:"function") (List.assoc_opt "function" flags) in
  exec db "BEGIN" ;
  let stmt =
    Sqlite3.prepare db
      "INSERT INTO gardening_tasks(github_issue,category,title,target_module_id,target_function_id,status) \
       VALUES(?,?,?,?,?,'open')"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT (Int64.of_int issue))) ;
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT category)) ;
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT title)) ;
  bind_int_opt stmt 4 module_id ;
  bind_int_opt stmt 5 function_id ;
  (match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> ()
  | Sqlite3.Rc.CONSTRAINT ->
      ignore (Sqlite3.finalize stmt) ;
      exec db "ROLLBACK" ;
      die 2 (Printf.sprintf "arch-curate: issue #%d already has a gardening task — reuse it or pick a different issue" issue)
  | rc ->
      ignore (Sqlite3.finalize stmt) ;
      exec db "ROLLBACK" ;
      die 2 (Printf.sprintf "arch-curate: insert failed: %s (%s)" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))) ;
  ignore (Sqlite3.finalize stmt) ;
  exec db "COMMIT" ;
  Printf.eprintf "arch-curate: opened task for issue #%d (%s)\n" issue category

let cmd_mark_fixed db flags =
  check_allowed flags [ "function"; "param" ] ;
  let fn = need flags "function" and param = need flags "param" in
  let fid = resolve_one_exn db ~table:"functions" ~col:"name" ~what:"function" fn in
  exec db "BEGIN" ;
  let stmt =
    Sqlite3.prepare db
      "UPDATE unsafe_params SET fixed=1, fixed_at=? WHERE function_id=? AND param_name=?"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT (utc_date ()))) ;
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.INT fid)) ;
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT param)) ;
  (match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> ()
  | rc ->
      ignore (Sqlite3.finalize stmt) ;
      exec db "ROLLBACK" ;
      die 2 (Printf.sprintf "arch-curate: update failed: %s (%s)" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))) ;
  let changed = Sqlite3.changes db in
  ignore (Sqlite3.finalize stmt) ;
  if changed = 0 then (
    exec db "ROLLBACK" ;
    die 2
      (Printf.sprintf
         "arch-curate: no unsafe_params row for %s.%s — record it first with add-unsafe-param" fn
         param)) ;
  exec db "COMMIT" ;
  Printf.eprintf "arch-curate: marked %s.%s fixed\n" fn param

let cmd_add_unsafe_param db flags =
  check_allowed flags [ "function"; "param"; "current"; "target"; "issue" ] ;
  let fn = need flags "function" and param = need flags "param" and current = need flags "current" in
  let target = List.assoc_opt "target" flags in
  let issue = Option.map Int64.of_int (opt_int_flag flags "issue") in
  let fid = resolve_one_exn db ~table:"functions" ~col:"name" ~what:"function" fn in
  exec db "BEGIN" ;
  let stmt =
    Sqlite3.prepare db
      "INSERT INTO unsafe_params(function_id,param_name,current_type,target_type,github_issue) \
       VALUES(?,?,?,?,?)"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.INT fid)) ;
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT param)) ;
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT current)) ;
  bind_opt stmt 4 target ;
  bind_int_opt stmt 5 issue ;
  (match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> ()
  | Sqlite3.Rc.CONSTRAINT ->
      ignore (Sqlite3.finalize stmt) ;
      exec db "ROLLBACK" ;
      die 2
        (Printf.sprintf
           "arch-curate: %s.%s is already tracked in unsafe_params — use mark-fixed, not \
            add-unsafe-param, to update it"
           fn param)
  | rc ->
      ignore (Sqlite3.finalize stmt) ;
      exec db "ROLLBACK" ;
      die 2 (Printf.sprintf "arch-curate: insert failed: %s (%s)" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))) ;
  ignore (Sqlite3.finalize stmt) ;
  exec db "COMMIT" ;
  Printf.eprintf "arch-curate: recorded %s.%s : %s (unfixed)\n" fn param current

let cmd_log db flags =
  check_allowed flags [ "contributor"; "category"; "description"; "pr"; "issue"; "date" ] ;
  let contributor = need flags "contributor" and category = need flags "category" in
  let description = need flags "description" in
  let pr = int_flag flags "pr" in
  let issue = opt_int_flag flags "issue" in
  let date = match List.assoc_opt "date" flags with Some d -> d | None -> utc_date () in
  if not (valid_date_shape date) then
    die 2 (Printf.sprintf "arch-curate: --date must look like YYYY-MM-DD, got %S" date) ;
  exec db "BEGIN" ;
  let stmt =
    Sqlite3.prepare db
      "INSERT INTO gardening_log(date,contributor,category,description,pr_number,issue_number) \
       VALUES(?,?,?,?,?,?)"
  in
  ignore (Sqlite3.bind stmt 1 (Sqlite3.Data.TEXT date)) ;
  ignore (Sqlite3.bind stmt 2 (Sqlite3.Data.TEXT contributor)) ;
  ignore (Sqlite3.bind stmt 3 (Sqlite3.Data.TEXT category)) ;
  ignore (Sqlite3.bind stmt 4 (Sqlite3.Data.TEXT description)) ;
  ignore (Sqlite3.bind stmt 5 (Sqlite3.Data.INT (Int64.of_int pr))) ;
  bind_int_opt stmt 6 (Option.map Int64.of_int issue) ;
  (match Sqlite3.step stmt with
  | Sqlite3.Rc.DONE -> ()
  | rc ->
      ignore (Sqlite3.finalize stmt) ;
      exec db "ROLLBACK" ;
      die 2 (Printf.sprintf "arch-curate: insert failed: %s (%s)" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))) ;
  ignore (Sqlite3.finalize stmt) ;
  exec db "COMMIT" ;
  Printf.eprintf "arch-curate: logged (%s, %s, PR #%d)\n" date contributor pr

(* ------------------------------------------------------------------ *)

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let db_path, cmd, rest =
    match args with
    | d :: c :: rest -> (d, c, rest)
    | _ ->
        prerr_endline usage ;
        exit 2
  in
  if not (Sys.file_exists db_path) then die 2 (Printf.sprintf "arch-curate: no such db: %s" db_path) ;
  let db = Sqlite3.db_open db_path in
  if not (has_table db "functions") then
    die 2 (Printf.sprintf "arch-curate: %s has no `functions` table — not an arch-index DB" db_path) ;
  let need_table name what =
    if not (has_table db name) then
      die 3
        (Printf.sprintf
           "arch-curate: %s requires the main schema's %s table (not built from \
            architecture-schema.sql)."
           what name)
  in
  let flags = parse_flags [] rest in
  (match cmd with
  | "open-task" ->
      need_table "gardening_tasks" "open-task" ;
      cmd_open_task db flags
  | "mark-fixed" ->
      need_table "unsafe_params" "mark-fixed" ;
      cmd_mark_fixed db flags
  | "add-unsafe-param" ->
      need_table "unsafe_params" "add-unsafe-param" ;
      cmd_add_unsafe_param db flags
  | "log" ->
      need_table "gardening_log" "log" ;
      cmd_log db flags
  | other ->
      prerr_endline (Printf.sprintf "arch-curate: unknown subcommand %S" other) ;
      prerr_endline usage ;
      exit 2) ;
  ignore (Sqlite3.db_close db)
