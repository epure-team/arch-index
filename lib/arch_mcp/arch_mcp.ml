(* arch_mcp — MCP stdio server engine (specs/arch-mcp-server.md).
   Read-only query tools over an arch-index SQLite DB. Newline-delimited
   JSON-RPC 2.0; tool failures are MCP isError results, never RPC errors.
   Sound tools port the arch-query recursive-CTE SQL with bound parameters —
   OCaml-side BFS (arch-serve style) is kind-blind and must not be used here. *)

(* ── schema detection ────────────────────────────────────────────────────── *)

type schema_info = {
  has_functions : bool;
  exp_col : string option; (* "exposed" (main) preferred over "exported" (flat) *)
  has_caller_name : bool; (* calls.caller_name TEXT (flat) vs caller_id FK (main) *)
  has_calls : bool;
  has_kind : bool;
  has_file_path : bool;
  has_line_count : bool;
  has_cq : bool; (* comment_quality_score *)
  has_modules : bool;
  has_mod_lines : bool;
}

type ctx = {db : Sqlite3.db; si : schema_info}

let table_exists db name =
  let stmt =
    Sqlite3.prepare db "SELECT 1 FROM sqlite_master WHERE type='table' AND name=? LIMIT 1"
  in
  ignore (Sqlite3.bind_text stmt 1 name);
  let r = Sqlite3.step stmt = Sqlite3.Rc.ROW in
  ignore (Sqlite3.finalize stmt);
  r

(* table is an internal literal, never user input. pragma_table_xinfo, NOT
   table_info: generated columns (functions.line_count) are hidden from the
   latter. *)
let col_exists db table col =
  let stmt =
    Sqlite3.prepare db
      (Printf.sprintf "SELECT 1 FROM pragma_table_xinfo('%s') WHERE name=? LIMIT 1" table)
  in
  ignore (Sqlite3.bind_text stmt 1 col);
  let r = Sqlite3.step stmt = Sqlite3.Rc.ROW in
  ignore (Sqlite3.finalize stmt);
  r

let detect_schema db =
  let has_functions = table_exists db "functions" in
  let has_calls = table_exists db "calls" in
  let has_modules = table_exists db "modules" in
  {
    has_functions;
    exp_col =
      (if has_functions && col_exists db "functions" "exposed" then Some "exposed"
       else if has_functions && col_exists db "functions" "exported" then Some "exported"
       else None);
    has_caller_name = has_calls && col_exists db "calls" "caller_name";
    has_calls;
    has_kind = has_calls && col_exists db "calls" "kind";
    has_file_path = has_functions && col_exists db "functions" "file_path";
    has_line_count = has_functions && col_exists db "functions" "line_count";
    has_cq = has_functions && col_exists db "functions" "comment_quality_score";
    has_modules;
    has_mod_lines = has_modules && col_exists db "modules" "lines";
  }

(* ── SQL helpers (prepared statements only; FR-011) ──────────────────────── *)

type bind = B_text of string | B_int of int

exception Sql_error of string

let bind_all stmt binds =
  List.iteri
    (fun i b ->
      let rc =
        match b with
        | B_text s -> Sqlite3.bind_text stmt (i + 1) s
        | B_int n -> Sqlite3.bind stmt (i + 1) (Sqlite3.Data.INT (Int64.of_int n))
      in
      if rc <> Sqlite3.Rc.OK then raise (Sql_error (Sqlite3.Rc.to_string rc)))
    binds

(* One retry on BUSY (spec C-28), then error. *)
let step_retry stmt =
  match Sqlite3.step stmt with
  | Sqlite3.Rc.BUSY ->
      Unix.sleepf 0.05;
      Sqlite3.step stmt
  | rc -> rc

let q_rows db sql binds ~row =
  let stmt =
    try Sqlite3.prepare db sql
    with Sqlite3.Error m -> raise (Sql_error m)
  in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
    (fun () ->
      bind_all stmt binds;
      let out = ref [] in
      let rec loop () =
        match step_retry stmt with
        | Sqlite3.Rc.ROW ->
            out := row stmt :: !out;
            loop ()
        | Sqlite3.Rc.DONE -> ()
        | Sqlite3.Rc.BUSY -> raise (Sql_error "database busy")
        | rc -> raise (Sql_error (Sqlite3.Rc.to_string rc))
      in
      loop ();
      List.rev !out)

