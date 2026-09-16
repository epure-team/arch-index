type occurrence = {
  cell : Arch_index_cfa.cell;
  head : Typedtree.expression;
  supplied : int;
  omitted_slots : int;
  legacy_residual : bool;
  forced_callback : bool;
}

type owner = {session : int; serial : int}

let same_owner left right =
  left.session = right.session && left.serial = right.serial

type root = {
  body : Typedtree.expression;
  name : string;
  arity : int;
  mutable notified : bool;
}

type literal = {
  expr : Typedtree.expression;
  cell : Arch_index_cfa.cell;
  mutable eval_owner : owner option;
  mutable observed : (string * int) option;
  mutable stored : bool;
  mutable ambiguous : bool;
}

type t = {
  domain : Arch_index_cfa.t;
  cells : (string, Arch_index_cfa.cell) Hashtbl.t;
  eligible : (string, unit) Hashtbl.t;
  owners : (string, owner option) Hashtbl.t;
  arities : (string, int) Hashtbl.t;
  roots : (string, root) Hashtbl.t;
  mutable literals : literal list;
  calls : (int, occurrence) Hashtbl.t;
  mutable next_call : int;
  mutable next_owner : int;
  session : int;
  mutable finalized : bool;
}

let flat_symbol_unique ~lsp_count ~root_count =
  lsp_count = 1 && root_count = 1

let%test "flat CFA rejects a CMT duplicate hidden by LSP" =
  not (flat_symbol_unique ~lsp_count:1 ~root_count:2)
  && flat_symbol_unique ~lsp_count:1 ~root_count:1

let%test "CFA owners are session-local tokens" =
  not (same_owner {session = 1; serial = 0} {session = 2; serial = 0})

let next_session = ref 0

let create ~binding_name ~fn_arity (structure : Typedtree.structure) =
  let domain = Arch_index_cfa.create () in
  let cells = Hashtbl.create 32 in
  let eligible = Hashtbl.create 32 in
  let owners = Hashtbl.create 32 in
  let arities = Hashtbl.create 32 in
  let roots = Hashtbl.create 16 in
  let literals = ref [] in
  let literal_cell ?owner expr =
    match List.find_opt (fun literal -> literal.expr == expr) !literals with
    | Some literal -> literal.cell
    | None ->
        let value = Arch_index_cfa.fresh domain in
        literals := {expr; cell = value; eval_owner = owner; observed = None; stored = false; ambiguous = false} :: !literals ;
        value
  in
  let cell id =
    let key = Ident.unique_name id in
    match Hashtbl.find_opt cells key with
    | Some cell -> cell
    | None ->
        let cell = Arch_index_cfa.fresh domain in
        Hashtbl.add cells key cell ;
        cell
  in
  let rec root_expr_cell (expr : Typedtree.expression) =
    let dst = match expr.exp_desc with Texp_function _ -> literal_cell expr | _ -> Arch_index_cfa.fresh domain in
    let copy_expr child = Arch_index_cfa.copy domain ~src:(root_expr_cell child) ~dst in
    (match expr.exp_desc with
    | Texp_ident (Path.Pident id, _, _) ->
        let stamp = Ident.unique_name id in
        (match Hashtbl.find_opt owners stamp, Hashtbl.find_opt cells stamp with
        | Some None, Some src -> Arch_index_cfa.copy domain ~src ~dst
        | _ -> Arch_index_cfa.seed_reason domain dst "callback_param")
    | Texp_ifthenelse (_, yes, Some no) -> copy_expr yes ; copy_expr no
    | Texp_ifthenelse (_, yes, None) ->
        copy_expr yes ; Arch_index_cfa.seed_reason domain dst "callback_param"
    | Texp_match (_, computation_cases, value_cases, _) ->
        List.iter (fun case -> copy_expr case.Typedtree.c_rhs) computation_cases ;
        List.iter (fun case -> copy_expr case.Typedtree.c_rhs) value_cases
    | Texp_sequence (_, last) -> copy_expr last
    | Texp_function _ -> ()
    | _ -> Arch_index_cfa.seed_reason domain dst "callback_param") ;
    dst
  in
  let visit_structure (items : Typedtree.structure_item list) =
    List.iter
      (fun (item : Typedtree.structure_item) ->
        match item.str_desc with
        | Tstr_value (Asttypes.Nonrecursive, bindings) ->
            List.iter
              (fun (binding : Typedtree.value_binding) ->
                match binding.vb_pat.pat_desc with
                | Tpat_var (id, _, _) when Ident.name id <> "_" ->
                    (match binding.vb_expr.exp_desc with
                    | Texp_function _ ->
                        let dst = cell id in
                        let name = binding_name ~prefix:"" id in
                        let arity = fn_arity binding.vb_expr in
                        (* A CMT declaration is not yet proof that the target
                           body was retained by this producer.  The actual
                           function-row insertion later sends the authoritative
                           physical-body notification. *)
                        Hashtbl.replace roots (Ident.unique_name id)
                          {body = binding.vb_expr; name; arity; notified = false} ;
                        Hashtbl.replace eligible (Ident.unique_name id) () ;
                        Hashtbl.replace owners (Ident.unique_name id) None ;
                        ignore dst
                    | Texp_ident (Path.Pident source, _, _) ->
                        (* A plain alias is the supported transfer itself even
                           when its source is opaque: it must remain an
                           explicit CFA frontier.  In contrast, an unsupported
                           RHS (open wrapper, call result, computed value) is
                           never enrolled merely because it has a root binder. *)
                        let dst = cell id in
                        Arch_index_cfa.copy domain ~src:(cell source) ~dst ;
                        if not (Hashtbl.mem eligible (Ident.unique_name source)) then
                          Arch_index_cfa.seed_reason domain dst "callback_param" ;
                        Hashtbl.replace eligible (Ident.unique_name id) () ;
                        Hashtbl.replace owners (Ident.unique_name id) None
                    | (Texp_ifthenelse _ | Texp_match _ | Texp_sequence _) ->
                        Hashtbl.replace cells (Ident.unique_name id)
                          (root_expr_cell binding.vb_expr) ;
                        Hashtbl.replace eligible (Ident.unique_name id) () ;
                        Hashtbl.replace owners (Ident.unique_name id) None
                    | _ -> ())
                | _ -> ())
              bindings
        | _ -> ())
      items
  in
  visit_structure structure.str_items ;
  let session = !next_session in
  incr next_session ;
  {domain; cells; eligible; owners; arities; roots; calls = Hashtbl.create 32; next_call = 0;
   literals = !literals; next_owner = 0; session;
   finalized = false}

