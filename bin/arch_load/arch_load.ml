(** arch-load — build a ⊤-MARKED arch-index DB from a generic NDJSON call-edge stream.

    This is the WRITE side of the edge-kind contract ([arch-query] is the read side). Any Tier-0
    producer (a tree-sitter call-site shim) or Tier-1 producer (Go go/ssa+CHA, OCaml typedtree)
    emits NDJSON of function + call records; this loader builds a SQLite DB that [arch-query] can
    soundly query and — crucially — {b guarantees} the contract: every call edge has a valid
    [kind], and only then is the [callgraph_contract] flag set. An invalid or missing kind
    ABORTS. The loader is the enforcement point, so a ⊤-marked DB is never a lie.

    {1 STRICTNESS}

    Unknown record types and unknown fields ABORT. The loader already refuses a call edge with
    an invalid [kind] on the grounds that a silently-dropped edge is a lie; a silently-dropped
    FIELD is the same failure wearing a different hat — the producer author believes data was
    carried when it was not. Fields prefixed [x_] are reserved for producer-private extensions
    and are accepted-and-ignored, so a future field is not a breaking change. *)

let usage =
  {|arch-load — build a ⊤-marked arch-index DB from an NDJSON call-edge stream.

Usage:  arch-load [--allow-empty] [--producer=NAME] [--producer-version=V]
                   [--soundness-class=sound_with_top|heuristic|asserted]
                   <out.db> [input.ndjson]      (input defaults to stdin)
        --producer / --producer-version declare who emitted this NDJSON stream (roadmap 1.2);
        absent means NULL, never guessed. --soundness-class defaults to 'heuristic' (ADR 002's
        conservative default) — only an explicit flag can claim 'sound_with_top'.

NDJSON records (one JSON object per line; order-independent):
  function: {"type":"function","name":"f","file_path":"x.go","exported":true|false,
             "line_start":10,"line_end":42,"language":"go"}
            line_start/line_end are OPTIONAL but required for any per-diff or per-line join
            (arch-impact, arch-mutants, arch-coverage); without them a diff maps to a whole FILE.
            language is OPTIONAL (roadmap 1.1) — a producer that knows its own language should
            set it; absent means NULL, never guessed by this loader.
  call:     {"type":"call","caller_name":"f","caller_file":"x.go",
             "callee_name":"g","callee_file":"x.go"|null,"call_site":"x.go:12","kind":"MUST",
             "top_reason":"reflection","top_anchor":"x.go:12:5"}
            top_reason/top_anchor are OPTIONAL (roadmap 1.4) and meaningful only on a MAY_TOP
            edge — absent means NULL, never guessed. top_reason must be one of the agnostic
            vocabulary (see below) if given at all.
  decision: {"type":"decision","file_path":"x.go","line":42,"col":7,"form":"if",
             "arity":3,"verdict":"DEAD_SUBTERM","decided_by":"enumeration",
             "evidence":"...","snippet":"..."}
  dead_site:{"type":"dead_site","function_name":"f","call_site":"x.go:12","callee_name":"g"}
  `type` may be omitted: a record with "callee_name" is a call, else a function.
  kind ∈ {MUST, MAY_ENUMERATED, MAY_TOP}. A MAY_TOP edge's callee_name is conventionally "*TOP*".
  top_reason ∈ {callback_param, module_param, dropped_node, reflection, ffi, dynamic_load,
  dispatch_unbounded, trait_object, fn_pointer, extern} (see docs/edge-kind-contract.md).|}

let kinds = [ "MUST"; "MAY_ENUMERATED"; "MAY_TOP" ]

(* Roadmap 1.4 (⊤-anchor taxonomy). Mirrors architecture-schema.sql's
   [calls.top_reason] CHECK constraint exactly — kept as two copies for the
   same reason [kind]'s own vocabulary already is (this loader depends only
   on sqlite3+yojson, not the arch_index library that owns the schema
   text). Optional: unlike [kind], a MAY_TOP edge with no top_reason is not
   itself a contract violation (a producer that does not yet compute reasons
   can still emit sound MAY_TOP edges) — only an out-of-vocabulary VALUE, if
   one is given, is rejected. No producer in this codebase (callgraph-go,
   callgraph-rust) emits this field yet; accepting it here lays the tracks
   for when one does, per the same "documented, not silently dropped"
   discipline as the [language] field in roadmap 1.1. *)
