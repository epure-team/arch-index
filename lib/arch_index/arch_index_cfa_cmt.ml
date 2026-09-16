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
  mutable domain : Arch_index_cfa.t;
  cells : (string, Arch_index_cfa.cell) Hashtbl.t;
  eligible : (string, unit) Hashtbl.t;
  owners : (string, owner option) Hashtbl.t;
  mutable arities : (string, int) Hashtbl.t;
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

type transfer_policy = {
  lookup : Ident.t -> Arch_index_cfa.cell option;
  literal : Typedtree.expression -> Arch_index_cfa.cell;
  application : Typedtree.expression -> Arch_index_cfa.cell option;
}

let expression_cell domain ~fresh ~policy expr =
  let rec build locals (e : Typedtree.expression) =
    let source id =
      let stamp = Ident.unique_name id in
      match List.assoc_opt stamp locals with
      | Some cell -> Some cell
      | None -> policy.lookup id
    in
    let dst =
      match e.exp_desc with
      | Texp_function _ -> policy.literal e
      | _ -> fresh ()
    in
    let copy child = Arch_index_cfa.copy domain ~src:(build locals child) ~dst in
    (match e.exp_desc with
    | Texp_ident (Path.Pident id, _, _) -> (
        match source id with
        | Some src -> Arch_index_cfa.copy domain ~src ~dst
        | None -> Arch_index_cfa.seed_reason domain dst Arch_index_cfa.Callback_param)
    | Texp_ifthenelse (_, yes, Some no) -> copy yes ; copy no
    | Texp_ifthenelse (_, yes, None) ->
        copy yes ; Arch_index_cfa.seed_reason domain dst Arch_index_cfa.Callback_param
    | Texp_match (_, computation_cases, value_cases, _) ->
        List.iter (fun case -> copy case.Typedtree.c_rhs) computation_cases ;
        List.iter (fun case -> copy case.Typedtree.c_rhs) value_cases
    | Texp_sequence (_, last) -> copy last
    | Texp_let (Asttypes.Nonrecursive, [binding], body) -> (
        match binding.Typedtree.vb_pat.pat_desc with
        | Tpat_var (id, _, _) ->
            let rhs = build locals binding.vb_expr in
            let body = build ((Ident.unique_name id, rhs) :: locals) body in
            Arch_index_cfa.copy domain ~src:body ~dst
        | _ -> Arch_index_cfa.seed_reason domain dst Arch_index_cfa.Callback_param)
    | Texp_apply _ -> (
        match policy.application e with
        | Some src -> Arch_index_cfa.copy domain ~src ~dst
        | None -> Arch_index_cfa.seed_reason domain dst Arch_index_cfa.Callback_param)
    | Texp_function _ -> ()
    | _ -> Arch_index_cfa.seed_reason domain dst Arch_index_cfa.Callback_param) ;
    dst
  in
  build [] expr

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
  let root_expr_cell expr =
    expression_cell domain ~fresh:(fun () -> Arch_index_cfa.fresh domain)
      ~policy:{
        lookup = (fun id ->
          let stamp = Ident.unique_name id in
          match Hashtbl.find_opt owners stamp, Hashtbl.find_opt cells stamp with
          | Some None, Some src -> Some src
          | _ -> None);
        literal = literal_cell;
        application = (fun _ -> None);
      }
      expr
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
                          Arch_index_cfa.seed_reason domain dst Arch_index_cfa.Callback_param ;
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

let ensure_open t =
  if t.finalized then invalid_arg "CFA CMT session already finalized"

let observe_literal t ~owner ~expr ~name ~arity =
  ensure_open t ;
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
  ensure_open t ;
  match List.filter (fun literal -> match literal.observed with Some (n, _) -> n = name | None -> false) t.literals with
  | [literal] ->
      literal.stored <- true
  | _ -> ()

let notify_stored_root t ~binder ~body ~canonical_name =
  ensure_open t ;
  match Hashtbl.find_opt t.roots (Ident.unique_name binder) with
  | Some root when root.body == body && root.name = canonical_name ->
      let cell = Hashtbl.find t.cells (Ident.unique_name binder) in
      root.notified <- true ;
      Hashtbl.replace t.arities canonical_name root.arity ;
      Arch_index_cfa.seed_target t.domain cell canonical_name
  | _ -> ()

let notify_rejected_root t ~binder ~body =
  ensure_open t ;
  match Hashtbl.find_opt t.roots (Ident.unique_name binder) with
  | Some root when root.body == body ->
      let cell = Hashtbl.find t.cells (Ident.unique_name binder) in
      root.notified <- true ;
      Arch_index_cfa.seed_reason t.domain cell Arch_index_cfa.Dropped_node
  | _ -> ()

