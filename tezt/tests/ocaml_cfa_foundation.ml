open Arch_tezt

let fixture_files =
  let fixture_path name =
    Filename.concat (repo_root ()) ("tezt/fixtures/ocaml_cfa/" ^ name)
  in
  [ ("dune-project", read_file (fixture_path "dune-project"));
    ("dune", read_file (fixture_path "dune"));
    ("alias_chain.ml", read_file (fixture_path "alias_chain.ml"));
    ("shadowed_target.ml", read_file (fixture_path "shadowed_target.ml"));
    ("homonym_caller.ml", read_file (fixture_path "homonym_caller.ml"));
    ("homonym_other.ml", read_file (fixture_path "homonym_other.ml"));
    ("local_alias.ml", read_file (fixture_path "local_alias.ml"));
    ("named_joins.ml", read_file (fixture_path "named_joins.ml"));
    ("literal_values.ml", read_file (fixture_path "literal_values.ml"));
    ("metadata.ml", read_file (fixture_path "metadata.ml"));
    ("higher_order.ml", read_file (fixture_path "higher_order.ml")) ]

let count db sql = Db.with_db db (fun conn -> Db.int conn sql)

let check_session_lifecycle build_dir =
  let module C = Arch_index__Arch_index_cfa_cmt in
  let module M = Arch_index__Arch_index_cmt in
  let rec find root =
    Sys.readdir root |> Array.to_list |> List.find_map (fun entry ->
      let path = Filename.concat root entry in
      if Sys.is_directory path then find path
      else if entry = "metadata.cmt" then Some path else None)
  in
  let structure =
    match Option.bind (find build_dir) (fun path -> snd (Cmt_format.read path)) with
    | Some {Cmt_format.cmt_annots = Cmt_format.Implementation structure; _} -> structure
    | _ -> Test.fail "OCAML_CFA_LIFECYCLE_SETUP: metadata implementation CMT absent"
  in
  let roots =
    structure.str_items |> List.concat_map (fun item ->
      match item.Typedtree.str_desc with
      | Typedtree.Tstr_value (_, bindings) ->
          List.filter_map (fun binding ->
            match binding.Typedtree.vb_pat.pat_desc, binding.vb_expr.exp_desc with
            | Typedtree.Tpat_var (id, _, _), Typedtree.Texp_function _ ->
                Some (id, binding.vb_expr)
            | _ -> None) bindings
      | _ -> [])
  in
  let application = ref None in
  let open Tast_iterator in
  let iterator =
    {
      default_iterator with
      expr = (fun self (expr : Typedtree.expression) ->
        (match !application, expr.exp_desc with
        | None, Texp_apply _ -> application := Some expr
        | _ -> ()) ;
        default_iterator.expr self expr);
    }
  in
  iterator.structure iterator structure ;
  let binder, body, source =
    match roots with
    | (binder, body) :: (source, _) :: _ -> binder, body, source
    | _ -> Test.fail "OCAML_CFA_LIFECYCLE_SETUP: two root functions required"
  in
  let names = M.build_binding_names structure in
  let session = C.create ~binding_name:(M.binding_name names) ~fn_arity:M.fn_arity structure in
  let owner = C.fresh_owner session ~body in
  let token =
    C.register_expr_call session ~owner body ~head:body ~supplied:1
      ~omitted_slots:0 ~legacy_residual:false
  in
  (match !application with
  | Some ({exp_desc = Texp_apply (head, args); _} as application) ->
      ignore
        (C.register_application session ~owner ~application ~head ~args
           ~legacy_residual:false)
  | _ -> Test.fail "OCAML_CFA_LIFECYCLE_SETUP: application absent") ;
  let residual_identities = C.For_tests.residual_identity_count session in
  let invalid_message = "CFA CMT session already finalized" in
  let expect_invalid label expected thunk =
    match (try thunk () ; None with Invalid_argument message -> Some message) with
    | Some message when String.starts_with ~prefix:expected message -> ()
    | Some message ->
        Test.fail "OCAML_CFA_LIFECYCLE_ASSERTION: %s raised Invalid_argument %S" label message
    | None -> Test.fail "OCAML_CFA_LIFECYCLE_ASSERTION: %s did not reject" label
  in
  expect_invalid "pre-finalize query" "CFA CMT session not finalized"
    (fun () -> ignore (C.value_of_call session token)) ;
  C.notify_stored_root session ~binder ~body
    ~canonical_name:(M.binding_name names ~prefix:"" binder) ;
  (match
     try C.For_tests.finalize_with_after_staging_hook session (fun () -> raise Exit) ; None
     with Exit -> Some ()
   with
  | Some () -> ()
  | None -> Test.fail "OCAML_CFA_LIFECYCLE_ASSERTION: injected finalize fault absent") ;
  expect_invalid "query after failed finalize" "CFA CMT session not finalized"
    (fun () -> ignore (C.value_of_call session token)) ;
  ignore (C.fresh_owner session ~body) ;
  C.finalize session ;
  if C.For_tests.residual_identity_count session <> residual_identities then
    Test.fail
      "OCAML_CFA_LIFECYCLE_ASSERTION: solve allocated a residual identity" ;
  let snapshot () = C.value_of_call session token in
  let initial = snapshot () in
  C.finalize session ;
  if snapshot () <> initial then
    Test.fail "OCAML_CFA_LIFECYCLE_ASSERTION: repeated finalize changed query result" ;
  let mutations =
    [ "fresh_owner", (fun () -> ignore (C.fresh_owner session ~body));
      "notify_stored_root", (fun () ->
        C.notify_stored_root session ~binder ~body
          ~canonical_name:(M.binding_name names ~prefix:"" binder));
      "notify_rejected_root", (fun () -> C.notify_rejected_root session ~binder ~body);
      "observe_literal", (fun () ->
        C.observe_literal session ~owner ~expr:body ~name:"late" ~arity:1);
      "notify_stored_literal", (fun () -> C.notify_stored_literal session ~name:"late");
      "register_local_alias", (fun () ->
        C.register_local_alias session ~owner ~binder ~source);
      "register_local_expr", (fun () -> C.register_local_expr session ~owner ~binder body);
      "register_call", (fun () ->
        ignore (C.register_call session ~owner ~binder ~head:body ~supplied:1
          ~omitted_slots:0 ~legacy_residual:false));
      "register_expr_call", (fun () ->
        ignore (C.register_expr_call session ~owner body ~head:body ~supplied:1
          ~omitted_slots:0 ~legacy_residual:false));
      "register_application", (fun () ->
        match !application with
        | Some ({exp_desc = Texp_apply (head, args); _} as application) ->
            ignore
              (C.register_application session ~owner ~application ~head ~args
                 ~legacy_residual:false)
        | _ -> Test.fail "OCAML_CFA_LIFECYCLE_SETUP: application absent") ]
  in
  List.iter (fun (label, mutation) ->
    expect_invalid label invalid_message mutation ;
    if snapshot () <> initial then
      Test.fail "OCAML_CFA_LIFECYCLE_ASSERTION: %s changed finalized state" label)
    mutations