let col_text stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.TEXT s -> s
  | Sqlite3.Data.NULL -> ""
  | d -> Sqlite3.Data.to_string_coerce d

let col_int stmt i =
  match Sqlite3.column stmt i with
  | Sqlite3.Data.INT n -> Int64.to_int n
  | Sqlite3.Data.FLOAT f -> int_of_float f
  | _ -> 0

let q_int db sql binds =
  match q_rows db sql binds ~row:(fun s -> col_int s 0) with n :: _ -> n | [] -> 0

let q_float db sql binds =
  let row s =
    match Sqlite3.column s 0 with
    | Sqlite3.Data.FLOAT f -> f
    | Sqlite3.Data.INT n -> Int64.to_float n
    | _ -> 0.
  in
  match q_rows db sql binds ~row with f :: _ -> f | [] -> 0.

let meta_contract db =
  if not (table_exists db "comment_db_meta") then None
  else
    match
      q_rows db "SELECT value FROM comment_db_meta WHERE key='callgraph_contract' LIMIT 1"
        [] ~row:(fun s -> col_text s 0)
    with
    | v :: _ when v <> "" -> Some v
    | _ -> None

(* ── contract check (arch-query require_contract parity; FR-016) ─────────── *)

let contract_check ctx =
  match meta_contract ctx.db with
  | None ->
      Error
        "REFUSED — this index is NOT ⊤-marked (no 'callgraph_contract' meta flag). The query \
         would be UNSOUND: a 'no path' result may merely hide a silently-dropped dynamic/interface \
         edge. Rebuild with a Tier-0+ backend that emits MAY_TOP edges."
  | Some _ when not ctx.si.has_kind ->
      Error
        "REFUSED — 'callgraph_contract' is set but there is no 'kind' column: malformed ⊤-marked \
         index."
  | Some _ ->
      let bad =
        q_int ctx.db
          "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN \
           ('MUST','MAY_ENUMERATED','MAY_TOP')"
          []
      in
      if bad <> 0 then
        Error
          (Printf.sprintf
             "REFUSED — %d call edge(s) have NULL/invalid kind, violating the ⊤-marking contract \
              (every edge must be MUST | MAY_ENUMERATED | MAY_TOP). Rebuild the index."
             bad)
      else Ok ()

(* ── caller/callee access per schema flavor ──────────────────────────────── *)

(* SELECT fragment for "edges as (caller_name, callee_name, kind?)".
   FK schema: callee_name may be a qualified display string ("M.g") while
   functions.name is unqualified — resolving through callee_id keeps the
   recursive closure connected (codex review finding); unresolved callees
   (callee_id NULL) fall back to the display name. *)
let edges_from si =
  if si.has_caller_name then "calls c"
  else
    "calls c JOIN functions cf ON cf.id = c.caller_id LEFT JOIN functions tf ON tf.id = \
     c.callee_id"

let caller_expr si = if si.has_caller_name then "c.caller_name" else "cf.name"

let callee_expr si =
  if si.has_caller_name then "c.callee_name" else "COALESCE(tf.name, c.callee_name)"

(* Recursive closure CTE, bash arch-query parity (:100,:103-105,:113-116).
   [filter] is a trusted SQL fragment over c.kind ("" | " AND c.kind='MUST'" |
   " AND c.kind IN ('MUST','MAY_ENUMERATED')"). Seed is bound as ?1. *)
let closure_cte si filter =
  Printf.sprintf
    "WITH RECURSIVE reach(n) AS (SELECT ?1 UNION SELECT %s FROM %s JOIN reach r ON %s = r.n \
     WHERE 1=1%s)"
    (callee_expr si) (edges_from si) (caller_expr si) filter

(* ── tool argument specs: schema + validator from ONE source (FR-003/026) ── *)