let top_reasons =
  [
    "callback_param"; "module_param"; "dropped_node"; "reflection"; "ffi";
    "dynamic_load"; "dispatch_unbounded"; "trait_object"; "fn_pointer"; "extern";
  ]

(** The contract, field by field. Anything outside these sets aborts the load unless it is an
    [x_]-prefixed producer-private extension. *)
let fields = function
  | "function" ->
      [ "type"; "name"; "file_path"; "exported"; "line_start"; "line_end"; "language" ]
  | "call" ->
      [
        "type"; "caller_name"; "caller_file"; "callee_name"; "callee_file"; "call_site"; "kind";
        "top_reason"; "top_anchor";
      ]
  | "decision" ->
      [ "type"; "file_path"; "line"; "col"; "form"; "arity"; "verdict"; "decided_by"; "evidence";
        "snippet" ]
  | "dead_site" -> [ "type"; "function_name"; "call_site"; "callee_name" ]
  | _ -> []

let record_types = [ "call"; "dead_site"; "decision"; "function" ]

let die ?line fmt =
  Printf.ksprintf
    (fun s ->
      (match line with
      | Some n -> Printf.eprintf "arch-load: %s (line %d)\n" s n
      | None -> Printf.eprintf "arch-load: %s\n" s) ;
      exit 2)
    fmt

(* FIX (roadmap 1.1, found while adding the [language] column): this loader
   never stamped [comment_db_meta.schema_version] at all — a third, previously
   undiscovered instance of the exact silent-schema-drift bug class #51 was
   about (the other two were fixed in the schema-versioning task: the main
   schema, architecture-schema.sql, and runner.ml's own flat schema). This
   loader's schema is structurally identical to runner.ml's flat schema but
   written by an independent code path with its own evolution — deliberately
   NOT sharing a dependency on the arch_index library for one string constant
   (this binary depends only on sqlite3+yojson by design), so it gets its own
   local version identity, starting at "1.0" (the schema before this fix) and
   bumped to "1.1" for the [language] column added here. *)
let schema_version = "1.2"

let schema =
  {|
DROP TABLE IF EXISTS comment_db_meta;
DROP TABLE IF EXISTS functions;
DROP TABLE IF EXISTS calls;
CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT);
CREATE TABLE functions(name TEXT, file_path TEXT, exported INTEGER DEFAULT 0,
                       line_start INTEGER, line_end INTEGER, language TEXT);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT,
                   call_site TEXT, kind TEXT, top_reason TEXT, top_anchor TEXT);
CREATE INDEX idx_calls_caller ON calls(caller_name);
CREATE INDEX idx_calls_callee ON calls(callee_name);
DROP TABLE IF EXISTS decisions;
DROP TABLE IF EXISTS dead_code_sites;
CREATE TABLE decisions(file_path TEXT, line INTEGER, col INTEGER, form TEXT,
                       arity INTEGER, verdict TEXT, decided_by TEXT,
                       evidence TEXT, snippet TEXT, function_id INTEGER);
CREATE TABLE dead_code_sites(function_name TEXT, call_site TEXT, callee_name TEXT);
CREATE VIEW v_useless_branches AS
SELECT file_path, line, NULL AS function_name, form, verdict, decided_by, evidence, snippet
FROM decisions WHERE verdict NOT IN ('OK','HIGH_ARITY') ORDER BY file_path, line;
CREATE VIEW v_dead_code AS
SELECT NULL AS module_path, function_name, call_site, callee_name
FROM dead_code_sites ORDER BY function_name, call_site;
|}

(* ------------------------------------------------------------------ *)
(* JSON access, tolerant of the shapes producers actually emit          *)
(* ------------------------------------------------------------------ *)

let mem k assoc = List.mem_assoc k assoc

