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

type reason_kind = May_top_edge | External | Unknown_exn_value | Inferred_bind

let reason_kind_to_string = function
  | May_top_edge -> "may_top_edge"
  | External -> "external"
  | Unknown_exn_value -> "unknown_exn_value"
  | Inferred_bind -> "inferred_bind"

(* Dominant-reason order for exn-stats (spec C-8). *)
let reason_rank = function
  | May_top_edge -> 0
  | External -> 1
  | Unknown_exn_value -> 2
  | Inferred_bind -> 3

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
  channel : string;
  names : string SM.t;  (** key → display name *)
  files : string SM.t;
  by_name : string list SM.t;  (** name → keys *)
  edges : edge list SM.t;  (** caller key → out edges (MUST ∪ MAY_ENUMERATED ∪ MAY_TOP) *)
  scopes : scope SM.t;  (** scope id (as string) → scope *)
  origins : origin list SM.t;  (** node key → origins *)
  rebinds : string SM.t;
  carriers : unit SM.t;
      (** node keys marked a c-carrier of [channel] in [channel_carriers]
          (specs/error-channels.md "Carrier check"). Only populated — and
          only meaningful — for a value channel; the [exception] channel has
          no such table (every node may raise) so {!is_carrier} always
          answers [true] for it. *)
  summaries : SS.t SM.t;
      (** [\[summaries\]] (FR-031): external callee display name -> the
          declared origin set on THIS channel. Consulted only when an edge's
          callee is external (absent from the index) — see [contribution]. *)
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

