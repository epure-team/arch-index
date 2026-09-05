(** The call graph, keyed correctly for whichever schema is in front of us.

    {1 Why the key is not the name}

    On the main schema [functions] is [UNIQUE(module_id, name)], so a name is unique only
    {i within} its module. Keying the graph by name there silently merges same-named functions
    from different modules and inflates every closure. Resolved and unresolved callees also live
    in different namespaces ([callee_id] FK vs a qualified [callee_name] string), so a name join
    finds {b zero} callers for a function that has them.

    So: the key is the row id on the main schema and the name on the flat one, where names are
    already global. Callers see an opaque {!key} and a separate display label. *)

module SM = Map.Make (String)
module SS = Set.Make (String)

type key = string

type node = {
  key : key;
  name : string;
  file : string option;
  exported : bool;
  line_start : int option;
  line_end : int option;
}

type t = {
  nodes : node SM.t;
  fwd : SS.t SM.t;  (** MUST ∪ MAY_ENUMERATED, forward *)
  bwd : SS.t SM.t;  (** the same edges, reversed *)
  must_fwd : SS.t SM.t;  (** MUST only — a positive here is ground truth *)
  tops : int SM.t;  (** key → number of ⊤ edges it holds *)
}

let top_sentinel = "*TOP*"

(* Typed accessors. These replaced string re-parsing (`if s = "" then None else
   int_of_string_opt s`), which conflated a NULL span with a zero-length one and could not tell
   an empty file path from an absent one. *)
let text = function Arch_db.Text s -> Some s | _ -> None
let int_of = function
  | Arch_db.Int i -> Some i
  | Arch_db.Text s -> int_of_string_opt s
  | _ -> None
let bool_of = function Arch_db.Int i -> i <> 0 | _ -> false
let str = function Arch_db.Text s -> s | c -> Arch_db.string_of_cell c

let load_nodes (db : Arch_db.t) =
  let sql =
    match db.schema with
    | Arch_db.Flat ->
        "SELECT name, name, file_path, COALESCE(exported,0), line_start, line_end FROM functions"
    | Arch_db.Main ->
        (* LEFT, not INNER: a `functions` row whose `module_id` does not join is still an
           INTERNAL function — it must still become a node, with [file = None], or it falls out
           of [nodes] while its edges (built straight off [calls.caller_id]/[callee_id] in
           [load], independently of this join) survive, and [ext_keys] — "in [bwd], absent from
           [nodes]" — would then misclassify it as an external leaf. This cannot happen from any
           producer in this repo (FKs are on; `arch_index.ml` is the sole writer), so this join
           guards a foreign/malformed-DB case, not a live one. *)
        "SELECT '#'||f.id, f.name, m.path, COALESCE(f.exposed,0), f.line_start, f.line_end \
         FROM functions f LEFT JOIN modules m ON f.module_id = m.id"
  in
  let rows =
    Arch_db.rows db ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.node_shape
      ~to_cells:Arch_db.Rows.node_cells sql ()
  in
  List.fold_left
    (fun acc r ->
      match r with
      | [ key; name; file; exported; ls; le ] ->
          let key = str key in
          SM.add key
            { key; name = str name; file = text file; exported = bool_of exported;
              line_start = int_of ls; line_end = int_of le }
            acc
      | _ -> acc)
    SM.empty rows

let add_edge m a b =
  SM.update a (function None -> Some (SS.singleton b) | Some s -> Some (SS.add b s)) m

