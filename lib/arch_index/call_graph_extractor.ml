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
  edge_form : string option;
}

(* Third duplicate of the strip; delegates to the module that owns the pair. *)
let strip_file_uri = Lsp_client.path_of_file_uri

(** [relative_path ~project_dir abs_path] makes path relative to project_dir. *)
let relative_path = Lsp_client.relative_path

(** [call_site_label ~project_dir item range] creates a human-readable
    call site string from a file URI and line number. *)
let call_site_label ~project_dir uri range =
  let abs = strip_file_uri uri in
  let rel = relative_path ~project_dir abs in
  Printf.sprintf "%s:%d" rel (range.Lsp_types.start.line + 1)

(* [name_column ~abs_path ~line ~name] is the column at which [name] occurs on
   [line], if it does.  workspace/symbol reports the range of the whole
   declaration, so its start column lands on [pub] or [func] rather than on the
   identifier -- and rust-analyzer only answers prepareCallHierarchy when the
   position is on the name itself. *)
let name_column ~abs_path ~line ~name =
  match open_in_bin abs_path with
  | exception _ -> None
  | ic ->
      let rec nth_line i =
        match input_line ic with
        | exception End_of_file -> None
        | l -> if i = line then Some l else nth_line (i + 1)
      in
      let result =
        match nth_line 0 with
        | None -> None
        | Some l ->
            let n = String.length name and len = String.length l in
            let rec find i =
              if i + n > len then None
              else if String.sub l i n = name then Some i
              else find (i + 1)
            in
            if n = 0 then None else find 0
      in
      close_in_noerr ic ;
      result

(** [prepare_call_hierarchy client ~project_dir row] sends
    callHierarchy/prepare for the function at its location.  When the position
    the symbol reported yields nothing, it retries on the identifier itself. *)
(* One line per distinct fact, not per attempt. The diagnostics below sit inside
   the warm-up retry loop ([attempt 20] in [extract_calls]), which re-sweeps every
   function while the server loads — so a server that refuses
   prepareCallHierarchy throughout emitted the identical line up to 21 times per
   function: 315 lines on a 15-function fixture, ~9000 on this repo. That defeats
   the reason the line is per-item at all, which is that the COUNT distinguishes
   "one document refused" from "all of them".

   The memo is created per run in [extract_calls] and threaded, rather than being
   a module-level table: a global would leak between runs in a process that
   indexes more than one project. Two scenarios, and they are not equally
   real. Cross-pass collision is IMPOSSIBLE, not merely unlikely:
   [Language_registry.detect_language_roots] keeps one root per language
   ([add_in] guards on [Hashtbl.mem]), the per-language extension sets are
   disjoint, and both call sites key on paths — so two passes can never
   produce the same (method, path). The remaining scenario is one process
   indexing the same project twice, where a global table would suppress the
   second run's diagnostics entirely. That one IS constructible, and
   [Arch_index.run_lsp] is public, so a test could pin it; no current caller
   does it ([arch_index_cli] calls [run_lsp] or [run_lsp_multi] exactly once),
   so this guard is DEFENSIVE and untested by choice, not untestable.

   [path] must be a path at BOTH call sites, so the bound is one line per
   (method, file) and not one per function: keying the outgoingCalls site on
   [item.name] would emit one line per function -- 432 on this repo -- and would
   print "failed for <name>" where the reader expects a file. *)
let report_once seen ~method_ ~path msg =
  let key = method_ ^ " " ^ path in
  if not (Hashtbl.mem seen key) then begin
    Hashtbl.replace seen key () ;
    Arch_io.eprintf "arch_index: %s failed for %s — %s\n%!" method_ path msg
  end

let prepare_call_hierarchy ~seen client ~project_dir (row : Lsp_extractor.fn_row)
    =
  let abs_path = Filename.concat project_dir row.file_path in
  let uri = Lsp_client.file_uri_of_path abs_path in
  let request_at character =
    let params =
      `Assoc
        [
          ("textDocument", `Assoc [("uri", `String uri)]);
          ( "position",
            `Assoc [("line", `Int row.line_start); ("character", `Int character)]
          );
        ]
    in
    match
      Lsp_client.request client ~method_:"textDocument/prepareCallHierarchy"
        ~params ()
    with
    | Error msg ->
        report_once
          seen
          ~method_:"prepareCallHierarchy"
          ~path:row.Lsp_extractor.file_path
          msg ;
        []
    | Ok `Null -> []
    | Ok (`List lst) ->
        List.filter_map
          (fun j ->
            match Lsp_types.call_hierarchy_item_of_yojson j with
            | Ok item -> Some item
            | Error _ -> None)
          lst
    | Ok _ -> []
  in
  match request_at row.name_char with
  | _ :: _ as items -> items
  | [] -> (
      match name_column ~abs_path ~line:row.line_start ~name:row.name with
      | Some col when col <> row.name_char -> request_at col
      | _ -> [])

