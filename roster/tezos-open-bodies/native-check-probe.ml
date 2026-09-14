module C = Open_cmt
open Typedtree

let json_call (p : C.pending_call) =
  let callee, _ = C.pending_display p in
  let head =
    match p.head with
    | C.Head_enumerated _ -> "enumerated"
    | C.Head_unknown (_, r) -> C.top_reason_to_string r
    | C.Head_local _ -> "local"
    | C.Head_qualified _ -> "qualified"
  in
  `Assoc
    [ ("callee", `String callee); ("head", `String head);
      ("partial", `Bool p.partial);
      ("form", match p.edge_form with None -> `Null | Some s -> `String s) ]

let () =
  let info = Cmt_format.read_cmt Sys.argv.(1) in
  let structure =
    match info.cmt_annots with Implementation s -> s | _ -> failwith "implementation required"
  in
  let local_fn_stamps = C.build_local_fn_stamps structure in
  let targets = C.build_open_body_targets structure in
  let rows = ref [] in
  List.iter
    (fun (it : structure_item) ->
      match it.str_desc with
      | Tstr_value (_, vbs) ->
          List.iter
            (fun (vb : value_binding) ->
              match vb.vb_pat.pat_desc with
              | Tpat_var (id, _, _) ->
                  let caller = Ident.name id in
                  let slots = ref [] in
                  let iter =
                    { Tast_iterator.default_iterator with
                      expr =
                        (fun self e ->
                          (match e.exp_desc with
                          | Texp_apply ({exp_desc = Texp_ident (Path.Pident callee, _, _); _}, args)
                            when Hashtbl.mem targets (Ident.unique_name callee) ->
                              slots :=
                                (List.length args, List.length (List.filter_map snd args)) :: !slots
                          | _ -> ()) ;
                          Tast_iterator.default_iterator.expr self e) }
                  in
                  iter.expr iter vb.vb_expr ;
                  let legacy, legacy_lams, legacy_exn, legacy_err =
                    C.collect_calls_from_expr ~local_fn_stamps ~src_path:"native.ml"
                      ~caller_module:"native.ml" ~caller_name:caller vb.vb_expr
                  in
                  let rich, rich_lams, rich_exn, rich_err =
                    C.collect_calls_from_expr_with_open_bodies ~open_body_targets:targets
                      ~local_fn_stamps ~src_path:"native.ml" ~caller_module:"native.ml"
                      ~caller_name:caller vb.vb_expr
                  in
                  let shape lams exn err =
                    `Assoc
                      [ ("lambdas", `Int (List.length lams));
                        ("exn_nodes", `Int (List.length exn));
                        ("err_nodes", `Int (List.length err));
                        ( "exact_digest",
                          `String
                            (Digest.to_hex
                               (Digest.string (Marshal.to_string (lams, exn, err) []))) ) ]
                  in
                  rows :=
                    `Assoc
                      [ ("caller", `String caller);
                        ("slots", `List (List.map (fun (a, b) -> `List [`Int a; `Int b]) !slots));
                        ("legacy", `List (List.map json_call legacy));
                        ("rich", `List (List.map json_call rich));
                        ( "legacy_calls_digest",
                          `String (Digest.to_hex (Digest.string (Marshal.to_string legacy []))) );
                        ( "rich_calls_digest",
                          `String (Digest.to_hex (Digest.string (Marshal.to_string rich []))) );
                        ("legacy_shape", shape legacy_lams legacy_exn legacy_err);
                        ("rich_shape", shape rich_lams rich_exn rich_err) ]
                    :: !rows
              | _ -> ())
            vbs
      | _ -> ())
    structure.str_items ;
  let target_rows =
    Hashtbl.fold
      (fun stamp (t : C.open_body_target) acc ->
        `Assoc
          [ ("stamp", `String stamp); ("display", `String t.display_name);
            ("body", `String t.body_name); ("arity", `Int t.body_arity);
            ("matches", `Int t.matching_bodies);
            ("expected", `Bool t.expected_body_observed) ]
        :: acc)
      targets []
  in
  (* Identity-negative control: give the wrapped descriptor a different
     literal as its expected physical root while retaining the wrapped root's
     canonical name.  The name/location premise still matches once, but the
     physical-root premise must refuse it.  This models the ghost/shared-loc
     collision class without trusting source coordinates as identity. *)
  let control_targets = C.build_open_body_targets structure in
  let wrapped = ref None and wrapped_expr = ref None and decoy = ref None in
  Hashtbl.iter
    (fun stamp (t : C.open_body_target) ->
      if t.display_name = "wrapped" then wrapped := Some (stamp, t))
    control_targets ;
  List.iter
    (fun (it : structure_item) ->
      match it.str_desc with
      | Tstr_value (_, vbs) ->
          List.iter
            (fun (vb : value_binding) ->
              (match vb.vb_pat.pat_desc with
              | Tpat_var (id, _, _) when Ident.name id = "wrapped" -> wrapped_expr := Some vb.vb_expr
              | _ -> ()) ;
              let iterator =
                { Tast_iterator.default_iterator with
                  expr =
                    (fun self e ->
                      (match e.exp_desc, !wrapped with
                      | Texp_function _, Some (_, t) when e != t.expected_body && !decoy = None ->
                          decoy := Some e
                      | _ -> ()) ;
                      Tast_iterator.default_iterator.expr self e) }
              in
              iterator.expr iterator vb.vb_expr)
            vbs
      | _ -> ())
    structure.str_items ;
  let identity_control =
    match !wrapped, !wrapped_expr, !decoy with
    | Some (stamp, t), Some expr, Some wrong_body ->
        let shared_ghost_loc = {t.expected_body.exp_loc with loc_ghost = true} in
        let wrong_body = {wrong_body with exp_loc = shared_ghost_loc} in
        let wrong =
          {t with expected_body = wrong_body; matching_bodies = 0;
                  expected_body_observed = false; stored_body = false}
        in
        Hashtbl.replace control_targets stamp wrong ;
        ignore
          (C.collect_calls_from_expr_with_open_bodies ~open_body_targets:control_targets
             ~local_fn_stamps ~src_path:"native.ml" ~caller_module:"native.ml"
             ~caller_name:"wrapped" expr) ;
        `Assoc
          [ ("canonical_matches", `Int wrong.matching_bodies);
            ("physical_expected", `Bool wrong.expected_body_observed) ]
    | _ -> failwith "identity-control premise"
  in
  let multiple_control =
    let multiple_targets = C.build_open_body_targets structure in
    match !wrapped_expr with
    | Some expr ->
        let t =
          Hashtbl.fold
            (fun _ (t : C.open_body_target) found ->
              if t.display_name = "wrapped" then Some t else found)
            multiple_targets None
          |> Option.get
        in
        for _ = 1 to 2 do
          ignore
            (C.collect_calls_from_expr_with_open_bodies ~open_body_targets:multiple_targets
               ~local_fn_stamps ~src_path:"native.ml" ~caller_module:"native.ml"
               ~caller_name:"wrapped" expr)
        done ;
        `Assoc [("canonical_matches", `Int t.matching_bodies);
                ("physical_expected", `Bool t.expected_body_observed)]
    | None -> failwith "multiple-control premise"
  in
  print_endline
    (Yojson.Basic.to_string
       (`Assoc
          [("rows", `List !rows); ("targets", `List target_rows);
          ("identity_control", identity_control);
          ("multiple_control", multiple_control)]))
