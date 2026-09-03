(** Transitive, handler-aware may-raise sets (specs/exn-raise-sets.md).

    {1 Lattice}

    Per node: [Known s] — a finite set of canonical exception paths, a sound
    over-approximation of what may escape — or [Top rs], unbounded, with one
    reason per witness (a [MAY_TOP] edge, an external callee not in the index,
    a [raise] of a non-literal value; a dropped callee is already a [MAY_TOP]
    edge in [calls]). [Top] absorbs; the
    universe of paths is finite (those in the DB), the join is monotone, so the
    worklist terminates.

    {1 Handler subtraction at CALL sites}

    An edge [n → m] carries the innermost handler scope enclosing its call
    site in [n]; walking that scope's parent chain gives [close_S]:
    ∅ when any scope is a catch-all, otherwise [raises(m) − ⋃ caught]. ⊤
    minus a finite set stays ⊤ — only a catch-all closes ⊤. This is applied
    once per edge; [raises(m)] already has [m]'s own handlers applied to
    [m]'s edges, so multi-hop chains compose by induction.

    {1 Not analysed}

    A DB whose producer emitted no exception rows has no
    [comment_db_meta.exn_contract]; every entry point refuses rather than
    answer "raises nothing". *)

module SM = Map.Make (String)
module SS = Set.Make (String)

type reason_kind = May_top_edge | External | Unknown_exn_value

let reason_kind_to_string = function
  | May_top_edge -> "may_top_edge"
  | External -> "external"
  | Unknown_exn_value -> "unknown_exn_value"

(* Dominant-reason order for exn-stats (spec C-8). *)
let reason_rank = function
  | May_top_edge -> 0
  | External -> 1
  | Unknown_exn_value -> 2

type reason = {kind : reason_kind; witness : string}

module RS = Set.Make (struct
  type t = reason

  let compare a b =
    match compare (reason_rank a.kind) (reason_rank b.kind) with
    | 0 -> compare a.witness b.witness
    | c -> c
end)

(* [Top (known, reasons)]: unbounded, but the part we DO know may escape is
   kept and reported — a ⊤ verdict never hides a resolved exception. *)
type set = Known of SS.t | Top of SS.t * RS.t

type scope = {parent : int option; catch_all : bool; caught : SS.t}

type edge = {callee : string; kind : string; scope : int option; site : string}

type origin = {o_node : string; o_form : string; o_path : string option; o_escapes : bool}

type t = {
  names : string SM.t;  (** key → display name *)
  files : string SM.t;
  by_name : string list SM.t;  (** name → keys *)
  edges : edge list SM.t;  (** caller key → out edges (MUST ∪ MAY_ENUMERATED ∪ MAY_TOP) *)
  scopes : scope SM.t;  (** scope id (as string) → scope *)
  origins : origin list SM.t;  (** node key → origins *)
  rebinds : string SM.t;
  n_origins : int;
  n_scopes : int;
  n_escaping : int;
}

let not_analysed =
  "NOT_ANALYSED: this index has no exception sites (its producer did not emit them). Rebuild \
   with arch-callgraph-ocaml — the CMT producer — to get raises / raisers-of / exn-stats."

(** Fixed table of [Stdlib] leaves that contribute nothing as CALLEES:

    - heads whose effect the producer already recorded as an origin at the
      call site (raise family, failwith/invalid_arg, comparison, integer
      division, bounds-checked access);
    - primitives that cannot raise (ignore, boolean/integer/float arithmetic,
      bit operations, projections, references, physical equality,
      int/float conversions, application operators).

    Everything else outside the index — [List.hd], [Hashtbl.find], I/O — is
    ⊤ [external] unless the caller states the [externals_pure] hypothesis. *)