let observe_literal t ~owner ~expr ~name ~arity =
  match List.find_opt (fun literal -> literal.expr == expr) t.literals with
  | Some literal ->
      (match literal.eval_owner with
      | None -> literal.eval_owner <- Some owner; literal.observed <- Some (name, arity)
      | Some expected when same_owner expected owner ->
          (match literal.observed with
          | None -> literal.observed <- Some (name, arity)
          | Some prior when prior = (name, arity) -> ()
          | Some _ -> literal.ambiguous <- true)
      | Some _ -> literal.ambiguous <- true)
  | None ->
      let cell = Arch_index_cfa.fresh t.domain in
      t.literals <-
        {expr; cell; eval_owner = Some owner; observed = Some (name, arity); stored = false; ambiguous = false}
        :: t.literals

let notify_stored_literal t ~name =
  match List.filter (fun literal -> match literal.observed with Some (n, _) -> n = name | None -> false) t.literals with
  | [literal] ->
      literal.stored <- true
  | _ -> ()

let notify_stored_root t ~binder ~body ~canonical_name =
  match Hashtbl.find_opt t.roots (Ident.unique_name binder) with
  | Some root when root.body == body && root.name = canonical_name ->
      let cell = Hashtbl.find t.cells (Ident.unique_name binder) in
      root.notified <- true ;
      Hashtbl.replace t.arities canonical_name root.arity ;
      Arch_index_cfa.seed_target t.domain cell canonical_name
  | _ -> ()

let notify_rejected_root t ~binder ~body =
  match Hashtbl.find_opt t.roots (Ident.unique_name binder) with
  | Some root when root.body == body ->
      let cell = Hashtbl.find t.cells (Ident.unique_name binder) in
      root.notified <- true ;
      Arch_index_cfa.seed_reason t.domain cell "dropped_node"
  | _ -> ()

let fresh_owner t =
  let owner = {session = t.session; serial = t.next_owner} in
  t.next_owner <- t.next_owner + 1 ;
  owner

let register_local_alias t ~owner ~binder ~source =
  if t.finalized then invalid_arg "CFA CMT session already finalized" ;
  let cell id =
    let stamp = Ident.unique_name id in
    match Hashtbl.find_opt t.cells stamp with
    | Some cell -> cell
    | None ->
        let cell = Arch_index_cfa.fresh t.domain in
        Hashtbl.add t.cells stamp cell ;
        cell
  in
  let dst = cell binder in
  let source_stamp = Ident.unique_name source in
  let source_owner = Hashtbl.find_opt t.owners source_stamp in
  (match source_owner with
  | Some None -> Arch_index_cfa.copy t.domain ~src:(cell source) ~dst
  | Some (Some source_owner) when same_owner source_owner owner ->
      Arch_index_cfa.copy t.domain ~src:(cell source) ~dst
  | _ -> Arch_index_cfa.seed_reason t.domain dst "callback_param") ;
  Hashtbl.replace t.eligible (Ident.unique_name binder) () ;
  Hashtbl.replace t.owners (Ident.unique_name binder) (Some owner)