type arg_ty = A_string | A_int of {default : int option; min : int; max : int}

type arg_spec = {a_name : string; a_ty : arg_ty; a_req : bool; a_descr : string}

type value = V_str of string | V_int of int

let limit_arg ?(default = 500) () =
  {
    a_name = "limit";
    a_ty = A_int {default = Some default; min = 1; max = 10000};
    a_req = false;
    a_descr = Printf.sprintf "max rows returned (default %d)" default;
  }

let schema_of_args (args : arg_spec list) : Yojson.Safe.t =
  `Assoc
    [
      ("type", `String "object");
      ( "properties",
        `Assoc
          (List.map
             (fun a ->
               ( a.a_name,
                 `Assoc
                   [
                     ("type", `String (match a.a_ty with A_string -> "string" | A_int _ -> "integer"));
                     ("description", `String a.a_descr);
                   ] ))
             args) );
      ("required", `List (List.filter_map (fun a -> if a.a_req then Some (`String a.a_name) else None) args));
      ("additionalProperties", `Bool false);
    ]

let as_int = function
  | `Int n -> Some n
  | `Float f when Float.is_integer f -> Some (int_of_float f)
  | `Intlit s -> int_of_string_opt s
  | _ -> None

let validate_args (specs : arg_spec list) (args : Yojson.Safe.t) :
    ((string * value) list, string) result =
  let fields = match args with `Assoc l -> Ok l | `Null -> Ok [] | _ -> Error "arguments must be an object" in
  match fields with
  | Error e -> Error e
  | Ok fields -> (
      match
        List.find_opt (fun (k, _) -> not (List.exists (fun s -> s.a_name = k) specs)) fields
      with
      | Some (k, _) -> Error (Printf.sprintf "unknown argument %S" k)
      | None ->
          List.fold_left
            (fun acc spec ->
              match acc with
              | Error _ -> acc
              | Ok vals -> (
                  match (List.assoc_opt spec.a_name fields, spec.a_ty) with
                  | Some (`String s), A_string ->
                      if s = "" then Error (Printf.sprintf "argument %S must be non-empty" spec.a_name)
                      else Ok ((spec.a_name, V_str s) :: vals)
                  | Some j, A_int {min; max; _} -> (
                      match as_int j with
                      | Some n when n >= min && n <= max -> Ok ((spec.a_name, V_int n) :: vals)
                      | Some n ->
                          Error (Printf.sprintf "argument %S out of range [%d,%d]: %d" spec.a_name min max n)
                      | None -> Error (Printf.sprintf "argument %S must be an integer" spec.a_name))
                  | Some _, A_string -> Error (Printf.sprintf "argument %S must be a string" spec.a_name)
                  | None, _ when spec.a_req -> Error (Printf.sprintf "missing required argument %S" spec.a_name)
                  | None, A_int {default = Some d; _} -> Ok ((spec.a_name, V_int d) :: vals)
                  | None, _ -> Ok vals))
            (Ok []) specs)

let get_str vals k = match List.assoc_opt k vals with Some (V_str s) -> s | _ -> assert false

let get_int vals k = match List.assoc_opt k vals with Some (V_int n) -> n | _ -> assert false

(* ── shared result helpers ───────────────────────────────────────────────── *)

(* limit+1 fetch: honest truncated flag (plan risk "false confidence"). *)
let with_truncation ~limit rows k =
  let truncated = List.length rows > limit in
  let rows = if truncated then List.filteri (fun i _ -> i < limit) rows else rows in
  k rows truncated

let escape_like s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      if c = '%' || c = '_' || c = '\\' then Buffer.add_char buf '\\';
      Buffer.add_char buf c)
    s;
  Buffer.contents buf

(* Refusals are structured JSON in the isError text (spec C-21). *)
let refused reason =
  Yojson.Safe.to_string (`Assoc [("error", `String "REFUSED"); ("reason", `String reason)])

let sound_gate ctx =
  match contract_check ctx with Ok () -> Ok () | Error reason -> Error (refused reason)

let require_index ctx =
  if not ctx.si.has_functions then Error "not an arch-index index (no 'functions' table)" else Ok ()

let ( let* ) = Result.bind

(* ── tool handlers ───────────────────────────────────────────────────────── *)

let run_stats ctx _vals =
  let* () = require_index ctx in
  let count sql = q_int ctx.db sql [] in
  let base =
    [
      ("functions", `Int (count "SELECT count(*) FROM functions"));
      ( "contract",
        `String (match meta_contract ctx.db with Some v -> v | None -> "none — not ⊤-marked; arch_unreachable will refuse") );
    ]
  in
  let exported =
    match ctx.si.exp_col with
    | Some col -> [("exported", `Int (count (Printf.sprintf "SELECT count(*) FROM functions WHERE %s=1" col)))]
    | None -> []
  in
  let calls = if ctx.si.has_calls then [("call_edges", `Int (count "SELECT count(*) FROM calls"))] else [] in
  let kinds =
    if ctx.si.has_kind then
      [
        ( "edges_by_kind",
          `Assoc
            (q_rows ctx.db "SELECT COALESCE(kind,'NULL'), count(*) FROM calls GROUP BY kind ORDER BY 2 DESC" []
               ~row:(fun s -> (col_text s 0, `Int (col_int s 1)))) );
      ]
    else []
  in
  Ok (`Assoc (base @ exported @ calls @ kinds))

(* Row shape for function lists: name, file_path?, exported? (US-2.2).
   Queries must SELECT: name, <file_path|NULL>, <exp_col|NULL>. *)
let fn_row ctx stmt =
  let base = [("name", `String (col_text stmt 0))] in
  let fp = if ctx.si.has_file_path then [("file_path", `String (col_text stmt 1))] else [] in
  let exp_ =
    match ctx.si.exp_col with Some _ -> [("exported", `Bool (col_int stmt 2 = 1))] | None -> []
  in
  `Assoc (base @ fp @ exp_)

let fn_select ctx =
  Printf.sprintf "name, %s, %s"
    (if ctx.si.has_file_path then "file_path" else "NULL")
    (match ctx.si.exp_col with Some c -> c | None -> "NULL")

let run_find ctx vals =
  let* () = require_index ctx in
  let substr = get_str vals "substr" and limit = get_int vals "limit" in
  let rows =
    q_rows ctx.db
      (Printf.sprintf "SELECT %s FROM functions WHERE name LIKE ? ESCAPE '\\' ORDER BY name LIMIT ?"
         (fn_select ctx))
      [B_text ("%" ^ escape_like substr ^ "%"); B_int (limit + 1)]
      ~row:(fn_row ctx)
  in
  with_truncation ~limit rows (fun rows truncated ->
      Ok (`Assoc [("matches", `List rows); ("truncated", `Bool truncated)]))

