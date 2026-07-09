(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Call graph extraction using LSP callHierarchy. *)

type call_row = {
  caller_name : string;
  caller_file : string;
  callee_name : string;
  callee_file : string option;
  call_site : string;
}

(** [strip_file_uri uri] removes the "file://" prefix. *)
let strip_file_uri uri =
  if String.length uri > 7 && String.sub uri 0 7 = "file://" then
    String.sub uri 7 (String.length uri - 7)
  else uri

(** [relative_path ~project_dir abs_path] makes path relative to project_dir. *)
let relative_path ~project_dir abs_path =
  let plen = String.length project_dir in
  if
    String.length abs_path > plen
    && String.sub abs_path 0 plen = project_dir
    && abs_path.[plen] = '/'
  then String.sub abs_path (plen + 1) (String.length abs_path - plen - 1)
  else abs_path

(** [call_site_label ~project_dir item range] creates a human-readable
    call site string from a file URI and line number. *)
let call_site_label ~project_dir uri range =
  let abs = strip_file_uri uri in
  let rel = relative_path ~project_dir abs in
  Printf.sprintf "%s:%d" rel (range.Lsp_types.start.line + 1)

(** [prepare_call_hierarchy client ~project_dir row] sends
    callHierarchy/prepare for the function at its location. *)
let prepare_call_hierarchy client ~project_dir (row : Lsp_extractor.fn_row) =
  let abs_path = Filename.concat project_dir row.file_path in
  let uri = "file://" ^ abs_path in
  let params =
    `Assoc
      [
        ("textDocument", `Assoc [("uri", `String uri)]);
        ( "position",
          `Assoc [("line", `Int row.line_start); ("character", `Int row.name_char)] );
      ]
  in
  match
    Lsp_client.request client ~method_:"textDocument/prepareCallHierarchy" ~params ()
  with
  | Error _ -> []
  | Ok `Null -> []
  | Ok (`List lst) ->
      List.filter_map
        (fun j ->
          match Lsp_types.call_hierarchy_item_of_yojson j with
          | Ok item -> Some item
          | Error _ -> None)
        lst
  | Ok _ -> []

(** [outgoing_calls client ~project_dir item] fetches outgoing calls for a
    CallHierarchyItem. *)
