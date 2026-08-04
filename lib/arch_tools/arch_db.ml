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

let ok = function Ok v -> v | Error e -> broken "%s" (Caqti_error.show e)

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