(* -------------------------------------------------------------------- *)
(* [summaries] (FR-031): decode [comment_db_meta.error_summaries] (see    *)
(* arch_index.ml's encoder — TAB between callee and per-channel lists,   *)
(* [|] between channel entries, [name:path1,path2]) and pick out THIS    *)
(* channel's declared set per external callee.                          *)
(* -------------------------------------------------------------------- *)

let split_nonempty sep s =
  String.split_on_char sep s |> List.filter (fun x -> x <> "")

let decode_summaries ~channel (raw : string) : SS.t SM.t =
  if raw = "" then SM.empty
  else
    String.split_on_char '\n' raw
    |> List.filter (fun l -> l <> "")
    |> List.fold_left
         (fun acc line ->
           match String.index_opt line '\t' with
           | None -> acc
           | Some i ->
               let callee = String.sub line 0 i in
               let rest = String.sub line (i + 1) (String.length line - i - 1) in
               List.fold_left
                 (fun acc entry ->
                   match String.index_opt entry ':' with
                   | None -> acc
                   | Some j ->
                       let c = String.sub entry 0 j in
                       if c <> channel then acc
                       else
                         let paths =
                           String.sub entry (j + 1) (String.length entry - j - 1)
                           |> split_nonempty ','
                         in
                         SM.add callee (SS.of_list paths) acc)
                 acc (split_nonempty '|' rest))
         SM.empty

(** Built-in [Stdlib] summary table (FR-031), [exception] channel only,
    OFF by default — see [load]'s [~use_builtin_summaries]. *)
let builtin_stdlib_summaries : SS.t SM.t =
  let one p = SS.singleton p in
  List.fold_left
    (fun acc (name, exn) -> SM.add name (one exn) acc)
    SM.empty
    [
      (* Canonical predefined-exception paths are BARE (docs/exception-raise-sets.md
         "Canonical paths": the .cmt spells them [Stdlib.Not_found] etc.,
         normalised) — matching the same convention here so a summary's
         contribution equals what a real in-index raise of the same
         exception would have produced. *)
      ("Stdlib.List.hd", "Failure");
      ("Stdlib.List.nth", "Failure");
      ("Stdlib.List.tl", "Failure");
      ("Stdlib.Hashtbl.find", "Not_found");
      ("Stdlib.List.find", "Not_found");
      ("Stdlib.List.assoc", "Not_found");
      ("Stdlib.Option.get", "Invalid_argument");
      ("Stdlib.int_of_string", "Failure");
      ("Stdlib.String.sub", "Invalid_argument");
      ("Stdlib.String.get", "Invalid_argument");
    ]

(* [channel]: the exception channel keeps "every edge in [calls]" (FR-029's
   byte-identical requirement — its rows and query output must not move) and
   its [exn_origins]/[exn_scopes]/[exn_scope_catches] rows are those tagged
   [channel='exception'] (the ones this channel has ALWAYS written, slices
   0-1 included). A value channel's origins/scopes are the rows tagged with
   its own name, and its edges come from [exn_edges] rows with
   [role='propagates'] on that channel — NOT from [calls] directly, since an
   unrelated call inside a c-carrier node that is not itself a propagating
   fact must contribute nothing (specs/error-channels.md "Propagating
   edges"). *)
let not_analysed_channel channel error_contract =
  Printf.sprintf
    "NOT_ANALYSED: channel %s was not emitted by the producer (error_contract = %s)"
    channel
    (match error_contract with Some s -> s | None -> "<absent>")

let load ?(channel = "exception") ?(use_builtin_summaries = false) (t : Arch_db.t) =
  (* FIX (review round 1, MEDIUM): {!not_analysed} is worded for the
     exception channel — it names [raises]/[raisers-of]/[exn-stats]. Reaching
     it on a value channel told a user who asked about [result] to rebuild in
     order to get commands that have nothing to do with their question.
     {!not_analysed_channel} says the same thing about the channel actually
     asked for, so use it whenever one was named. *)
  let refuse_not_analysed () =
    if channel = "exception" then Arch_db.refuse "%s" not_analysed
    else Arch_db.refuse "%s" (not_analysed_channel channel (Arch_db.meta t "error_contract"))
  in
  if t.schema = Arch_db.Flat then refuse_not_analysed () ;
  if channel = "exception" then
    match Arch_db.meta t "exn_contract" with
    | Some _ when Arch_db.has_table t "exn_origins" -> ()
    | _ -> Arch_db.refuse "%s" not_analysed
  else (
    (* A value channel's contract lives in [error_contract]
       ("v1:exception,result,option,…") — FR-032: a channel absent there
       MUST refuse NOT_ANALYSED, distinctly from the [exception] channel's
       own (unchanged) check above. *)
    if not (Arch_db.has_table t "exn_origins") then refuse_not_analysed () ;
    let ec = Arch_db.meta t "error_contract" in
    let emitted =
      match ec with
      | None -> false
      | Some s -> (
          match String.index_opt s ':' with
          | None -> false
          | Some i ->
              let rest = String.sub s (i + 1) (String.length s - i - 1) in
              List.mem channel (String.split_on_char ',' rest))
    in
    if not emitted then Arch_db.refuse "%s" (not_analysed_channel channel ec)) ;
  let q shape sql = Arch_db.collect t (Arch_db.dyn Arch_db.Ty.unit shape sql) () in
  let qc shape sql = Arch_db.collect t (Arch_db.dyn Arch_db.Ty.string shape sql) channel in
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
      (* The [call_exn_scopes] join MUST be filtered to scopes on the channel
         being loaded. Its key is (call_id, scope_id), so one call site can
         carry both an exception-channel scope and a value-channel one; an
         unfiltered join would (a) emit that call's edge TWICE and (b) — far
         worse — hand this channel's solver a scope belonging to another
         channel, whose caught set would then be subtracted from an answer it
         has nothing to do with. The [EXISTS] sits in the ON clause so the
         join stays a LEFT one: a call with no scope on THIS channel must
         still produce its edge, with a NULL scope. *)
      (if channel = "exception" then
         q
           Arch_db.Ty.(t2 (t3 s s s) (t2 i s))
           (Printf.sprintf
              "SELECT '#'||c.caller_id, CASE WHEN c.callee_id IS NULL THEN 'ext:'||c.callee_name \
               ELSE '#'||c.callee_id END, %s, l.scope_id, COALESCE(c.call_site,'') FROM calls c \
               LEFT JOIN call_exn_scopes l ON l.call_id=c.id AND EXISTS (SELECT 1 FROM \
               exn_scopes s WHERE s.id=l.scope_id AND s.channel='exception') ORDER BY c.id"
              (Arch_db.kind_sql t))
       else
         qc
           Arch_db.Ty.(t2 (t3 s s s) (t2 i s))
           (Printf.sprintf
              "SELECT '#'||c.caller_id, CASE WHEN c.callee_id IS NULL THEN 'ext:'||c.callee_name \
               ELSE '#'||c.callee_id END, %s, l.scope_id, COALESCE(c.call_site,'') FROM calls c \
               JOIN exn_edges ee ON ee.call_id=c.id AND ee.role='propagates' AND ee.channel=? \
               LEFT JOIN call_exn_scopes l ON l.call_id=c.id AND EXISTS (SELECT 1 FROM \
               exn_scopes s WHERE s.id=l.scope_id AND s.channel=ee.channel) ORDER BY c.id"
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
      (qc Arch_db.Ty.(t3 i i i) "SELECT id, parent_id, catch_all FROM exn_scopes WHERE channel=?")
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
      (qc Arch_db.Ty.(t2 (t2 i s) (t2 s i))
         "SELECT function_id, form, exn_path, escapes FROM exn_origins WHERE channel=? ORDER BY id")
  in
  let carriers =
    if channel = "exception" || not (Arch_db.has_table t "channel_carriers") then SM.empty
    else
      List.fold_left
        (fun acc fid ->
          match fid with None -> acc | Some fid -> SM.add ("#" ^ string_of_int fid) () acc)
        SM.empty
        (qc i "SELECT function_id FROM channel_carriers WHERE channel=?")
  in
  let summaries =
    let declared = decode_summaries ~channel (text (Arch_db.meta t "error_summaries")) in
    if use_builtin_summaries && channel = "exception" then
      SM.union (fun _ a _ -> Some a) declared builtin_stdlib_summaries
    else declared
  in
  {
    channel;
    names;
    files;
    by_name;
    edges;
    scopes;
    origins;
    rebinds;
    carriers;
    summaries;
    n_origins = !n_origins;
    n_scopes = SM.cardinal scopes;
    n_escaping = !n_escaping;
  }

let is_carrier t key = t.channel = "exception" || SM.mem key t.carriers

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
            | "inferred_bind", Some witness -> join acc (top Inferred_bind witness)
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
      if known_leaf name then Known SS.empty
      else
        match SM.find_opt name t.summaries with
        | Some s -> Known s (* FR-031: a declared external summary replaces ⊤ [external]. *)
        | None -> if assume_externals_pure then Known SS.empty else top External name
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