(** [outgoing_calls client ~project_dir item] fetches outgoing calls for a
    CallHierarchyItem. *)
let outgoing_calls ~seen client ~project_dir
    (item : Lsp_types.call_hierarchy_item) =
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
  | Error msg ->
      report_once seen ~method_:"outgoingCalls"
        ~path:(relative_path ~project_dir (strip_file_uri item.uri))
        msg ;
      []
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
                  (* The LSP path reports CALLS. A point-free binding makes
                     none, so callHierarchy cannot observe one and this backend
                     has nothing to mark. *)
                  edge_form = None;
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
                       stamp is here — shared pre-pass with the main indexer. *)
                    let local_fn_stamps =
                      Arch_index_cmt.build_local_fn_stamps structure
                    in
                    (* Issue #41's row-collapse (INSERT OR REPLACE on
                       UNIQUE(module_id, name)) never applies on this path:
                       this schema's `functions` rows come from LSP document
                       symbols (Lsp_extractor), not from this CMT walk, and
                       carry no UNIQUE(name) constraint — so there is no
                       shadowed-binding identity problem here to fix. Naming
                       a caller here with the main indexer's ordinal suffix
                       would instead BREAK consumers that join calls.caller_name
                       to functions.name by bare string (e.g. arch_serve.ml),
                       since those rows are never renamed to match. Bare
                       Ident.name id is deliberately kept, matching pre-#41
                       behavior on this path. *)
                    List.iter
                      (fun (item : Typedtree.structure_item) ->
                        match item.str_desc with
                        | Typedtree.Tstr_value (_, vbs) ->
                            List.iter
                              (fun (vb : Typedtree.value_binding) ->
                                match vb.vb_pat.pat_desc with
                                | Typedtree.Tpat_var (id, _, _) ->
                                    let caller_name = Ident.name id in
                                    let calls, _lam_nodes, _exn_facts, _errch_facts =
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
                          edge_form = pc.edge_form;
                        })
                      !pending)
            | _ -> []))
      cmt_only
  end

(* A server that is still loading its workspace answers prepareCallHierarchy
   with nothing rather than with an error -- rust-analyzer does exactly that
   until cargo metadata and the initial index are done, and a warm target/ does
   not help because each process reloads.  So an empty first sweep is not
   evidence of a call-free program: wait and sweep again, a bounded number of
   times, before believing it. *)
let sweep ~seen client ~project_dir fn_rows =
  List.concat_map
    (fun row ->
      let items = prepare_call_hierarchy ~seen client ~project_dir row in
      List.concat_map (outgoing_calls ~seen client ~project_dir) items)
    fn_rows

let extract_calls ?clock client ~project_dir fn_rows =
  (* Try LSP call hierarchy first; fall back to CMT if it yields nothing.

     Every row is queried, not just the exported ones: a private function's
     outgoing calls are exactly what reachability needs -- dropping them makes
     whatever it calls look uncalled.  The previous filter tied call-graph
     completeness to visibility, so tightening Go's visibility rule silently
     cost the graph its `main -> Entry` edge. *)
  (* A server still loading its workspace answers prepareCallHierarchy with
     nothing rather than with an error -- rust-analyzer does that until cargo
     metadata and the initial index are done.  An empty sweep is therefore not
     evidence of a call-free program: wait and sweep again, bounded.  Sweeping
     repeatedly once results have started arriving does not help and destabil-
     ises the server, so the first non-empty sweep is taken as the answer; an
     index built against a project that has never been compiled may still be
     partial, which is why the selftest warms its fixture first. *)
  let seen = Hashtbl.create 64 in
  let rec attempt n =
    match sweep ~seen client ~project_dir fn_rows with
    | _ :: _ as calls -> calls
    | [] -> (
        match clock with
        | Some clock when n > 0 ->
            Eio.Time.sleep clock 1.0 ;
            attempt (n - 1)
        | _ -> [])
  in
  let lsp_calls = if fn_rows = [] then [] else attempt 20 in
  if lsp_calls <> [] then lsp_calls
  else extract_calls_from_cmts ~project_dir fn_rows