let outgoing_calls client ~project_dir (item : Lsp_types.call_hierarchy_item) =
  let params =
    `Assoc
      [
        ( "item",
          `Assoc
            [
              ("name", `String item.name);
              ("kind", `Int 12 (* arbitrary, server re-resolves *));
              ("uri", `String item.uri);
              ( "range",
                `Assoc
                  [
                    ( "start",
                      `Assoc
                        [
                          ("line", `Int item.range.start.line);
                          ("character", `Int item.range.start.character);
                        ] );
                    ( "end",
                      `Assoc
                        [
                          ("line", `Int item.range.end_.line);
                          ("character", `Int item.range.end_.character);
                        ] );
                  ] );
              ( "selectionRange",
                `Assoc
                  [
                    ( "start",
                      `Assoc
                        [
                          ("line", `Int item.selection_range.start.line);
                          ( "character",
                            `Int item.selection_range.start.character );
                        ] );
                    ( "end",
                      `Assoc
                        [
                          ("line", `Int item.selection_range.end_.line);
                          ("character", `Int item.selection_range.end_.character);
                        ] );
                  ] );
            ] );
      ]
  in
  match
    Lsp_client.request client ~method_:"callHierarchy/outgoingCalls" ~params ()
  with
  | Error _ -> []
  | Ok `Null -> []
  | Ok (`List lst) ->
      List.filter_map
        (fun j ->
          match Lsp_types.call_hierarchy_outgoing_call_of_yojson j with
          | Ok call ->
              let callee_abs = strip_file_uri call.to_.uri in
              let callee_file =
                let rel = relative_path ~project_dir callee_abs in
                if rel = callee_abs then None else Some rel
              in
              let call_site =
                match call.from_ranges with
                | range :: _ -> call_site_label ~project_dir item.uri range
                | [] -> call_site_label ~project_dir item.uri item.range
              in
              Some
                {
                  caller_name = item.name;
                  caller_file =
                    relative_path ~project_dir (strip_file_uri item.uri);
                  callee_name = call.to_.name;
                  callee_file;
                  call_site;
                }
          | Error _ -> None)
        lst
  | Ok _ -> []

(* -------------------------------------------------------------------------- *)
(* CMT-based call extraction (fallback when LSP call hierarchy unavailable)  *)
(* -------------------------------------------------------------------------- *)

(** [extract_calls_from_cmts ~project_dir fn_rows] reads OCaml CMT files from
    [_build/default/] and extracts call edges by walking the typed AST.
    This is the fallback path for LSP servers (like ocamllsp ≤1.23) that do
    not yet implement callHierarchy. *)
let extract_calls_from_cmts ~project_dir fn_rows =
  let build_dir = Filename.concat project_dir "_build/default" in
  if not (Sys.file_exists build_dir) then []
  else begin
    (* name -> file_path index for resolving callee files *)
    let name_to_file : (string, string) Hashtbl.t = Hashtbl.create 512 in
    List.iter
      (fun (r : Lsp_extractor.fn_row) ->
        Hashtbl.replace name_to_file r.name r.file_path)
      fn_rows ;
    let cmt_files = Arch_index_cmt.find_cmt_files build_dir in
    let cmt_only =
      List.filter
        (fun p -> not (Filename.check_suffix p ".cmti"))
        cmt_files
    in
    List.concat_map
      (fun cmt_path ->
        match Cmt_format.read cmt_path with
        | _, None -> []
        | _, Some info -> (
            match info.Cmt_format.cmt_annots with
            | Cmt_format.Implementation structure -> (
                match
                  Arch_index_support.source_path_of_cmt ~project_root:project_dir info
                with
                | None -> []
                | Some abs_src ->
                    let rel_src = relative_path ~project_dir abs_src in
                    let pending = ref [] in
                    (* Same-module top-level function-body stamps: an applied
                       unqualified identifier is MUST-resolvable only if its
                       stamp is here (see Arch_index_cmt.collect_calls_from_expr). *)
                    let local_fn_stamps = Hashtbl.create 64 in
                    List.iter
                      (fun (item : Typedtree.structure_item) ->
                        match item.str_desc with
                        | Typedtree.Tstr_value (_, vbs) ->
                            List.iter
                              (fun (vb : Typedtree.value_binding) ->
                                match vb.vb_pat.pat_desc with
                                | Typedtree.Tpat_var (id, _, _)
                                  when Arch_index_cmt.is_function_rhs vb.vb_expr
                                  ->
                                    Hashtbl.replace
                                      local_fn_stamps
                                      (Ident.unique_name id)
                                      (Arch_index_cmt.fn_arity vb.vb_expr)
                                | _ -> ())
                              vbs
                        | _ -> ())
                      structure.Typedtree.str_items ;
                    List.iter
                      (fun (item : Typedtree.structure_item) ->
                        match item.str_desc with
                        | Typedtree.Tstr_value (_, vbs) ->
                            List.iter
                              (fun (vb : Typedtree.value_binding) ->
                                match vb.vb_pat.pat_desc with
                                | Typedtree.Tpat_var (id, _, _) ->
                                    let caller_name = Ident.name id in
                                    let calls, _lam_nodes =
                                      Arch_index_cmt.collect_calls_from_expr
                                        ~src_path:rel_src
                                        ~caller_module:rel_src
                                        ~caller_name
                                        ~local_fn_stamps
                                        vb.vb_expr
                                    in
                                    (* Flat path: lambda-attributed calls flow
                                       through with synthetic caller names; no
                                       function rows here (kind-less schema). *)
                                    pending := calls @ !pending
                                | _ -> ())
                              vbs
                        | _ -> ())
                      structure.Typedtree.str_items ;
                    List.map
                      (fun (pc : Arch_index_cmt.pending_call) ->
                        let callee_name, _mod =
                          Arch_index_cmt.pending_display pc
                        in
                        let callee_file =
                          Hashtbl.find_opt name_to_file callee_name
                        in
                        {
                          caller_name = pc.caller_name;
                          caller_file = rel_src;
                          callee_name;
                          callee_file;
                          call_site = pc.call_site;
                        })
                      !pending)
            | _ -> []))
      cmt_only
  end

let extract_calls client ~project_dir fn_rows =
  (* Try LSP call hierarchy first; fall back to CMT if it yields nothing. *)
  let candidates =
    List.filter
      (fun (row : Lsp_extractor.fn_row) -> row.exported || row.summary <> None)
      fn_rows
  in
  let lsp_calls =
    List.concat_map
      (fun row ->
        let items = prepare_call_hierarchy client ~project_dir row in
        List.concat_map (outgoing_calls client ~project_dir) items)
      candidates
  in
  if lsp_calls <> [] then lsp_calls
  else extract_calls_from_cmts ~project_dir fn_rows
