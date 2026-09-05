(** SQLite access and schema detection, on Caqti.

    {1 Why Caqti, and what it does and does not buy here}

    The gain is that a query's {b parameter arity and row shape are declared and checked by the
    compiler}. The previous layer bound a positional [value list] against a SQL string: nothing
    connected the two, and SQLite leaves an unbound [?] as NULL rather than erroring — so a
    miscount produced a wrong reachability verdict instead of a failure.

    The second gain is subtler and matters for [-json]: a row's types are now {b declared} rather
    than sniffed from whatever the driver happened to return. A COUNT column is an [int] because
    the request says so, so it renders as a JSON number by construction rather than by
    inspection.

    What Caqti cannot express is "run this arbitrary SQL and print whatever comes back" — it is a
    typed API, and that is the point. Every result shape is therefore declared below in {!Rows}.
    Dynamically-assembled SQL (schema branches, LIMIT) uses [~oneshot:true] requests, which skip
    the prepared-statement cache; the alternative would be a prepared statement per (schema,
    limit) pair, which is worse. *)

module C = Caqti_blocking

exception Refused of string
(** A verdict-bearing refusal, not a crash: the index cannot support a SOUND answer to the
    question asked. Callers map this to exit 3. *)

exception Broken of string
(** The database could not be read at all — missing file, locked, corrupt, a SQL error. Callers
    map this to exit 2.

    Distinct from {!Refused} on purpose. Exit 3 is documented as "the index cannot answer this
    soundly", and a caller (the MCP server, a CI gate) is expected to report it as a verdict
    rather than a failure. Routing an I/O error through it would present "the file is locked" as
    a considered analysis result. *)

let refuse fmt = Printf.ksprintf (fun s -> raise (Refused s)) fmt
let broken fmt = Printf.ksprintf (fun s -> raise (Broken s)) fmt

type schema =
  | Flat  (** [arch-load]: [calls.caller_name] TEXT, [functions.file_path] *)
  | Main  (** [architecture-schema.sql]: [calls.caller_id] FK, [modules] join *)

type t = {
  conn : (module C.CONNECTION);
  path : string;
  schema : schema;
  kinded : bool;  (** [calls.kind] exists at all *)
  contract : string option;  (** [callgraph_contract] meta flag *)
}

(* ------------------------------------------------------------------ *)
(* a display cell — what the formatter consumes                        *)
(* ------------------------------------------------------------------ *)

(** Rows keep their TYPE all the way to the renderer. Stringifying here would make [-json]
    impossible to render correctly: sqlite emits integers as JSON numbers and NULL as [null],
    and a stringified cell cannot be turned back into either without guessing. *)
type cell = Nul | Int of int | Real of float | Text of string

let text_cell = function None -> Nul | Some s -> Text s
let int_cell = function None -> Nul | Some i -> Int i
let real_cell = function None -> Nul | Some f -> Real f

(* SQLite's text renderer for a REAL is exactly C's [%.15g], with a decimal point forced into
   whatever comes out: a plain integer form gets ".0" appended (125 -> "125.0") and an EXPONENT
   form gets ".0" inserted into its mantissa (1e+300 -> "1.0e+300", 3e+22 -> "3.0e+22").

   Two earlier deviations, both found by rendering values outside the range this schema actually
   stores and diffing against sqlite 3.45:
     - the exponent case was returned untouched, so 1e300 printed as "1e+300"
     - a [%.17g] fallback fired when [%.15g] did not round-trip, which prints a different
       mantissa than sqlite does (sqlite's text output is presentation and does NOT round-trip:
       123456789012345678.0 prints as "1.23456789012346e+17"). Matching sqlite means dropping it. *)