let check_metadata_pending build_dir =
  let module C = Arch_index__Arch_index_cfa_cmt in
  let module M = Arch_index__Arch_index_cmt in
  let rec find root = Sys.readdir root |> Array.to_list |> List.find_map (fun entry ->
    let path = Filename.concat root entry in
    if Sys.is_directory path then find path else if entry = "metadata.cmt" then Some path else None)
  in
  let structure = match Option.bind (find build_dir) (fun path -> snd (Cmt_format.read path)) with
    | Some {Cmt_format.cmt_annots = Cmt_format.Implementation structure; _} -> structure
    | _ -> Test.fail "OCAML_CFA_SETUP: metadata implementation CMT absent"
  in
  let names = M.build_binding_names structure in
  let local_fn_stamps = M.build_local_fn_stamps structure in
  let collect session =
    let pending = ref [] in
    List.iter (fun item -> match item.Typedtree.str_desc with
      | Typedtree.Tstr_value (_, bindings) -> List.iter (fun binding ->
          match binding.Typedtree.vb_pat.pat_desc with
          | Typedtree.Tpat_var (id, _, _) ->
              let caller_name = M.binding_name names ~prefix:"" id in
              (match binding.vb_expr.exp_desc with Typedtree.Texp_function _ ->
                C.notify_stored_root session ~binder:id ~body:binding.vb_expr
                  ~canonical_name:caller_name
              | _ -> ()) ;
              let calls, _, _, _ = M.collect_calls_from_expr ~src_path:"metadata.ml"
                ~caller_module:"metadata.ml" ~caller_name ~local_fn_stamps
                ~cfa_session:session binding.vb_expr in
              pending := calls @ !pending
          | _ -> ()) bindings
      | _ -> ()) structure.str_items ;
    C.finalize session ;
    let raw_calls = !pending in
    raw_calls, M.expand_cfa_calls session raw_calls
  in
  let session = C.create ~binding_name:(M.binding_name names) ~fn_arity:M.fn_arity structure in
  let raw_calls, calls = collect session in
  let selected caller callee = List.filter (fun (c : M.pending_call) ->
    c.caller_name = caller && match c.head with M.Head_enumerated name -> name = callee | _ -> false) calls in
  let require label predicate = if not predicate then Test.fail "OCAML_CFA_METADATA_ASSERTION: %s" label in
  let exactly count rows = List.length rows = count in
  let mixed_one = selected "mixed_arity" "meta_returned"
  and mixed_two = selected "mixed_arity" "meta_two" in
  require "mixed arity keeps both candidates"
    (exactly 1 mixed_one && exactly 1 mixed_two) ;
  require "mixed arity copies source partiality"
    (List.for_all (fun c -> c.M.partial) (mixed_one @ mixed_two)) ;
  require "same-line occurrences remain four physical expanded rows"
    (List.length (List.filter (fun c -> c.M.caller_name = "same_line" && match c.head with M.Head_enumerated ("meta_one" | "meta_cases") -> true | _ -> false) calls) = 4) ;
  let conditional = selected "conditional" "meta_one" @ selected "conditional" "meta_cases" in
  let dead = selected "dead" "meta_one" @ selected "dead" "meta_cases" in
  require "conditional metadata copied" (exactly 2 conditional && List.for_all (fun c -> c.M.cond) conditional) ;
  require "dead metadata copied" (exactly 2 dead && List.for_all (fun c -> c.M.dead) dead) ;
  let partial = selected "partial_curried" "meta_two" in
  require "curried partial is partial" (exactly 1 partial && List.for_all (fun c -> c.M.partial) partial) ;
  let saturated = selected "tuple_call" "meta_tuple" @ selected "cases_call" "meta_cases" in
  require "tuple and cases saturated" (exactly 2 saturated && List.for_all (fun c -> not c.M.partial) saturated) ;
  let labeled = selected "labeled_partial" "meta_labeled" in
  require "labeled omission keeps partial candidate" (exactly 1 labeled && List.for_all (fun c -> c.M.partial) labeled) ;
  let raw_scoped = List.filter (fun (c : M.pending_call) ->
    c.caller_name = "scoped" && match c.edge_form with Some marker -> String.starts_with ~prefix:"__cfa:" marker | None -> false) raw_calls in
  let scoped = selected "scoped" "meta_one" @ selected "scoped" "meta_cases" in
  require "one raw scoped occurrence" (exactly 1 raw_scoped) ;
  let original = List.hd raw_scoped in
  require "scope and occurrence metadata copied exactly"
    (exactly 2 scoped && List.for_all (fun c ->
       c.M.exn_scope = original.exn_scope && c.errch_scope = original.errch_scope
       && c.call_site = original.call_site && c.cond = original.cond && c.dead = original.dead) scoped) ;
  List.iter (fun unknown_arity ->
    let session = C.create ~binding_name:(M.binding_name names)
      ~fn_arity:(fun _ -> unknown_arity) structure in
    let raw_calls, calls = collect session in
    let raw = List.filter (fun (c : M.pending_call) ->
      c.caller_name = "scoped" && match c.edge_form with
      | Some marker -> String.starts_with ~prefix:"__cfa:" marker
      | None -> false) raw_calls in
    let expanded = List.filter (fun (c : M.pending_call) -> c.caller_name = "scoped") calls in
    let candidates = List.filter (fun (c : M.pending_call) -> match c.head with
      | M.Head_enumerated ("meta_one" | "meta_cases") -> true
      | _ -> false) expanded in
    let unknowns = List.filter (fun (c : M.pending_call) -> match c.head with
      | M.Head_unknown (_, M.Callback_param) -> true
      | _ -> false) expanded in
    require (Printf.sprintf "arity %d retains both bounded candidates" unknown_arity)
      (exactly 2 candidates) ;
    require (Printf.sprintf "arity %d adds exactly one callback frontier" unknown_arity)
      (exactly 1 unknowns) ;
    require (Printf.sprintf "arity %d has one authentic source occurrence" unknown_arity)
      (exactly 1 raw) ;
    let original = List.hd raw in
    require (Printf.sprintf "arity %d copies occurrence metadata" unknown_arity)
      (List.for_all (fun c -> c.M.exn_scope = original.exn_scope
        && c.errch_scope = original.errch_scope && c.call_site = original.call_site
        && c.cond = original.cond && c.dead = original.dead
        && c.partial = original.partial) (candidates @ unknowns))
  ) [0; -1]