let fresh_owner t =
  ensure_open t ;
  let owner = {session = t.session; serial = t.next_owner} in
  t.next_owner <- t.next_owner + 1 ;
  owner

let register_local_alias t ~owner ~binder ~source =
  ensure_open t ;
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
  | _ -> Arch_index_cfa.seed_reason t.domain dst Arch_index_cfa.Callback_param) ;
  Hashtbl.replace t.eligible (Ident.unique_name binder) () ;
  Hashtbl.replace t.owners (Ident.unique_name binder) (Some owner)

let expr_cell t owner expr =
  let fresh () = Arch_index_cfa.fresh t.domain in
  let lookup id =
    match Hashtbl.find_opt t.owners (Ident.unique_name id), Hashtbl.find_opt t.cells (Ident.unique_name id) with
    | Some None, Some src -> Some src
    | Some (Some source_owner), Some src when same_owner source_owner owner -> Some src
    | _ -> None
  in
  let literal e =
    match List.find_opt (fun literal -> literal.expr == e) t.literals with
    | Some literal ->
        (match literal.eval_owner with
        | None -> literal.eval_owner <- Some owner; literal.cell
        | Some expected when same_owner expected owner -> literal.cell
        | Some _ ->
            let rejected = fresh () in
            Arch_index_cfa.seed_reason t.domain rejected Arch_index_cfa.Dropped_node ;
            rejected)
    | None ->
        let cell = fresh () in
        t.literals <-
          {expr=e; cell; eval_owner=Some owner; observed=None; stored=false; ambiguous=false}
          :: t.literals ;
        cell
  in
  expression_cell t.domain ~fresh
    ~policy:{lookup; literal; application = (fun _ -> None)} expr

let register_local_expr t ~owner ~binder expr =
  ensure_open t ;
  let dst = expr_cell t owner expr in
  Hashtbl.replace t.cells (Ident.unique_name binder) dst ;
  Hashtbl.replace t.eligible (Ident.unique_name binder) () ;
  Hashtbl.replace t.owners (Ident.unique_name binder) (Some owner)

let register_call t ~owner ~binder ~head ~supplied ~omitted_slots ~legacy_residual =
  ensure_open t ;
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
  ensure_open t ;
  let cell = expr_cell t owner expr in
  let token = t.next_call in t.next_call <- token + 1 ;
  Hashtbl.add t.calls token {cell; head; supplied; omitted_slots; legacy_residual; forced_callback = false} ; token

let finalize_with_hook ~before_solve t =
  if not t.finalized then (
    let domain = Arch_index_cfa.clone t.domain in
    let arities = Hashtbl.copy t.arities in
    (* A declared root that did not receive its authoritative producer
       notification is a known body the producer cannot represent, not a
       closed value.  This runs after the entire CMT collection so a later
       successful row/literal notification still wins. *)
    Hashtbl.iter
      (fun stamp root ->
        if not root.notified then
          Arch_index_cfa.seed_reason domain (Hashtbl.find t.cells stamp)
            Arch_index_cfa.Dropped_node)
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
          Hashtbl.replace arities target arity ;
          Arch_index_cfa.seed_target domain literal.cell target
      | _ -> Arch_index_cfa.seed_reason domain literal.cell Arch_index_cfa.Dropped_node) t.literals ;
    before_solve () ;
    Arch_index_cfa.solve domain ;
    t.domain <- domain ;
    t.arities <- arities ;
    t.finalized <- true)

let finalize t = finalize_with_hook ~before_solve:(fun () -> ()) t

module For_tests = struct
  let finalize_with_after_staging_hook t hook =
    finalize_with_hook ~before_solve:hook t
end

let value_of_call t token =
  if not t.finalized then invalid_arg "CFA CMT session not finalized" ;
  Option.map
    (fun occurrence ->
      ignore occurrence.head ;
      let value =
        if occurrence.forced_callback then
          {Arch_index_cfa.targets = Arch_index_cfa.String_set.empty;
           reasons = Arch_index_cfa.Reason_set.singleton Arch_index_cfa.Callback_param}
        else Arch_index_cfa.value t.domain
          occurrence.cell
      in
      ( Arch_index_cfa.String_set.elements value.targets
        |> List.map (fun name ->
               (name, Option.value (Hashtbl.find_opt t.arities name) ~default:0)),
        Arch_index_cfa.Reason_set.elements value.reasons,
        occurrence.supplied, occurrence.omitted_slots, occurrence.legacy_residual ))
    (Hashtbl.find_opt t.calls token)