let float_to_string f =
  if Float.is_nan f then "NaN"
  else if Float.is_integer f && Float.abs f < 1e15 then Printf.sprintf "%.1f" f
  else
    let s = Printf.sprintf "%.15g" f in
    if String.exists (fun c -> c = 'n' || c = 'i') s then s (* inf / nan *)
    else
      match String.index_opt s 'e' with
      | Some i ->
          if String.contains (String.sub s 0 i) '.' then s
          else String.sub s 0 i ^ ".0" ^ String.sub s i (String.length s - i)
      | None -> if String.contains s '.' then s else s ^ ".0"

let string_of_cell = function
  | Nul -> ""
  | Int i -> string_of_int i
  | Text s -> s
  | Real f -> float_to_string f

(* ------------------------------------------------------------------ *)
(* request construction                                                *)
(* ------------------------------------------------------------------ *)

module Ty = Caqti_type.Std
open Caqti_request.Infix

(* [Sqlite3.prepare: no such column: s.channel] / [no such table: exn_origins] are the
   driver's verdict on a query that names something an OLDER index simply does not have
   yet — every consumer that skips a [has_col]/[has_table] guard and gets it wrong hits
   this. Left as {!Broken} (exit 2) it is indistinguishable from a locked file or a
   corrupt database: a crash, not an answer. Matching it here converts EVERY such site —
   including the ones no guard has been written for yet — into a {!Refused} that names
   the missing column/table and says the index predates it. This does not replace a
   targeted [has_col] guard (which can give a better-scoped message and let the caller
   answer something else instead of refusing outright) — it is the backstop for what a
   guard was not written for.

   {b What this backstop does and does not change, per binary.} It improves the MESSAGE
   everywhere; it does NOT make every binary exit 3, and an earlier version of this
   comment claimed it did. Exit 3 is not a repo-wide convention — it is a contract each
   tool signs separately, and only two have:

   - [arch-query] and [arch-report] map a query-time {!Refused} to exit 3 (see their
     [die 3] handlers). There the conversion really does turn a crash into a verdict.
   - [arch-impact] deliberately does not: [docs/change-impact.md] pins exit 3 to the
     [--fail-on-new-findings] refusal and keeps it in LOCKSTEP with the JSON [verdict]
     field, on the stated ground that exit 2 is the code with no stdout to parse. A
     schema-drift exit 3 printing no JSON would be exactly the confusion that section
     forbids.
   - [arch-rules] deliberately does not: [docs/fitness-functions.md] states it has no
     process-level sound-refusal path, and the tool already routes its own
     refusal-shaped aborts (an unknown [channel:], an undeclared origin [form:]) through
     [die] at exit 2. One refusal cause exiting 3 while its siblings exit 2 would make
     the tool's own exit vocabulary incoherent.
   - [arch-coverage] and [arch-mutants] follow the same [die]-at-2 convention.

   So in those four, a schema-drift {!Refused} is reported as an abort at exit 2 — but
   with THIS message rather than a raw [Sqlite3.prepare: no such column] or (before the
   top-level handlers were added alongside this comment) an uncaught
   [Fatal error: exception Arch_tools.Arch_db.Refused(…)] dump. That is the whole of what
   the backstop buys them, and it is worth having on its own.

   This also catches a genuine SQL typo in repo-authored code (a column name that never
   existed in ANY schema version), reported the same way as a real version-drift miss —
   "predates X, re-index with a newer producer" is then bad advice. Deliberately NOT
   distinguishing the two here: by the time [ok] sees the error, the query has already run
   against THIS connection, so [has_col_conn]/[has_table_conn] on it would only confirm
   what the driver already told us (the column is absent here) — there is no way to ask
   from inside this function whether the name was ever valid on any OTHER schema version,
   which is the only fact that would actually discriminate a typo from real drift. A typo
   in a query that runs unconditionally (no [has_col] guard in front of it) is instead
   caught by the test suite, which runs the whole CLI against the CURRENT schema on every
   build — a typo'd column name that is not the deliberate output of some future migration
   fails a real test with a wrong exit code, immediately, rather than lurking. Under-catch
   (syntax errors, [no such function], truncated SQL) is unaffected and stays {!Broken}. *)