let run_exported ctx vals =
  let* () = require_index ctx in
  let limit = get_int vals "limit" in
  match ctx.si.exp_col with
  | None -> Error "no exposed/exported column in this index"
  | Some col ->
      let rows =
        q_rows ctx.db
          (Printf.sprintf "SELECT %s FROM functions WHERE %s=1 ORDER BY name LIMIT ?"
             (fn_select ctx) col)
          [B_int (limit + 1)] ~row:(fn_row ctx)
      in
      with_truncation ~limit rows (fun rows truncated ->
          Ok (`Assoc [("exported", `List rows); ("truncated", `Bool truncated)]))

let run_fan_in ctx vals =
  let* () = require_index ctx in
  if not ctx.si.has_calls then Error "no 'calls' table in this index"
  else
    let n = get_int vals "n" in
    let caller = caller_expr ctx.si and from = edges_from ctx.si in
    let rows =
      q_rows ctx.db
        (Printf.sprintf
           "SELECT %s AS callee, count(DISTINCT %s) AS callers FROM %s GROUP BY callee ORDER BY \
            callers DESC, callee ASC LIMIT ?"
           (callee_expr ctx.si) caller from)
        [B_int (n + 1)]
        ~row:(fun s -> `Assoc [("name", `String (col_text s 0)); ("callers", `Int (col_int s 1))])
    in
    with_truncation ~limit:n rows (fun rows truncated ->
        Ok (`Assoc [("fan_in", `List rows); ("truncated", `Bool truncated)]))

let run_callers_of ctx vals =
  let* () = require_index ctx in
  if not ctx.si.has_calls then Error "no 'calls' table in this index"
  else
    let name = get_str vals "name" and limit = get_int vals "limit" in
    let rows =
      q_rows ctx.db
        (Printf.sprintf
           "SELECT DISTINCT %s FROM %s WHERE %s = ? ORDER BY 1 LIMIT ?"
           (caller_expr ctx.si) (edges_from ctx.si) (callee_expr ctx.si))
        [B_text name; B_int (limit + 1)]
        ~row:(fun s -> `String (col_text s 0))
    in
    with_truncation ~limit rows (fun rows truncated ->
        Ok (`Assoc [("callers", `List rows); ("truncated", `Bool truncated)]))

let run_callees_of ctx vals =
  let* () = require_index ctx in
  if not ctx.si.has_calls then Error "no 'calls' table in this index"
  else
    let name = get_str vals "name" and limit = get_int vals "limit" in
    let rows =
      q_rows ctx.db
        (Printf.sprintf
           "SELECT DISTINCT %s FROM %s WHERE %s = ? ORDER BY 1 LIMIT ?"
           (callee_expr ctx.si) (edges_from ctx.si) (caller_expr ctx.si))
        [B_text name; B_int (limit + 1)]
        ~row:(fun s -> `String (col_text s 0))
    in
    with_truncation ~limit rows (fun rows truncated ->
        Ok (`Assoc [("callees", `List rows); ("truncated", `Bool truncated)]))

let run_reachable_from ctx vals =
  let* () = require_index ctx in
  if not ctx.si.has_calls then Error "no 'calls' table in this index"
  else
    let name = get_str vals "name" and limit = get_int vals "limit" in
    let rows =
      q_rows ctx.db
        (closure_cte ctx.si "" ^ " SELECT n FROM reach WHERE n <> ?1 ORDER BY n LIMIT ?2")
        [B_text name; B_int (limit + 1)]
        ~row:(fun s -> `String (col_text s 0))
    in
    with_truncation ~limit rows (fun rows truncated ->
        Ok (`Assoc [("reachable", `List rows); ("truncated", `Bool truncated)]))

let found ctx name =
  q_int ctx.db "SELECT EXISTS(SELECT 1 FROM functions WHERE name = ?)" [B_text name] = 1

let run_reaches ctx vals =
  let* () = require_index ctx in
  if not ctx.si.has_calls then Error "no 'calls' table in this index"
  else
    let from_ = get_str vals "from" and to_ = get_str vals "to" in
    (* bash parity (:69): MUST filter when kind exists, else legacy all-MUST. *)
    let filter = if ctx.si.has_kind then " AND c.kind='MUST'" else "" in
    let hit =
      q_int ctx.db
        (closure_cte ctx.si filter ^ " SELECT EXISTS(SELECT 1 FROM reach WHERE n = ?2)")
        [B_text from_; B_text to_]
    in
    let base =
      [
        ("result", `String (if hit = 1 then "PATH_EXISTS" else "NO_MUST_PATH"));
        ("from", `String from_);
        ("to", `String to_);
        ("from_found", `Bool (found ctx from_));
        ("to_found", `Bool (found ctx to_));
      ]
    in
    let legacy = if ctx.si.has_kind then [] else [("legacy", `Bool true)] in
    let note =
      if hit = 1 then []
      else [("note", `String "no MUST path is NOT proof of unreachability — use arch_unreachable")]
    in
    Ok (`Assoc (base @ legacy @ note))

let resolved_filter = " AND c.kind IN ('MUST','MAY_ENUMERATED')"

(* ⊤ frontier reachable from the resolved closure (bash :120,:131-132). *)
let top_frontier_sql si select =
  closure_cte si resolved_filter
  ^ Printf.sprintf
      " SELECT %s FROM %s WHERE %s IN (SELECT n FROM reach) AND (c.kind IS NULL OR c.kind NOT IN \
       ('MUST','MAY_ENUMERATED'))"
      select (edges_from si) (caller_expr si)

let run_unreachable ctx vals =
  let* () = require_index ctx in
  let* () = sound_gate ctx in
  let from_ = get_str vals "from" and to_ = get_str vals "to" in
  let reachable =
    q_int ctx.db
      (closure_cte ctx.si resolved_filter ^ " SELECT EXISTS(SELECT 1 FROM reach WHERE n = ?2)")
      [B_text from_; B_text to_]
    = 1
  in
  let verdict, explanation =
    if reachable then ("REACHABLE", Printf.sprintf "may-reach: %s -> %s" from_ to_)
    else
      let top = q_int ctx.db (top_frontier_sql ctx.si "EXISTS(SELECT 1)") [B_text from_] in
      if top = 1 then
        ( "UNKNOWN",
          Printf.sprintf
            "no resolved path %s -> %s, but %s reaches a non-resolved (MAY_TOP) edge — \
             could-call-anything; cannot rule out a path"
            from_ to_ from_ )
      else
        ( "UNREACHABLE",
          Printf.sprintf "no resolved path %s -> %s and no reachable MAY_TOP — sound verdict" from_ to_ )
  in
  Ok
    (`Assoc
       [
         ("verdict", `String verdict);
         ("from", `String from_);
         ("to", `String to_);
         ("from_found", `Bool (found ctx from_));
         ("to_found", `Bool (found ctx to_));
         ("explanation", `String explanation);
       ])

let run_escapes ctx vals =
  let* () = require_index ctx in
  let* () = sound_gate ctx in
  let from_ = get_str vals "from" and limit = get_int vals "limit" in
  let rows =
    q_rows ctx.db
      (top_frontier_sql ctx.si
         (Printf.sprintf "DISTINCT %s, c.call_site, COALESCE(c.kind,'NULL')" (caller_expr ctx.si))
      ^ " ORDER BY 1 LIMIT ?2")
      [B_text from_; B_int (limit + 1)]
      ~row:(fun s ->
        `Assoc
          [
            ("escaping_fn", `String (col_text s 0));
            ("call_site", `String (col_text s 1));
            ("kind", `String (col_text s 2));
          ])
  in
  with_truncation ~limit rows (fun rows truncated ->
      Ok (`Assoc [("escapes", `List rows); ("truncated", `Bool truncated)]))

(* Same metric set, detection, and omission semantics as `arch-query metrics`
   (specs/arch-metrics-gate.md FR-002/FR-003) — keys sorted lexicographically. *)
let run_metrics ctx _vals =
  let* () = require_index ctx in
  let si = ctx.si in
  let m = ref [] in
  let add k v = m := (k, v) :: !m in
  if si.has_calls then add "call_edges" (`Int (q_int ctx.db "SELECT count(*) FROM calls" []));
  (match si.exp_col with
  | Some col when si.has_cq ->
      let exposed = q_int ctx.db (Printf.sprintf "SELECT count(*) FROM functions WHERE %s=1" col) [] in
      let undoc =
        q_int ctx.db
          (Printf.sprintf
             "SELECT count(*) FROM functions WHERE %s=1 AND (comment_quality_score IS NULL OR \
              comment_quality_score=0)"
             col)
          []
      in
      let pct =
        if exposed = 0 then 100.0
        else
          q_float ctx.db "SELECT ROUND(100.0 * (1.0 - CAST(? AS REAL) / ?), 1)"
            [B_int undoc; B_int exposed]
      in
      (* one-decimal literal: Yojson would print 86.4 as 86.40000000000001,
         breaking byte-parity with `arch-query metrics` (sqlite ROUND text). *)
      add "doc_coverage_pct"
        (if Float.is_integer pct then `Float pct else `Intlit (Printf.sprintf "%.1f" pct));
      add "undocumented_exposed" (`Int undoc)
  | _ -> ());
  (match si.exp_col with
  | Some col ->
      add "exported_functions" (`Int (q_int ctx.db (Printf.sprintf "SELECT count(*) FROM functions WHERE %s=1" col) []))
  | None -> ());
  if si.has_mod_lines then add "large_files" (`Int (q_int ctx.db "SELECT count(*) FROM modules WHERE lines > 500" []));
  if si.has_line_count then
    add "large_functions" (`Int (q_int ctx.db "SELECT count(*) FROM functions WHERE line_count > 50" []));
  if si.has_calls && si.has_kind then
    add "may_top_edges" (`Int (q_int ctx.db "SELECT count(*) FROM calls WHERE kind='MAY_TOP'" []));
  if si.has_modules then add "modules" (`Int (q_int ctx.db "SELECT count(*) FROM modules" []));
  add "total_functions" (`Int (q_int ctx.db "SELECT count(*) FROM functions" []));
  Ok (`Assoc (List.sort (fun (a, _) (b, _) -> String.compare a b) !m))

(* ── tool registry ───────────────────────────────────────────────────────── *)

type tool = {
  t_name : string;
  t_descr : string;
  t_args : arg_spec list;
  t_run : ctx -> (string * value) list -> (Yojson.Safe.t, string) result;
}

let str_arg name descr = {a_name = name; a_ty = A_string; a_req = true; a_descr = descr}

let tools : tool list =
  [
    {t_name = "arch_stats"; t_descr = "Index row counts, edge-kind breakdown, and ⊤-marking contract status";
     t_args = []; t_run = run_stats};
    {t_name = "arch_find"; t_descr = "Find functions whose name contains a substring (SQL LIKE, wildcards escaped)";
     t_args = [str_arg "substr" "substring to match in function names"; limit_arg ~default:200 ()]; t_run = run_find};
    {t_name = "arch_exported"; t_descr = "All exported/exposed functions (external attack surface)";
     t_args = [limit_arg ~default:1000 ()]; t_run = run_exported};
    {t_name = "arch_fan_in"; t_descr = "Top-N most-called functions (shared sinks / high-value targets)";
     t_args = [{a_name = "n"; a_ty = A_int {default = Some 25; min = 1; max = 10000}; a_req = false;
                a_descr = "how many rows (default 25)"}]; t_run = run_fan_in};
    {t_name = "arch_callers_of"; t_descr = "Direct callers of a function (1 hop)";
     t_args = [str_arg "name" "function name"; limit_arg ()]; t_run = run_callers_of};
    {t_name = "arch_callees_of"; t_descr = "Direct callees of a function (1 hop)";
     t_args = [str_arg "name" "function name"; limit_arg ()]; t_run = run_callees_of};
    {t_name = "arch_reachable_from"; t_descr = "Transitive closure of callees from a function (all edge kinds)";
     t_args = [str_arg "name" "function name"; limit_arg ()]; t_run = run_reachable_from};
    {t_name = "arch_reaches"; t_descr = "MUST-only reachability: a PATH_EXISTS answer is ground truth; \
                                         NO_MUST_PATH is NOT proof of unreachability";
     t_args = [str_arg "from" "source function"; str_arg "to" "target function"]; t_run = run_reaches};
    {t_name = "arch_unreachable"; t_descr = "Sound unreachability verdict (REACHABLE | UNKNOWN | UNREACHABLE); \
                                             REFUSES on a non-⊤-marked index";
     t_args = [str_arg "from" "source function"; str_arg "to" "target function"]; t_run = run_unreachable};
    {t_name = "arch_escapes"; t_descr = "MAY_TOP (⊤) edges reachable from a function — the frontier forcing \
                                         UNKNOWN verdicts; REFUSES on a non-⊤-marked index";
     t_args = [str_arg "from" "source function"; limit_arg ()]; t_run = run_escapes};
    {t_name = "arch_metrics"; t_descr = "Flat JSON metrics object (same shape as `arch-query metrics`; \
                                         feature-detected, absent sources omitted)";
     t_args = []; t_run = run_metrics};
  ]

let tool_names () = List.map (fun t -> t.t_name) tools

(* ── JSON-RPC / MCP dispatch (FR-001..006) ───────────────────────────────── *)

let protocol_version = "2024-11-05"

let server_version = "0.1.0"

let rpc_error ~id code message =
  `Assoc
    [
      ("jsonrpc", `String "2.0");
      ("id", id);
      ("error", `Assoc [("code", `Int code); ("message", `String message)]);
    ]

let rpc_result ~id result =
  `Assoc [("jsonrpc", `String "2.0"); ("id", id); ("result", result)]

(* Tool outcome → MCP content envelope; tool failures are isError, never RPC
   errors (FR-004). *)
let tool_content ~is_error text =
  `Assoc
    [
      ("content", `List [`Assoc [("type", `String "text"); ("text", `String text)]]);
      ("isError", `Bool is_error);
    ]

let handle_tools_call ctx params =
  let member k = function `Assoc l -> Option.value ~default:`Null (List.assoc_opt k l) | _ -> `Null in
  let name = match member "name" params with `String s -> s | _ -> "" in
  let args = member "arguments" params in
  match List.find_opt (fun t -> t.t_name = name) tools with
  | None -> tool_content ~is_error:true (Printf.sprintf "Unknown tool: %s" name)
  | Some tool -> (
      match validate_args tool.t_args args with
      | Error msg -> tool_content ~is_error:true (Printf.sprintf "Invalid arguments: %s" msg)
      | Ok vals -> (
          match tool.t_run ctx vals with
          | Ok json -> tool_content ~is_error:false (Yojson.Safe.to_string json)
          | Error msg -> tool_content ~is_error:true msg
          | exception Sql_error m -> tool_content ~is_error:true (Printf.sprintf "SQL error: %s" m)))

(* Pure dispatch: Yojson in → Yojson out; None = nothing to write (FR-008).
   Notifications (no "id") are never answered (FR-005). *)
let handle_message ctx (json : Yojson.Safe.t) : Yojson.Safe.t option =
  match json with
  | `List _ -> Some (rpc_error ~id:`Null (-32600) "batch requests are not supported")
  | `Assoc fields -> (
      let id = List.assoc_opt "id" fields in
      let method_ = match List.assoc_opt "method" fields with Some (`String m) -> Some m | _ -> None in
      let params = Option.value ~default:`Null (List.assoc_opt "params" fields) in
      match (id, method_) with
      | None, _ -> None (* notification *)
      | Some id, Some "initialize" ->
          Some
            (rpc_result ~id
               (`Assoc
                  [
                    ("protocolVersion", `String protocol_version);
                    ("serverInfo", `Assoc [("name", `String "arch-mcp"); ("version", `String server_version)]);
                    ("capabilities", `Assoc [("tools", `Assoc [("listChanged", `Bool false)])]);
                  ]))
      | Some id, Some "tools/list" ->
          Some
            (rpc_result ~id
               (`Assoc
                  [
                    ( "tools",
                      `List
                        (List.map
                           (fun t ->
                             `Assoc
                               [
                                 ("name", `String t.t_name);
                                 ("description", `String t.t_descr);
                                 ("inputSchema", schema_of_args t.t_args);
                               ])
                           tools) );
                  ]))
      | Some id, Some "tools/call" -> Some (rpc_result ~id (handle_tools_call ctx params))
      | Some id, Some m -> Some (rpc_error ~id (-32601) (Printf.sprintf "Unknown method: %s" m))
      | Some id, None -> Some (rpc_error ~id (-32600) "missing method"))
  | _ -> Some (rpc_error ~id:`Null (-32600) "request must be a JSON object")

(* Framing: one JSON document per line; blank lines skipped; CR stripped;
   parse errors answered with -32700 id null (FR-001/005). *)
let handle_line ctx line : Yojson.Safe.t option =
  let line =
    let n = String.length line in
    if n > 0 && line.[n - 1] = '\r' then String.sub line 0 (n - 1) else line
  in
  if String.trim line = "" then None
  else
    match Yojson.Safe.from_string line with
    | exception Yojson.Json_error msg -> Some (rpc_error ~id:`Null (-32700) ("Parse error: " ^ msg))
    | json -> handle_message ctx json