let load (db : Arch_db.t) =
  let nodes = load_nodes db in
  let k = Arch_db.kind_sql db in
  let sql =
    match db.schema with
    | Arch_db.Flat ->
        Printf.sprintf "SELECT caller_name, callee_name, %s FROM calls" k
    | Arch_db.Main ->
        (* An UNRESOLVED callee (callee_id IS NULL — a call to a name outside the indexed set)
           becomes an `ext:` leaf. It must stay in the graph rather than be dropped: it is a
           real successor, it just has no body here, and dropping it understates the blast
           radius — the wrong direction. *)
        Printf.sprintf
          "SELECT '#'||caller_id, CASE WHEN callee_id IS NULL THEN 'ext:'||callee_name ELSE \
           '#'||callee_id END, %s FROM calls"
          k
  in
  let rows =
    Arch_db.rows db ~params_ty:Arch_db.Ty.unit ~shape:Arch_db.Rows.t3'
      ~to_cells:Arch_db.Rows.c3 sql ()
  in
  let fwd, bwd, must_fwd, tops =
    List.fold_left
      (fun (fwd, bwd, must, tops) r ->
        match List.map str r with
        | [ caller; callee; kind ] ->
            (* A ⊤ edge does not go anywhere in particular, it goes everywhere, so following it
               would make every closure the whole program. It is recorded as a frontier marker
               instead — never dropped, never traversed. *)
            if kind = "MAY_TOP" || callee = top_sentinel || callee = "ext:" ^ top_sentinel then
              ( fwd, bwd, must,
                SM.update caller
                  (function None -> Some 1 | Some n -> Some (n + 1))
                  tops )
            else
              ( add_edge fwd caller callee,
                add_edge bwd callee caller,
                (if kind = "MUST" then add_edge must caller callee else must),
                tops )
        | _ -> (fwd, bwd, must, tops))
      (SM.empty, SM.empty, SM.empty, SM.empty)
      rows
  in
  { nodes; fwd; bwd; must_fwd; tops }

(** Transitive closure of [seeds] under [adj], {b excluding} the seeds themselves. *)
let closure seeds adj =
  let rec go seen stack =
    match stack with
    | [] -> seen
    | x :: rest ->
        let succ = match SM.find_opt x adj with Some s -> s | None -> SS.empty in
        let seen, stack =
          SS.fold
            (fun n (seen, stack) ->
              if SS.mem n seen then (seen, stack) else (SS.add n seen, n :: stack))
            succ (seen, rest)
        in
        go seen stack
  in
  SS.diff (go seeds (SS.elements seeds)) seeds

(* Shared BFS core for every witness-path query below. [seeds] may be a single key or several —
   a `reach` rule's source selector is a SET, and the shortest path a reviewer wants is the
   shortest from ANY seed, not an arbitrary one. [stop] decides early termination: given the node
   just discovered, is it (or does it satisfy) the thing we are looking for? Returns the key that
   satisfied [stop], or [None] if the frontier is exhausted first. *)
let bfs_search ~adj ~seeds ~stop =
  let parent = Hashtbl.create 64 in
  let q = Queue.create () in
  SS.iter
    (fun s ->
      if not (Hashtbl.mem parent s) then begin
        Hashtbl.replace parent s s ;
        Queue.push s q
      end)
    seeds ;
  let found = ref None in
  while Option.is_none !found && not (Queue.is_empty q) do
    let x = Queue.pop q in
    if stop x then found := Some x
    else
      let succ = match SM.find_opt x adj with Some s -> s | None -> SS.empty in
      SS.iter
        (fun n ->
          if not (Hashtbl.mem parent n) then begin
            Hashtbl.replace parent n x ;
            Queue.push n q
          end)
        succ
  done ;
  match !found with
  | None -> None
  | Some target ->
      let rec build acc cur =
        let p = Hashtbl.find parent cur in
        if p = cur then cur :: acc else build (cur :: acc) p
      in
      Some (build [] target)

(** [shortest_path g ~from ~to_] is the BFS-shortest sequence of keys from [from] to [to_]
    inclusive, over the resolved edges ([fwd] — MUST ∪ MAY_ENUMERATED, the same set a
    reachability {!closure} follows). [None] when [to_] is unreachable from [from]. A key absent
    from the graph is reachable only from (and to) itself: [shortest_path g ~from:k ~to_:k] is
    [Some [k]] for ANY [k], present or not — [bfs_search] never consults {!t.nodes}, only the
    edge maps. A ⊤ frontier is never part of a path: [fwd] already excludes it (see {!load}) —
    that is what {!witness_to_top} is for. *)