let known_leaf name =
  match name with
  (* effect recorded as an origin *)
  | "Stdlib.raise" | "Stdlib.raise_notrace" | "Stdlib.failwith" | "Stdlib.invalid_arg"
  | "Stdlib.exit" | "Stdlib.Printexc.raise_with_backtrace" | "Stdlib.=" | "Stdlib.<>"
  | "Stdlib.<" | "Stdlib.>" | "Stdlib.<=" | "Stdlib.>=" | "Stdlib.compare" | "Stdlib./"
  | "Stdlib.mod" | "Stdlib.Int32.div" | "Stdlib.Int32.rem" | "Stdlib.Int64.div"
  | "Stdlib.Int64.rem" | "Stdlib.Nativeint.div" | "Stdlib.Nativeint.rem" | "Stdlib.Array.get"
  | "Stdlib.Array.set" | "Stdlib.String.get" | "Stdlib.Bytes.get" | "Stdlib.Bytes.set"
  (* cannot raise *)
  | "Stdlib.ignore" | "Stdlib.not" | "Stdlib.&&" | "Stdlib.||" | "Stdlib.&" | "Stdlib.or"
  | "Stdlib.+" | "Stdlib.-" | "Stdlib.*" | "Stdlib.~-" | "Stdlib.~+" | "Stdlib.succ"
  | "Stdlib.pred" | "Stdlib.land" | "Stdlib.lor" | "Stdlib.lxor" | "Stdlib.lnot" | "Stdlib.lsl"
  | "Stdlib.lsr" | "Stdlib.asr" | "Stdlib.+." | "Stdlib.-." | "Stdlib.*." | "Stdlib./."
  | "Stdlib.~-." | "Stdlib.~+." | "Stdlib.**" | "Stdlib.float_of_int" | "Stdlib.int_of_float"
  | "Stdlib.float" | "Stdlib.truncate" | "Stdlib.fst" | "Stdlib.snd" | "Stdlib.|>" | "Stdlib.@@"
  | "Stdlib.ref" | "Stdlib.!" | "Stdlib.:=" | "Stdlib.incr" | "Stdlib.decr" | "Stdlib.=="
  | "Stdlib.!=" | "Stdlib.Array.length" | "Stdlib.String.length" | "Stdlib.Bytes.length" ->
      true
  | _ -> false

let text = function Some s -> s | None -> ""

let load (t : Arch_db.t) =
  if t.schema = Arch_db.Flat then Arch_db.refuse "%s" not_analysed ;
  (match Arch_db.meta t "exn_contract" with
  | Some _ when Arch_db.has_table t "exn_origins" -> ()
  | _ -> Arch_db.refuse "%s" not_analysed) ;
  let q shape sql = Arch_db.collect t (Arch_db.dyn Arch_db.Ty.unit shape sql) () in
  let s = Arch_db.Rows.s and i = Arch_db.Rows.i in
  let names, files, by_name =
    List.fold_left
      (fun (names, files, by_name) (k, n, f) ->
        let k = text k and n = text n in
        ( SM.add k n names,
          SM.add k (text f) files,
          SM.update n (function None -> Some [k] | Some l -> Some (k :: l)) by_name ))
      (SM.empty, SM.empty, SM.empty)
      (q
         Arch_db.Ty.(t3 s s s)
         "SELECT '#'||f.id, f.name, m.path FROM functions f JOIN modules m ON f.module_id=m.id \
          ORDER BY f.id")
  in
  let edges =
    List.fold_left
      (fun acc ((caller, callee, kind), (scope, site)) ->
        let e = {callee = text callee; kind = text kind; scope; site = text site} in
        SM.update (text caller) (function None -> Some [e] | Some l -> Some (e :: l)) acc)
      SM.empty
      (q
         Arch_db.Ty.(t2 (t3 s s s) (t2 i s))
         (Printf.sprintf
            "SELECT '#'||c.caller_id, CASE WHEN c.callee_id IS NULL THEN 'ext:'||c.callee_name \
             ELSE '#'||c.callee_id END, %s, l.scope_id, COALESCE(c.call_site,'') FROM calls c \
             LEFT JOIN call_exn_scopes l ON l.call_id=c.id ORDER BY c.id"
            (Arch_db.kind_sql t)))
  in
  (* edges were consed in reverse; restore call order for deterministic provenance *)
  let edges = SM.map List.rev edges in
  let rebinds =
    List.fold_left
      (fun acc (a, b) -> SM.add (text a) (text b) acc)
      SM.empty
      (q Arch_db.Ty.(t2 s s) "SELECT alias_path, target_path FROM exn_rebinds")
  in
  (* [exception Alias = Target]: both sides of every set operation are
     canonical, so the caught side is canonicalised at load (FR-014). *)
  let canon_r p =
    let rec go p n = match SM.find_opt p rebinds with Some q when n < 16 -> go q (n + 1) | _ -> p in
    go p 0
  in
  let catches =
    List.fold_left
      (fun acc (sid, p) ->
        match sid with
        | None -> acc
        | Some sid ->
            let p = canon_r (text p) in
            SM.update (string_of_int sid)
              (function None -> Some (SS.singleton p) | Some x -> Some (SS.add p x))
              acc)
      SM.empty
      (q Arch_db.Ty.(t2 i s) "SELECT scope_id, exn_path FROM exn_scope_catches")
  in
  let scopes =
    List.fold_left
      (fun acc (id, parent, catch_all) ->
        match id with
        | None -> acc
        | Some id ->
            let id = string_of_int id in
            SM.add id
              {
                parent;
                catch_all = catch_all = Some 1;
                caught = (match SM.find_opt id catches with Some x -> x | None -> SS.empty);
              }
              acc)
      SM.empty
      (q Arch_db.Ty.(t3 i i i) "SELECT id, parent_id, catch_all FROM exn_scopes")
  in
  let n_origins = ref 0 and n_escaping = ref 0 in
  let origins =
    List.fold_left
      (fun acc ((fid, form), (path, escapes)) ->
        match fid with
        | None -> acc
        | Some fid ->
            incr n_origins ;
            let o_escapes = escapes = Some 1 in
            if o_escapes then incr n_escaping ;
            let o = {o_node = "#" ^ string_of_int fid; o_form = text form; o_path = path; o_escapes} in
            SM.update o.o_node (function None -> Some [o] | Some l -> Some (o :: l)) acc)
      SM.empty
      (q Arch_db.Ty.(t2 (t2 i s) (t2 s i))
         "SELECT function_id, form, exn_path, escapes FROM exn_origins ORDER BY id")
  in
  {
    names;
    files;
    by_name;
    edges;
    scopes;
    origins;
    rebinds;
    n_origins = !n_origins;
    n_scopes = SM.cardinal scopes;
    n_escaping = !n_escaping;
  }