let str k assoc =
  match List.assoc_opt k assoc with
  | Some (`String s) -> Some s
  | Some `Null | None -> None
  | Some other -> Some (Yojson.Safe.to_string other)

let int_field k assoc =
  match List.assoc_opt k assoc with
  | Some (`Int n) -> Some n
  | Some (`Intlit s) -> int_of_string_opt s
  | _ -> None

let truthy k assoc =
  match List.assoc_opt k assoc with
  | Some (`Bool b) -> b
  | Some (`Int n) -> n <> 0
  | Some (`String s) -> s <> "" && s <> "false"
  | _ -> false

let starts_with ~prefix s =
  String.length s >= String.length prefix && String.sub s 0 (String.length prefix) = prefix

(* ------------------------------------------------------------------ *)

type fn = {
  file : string option;
  exported : bool;
  ls : int option;
  le : int option;
  language : string option;
}

(* Roadmap 1.2 (ADR 002): this loader is producer-agnostic by design (it
   depends on no producer-specific code), so provenance cannot be hardcoded
   the way runner.ml's own single-backend flat schema does — it must be
   DECLARED by whatever wrapped this invocation (the shell script that ran
   `callgraph-go`, say), via a flag, or left absent. Absent is not "unknown
   producer, assume sound" — [soundness_class] still defaults to the
   conservative 'heuristic' per ADR 002's governing rule; only an explicit
   flag can claim 'sound_with_top'. An invalid class ABORTS, matching this
   loader's own strictness discipline for [kind]. *)
(* [None] means "not present at all". A PRESENT-but-empty value (`--producer=`)
   is a near-certain shell-scripting bug (an unset variable substituted into
   the flag) — ABORTS rather than silently downgrading to "not declared",
   matching this loader's die-on-ambiguity philosophy for [kind] below. *)
let opt_flag_value args prefix =
  match
    List.find_map
      (fun a ->
        if starts_with ~prefix a then
          Some (String.sub a (String.length prefix) (String.length a - String.length prefix))
        else None)
      args
  with
  | Some "" -> die "%s must not be empty" prefix
  | v -> v

let provenance_flag_prefixes =
  [ "--producer="; "--producer-version="; "--soundness-class=" ]

let () =
  let args = List.tl (Array.to_list Sys.argv) in
  let allow_empty = List.mem "--allow-empty" args in
  let producer = opt_flag_value args "--producer=" in
  let producer_version = opt_flag_value args "--producer-version=" in
  let soundness_class =
    match opt_flag_value args "--soundness-class=" with
    | None -> "heuristic"
    | Some ("sound_with_top" | "heuristic" | "asserted") as v -> Option.get v
    | Some other ->
        die "invalid --soundness-class=%s (want sound_with_top|heuristic|asserted)" other
  in
  let args =
    List.filter
      (fun a ->
        a <> "--allow-empty"
        && not (List.exists (fun prefix -> starts_with ~prefix a) provenance_flag_prefixes))
      args
  in
  (* Any surviving `--`-looking argument is an unrecognised flag (a typo in
     one of the four above, most likely) — reject it rather than let it fall
     through to [out]/[input] below and silently create a database named
     after the misspelled flag. *)
  List.iter
    (fun a -> if starts_with ~prefix:"--" a then die "unrecognised flag: %s" a)
    args ;
  let out, input =
    match args with
    | [] ->
        prerr_endline usage ;
        exit 2
    | [ o ] -> (o, None)
    | o :: i :: _ -> (o, if i = "-" then None else Some i)
  in
  let ic =
    match input with
    | None -> stdin
    | Some f -> ( try open_in f with Sys_error e -> die "cannot open input: %s" e)
  in

  let funcs : (string, fn) Hashtbl.t = Hashtbl.create 1024 in
  (* Row order must be DETERMINISTIC and must match the tool being replaced: DECLARED functions
     in stream order, then the rows derived from edge endpoints. A hash-table iteration order
     is neither. This is not cosmetic — `SELECT ... WHERE name LIKE '%direct%' LIMIT 1` with no
     ORDER BY is answered by rowid, so a shuffled table silently changes which function a
     consumer gets back. *)
  let decl_order = ref [] in
  let seen_order = ref [] in
  let calls = ref [] in
  let decisions = ref [] in
  let dead_sites = ref [] in
  let seen : (string, unit) Hashtbl.t = Hashtbl.create 1024 in
  let lineno = ref 0 in

  (try
     while true do
       let raw = String.trim (input_line ic) in
       incr lineno ;
       if raw <> "" then (
         let json =
           try Yojson.Safe.from_string raw
           with Yojson.Json_error e -> die ~line:!lineno "invalid JSON: %s" e
         in
         let assoc =
           match json with
           | `Assoc a -> a
           | _ -> die ~line:!lineno "record is not a JSON object"
         in
         (* Classify FIRST, then validate the field set. An unknown type or an unknown field
            aborts — same posture as an invalid kind, for the same reason: a silent drop makes
            the producer author believe data was carried when it was not. *)
         let rtype =
           match str "type" assoc with
           | Some t -> t
           | None -> if mem "callee_name" assoc then "call" else "function"
         in
         if not (List.mem rtype record_types) then
           die ~line:!lineno "unknown record type %S; the contract is [%s]" rtype
             (String.concat "; " record_types) ;
         let allowed = fields rtype in
         List.iter
           (fun (k, _) ->
             if not (List.mem k allowed || starts_with ~prefix:"x_" k) then
               die ~line:!lineno
                 "unknown field %S on a %s record; the contract is [%s] (use an x_-prefixed name \
                  for a producer-private extension)"
                 k rtype (String.concat "; " allowed))
           assoc ;
         match rtype with
         | "decision" ->
             let verdict =
               match str "verdict" assoc with
               | Some v when v <> "" -> v
               | _ -> die ~line:!lineno "decision record missing verdict"
             in
             decisions :=
               ( str "file_path" assoc, int_field "line" assoc, int_field "col" assoc,
                 str "form" assoc, int_field "arity" assoc, verdict,
                 Option.value ~default:"unknown" (str "decided_by" assoc),
                 str "evidence" assoc, str "snippet" assoc )
               :: !decisions
         | "dead_site" ->
             (match str "callee_name" assoc with
             | None | Some "" -> die ~line:!lineno "dead_site record missing callee_name"
             | Some _ -> ()) ;
             dead_sites :=
               (str "function_name" assoc, str "call_site" assoc, str "callee_name" assoc)
               :: !dead_sites
         | "call" ->
             let kind =
               match str "kind" assoc with
               | Some k when List.mem k kinds -> k
               | other ->
                   (* ENFORCEMENT: the loader guarantees ⊤-marking. An un-kinded edge would be
                      invisible to the sound queries (a silent drop), so refuse rather than emit
                      a lie. *)
                   die ~line:!lineno
                     "call edge has missing/invalid kind %s; must be one of [%s]"
                     (match other with Some k -> "\"" ^ k ^ "\"" | None -> "None")
                     (String.concat "; " kinds)
             in
             let top_reason =
               match str "top_reason" assoc with
               | None -> None
               | Some r when not (List.mem r top_reasons) ->
                   die ~line:!lineno "call edge has invalid top_reason %S; must be one of [%s]"
                     r (String.concat "; " top_reasons)
               (* FIX (review, MEDIUM): mirrors architecture-schema.sql's own
                  CHECK(top_reason IS NULL OR kind = 'MAY_TOP') — a reason is
                  meaningless on a resolved/bounded-candidate edge, and this
                  loader is the enforcement point for exactly this kind of
                  malformed producer output. *)
               | Some r when kind <> "MAY_TOP" ->
                   die ~line:!lineno
                     "call edge has top_reason %S but kind %S — top_reason is only meaningful on \
                      a MAY_TOP edge"
                     r kind
               | Some r -> Some r
             in
             let caller = str "caller_name" assoc and callee = str "callee_name" assoc in
             (match (caller, callee) with
             | Some c, Some e when c <> "" && e <> "" ->
                 calls :=
                   ( c, str "caller_file" assoc, e, str "callee_file" assoc, str "call_site" assoc,
                     kind, top_reason, str "top_anchor" assoc )
                   :: !calls ;
                 List.iter
                   (fun n ->
                     if not (Hashtbl.mem seen n) then (
                       Hashtbl.replace seen n () ;
                       seen_order := n :: !seen_order))
                   [ c; e ]
             | _ -> die ~line:!lineno "call edge missing caller_name/callee_name")
         | _ ->
             let name =
               match str "name" assoc with
               | Some n when n <> "" -> n
               | _ -> die ~line:!lineno "function record missing name"
             in
             (* The ⊤ sentinel is not a real function, even if a producer emits a row for it. *)
             if name <> "*TOP*" then (
               (* A span is only usable if BOTH ends are present and ordered; a HALF span would
                  silently mis-map every diff line in the file, so it is refused outright. *)
               let ls = int_field "line_start" assoc and le = int_field "line_end" assoc in
               let ls, le =
                 match (ls, le) with
                 | Some a, Some b when a > 0 && a <= b -> (Some a, Some b)
                 | None, None -> (None, None)
                 | _ ->
                     if mem "line_start" assoc || mem "line_end" assoc then
                       die ~line:!lineno
                         "function %S has an unusable line span (line_start=%s, line_end=%s); both \
                          must be integers with 0 < line_start <= line_end, or both omitted"
                         name
                         (match ls with Some n -> string_of_int n | None -> "None")
                         (match le with Some n -> string_of_int n | None -> "None")
                     else (None, None)
               in
               if not (Hashtbl.mem funcs name) then decl_order := name :: !decl_order ;
               Hashtbl.replace funcs name
                 {
                   file = str "file_path" assoc;
                   exported = truthy "exported" assoc;
                   ls;
                   le;
                   language = str "language" assoc;
                 } ;
               if not (Hashtbl.mem seen name) then (
                 Hashtbl.replace seen name () ;
                 seen_order := name :: !seen_order)))
     done
   with End_of_file -> ()) ;
  if input <> None then close_in ic ;

  (* Derive a minimal row for any name seen only in edges, so find/stats/exported work. They go
     AFTER every declared function, as in the tool being replaced. *)
  let derived =
    List.filter (fun n -> n <> "*TOP*" && not (Hashtbl.mem funcs n)) (List.rev !seen_order)
  in
  List.iter
    (fun n ->
      Hashtbl.replace funcs n
        { file = None; exported = false; ls = None; le = None; language = None })
    derived ;
  let insert_order = List.rev !decl_order @ derived in

  (* FALSE-CONFIDENCE GUARD: a producer that silently failed emits nothing, yet the resulting
     ⊤-marked DB would declare EVERYTHING UNREACHABLE. *)
  if !calls = [] then (
    prerr_endline
      "arch-load: 0 call edges loaded — aborting to prevent a trust-stamped empty DB that would \
       report EVERYTHING as UNREACHABLE. Pass --allow-empty for a genuinely call-free module \
       (rare)." ;
    if not allow_empty then exit 2) ;

  let db = Sqlite3.db_open out in
  let exec sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> ()
    | rc -> die "schema failed: %s (%s)" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)
  in
  (* BEGIN comes FIRST, before the schema. `schema` starts with DROP TABLE IF EXISTS: running it
     outside a transaction means that reloading an existing index destroys it, and then any
     failure during the inserts leaves an EMPTY database where a working one used to be. SQLite
     is transactional over DDL, so the drop and the reload succeed or fail together. *)
  exec "BEGIN" ;
  exec schema ;
  (* A failed bind leaves the parameter NULL. Ignoring the return code therefore does not skip a
     row — it writes a row with a silently missing column, which is worse than not writing one. *)
  let bind_ck stmt i d =
    match Sqlite3.bind stmt i d with
    | Sqlite3.Rc.OK -> ()
    | rc -> die "bind of parameter %d failed: %s (%s)" i (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)
  in
  let bind_text_ck stmt i s = bind_ck stmt i (Sqlite3.Data.TEXT s) in
  let bind_opt stmt i = function
    | Some s -> bind_ck stmt i (Sqlite3.Data.TEXT s)
    | None -> bind_ck stmt i Sqlite3.Data.NULL
  in
  let bind_int_opt stmt i = function
    | Some n -> bind_ck stmt i (Sqlite3.Data.INT (Int64.of_int n))
    | None -> bind_ck stmt i Sqlite3.Data.NULL
  in
  let run stmt =
    (match Sqlite3.step stmt with
    | Sqlite3.Rc.DONE -> ()
    | rc -> die "insert failed: %s (%s)" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)) ;
    ignore (Sqlite3.reset stmt)
  in
  let meta = Sqlite3.prepare db "INSERT INTO comment_db_meta(key,value) VALUES(?,?)" in
  let put_meta k v =
    bind_text_ck meta 1 k ;
    bind_text_ck meta 2 v ;
    run meta
  in
  put_meta "callgraph_contract" "v1" ;
  put_meta "built_by" "arch-load" ;
  put_meta "schema_version" schema_version ;
  (* Roadmap 1.2 (ADR 002). [producer]/[producer_version] are written only
     when declared via a flag — an absent [producer] key means "not
     declared", never a guess. [soundness_class] always writes (its own
     default is the conservative 'heuristic'). [invocation_digest] is an MD5
     identity fingerprint over (producer, producer_version, argv) — Stdlib
     [Digest], computed locally rather than depending on the arch_index
     library's own [Arch_index_db.invocation_digest] for one function: this
     binary's independence from that library (sqlite3+yojson only) is
     deliberate, per its own top-of-file documentation. *)
  Option.iter (put_meta "producer") producer ;
  Option.iter (put_meta "producer_version") producer_version ;
  put_meta "soundness_class" soundness_class ;
  put_meta
    "invocation_digest"
    (Digest.to_hex
       (Digest.string
          (String.concat
             "\x00"
             (Option.value producer ~default:""
             :: Option.value producer_version ~default:""
             :: Array.to_list Sys.argv)))) ;

  let sf =
    Sqlite3.prepare db
      "INSERT INTO functions(name,file_path,exported,line_start,line_end,language) \
       VALUES(?,?,?,?,?,?)"
  in
  List.iter
    (fun n ->
      let f = Hashtbl.find funcs n in
      bind_text_ck sf 1 n ;
      bind_opt sf 2 f.file ;
      bind_ck sf 3 (Sqlite3.Data.INT (if f.exported then 1L else 0L)) ;
      bind_int_opt sf 4 f.ls ;
      bind_int_opt sf 5 f.le ;
      bind_opt sf 6 f.language ;
      run sf)
    insert_order ;
  ignore (Sqlite3.finalize sf) ;

  let sc =
    Sqlite3.prepare db
      "INSERT INTO calls(caller_name,caller_file,callee_name,callee_file,call_site,kind,\
       top_reason,top_anchor) VALUES(?,?,?,?,?,?,?,?)"
  in
  List.iter
    (fun (cn, cf, en, ef, site, kind, top_reason, top_anchor) ->
      bind_text_ck sc 1 cn ;
      bind_opt sc 2 cf ;
      bind_text_ck sc 3 en ;
      bind_opt sc 4 ef ;
      bind_opt sc 5 site ;
      bind_text_ck sc 6 kind ;
      bind_opt sc 7 top_reason ;
      bind_opt sc 8 top_anchor ;
      run sc)
    (List.rev !calls) ;
  ignore (Sqlite3.finalize sc) ;

  if !decisions <> [] then (
    let sd =
      Sqlite3.prepare db
        "INSERT INTO decisions(file_path,line,col,form,arity,verdict,decided_by,evidence,snippet) \
         VALUES(?,?,?,?,?,?,?,?,?)"
    in
    List.iter
      (fun (fp, line, col, form, arity, verdict, by, ev, sn) ->
        bind_opt sd 1 fp ;
        bind_int_opt sd 2 line ;
        bind_int_opt sd 3 col ;
        bind_opt sd 4 form ;
        bind_int_opt sd 5 arity ;
        bind_text_ck sd 6 verdict ;
        bind_text_ck sd 7 by ;
        bind_opt sd 8 ev ;
        bind_opt sd 9 sn ;
        run sd)
      (List.rev !decisions) ;
    ignore (Sqlite3.finalize sd) ;
    (* Stamped ONLY when a producer actually supplied the analysis, so a consumer can tell
       "computed nothing" from "computed nothing to report". *)
    put_meta "decision_contract" "v1") ;

  if !dead_sites <> [] then (
    let ss =
      Sqlite3.prepare db
        "INSERT INTO dead_code_sites(function_name,call_site,callee_name) VALUES(?,?,?)"
    in
    List.iter
      (fun (fn, site, callee) ->
        bind_opt ss 1 fn ;
        bind_opt ss 2 site ;
        bind_opt ss 3 callee ;
        run ss)
      (List.rev !dead_sites) ;
    ignore (Sqlite3.finalize ss)) ;

  ignore (Sqlite3.finalize meta) ;
  exec "COMMIT" ;
  ignore (Sqlite3.db_close db) ;

  let count k = List.length (List.filter (fun (_, _, _, _, _, x, _, _) -> x = k) !calls) in
  Printf.eprintf
    "arch-load: wrote %s — %d functions, %d calls (MUST=%d MAY_ENUMERATED=%d MAY_TOP=%d); \
     callgraph_contract=v1\n"
    out (Hashtbl.length funcs) (List.length !calls) (count "MUST") (count "MAY_ENUMERATED")
    (count "MAY_TOP")