let expr_cell t owner expr =
  let fresh () = Arch_index_cfa.fresh t.domain in
  let copy_source dst id =
    match Hashtbl.find_opt t.owners (Ident.unique_name id), Hashtbl.find_opt t.cells (Ident.unique_name id) with
    | Some None, Some src ->
        Arch_index_cfa.copy t.domain ~src ~dst
    | Some (Some source_owner), Some src when same_owner source_owner owner ->
        Arch_index_cfa.copy t.domain ~src ~dst
    | _ -> Arch_index_cfa.seed_reason t.domain dst "callback_param"
  in
  let rec build e =
    let dst =
      match e.Typedtree.exp_desc with
      | Texp_function _ ->
          (match List.find_opt (fun literal -> literal.expr == e) t.literals with
          | Some literal ->
              (match literal.eval_owner with
              | None -> literal.eval_owner <- Some owner; literal.cell
              | Some expected when same_owner expected owner -> literal.cell
              | Some _ ->
                  let rejected = fresh () in
                  Arch_index_cfa.seed_reason t.domain rejected "dropped_node" ;
                  rejected)
          | None ->
              let cell = fresh () in
              t.literals <- {expr=e; cell; eval_owner=Some owner; observed=None; stored=false; ambiguous=false} :: t.literals ; cell)
      | _ -> fresh ()
    in
    (match e.Typedtree.exp_desc with
    | Texp_ident (Path.Pident id, _, _) -> copy_source dst id
    | Texp_ifthenelse (_, yes, Some no) ->
        Arch_index_cfa.copy t.domain ~src:(build yes) ~dst ; Arch_index_cfa.copy t.domain ~src:(build no) ~dst
    | Texp_match (_, computation_cases, value_cases, _) ->
        List.iter (fun c -> Arch_index_cfa.copy t.domain ~src:(build c.Typedtree.c_rhs) ~dst) computation_cases ;
        List.iter (fun c -> Arch_index_cfa.copy t.domain ~src:(build c.Typedtree.c_rhs) ~dst) value_cases
    | Texp_sequence (_, last) -> Arch_index_cfa.copy t.domain ~src:(build last) ~dst
    | Texp_function _ -> ()
    | _ -> Arch_index_cfa.seed_reason t.domain dst "callback_param") ; dst
  in build expr

let register_local_expr t ~owner ~binder expr =
  let dst = expr_cell t owner expr in
  Hashtbl.replace t.cells (Ident.unique_name binder) dst ;
  Hashtbl.replace t.eligible (Ident.unique_name binder) () ;
  Hashtbl.replace t.owners (Ident.unique_name binder) (Some owner)

let register_call t ~owner ~binder ~head ~supplied ~omitted_slots ~legacy_residual =
  if t.finalized then invalid_arg "CFA CMT session already finalized" ;
  let stamp = Ident.unique_name binder in
  if not (Hashtbl.mem t.eligible stamp) then None
  else
    let token = t.next_call in
    t.next_call <- token + 1 ;
    let forced_callback =
      match Hashtbl.find_opt t.owners stamp with
      | Some None -> false
      | Some (Some call_owner) when same_owner call_owner owner -> false
      | _ -> true
    in
    Hashtbl.add t.calls token
      {cell = Hashtbl.find t.cells stamp; head; supplied; omitted_slots; legacy_residual;
       forced_callback} ;
    Some token

let register_expr_call t ~owner expr ~head ~supplied ~omitted_slots ~legacy_residual =
  let cell = expr_cell t owner expr in
  let token = t.next_call in t.next_call <- token + 1 ;
  Hashtbl.add t.calls token {cell; head; supplied; omitted_slots; legacy_residual; forced_callback = false} ; token

let finalize t =
  if not t.finalized then (
    (* A declared root that did not receive its authoritative producer
       notification is a known body the producer cannot represent, not a
       closed value.  This runs after the entire CMT collection so a later
       successful row/literal notification still wins. *)
    Hashtbl.iter
      (fun stamp root ->
        if not root.notified then
          Arch_index_cfa.seed_reason t.domain (Hashtbl.find t.cells stamp)
            "dropped_node")
      t.roots ;
    List.iter (fun literal ->
      match literal.stored, literal.ambiguous, literal.observed with
      | true, false, Some (target, arity)
        when List.length
               (List.filter
                  (fun other ->
                    match other.observed with
                    | Some (name, _) -> name = target
                    | None -> false)
                  t.literals)
             = 1 ->
          Hashtbl.replace t.arities target arity ;
          Arch_index_cfa.seed_target t.domain literal.cell target
      | _ -> Arch_index_cfa.seed_reason t.domain literal.cell "dropped_node") t.literals ;
    Arch_index_cfa.solve t.domain ;
    t.finalized <- true)

let value_of_call t token =
  if not t.finalized then invalid_arg "CFA CMT session not finalized" ;
  Option.map
    (fun occurrence ->
      ignore occurrence.head ;
      let value =
        if occurrence.forced_callback then
          {Arch_index_cfa.targets = Arch_index_cfa.String_set.empty;
           reasons = Arch_index_cfa.String_set.singleton "callback_param"}
        else Arch_index_cfa.value t.domain
          occurrence.cell
      in
      ( Arch_index_cfa.String_set.elements value.targets
        |> List.map (fun name ->
               (name, Option.value (Hashtbl.find_opt t.arities name) ~default:0)),
        Arch_index_cfa.String_set.elements value.reasons,
        occurrence.supplied, occurrence.omitted_slots, occurrence.legacy_residual ))
    (Hashtbl.find_opt t.calls token)