(** Follow [exception A = B] chains (bounded, in case of a cycle). *)
let canon t p =
  let rec go p n = match SM.find_opt p t.rebinds with Some q when n < 16 -> go q (n + 1) | _ -> p in
  go p 0

(* ------------------------------------------------------------------ *)
(* Lattice                                                             *)
(* ------------------------------------------------------------------ *)

let join a b =
  match (a, b) with
  | Known x, Known y -> Known (SS.union x y)
  | Top (kx, rx), Top (ky, ry) -> Top (SS.union kx ky, RS.union rx ry)
  | Top (k, r), Known s | Known s, Top (k, r) -> Top (SS.union k s, r)

let equal a b =
  match (a, b) with
  | Known x, Known y -> SS.equal x y
  | Top (kx, rx), Top (ky, ry) -> SS.equal kx ky && RS.equal rx ry
  | _ -> false

let known_part = function Known s -> s | Top (k, _) -> k

(** [close t scope set]: apply the scope chain enclosing a call site. *)
let close t scope set =
  let rec chain acc = function
    | None -> Some acc
    | Some id -> (
        match SM.find_opt (string_of_int id) t.scopes with
        | None -> Some acc
        | Some s -> if s.catch_all then None else chain (SS.union acc s.caught) s.parent)
  in
  match chain SS.empty scope with
  | None -> Known SS.empty
  | Some caught -> (
      let sub s = SS.filter (fun p -> not (SS.mem (canon t p) caught)) s in
      match set with
      | Known s -> Known (sub s)
      | Top (k, r) -> Top (sub k, r) (* ⊤ − finite = ⊤; its known part still shrinks *))

let top kind witness = Top (SS.empty, RS.singleton {kind; witness})

(** Direct contribution of a node: its escaping literal origins, ⊤ for an
    escaping unknown value. Re-raise origins contribute nothing — the
    non-closing arm rule already leaves the forwarded exceptions in place. *)
let direct t key =
  match SM.find_opt key t.origins with
  | None -> Known SS.empty
  | Some os ->
      List.fold_left
        (fun acc o ->
          if not o.o_escapes then acc
          else
            match (o.o_form, o.o_path) with
            | "reraise", _ -> acc
            | "unknown", _ | _, None -> join acc (top Unknown_exn_value (key ^ ":" ^ o.o_form))
            | _, Some p -> join acc (Known (SS.singleton (canon t p))))
        (Known SS.empty) os

let is_ext k = String.length k > 4 && String.sub k 0 4 = "ext:"