let missing_schema_ref msg =
  let find_substring ~needle hay =
    let nlen = String.length needle and hlen = String.length hay in
    let rec loop i = if i + nlen > hlen then None else if String.sub hay i nlen = needle then Some i else loop (i + 1) in
    loop 0
  in
  let token_after prefix =
    match find_substring ~needle:prefix msg with
    | None -> None
    | Some idx ->
        let start = idx + String.length prefix in
        let rest = String.sub msg start (String.length msg - start) in
        let is_stop c = c = '"' || c = '\'' || c = ' ' || c = ')' || c = '\n' in
        let len = String.length rest in
        let j = ref 0 in
        while !j < len && not (is_stop rest.[!j]) do
          incr j
        done ;
        Some (String.sub rest 0 !j)
  in
  (* Caqti/sqlite terminate the whole clause with a sentence period before " Query: …" (e.g.
     ["no such column: nonexistent_col. Query: …"]) — [token_after]'s stop set does not include
     ['.'], so the captured token carries that trailing period. Strip it before anything else
     touches the token, or a table/column name that happens to contain no dot of its own (the
     common case) still comes out looking dot-terminated, and [bare_name]'s [rindex_opt '.']
     below then finds THAT period as the "qualifier" separator and returns the empty string. *)
  let strip_trailing_dot s =
    let n = String.length s in
    if n > 0 && s.[n - 1] = '.' then String.sub s 0 (n - 1) else s
  in
  (* sqlite qualifies a column with its table alias ("s.channel") and can qualify a table with
     its schema ("main.nosuch"); report the bare name in both cases. *)
  let bare_name s = match String.rindex_opt s '.' with Some i -> String.sub s (i + 1) (String.length s - i - 1) | None -> s in
  (* LOW-1: report the bare name AND, when they differ, the qualified token the query
     actually used. Two tables can carry a column of the same name (both [exn_scopes] and
     [exn_origins] carry [channel]), so "column channel" alone does not say WHICH of the
     query's tables was the old one — and the alias is often the only thing in the message
     that points back at a line of SQL. The bare name stays first because it is the name a
     reader greps the schema for; the alias is parenthetical because it is a coordinate in
     the failing query, not a schema fact. *)
  let describe kind raw =
    let bare = bare_name raw in
    if bare = raw then Printf.sprintf "%s %s" kind bare
    else Printf.sprintf "%s %s (written %s in the failing query)" kind bare raw
  in
  match token_after "no such column: " with
  | Some col -> Some (describe "column" (strip_trailing_dot col))
  | None -> (
      match token_after "no such table: " with
      | Some tbl -> Some (describe "table" (strip_trailing_dot tbl))
      | None -> None)

let ok = function
  | Ok v -> v
  | Error e -> (
      let msg = Caqti_error.show e in
      match missing_schema_ref msg with
      | Some what ->
          (* Do not append the raw Caqti/sqlite message here: the two per-command guards
             (escaping-origins, Arch_exn.load) are tested on the assumption that a refusal
             never surfaces "no such column" to the user (see
             tezt/tests/schema_column_guards.ml), and this backstop exists to give every
             OTHER site the same contract, not a laxer one. *)
          refuse "this index predates %s and should be re-indexed with a newer producer" what
      | None -> broken "%s" msg)

let collect t req p =
  let module Db = (val t.conn : C.CONNECTION) in
  ok (Db.collect_list req p)

let find t req p =
  let module Db = (val t.conn : C.CONNECTION) in
  ok (Db.find req p)

let find_opt t req p =
  let module Db = (val t.conn : C.CONNECTION) in
  ok (Db.find_opt req p)

(** A request whose SQL is assembled at runtime (schema branch, LIMIT). [oneshot] because a
    prepared-statement handle per assembled string would leak one per distinct limit. *)
let dyn pt rt sql = Caqti_request.create ~oneshot:true pt rt Caqti_mult.zero_or_more (fun _ -> Caqti_query.of_string_exn sql)