let check_literal_identity build_dir =
  let module C = Arch_index__Arch_index_cfa_cmt in
  let module R = Arch_index__Arch_index_cfa in
  let module M = Arch_index__Arch_index_cmt in
  let open Typedtree in
  let expect label condition =
    if not condition then Test.fail "OCAML_CFA_IDENTITY_ASSERTION: %s" label
  in
  let rec find root =
    Sys.readdir root |> Array.to_list |> List.find_map (fun entry ->
      let path = Filename.concat root entry in
      if Sys.is_directory path then find path
      else if entry = "literal_values.cmt" then Some path else None)
  in
  let path = match find build_dir with
    | Some path -> path
    | None -> Test.fail "OCAML_CFA_SETUP: literal_values.cmt absent"
  in
  let structure = match Cmt_format.read path with
    | _, Some {Cmt_format.cmt_annots = Cmt_format.Implementation s; _} -> s
    | _ -> Test.fail "OCAML_CFA_SETUP: implementation CMT absent"
  in
  let original = structure.str_items |> List.find_map (fun item ->
    match item.str_desc with
    | Tstr_value (_, bindings) -> List.find_opt (fun binding ->
        match binding.vb_pat.pat_desc with
        | Tpat_var (id, _, _) -> Ident.name id = "literal_pick"
        | _ -> false) bindings
    | _ -> None) |> function
    | Some binding -> binding
    | None -> Test.fail "OCAML_CFA_SETUP: literal_pick absent"
  in
  let rec body e = match e.exp_desc with
    | Texp_function (_, Tfunction_body b) -> body b
    | _ -> e
  in
  let branch, invocation = match (body original.vb_expr).exp_desc with
    | Texp_let (Asttypes.Nonrecursive, [binding], invocation) -> binding.vb_expr, invocation
    | _ -> Test.fail "OCAML_CFA_SETUP: literal_pick local binding shape changed"
  in
  let yes, no = match branch.exp_desc with
    | Texp_ifthenelse (_, ({exp_desc = Texp_function _; _} as yes),
        Some ({exp_desc = Texp_function _; _} as no)) -> yes, no
    | _ -> Test.fail "OCAML_CFA_SETUP: two native literal arms absent"
  in
  let ghost = {yes.exp_loc with loc_ghost = true} in
  let yes_copy = {yes with exp_loc = ghost} and no_copy = {no with exp_loc = ghost} in
  expect "distinct native records share one ghost location"
    (yes_copy != no_copy && yes_copy.exp_loc == no_copy.exp_loc && ghost.loc_ghost) ;
  let mapper = {Tast_mapper.default with expr = (fun self e ->
    if e == yes then yes_copy else if e == no then no_copy
    else Tast_mapper.default.expr self e)} in
  let cloned_body = mapper.expr mapper original.vb_expr in
  let cloned_branch = mapper.expr mapper branch in
  let structure = {structure with str_items = List.map (fun item ->
    match item.str_desc with
    | Tstr_value (flag, bindings) -> {item with str_desc = Tstr_value (flag,
        List.map (fun binding -> if binding == original
          then {binding with vb_expr = cloned_body} else binding) bindings)}
    | _ -> item) structure.str_items} in
  let create () = C.create
    ~binding_name:(M.binding_name (M.build_binding_names structure))
    ~fn_arity:M.fn_arity structure in
  (* Exercise actual collector names and collision ordinals, not a guessed
     spelling or a position-keyed lookup into the descriptors. *)
  let session = create () in
  let calls, lambdas, _, _ = M.collect_calls_from_expr
    ~src_path:"literal_values.ml" ~caller_module:"literal_values.ml"
    ~caller_name:"literal_pick" ~local_fn_stamps:(M.build_local_fn_stamps structure)
    ~cfa_session:session cloned_body in
  let names = List.map (fun (l : M.lambda_node) -> l.lam_name) lambdas
    |> List.sort_uniq String.compare in
  expect "collector emitted exactly two raw lambda descriptors" (List.length lambdas = 2) ;
  expect "collector assigned two distinct collision names" (List.length names = 2) ;
  expect "collector retained collision ordinal"
    (List.exists (contains ~needle:"#2>") names) ;
  List.iter (fun name -> C.notify_stored_literal session ~name) names ;
  C.finalize session ;
  let at_invocation = M.expand_cfa_calls session calls |> List.filter (fun (c : M.pending_call) ->
    c.caller_name = "literal_pick" && c.call_site =
      Printf.sprintf "literal_values.ml:%d" invocation.exp_loc.loc_start.pos_lnum) in
  let targets = List.filter_map (fun (c : M.pending_call) -> match c.head with
    | M.Head_enumerated name -> Some name | _ -> None) at_invocation |> List.sort String.compare in
  expect "equal-position literal call retains both actual targets and no extra frontier"
    (targets = names && List.length at_invocation = 2) ;
  let first = List.hd names and second = List.nth names 1 in
  let run label notifications expected_names expected_reasons =
    let session = create () in
    let owner = C.fresh_owner session ~body:cloned_branch
    and wrong_owner = C.fresh_owner session ~body:cloned_branch in
    let call1 = {invocation with exp_loc = ghost}
    and call2 = {invocation with exp_loc = ghost} in
    expect "same-position application objects remain distinct" (call1 != call2) ;
    let register head = C.register_expr_call session ~owner cloned_branch
      ~head ~supplied:1 ~omitted_slots:0 ~legacy_residual:false in
    let token1 = register call1 and token2 = register call2 in
    expect "physical occurrences receive distinct tokens" (token1 <> token2) ;
    let observe owner expr name = C.observe_literal session ~owner ~expr ~name ~arity:1 in
    let store name = C.notify_stored_literal session ~name in
    notifications owner wrong_owner observe store ;
    C.finalize session ;
    List.iter (fun token -> match C.value_of_call session token with
      | Some (targets, reasons, 1, 0, false) ->
          expect (label ^ ": exact targets")
            (targets = List.sort compare (List.map (fun name -> name, 1) expected_names)) ;
          expect (label ^ ": exact frontier") (reasons = expected_reasons)
      | _ -> Test.fail "OCAML_CFA_IDENTITY_ASSERTION: %s occurrence metadata" label)
      [token1; token2]
  in
  let both owner observe = observe owner yes_copy first ; observe owner no_copy second in
  run "accepted" (fun owner _ observe store -> both owner observe ; store first ; store second)
    names [] ;
  run "missing observation" (fun _ _ _ store -> store first ; store second)
    [] [R.Dropped_node] ;
  run "missing storage" (fun owner _ observe _ -> both owner observe)
    [] [R.Dropped_node] ;
  run "wrong owner" (fun _ wrong observe store -> both wrong observe ; store first ; store second)
    [] [R.Dropped_node] ;
  run "wrong physical bodies" (fun owner _ observe store ->
    observe owner {yes_copy with exp_loc = ghost} first ;
    observe owner {no_copy with exp_loc = ghost} second ; store first ; store second)
    [] [R.Dropped_node] ;
  run "late duplicate name" (fun owner _ observe store ->
    observe owner yes_copy first ; store first ; observe owner no_copy first ; store first)
    [] [R.Dropped_node] ;
  run "late conflicting owner" (fun owner wrong observe store ->
    both owner observe ; store first ; store second ; observe wrong yes_copy first)
    [second] [R.Dropped_node] ;
  run "late conflicting name" (fun owner _ observe store ->
    both owner observe ; store first ; store second ; observe owner yes_copy second)
    [second] [R.Dropped_node]