(** Contribution of one edge given the current solution. *)
let contribution t ~assume_externals_pure sol (e : edge) =
  let raw =
    if e.kind = "MAY_TOP" || e.callee = "ext:*TOP*" || e.callee = Arch_graph.top_sentinel then
      top May_top_edge e.site
    else if is_ext e.callee then
      let name = String.sub e.callee 4 (String.length e.callee - 4) in
      if known_leaf name || assume_externals_pure then Known SS.empty else top External name
    else match SM.find_opt e.callee sol with Some s -> s | None -> Known SS.empty
  in
  close t e.scope raw

(** Worklist fixpoint over every node. *)
let solve ?(assume_externals_pure = false) t =
  let sol = ref (SM.mapi (fun k _ -> direct t k) t.names) in
  let preds =
    SM.fold
      (fun caller es acc ->
        List.fold_left
          (fun acc (e : edge) ->
            SM.update e.callee (function None -> Some [caller] | Some l -> Some (caller :: l)) acc)
          acc es)
      t.edges SM.empty
  in
  let recompute k =
    let es = match SM.find_opt k t.edges with Some l -> l | None -> [] in
    List.fold_left (fun acc e -> join acc (contribution t ~assume_externals_pure !sol e)) (direct t k) es
  in
  let queue = Queue.create () in
  let queued = Hashtbl.create 1024 in
  let push k = if not (Hashtbl.mem queued k) then (Hashtbl.replace queued k () ; Queue.add k queue) in
  SM.iter (fun k _ -> push k) t.names ;
  while not (Queue.is_empty queue) do
    let k = Queue.pop queue in
    Hashtbl.remove queued k ;
    let v = recompute k in
    let old = match SM.find_opt k !sol with Some s -> s | None -> Known SS.empty in
    if not (equal v old) then begin
      sol := SM.add k v !sol ;
      match SM.find_opt k preds with Some ps -> List.iter push ps | None -> ()
    end
  done ;
  !sol

(* ------------------------------------------------------------------ *)
(* Provenance                                                          *)
(* ------------------------------------------------------------------ *)

let keys_of_name t name = match SM.find_opt name t.by_name with Some l -> List.rev l | None -> []

let set_to_string set = "{" ^ String.concat ", " (SS.elements (known_part set)) ^ "}"

let verdict ~assume_externals_pure = function
  | Known _ as s ->
      if assume_externals_pure then "BOUNDED_UNDER_HYP(externals_pure): " ^ set_to_string s
      else "BOUNDED: " ^ set_to_string s
  | Top _ as s -> "UNBOUNDED (⊤): " ^ set_to_string s

(** For a node, each escaping exception with how it got there. *)
let rows_for t ~assume_externals_pure sol key =
  let direct_set = known_part (direct t key) in
  let es = match SM.find_opt key t.edges with Some l -> l | None -> [] in
  let via p =
    List.find_map
      (fun (e : edge) ->
        if SS.mem p (known_part (contribution t ~assume_externals_pure sol e)) then
          Some (match SM.find_opt e.callee t.names with Some n -> n | None -> e.callee)
        else None)
      es
  in
  let set = match SM.find_opt key sol with Some s -> s | None -> Known SS.empty in
  (* Under ⊤ the known part is still listed: what we DO know may escape. *)
  let paths = SS.elements (known_part set) in
  List.map
    (fun p ->
      if SS.mem p direct_set then [Arch_db.Text p; Arch_db.Text "-"; Arch_db.Text "direct"]
      else
        [Arch_db.Text p; Arch_db.Text (match via p with Some v -> v | None -> "?"); Arch_db.Text "transitive"])
    paths

let reasons_of = function
  | Top (_, rs) -> List.map (fun (r : reason) -> reason_kind_to_string r.kind ^ " " ^ r.witness) (RS.elements rs)
  | Known _ -> []

let dominant_reason = function
  | Top (_, rs) when not (RS.is_empty rs) -> Some (RS.min_elt rs : reason).kind
  | _ -> None

let name_of t k = SM.find_opt k t.names
let file_of t k = SM.find_opt k t.files
let all_keys t = SM.fold (fun k _ acc -> k :: acc) t.names [] |> List.rev
let n_origins t = t.n_origins
let n_scopes t = t.n_scopes
let n_escaping t = t.n_escaping