let dyn1 pt rt sql = Caqti_request.create ~oneshot:true pt rt Caqti_mult.one (fun _ -> Caqti_query.of_string_exn sql)

(* ------------------------------------------------------------------ *)
(* result row shapes                                                   *)
(* ------------------------------------------------------------------ *)

(** Every result shape arch-query and the tools can return, declared once.

    Hardcoding these is what makes the row types checked. The column HEADERS that go with them
    are supplied by the caller, and the differential gate against the tool being replaced is what
    proves they match sqlite's own [AS] aliases. *)
module Rows = struct
  open Ty

  let s = option string
  let i = option int
  let f = option float

  let t1 = s
  let t2' = t2 s s
  let t3' = t3 s s s
  let t4' = t4 s s s s
  let t5' = t5 s s s s s
  let t6' = t2 (t3 s s s) (t3 s s s)
  let t8' = t2 (t4 s s s s) (t4 s s s s)
  let s_i = t2 s i
  let s_s_i = t3 s s i
  let i_i_i = t3 i i i
  let mut = t2 (t3 s s i) (t3 i i f)
  let i_i = t2 i i

  (* A graph node: key, name, path, exported flag, and the two span ends. Declared once because
     both the flat and main schema SELECTs project into it. *)
  let node_shape = t2 (t3 s s s) (t3 i i i)

  (* useless-branches: file_path, line (INTEGER), function_name, verdict, decided_by, evidence.
     The int column is declared, so -json renders it as a number rather than a quoted string. *)
  let ub_shape = t2 (t3 s i s) (t3 s s s)

  (* low-coverage: path, name, percentage (REAL), covered_lines, total_lines. *)
  let cov_shape = t2 (t3 s s f) (t2 i i)

  (* unsafe-params: path, name, param_name, current_type, target_type, github_issue, fixed. *)
  let unsafe_shape = t2 (t5 s s s s s) (t2 i i)

  (* gardening open: github_issue, category, title, module_path, function_name, status, created_at. *)
  let task_shape = t2 (t3 i s s) (t4 s s s s)

  (* gardening log: date, contributor, category, description, pr_number, issue_number. *)
  let log_shape = t2 (t4 s s s s) (t2 i i)

  let c1 a = [ text_cell a ]
  let c2 (a, b) = [ text_cell a; text_cell b ]
  let c3 (a, b, c) = [ text_cell a; text_cell b; text_cell c ]
  let c4 (a, b, c, d) = List.map text_cell [ a; b; c; d ]
  let c5 (a, b, c, d, e) = List.map text_cell [ a; b; c; d; e ]
  let c6 ((a, b, c), (d, e, g)) = List.map text_cell [ a; b; c; d; e; g ]
  let c8 ((a, b, c, d), (e, g, h, i)) = List.map text_cell [ a; b; c; d; e; g; h; i ]
  let csi (a, b) = [ text_cell a; int_cell b ]
  let cssi (a, b, c) = [ text_cell a; text_cell b; int_cell c ]
  let ciii (a, b, c) = [ int_cell a; int_cell b; int_cell c ]
  let cmut ((a, b, c), (d, e, g)) =
    [ text_cell a; text_cell b; int_cell c; int_cell d; int_cell e; real_cell g ]

  let ub_cells ((fp, ln, fn), (v, by, ev)) =
    [ text_cell fp; int_cell ln; text_cell fn; text_cell v; text_cell by; text_cell ev ]

  let node_cells ((k, n, p), (ex, ls, le)) =
    [ text_cell k; text_cell n; text_cell p; int_cell ex; int_cell ls; int_cell le ]

  let cov_cells ((path, name, pct), (covered, total)) =
    [ text_cell path; text_cell name; real_cell pct; int_cell covered; int_cell total ]

  let unsafe_cells ((path, name, param, cur, tgt), (issue, fixed)) =
    [ text_cell path; text_cell name; text_cell param; text_cell cur; text_cell tgt; int_cell issue;
      int_cell fixed ]

  let task_cells ((issue, cat, title), (mpath, fname, status, created)) =
    [ int_cell issue; text_cell cat; text_cell title; text_cell mpath; text_cell fname;
      text_cell status; text_cell created ]

  let log_cells ((date, contrib, cat, desc), (pr, issue)) =
    [ text_cell date; text_cell contrib; text_cell cat; text_cell desc; int_cell pr; int_cell issue ]
end

(** Run assembled SQL of a DECLARED row shape and return display cells.

    [shape] is the Caqti row type, [to_cells] its projection into display cells. The pair is what
    replaces "decode whatever the driver returned": both are checked against the request. *)
let rows t ~params_ty ~shape ~to_cells sql params =
  List.map to_cells (collect t (dyn params_ty shape sql) params)

(* ------------------------------------------------------------------ *)
(* introspection                                                       *)
(* ------------------------------------------------------------------ *)

let quote_lit s = String.concat "''" (String.split_on_char '\'' s)

(** Escape [%], [_] and the escape character itself so a caller-supplied substring cannot be
    read as a LIKE wildcard — a search for the literal type name ["int_id"] must not also match
    ["intXid"]. Pair with [~ESCAPE '\\'] in the SQL and wrap the result in ['%' ... '%'] for a
    substring search. *)
let like_escape s =
  let buf = Buffer.create (String.length s) in
  String.iter
    (fun c ->
      (match c with '%' | '_' | '\\' -> Buffer.add_char buf '\\' | _ -> ()) ;
      Buffer.add_char buf c)
    s ;
  Buffer.contents buf

let like_contains s = "%" ^ like_escape s ^ "%"

let has_table_conn conn name =
  let module Db = (val conn : C.CONNECTION) in
  let req =
    Caqti_request.create ~oneshot:true Ty.unit Ty.int Caqti_mult.one (fun _ ->
        Caqti_query.of_string_exn
          (Printf.sprintf
             "SELECT count(*) FROM sqlite_master WHERE type IN ('table','view') AND name='%s'"
             (quote_lit name)))
  in
  match Db.find req () with Ok n -> n > 0 | Error _ -> false

let has_col_conn conn table col =
  let module Db = (val conn : C.CONNECTION) in
  let req =
    Caqti_request.create ~oneshot:true Ty.unit Ty.(option string) Caqti_mult.zero_or_more
      (fun _ -> Caqti_query.of_string_exn (Printf.sprintf "SELECT name FROM pragma_table_info('%s')" (quote_lit table)))
  in
  match Db.collect_list req () with
  | Ok names -> List.exists (fun n -> n = Some col) names
  | Error _ -> false

let has_table t name = has_table_conn t.conn name
let has_col t table col = has_col_conn t.conn table col

let meta_conn conn key =
  if not (has_table_conn conn "comment_db_meta") then None
  else
    let module Db = (val conn : C.CONNECTION) in
    let req =
      Ty.string ->? Ty.(option string) @@ "SELECT value FROM comment_db_meta WHERE key = ? LIMIT 1"
    in
    match Db.find_opt req key with Ok (Some v) -> v | _ -> None

let meta t key = meta_conn t.conn key

(* ------------------------------------------------------------------ *)
(* open                                                                *)
(* ------------------------------------------------------------------ *)

(** Open READ-ONLY. The name used to be aspirational: the connection was opened with the driver's
    default mode, which is read-write-and-create, so a stray write in a query tool would have
    silently mutated the index it was reporting on — and a typo'd path would have created an
    empty database rather than failing. [write=false] makes the driver pass [`READONLY] to
    [sqlite3_open_v2], which enforces it. ([arch-coverage --write] opens its own second
    connection precisely because this one cannot write.) *)
let open_ro path =
  if not (Sys.file_exists path) then broken "no such db: %s" path ;
  let uri = Uri.make ~scheme:"sqlite3" ~path ~query:[ ("write", [ "false" ]) ] () in
  let conn =
    match C.connect uri with
    | Ok c -> c
    | Error e -> broken "cannot open %s: %s" path (Caqti_error.show e)
  in
  if not (has_table_conn conn "functions") then
    broken "%s has no `functions` table — not an arch-index DB" path ;
  {
    conn;
    path;
    schema = (if has_col_conn conn "calls" "caller_name" then Flat else Main);
    kinded = has_col_conn conn "calls" "kind";
    contract = meta_conn conn "callgraph_contract";
  }

(** The SQL expression yielding an edge kind.

    A legacy index predating the edge-kind contract has no [kind] column {i at all}, so the
    column cannot even be named in a query. Every edge then reads as [MUST], and [contract] stays
    unset, which is what stops any closed-universe claim being made about such an index. *)
let kind_sql t = if t.kinded then "COALESCE(kind,'MUST')" else "'MUST'"

let count t sql =
  find t (dyn1 Ty.unit Ty.int sql) ()

let count1 t sql p = find t (dyn1 Ty.string Ty.int sql) p
let count2 t sql p = find t (dyn1 Ty.(t2 string string) Ty.int sql) p
let count4 t sql p = find t (dyn1 Ty.(t2 (t2 string string) (t2 string string)) Ty.int sql) p

(* ------------------------------------------------------------------ *)
(* contract enforcement                                                *)
(* ------------------------------------------------------------------ *)

(** Refuse any query whose NEGATIVE answer would be a soundness claim the index cannot support.

    The third check matters most: a [callgraph_contract] flag with even one NULL/invalid kind is
    worse than no flag, because SQL's three-valued logic makes that edge invisible to both the
    closure filter and the ⊤ check — a real dropped edge would read as a false-sound UNREACHABLE.
    Never trust the flag alone. *)
let require_contract t cmd =
  match t.contract with
  | None ->
      refuse
        "REFUSED — this index is NOT ⊤-marked (no 'callgraph_contract' meta flag).\n\
         arch-query: '%s' would be UNSOUND: a 'no path' result may merely hide a \
         silently-dropped\n\
         arch-query: dynamic/interface edge. Rebuild with a Tier-0+ backend that emits MAY_TOP \
         edges."
        cmd
  | Some _ ->
      if not t.kinded then
        refuse
          "REFUSED — 'callgraph_contract' is set but there is no 'kind' column: malformed \
           ⊤-marked index." ;
      let bad =
        count t
          "SELECT count(*) FROM calls WHERE kind IS NULL OR kind NOT IN \
           ('MUST','MAY_ENUMERATED','MAY_TOP')"
      in
      if bad <> 0 then
        refuse
          "REFUSED — %d call edge(s) have NULL/invalid kind, violating the ⊤-marking contract \
           (every edge must be MUST | MAY_ENUMERATED | MAY_TOP). Rebuild the index."
          bad

(** [contract_ok t cmd] is the one true answer to "is this index sound", verified rather than
    trusted: [true] iff {!require_contract} would accept [cmd] on [t] — the flag is set, [kind]
    exists, and no edge has a NULL/invalid kind. Prefer this over checking [t.contract <> None]
    directly: that weaker check is satisfied by a malformed index (flag set, but a NULL-kind edge
    present) that this one correctly refuses — see {!require_contract}'s doc comment. Every
    caller that reports index soundness (as text, as JSON, as an exit code) should derive it from
    here, so two tools can never report two different answers for the same index. *)
let contract_ok t cmd = try require_contract t cmd ; true with Refused _ -> false

(** Present {b and non-empty}. Presence proves nothing: [arch-load] creates [decisions]
    unconditionally, so table-existence would let "the producer computed nothing" read as "there
    is nothing to report" — the same false-confidence shape that made [v_pure_functions] certify
    every function pure on an empty effects table. *)
let nonempty t table =
  has_table t table && count t (Printf.sprintf "SELECT count(*) FROM %s" table) > 0