let register () =
  Test.register ~__FILE__
    ~title:"OCaml CFA: a same-CMT alias chain reaches its actual target"
    ~tags:["cmt"; "calls"; "cfa"; "alias"]
  @@ fun () ->
  with_fixture ~name:"ocaml_cfa_alias_chain" ~files:fixture_files @@ fun fixture ->
  let rich = temp_db "ocaml_cfa_alias_chain_rich" in
  let code, output = index_raw_into ~db:rich fixture in
  if code <> 0 then
    Test.fail "OCAML_CFA_SETUP: rich producer exit %d: %s" code output ;
  let flat_env =
    match Sys.getenv_opt "EPURE_ARCH_INDEX_TIMEOUT_S" with
    | Some _ -> []
    | None -> [("EPURE_ARCH_INDEX_TIMEOUT_S", "60")]
  in
  let flat_code, flat_output, flat =
    index_project_raw ~env:flat_env ~name:"ocaml_cfa_alias_chain_flat" fixture.root
  in
  let incomplete_diagnostics =
    [ "arch_index_lsp: LSP lookup failed:";
      "arch_index_lsp: LSP start failed:";
      "arch_index_lsp: timeout after";
      "arch_index_lsp: unexpected error:" ]
  in
  if
    flat_code <> 0
    || not (Sys.file_exists flat)
    || List.exists (fun marker -> contains ~needle:marker flat_output) incomplete_diagnostics
  then
    Test.fail "OCAML_CFA_SETUP: incomplete flat producer (exit %d): %s" flat_code flat_output ;
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: main run reaches actual f as an ordinary MAY candidate"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='run' AND target.name='f' \
              AND caller.module_id=target.module_id \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL \
              AND c.top_reason IS NULL AND c.top_anchor IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: main preserves the earlier physical run occurrence"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='run#1' AND target.name='f' \
            AND caller.module_id=target.module_id \
            AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: closed alias refinement leaves no ordinary TOP"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='run' AND c.edge_form IS NULL \
              AND c.kind='MAY_TOP'")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: CFA candidates are never MUST"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='run' AND c.edge_form IS NULL AND c.kind='MUST'")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: one occurrence produces one bounded target row"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='run' AND c.edge_form IS NULL")
        1 ;
      List.iter
        (fun (caller, target) ->
          Batch.eq_int b
            ~msg:("OCAML_CFA_RED: immediate alias fact " ^ caller ^ " -> " ^ target)
            (count rich
               (Printf.sprintf
                  "SELECT count(*) FROM calls c \
                   JOIN functions source ON source.id=c.caller_id \
                   JOIN functions target ON target.id=c.callee_id \
                   WHERE source.name='%s' AND target.name='%s' \
                     AND source.module_id=target.module_id \
                     AND c.kind='MAY_ENUMERATED' AND c.edge_form='value_alias'"
                  caller target))
            1)
        [("a", "f"); ("b", "a")] ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: ambiguous flat caller keeps one exact unknown per occurrence"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_name='run' AND callee_name='*TOP*' \
              AND callee_file IS NULL AND edge_form IS NULL")
        2 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: ambiguous flat caller emits no bounded CFA target"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_name='run' AND callee_name='f' AND edge_form IS NULL")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: a unique flat alias-chain caller retains f"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_name='unique_run' AND callee_name='f' \
              AND callee_file=caller_file AND edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: the unique flat caller retains no CFA TOP"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_name='unique_run' AND callee_name='*TOP*' \
              AND edge_form IS NULL")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: main keeps the earlier shadowed target identity"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='shadow_run' AND target.name='shadow_f#1' \
              AND caller.module_id=target.module_id \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: an ordinal-only shadowed target is flat TOP"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_file LIKE '%shadowed_target.ml' \
              AND caller_name='shadow_run' AND callee_name='*TOP*' \
              AND callee_file IS NULL AND edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: same-file CFA target is never captured by a homonym"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_file LIKE '%homonym_caller.ml' \
              AND caller_name='homonym_run' AND callee_name='homonym_f' \
              AND callee_file=caller_file AND edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: same-callable local alias reaches its unit target"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='local_run' AND target.name='local_root' \
              AND caller.module_id=target.module_id \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: flat same-callable local alias keeps its actual target"
        (count flat
           "SELECT count(*) FROM calls \
            WHERE caller_file LIKE '%local_alias.ml' \
              AND caller_name='local_run' AND callee_name='local_root' \
              AND callee_file=caller_file AND edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: local positive has no TOP/MUST or duplicate"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='local_run' AND c.edge_form IS NULL \
              AND (c.kind='MAY_TOP' OR c.kind='MUST')")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: local positive has exactly one ordinary call"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='local_run' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_RED: saturated identity result reaches its target"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='ho_run' AND target.name='ho_target' \
              AND caller.module_id=target.module_id \
              AND c.call_site LIKE '%higher_order.ml:6' \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_ASSERTION: open-world identity keeps its frontier"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='ho_run' AND c.kind='MAY_TOP' AND c.edge_form IS NULL")
        1 ;
      List.iter
        (fun (caller, line) ->
          Batch.eq_int b
            ~msg:("OCAML_CFA_PROPAGATION_RED: shared formal/result merge at " ^ caller)
            (count rich
               (Printf.sprintf
                  "SELECT count(*) FROM calls c \
                   JOIN functions source ON source.id=c.caller_id \
                   JOIN functions target ON target.id=c.callee_id \
                   WHERE source.name='%s' AND target.name IN ('merge_a','merge_b') \
                     AND source.module_id=target.module_id \
                     AND c.call_site LIKE '%%higher_order.ml:%d' \
                     AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL"
                  caller line))
            2)
        [("merge_run_a", 14); ("merge_run_b", 18)] ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_ASSERTION: direct identity calls stay singular"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            WHERE source.name IN ('merge_run_a','merge_run_b') \
              AND c.callee_name='merge_identity' AND c.edge_form IS NULL")
        2 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RECURSION_RED: mutual return cycle converges to target"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='rec_run' AND target.name='rec_target' \
              AND source.module_id=target.module_id \
              AND c.call_site LIKE '%higher_order.ml:27' \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RESIDUAL_RED: staged application retains target at both stages"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='staged_run' AND target.name='staged_target' \
              AND source.module_id=target.module_id \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        2 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_RED: direct application-result head reaches target"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='direct_staged_run' AND target.name='ho_target' \
              AND source.module_id=target.module_id \
              AND c.call_site LIKE '%higher_order.ml:35' \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        2 ;
      List.iter
        (fun (caller, line) ->
          Batch.eq_int b
            ~msg:("OCAML_CFA_RECURSION_RED: " ^ caller ^ " reaches target")
            (count rich
               (Printf.sprintf
                  "SELECT count(*) FROM calls c \
                   JOIN functions source ON source.id=c.caller_id \
                   JOIN functions target ON target.id=c.callee_id \
                   WHERE source.name='%s' AND target.name='rec_target' \
                     AND source.module_id=target.module_id \
                     AND c.call_site LIKE '%%higher_order.ml:%d' \
                     AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL"
                  caller line))
            1)
        [("direct_rec_run", 41); ("local_rec_run", 47)] ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RECURSION_ASSERTION: mixed recursive group stays open"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='mixed_group_run' AND target.name='rec_target' \
              AND c.call_site LIKE '%higher_order.ml:54' \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RECURSION_ASSERTION: mixed recursive group retains TOP"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            WHERE source.name='mixed_group_run' AND c.kind='MAY_TOP' \
              AND c.top_reason='callback_param' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RESIDUAL_ASSERTION: overapplied result does not leak raw return"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='over_downstream' \
              AND target.name LIKE 'over_make.<fun:%' \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RESIDUAL_ASSERTION: overapplied result remains callback-open"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            WHERE source.name='over_downstream' AND c.kind='MAY_TOP' \
              AND c.top_reason='callback_param' AND c.edge_form IS NULL")
        2 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_RED: supported let expression head reaches target"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='let_head_run' AND target.name='ho_target' \
              AND source.module_id=target.module_id \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_ASSERTION: supported let expression head is closed"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            WHERE source.name='let_head_run' AND c.kind='MAY_TOP' \
              AND c.top_reason='callback_param' AND c.edge_form IS NULL")
        0 ;
      List.iter
        (fun caller ->
          Batch.eq_int b
            ~msg:("OCAML_CFA_PROPAGATION_RED: let admission reaches target for " ^ caller)
            (count rich
               (Printf.sprintf
                  "SELECT count(*) FROM calls c \
                   JOIN functions source ON source.id=c.caller_id \
                   JOIN functions target ON target.id=c.callee_id \
                   WHERE source.name='%s' AND target.name='ho_target' \
                     AND source.module_id=target.module_id \
                     AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL"
                  caller))
            1 ;
          Batch.eq_int b
            ~msg:("OCAML_CFA_PROPAGATION_ASSERTION: let admission is closed for " ^ caller)
            (count rich
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
                   WHERE source.name='%s' AND c.kind='MAY_TOP' \
                     AND c.top_reason='callback_param' AND c.edge_form IS NULL"
                  caller))
            0 ;
          Batch.eq_int b
            ~msg:("OCAML_CFA_PROPAGATION_RED: flat let admission reaches target for " ^ caller)
            (count flat
               (Printf.sprintf
                  "SELECT count(*) FROM calls \
                   WHERE caller_file LIKE '%%higher_order.ml' AND caller_name='%s' \
                     AND callee_name='ho_target' AND callee_file=caller_file \
                     AND edge_form IS NULL"
                  caller))
            1 ;
          Batch.eq_int b
            ~msg:("OCAML_CFA_PROPAGATION_ASSERTION: flat let admission is closed for " ^ caller)
            (count flat
               (Printf.sprintf
                  "SELECT count(*) FROM calls \
                   WHERE caller_file LIKE '%%higher_order.ml' AND caller_name='%s' \
                     AND callee_name='*TOP*' AND callee_file IS NULL \
                     AND edge_form IS NULL"
                  caller))
            0)
        ["let_head_run"; "root_let_run"; "local_let_run"] ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_ASSERTION: destructured let head stays unknown"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            WHERE source.name='let_pattern_head' AND c.kind='MAY_TOP' \
              AND c.top_reason='callback_param' AND c.edge_form IS NULL")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_PROPAGATION_ASSERTION: destructured let head gains no target"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions source ON source.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE source.name='let_pattern_head' AND target.name='ho_target' \
              AND c.kind='MAY_ENUMERATED' AND c.edge_form IS NULL")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_CAPTURE_RED: exact lexical alias capture reaches target"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name LIKE 'capture_outer.<fun:%' \
              AND target.name='local_root' AND c.kind='MAY_ENUMERATED'")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_CAPTURE_ASSERTION: exact lexical capture is closed"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name LIKE 'capture_outer.<fun:%' \
              AND c.kind='MAY_TOP' AND c.top_reason='callback_param'")
        0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_CAPTURE_RED: initializer lexical capture reaches target"
        (count rich "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id JOIN functions target ON target.id=c.callee_id WHERE caller.name LIKE 'initializer_outer.<fun:%' AND target.name='local_root' AND c.kind='MAY_ENUMERATED'")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: a unit alias stays visible in a nested lambda"
        (count rich
           "SELECT count(*) FROM calls c \
            JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name LIKE 'unit_outer.<fun:%' AND target.name='local_root' \
              AND caller.module_id=target.module_id AND c.kind='MAY_ENUMERATED'")
        1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: named if join preserves both known candidates"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='join_known' AND target.name IN ('join_f','join_g') \
              AND caller.module_id=target.module_id AND c.kind='MAY_ENUMERATED'")
        2 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: root branch-valued binding preserves both candidates"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='branch_run' AND target.name IN ('join_f','join_g') \
              AND caller.module_id=target.module_id AND c.kind='MAY_ENUMERATED'")
        2 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: root known-plus-opaque alias retains its known target"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='root_mixed_run' AND t.name='join_f' AND c.kind='MAY_ENUMERATED'") 1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: root known-plus-opaque alias retains callback uncertainty"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='root_mixed_run' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: pure known root join remains bounded-only"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='branch_run' AND c.kind='MAY_TOP' AND c.edge_form IS NULL") 0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: direct multi-hop opaque root alias remains TOP"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='root_opaque_run' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_ASSERTION: root opaque refinements are never MUST"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name IN ('root_mixed_run','root_opaque_run') AND c.kind='MUST' AND c.edge_form IS NULL") 0 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: named if join retains its callback frontier"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            WHERE caller.name='join_unknown' AND c.kind='MAY_TOP' \
              AND c.top_reason='callback_param'")
        1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_ASSERTION: named mixed join retains known target beside TOP"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='join_unknown' AND t.name='join_f' AND c.kind='MAY_ENUMERATED'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_ASSERTION: if guard call is preserved"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='guard_join' AND c.callee_name='join_side'") 1 ;
      Batch.eq_int b
        ~msg:"OCAML_CFA_RED: direct if head has both named candidates"
        (count rich
           "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
            JOIN functions target ON target.id=c.callee_id \
            WHERE caller.name='direct_join' AND target.name IN ('join_f','join_g') \
              AND caller.module_id=target.module_id AND c.kind='MAY_ENUMERATED'")
        2 ;
      List.iter
        (fun caller ->
          Batch.eq_int b ~msg:("OCAML_CFA_ASSERTION: " ^ caller ^ " retains named target(s)")
            (count rich (Printf.sprintf
               "SELECT count(*) FROM calls c JOIN functions caller ON caller.id=c.caller_id \
                JOIN functions target ON target.id=c.callee_id \
                WHERE caller.name='%s' AND target.name IN ('join_f','join_g') \
                  AND caller.module_id=target.module_id AND c.kind='MAY_ENUMERATED'" caller))
            (if caller = "match_join" || caller = "exception_join" then 2 else 1))
        ["match_join"; "sequence_join"; "pattern_join"; "exception_join"] ;
      Batch.eq_int b ~msg:"OCAML_CFA_ASSERTION: match scrutinee call is preserved"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='match_join' AND c.callee_name='join_side'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_ASSERTION: sequence prefix call is preserved"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='sequence_join' AND c.callee_name='join_side'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_ASSERTION: pattern-bound value remains unknown beside known"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='pattern_join' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 1) ;
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_RED: selected literals reach two actual stored targets"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='literal_pick' AND t.name LIKE 'literal_pick.<fun:%' AND c.call_site LIKE '%literal_values.ml:3' AND c.kind='MAY_ENUMERATED'") 2 ;
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_RED: mixed literal retains its actual target"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='literal_mixed' AND t.name LIKE 'literal_mixed.<fun:%' AND c.call_site LIKE '%literal_values.ml:7' AND c.kind='MAY_ENUMERATED'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_RED: mixed literal retains callback frontier"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='literal_mixed' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_RED: local literal alias chain reaches stored literal"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='literal_alias' AND t.name LIKE 'literal_alias.<fun:%' AND c.call_site LIKE '%literal_values.ml:12' AND c.kind='MAY_ENUMERATED'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_RED: root branch literals reach two actual stored targets"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN functions t ON t.id=c.callee_id WHERE f.name='root_literal_run' AND t.name LIKE 'root_literal.<fun:%' AND c.kind='MAY_ENUMERATED'") 2) ;
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_ASSERTION: literal CFA targets are never MUST"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name IN ('literal_pick','literal_mixed','literal_alias','root_literal_run') AND c.kind='MUST' AND c.edge_form IS NULL") 0 ;
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_ASSERTION: closed root literal join retains no TOP"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='root_literal_run' AND c.kind='MAY_TOP' AND c.edge_form IS NULL") 0 ;
      Batch.eq_int b ~msg:"OCAML_CFA_LITERAL_ASSERTION: closed local literal flows retain no TOP"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name IN ('literal_pick','literal_alias') AND c.kind='MAY_TOP' AND c.edge_form IS NULL") 0 ;
      List.iter (fun caller ->
        Batch.eq_int b ~msg:("OCAML_CFA_LITERAL_ASSERTION: flat literal is exact TOP for " ^ caller)
          (count flat (Printf.sprintf "SELECT count(*) FROM (SELECT DISTINCT caller_name,caller_file,callee_name,callee_file,call_site,edge_form FROM calls WHERE caller_name='%s' AND callee_name='*TOP*' AND callee_file IS NULL AND edge_form IS NULL)" caller)) 1)
        ["literal_pick"; "literal_mixed"; "literal_alias"; "root_literal_run"]) ;
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"OCAML_CFA_METADATA: same-line physical calls remain distinct"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='same_line' AND c.callee_name IN ('meta_one','meta_cases') AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL") 4 ;
      Batch.eq_int b ~msg:"OCAML_CFA_METADATA: conditional candidates remain bounded MAY"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='conditional' AND c.callee_name IN ('meta_one','meta_cases') AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL") 2 ;
      Batch.eq_int b ~msg:"OCAML_CFA_METADATA: dead expansions retain one dead fact per candidate"
        (count rich "SELECT count(*) FROM dead_code_sites d JOIN functions f ON f.id=d.function_id WHERE f.name='dead' AND d.callee_name IN ('meta_one','meta_cases')") 2 ;
      List.iter (fun (caller, target) ->
        Batch.eq_int b ~msg:("OCAML_CFA_ARITY: " ^ caller ^ " reaches " ^ target)
          (count rich (Printf.sprintf "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='%s' AND c.callee_name='%s' AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL" caller target)) 1)
        [("partial_curried","meta_two"); ("tuple_call","meta_tuple"); ("cases_call","meta_cases"); ("labeled_partial","meta_labeled")] ;
      Batch.eq_int b ~msg:"OCAML_CFA_ARITY: omitted label keeps independent TOP"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='labeled_partial' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 1 ;
      Batch.eq_int b ~msg:"OCAML_CFA_RESIDUAL: overapplication keeps known candidate"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='overapply' AND c.callee_name IN ('meta_over','meta_over2') AND c.kind='MAY_ENUMERATED' AND c.top_reason IS NULL AND c.top_anchor IS NULL") 2 ;
      Batch.eq_int b ~msg:"OCAML_CFA_RESIDUAL: opaque frontier and overapplication residual stay independent"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='overapply' AND c.kind='MAY_TOP' AND c.top_reason='callback_param'") 2 ;
      Batch.eq_int b ~msg:"OCAML_CFA_ARITY: authentic mixed candidates remain distinct"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='mixed_arity' AND c.callee_name IN ('meta_returned','meta_two') AND c.kind='MAY_ENUMERATED'") 2 ;
      Batch.eq_int b ~msg:"OCAML_CFA_METADATA: match c_guard and RHS calls both retain candidates"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id WHERE f.name='match_guard' AND c.callee_name IN ('meta_one','meta_cases') AND c.kind='MAY_ENUMERATED'") 4 ;
      Batch.eq_int b ~msg:"OCAML_CFA_CHANNELS: expanded candidates keep exception scope"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN call_exn_scopes l ON l.call_id=c.id JOIN exn_scopes s ON s.id=l.scope_id WHERE f.name='scoped' AND c.callee_name IN ('meta_one','meta_cases') AND s.channel='exception'") 2 ;
      Batch.eq_int b ~msg:"OCAML_CFA_CHANNELS: expanded candidates keep result scope"
        (count rich "SELECT count(*) FROM calls c JOIN functions f ON f.id=c.caller_id JOIN call_exn_scopes l ON l.call_id=c.id JOIN exn_scopes s ON s.id=l.scope_id WHERE f.name='scoped' AND c.callee_name IN ('meta_one','meta_cases') AND s.channel='result'") 2) ;
  check_metadata_pending fixture.build_dir ;
  check_literal_identity fixture.build_dir ;
  check_session_lifecycle fixture.build_dir ;
  let reaches_code, reaches_output = query_raw rich ["reaches"; "unique_run"; "f"] in
  if reaches_code <> 0 then
    Test.fail "OCAML_CFA_SETUP: arch-query reaches exited %d: %s" reaches_code reaches_output ;
  let unreachable_code, unreachable_output =
    query_raw rich ["unreachable"; "unique_run"; "f"]
  in
  if unreachable_code <> 0 then
    Test.fail "OCAML_CFA_SETUP: arch-query unreachable exited %d: %s"
      unreachable_code unreachable_output ;
  let frontier_code, frontier_output =
    query_raw rich ["unreachable"; "join_unknown"; "join_g"]
  in
  if frontier_code <> 0 then
    Test.fail "OCAML_CFA_SETUP: arch-query unknown-frontier exited %d: %s"
      frontier_code frontier_output ;
  let callers_code, callers_output = query_raw rich ["callers-of"; "f"] in
  if callers_code <> 0 then
    Test.fail "OCAML_CFA_SETUP: arch-query callers exited %d: %s"
      callers_code callers_output ;
  Batch.run (fun b ->
      Batch.eq_string b
        ~msg:"OCAML_CFA_CONSUMER_ASSERTION: CFA edge does not license MUST reachability"
        (verdict_token reaches_output) "no MUST path" ;
      Batch.eq_string b
        ~msg:"OCAML_CFA_CONSUMER_ASSERTION: CFA edge licenses may-reach"
        (verdict_token unreachable_output) "REACHABLE (may-reach)" ;
      Batch.eq_string b
        ~msg:"OCAML_CFA_CONSUMER_ASSERTION: unknown frontier blocks unrelated-leaf proof"
        (verdict_token frontier_output) "UNKNOWN:" ;
      Batch.contains b
        ~msg:"OCAML_CFA_CONSUMER_ASSERTION: callers reports the real caller"
        ~haystack:callers_output "unique_run" ;
      Batch.not_contains b
        ~msg:"OCAML_CFA_CONSUMER_ASSERTION: callers excludes alias a"
        ~haystack:callers_output "alias_chain.ml:a" ;
      Batch.not_contains b
        ~msg:"OCAML_CFA_CONSUMER_ASSERTION: callers excludes alias b"
        ~haystack:callers_output "alias_chain.ml:b") ;
  Lwt.return_unit
