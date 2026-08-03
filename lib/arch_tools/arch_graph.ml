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
        "SELECT '#'||f.id, f.name, m.path, COALESCE(f.exposed,0), f.line_start, f.line_end \
         FROM functions f JOIN modules m ON f.module_id = m.id"
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

let label g key =
  match SM.find_opt key g.nodes with
  | Some n -> ( match n.file with Some f -> Printf.sprintf "%s  (%s)" n.name f | None -> n.name)
  | None ->
      if String.length key > 4 && String.sub key 0 4 = "ext:" then
        String.sub key 4 (String.length key - 4)
      else key

let nodes g = SM.bindings g.nodes |> List.map snd
let find_by_name g name = List.filter (fun n -> n.name = name) (nodes g)
let keys_of g = SM.fold (fun k _ acc -> SS.add k acc) g.nodes SS.empty