let shortest_path g ~from ~to_ =
  bfs_search ~adj:g.fwd ~seeds:(SS.singleton from) ~stop:(fun x -> x = to_)

(** [shortest_path_from_set ~adj ~from ~to_] is {!shortest_path}, generalised to a SET of
    starting seeds — the shortest path from whichever seed reaches [to_] first. This is what a
    `reach` rule needs: its source selector is a set, and the rule's own VIOLATION/POSSIBLE
    verdict already says {i some} seed reaches the target, not which one. [adj] lets the caller
    choose [g.must_fwd] (a VIOLATION's own proof edges) or [g.fwd] (a POSSIBLE's wider cone). *)
let shortest_path_from_set ~adj ~from ~to_ =
  bfs_search ~adj ~seeds:from ~stop:(fun x -> x = to_)

(** [witness_to_top g ~from] is the shortest path (inclusive of [from]) to the nearest key that
    itself carries a ⊤ edge ([SM.mem key g.tops]) — concrete evidence for why a reachability
    query returned UNKNOWN rather than PASS: the source cone escapes exactly here. [None] when no
    such node is reachable. *)
let witness_to_top g ~from =
  bfs_search ~adj:g.fwd ~seeds:(SS.singleton from) ~stop:(fun x -> SM.mem x g.tops)

let ext_prefix = "ext:"

let has_ext_prefix k =
  String.length k > String.length ext_prefix
  && String.sub k 0 (String.length ext_prefix) = ext_prefix

(** The name as written at the call site: what a report shows and what a rule author can be asked
    to type. Strips [Main]'s prefix; [Flat]'s keys carry none. *)
let ext_name k =
  if has_ext_prefix k then
    String.sub k (String.length ext_prefix) (String.length k - String.length ext_prefix)
  else k

let label g key =
  match SM.find_opt key g.nodes with
  | Some n -> ( match n.file with Some f -> Printf.sprintf "%s  (%s)" n.name f | None -> n.name)
  | None -> ext_name key

(** External leaves: keys that appear as a call TARGET but have no indexed body.

    The definition is structural — {b in [bwd], absent from [nodes]} — and deliberately not "the
    key starts with [ext:]". The two schemas spell an unresolved callee differently: [Main] stores
    it as ["ext:" ^ callee_name] (see [load]), while [Flat] stores the bare [callee_name], which is
    indistinguishable from a resolved one by shape alone. A prefix test would therefore work on
    [Main] and silently return the EMPTY SET on [Flat] — a selector that quietly matches nothing is
    exactly the failure this vocabulary exists to prevent, so it is defined once, on the property
    both schemas share.

    Reading them off [bwd] (keyed by callee) rather than scanning [fwd]'s values is both cheaper
    and exact.

    Note what this set does NOT contain: a ⊤ edge never reaches [bwd] at all ([load] counts it in
    [tops] instead), so these are exactly the NULL-callee MUST and MAY_ENUMERATED targets — the
    calls asserted to happen towards something we do not hold.

    {b Exactness.} "Absent from [nodes]" is exact — never a false external — PROVIDED every
    internal function is guaranteed a node. [load_nodes] arranges that with a LEFT (not INNER)
    join on [Main]: an internal function whose [module_id] fails to join still gets a node (with
    [file = None]) rather than silently dropping out while its edges, built independently off
    [calls.caller_id]/[callee_id], survive. On a DB where that invariant does not hold — one
    written by something other than this repo's own producer — this can still return a false
    external for a genuinely internal, unjoinable function. *)
let ext_keys g =
  SM.fold (fun k _ acc -> if SM.mem k g.nodes then acc else SS.add k acc) g.bwd SS.empty

let nodes g = SM.bindings g.nodes |> List.map snd
let find_by_name g name = List.filter (fun n -> n.name = name) (nodes g)
let keys_of g = SM.fold (fun k _ acc -> SS.add k acc) g.nodes SS.empty
