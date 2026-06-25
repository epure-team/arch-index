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
          `Assoc [("line", `Int row.line_start); ("character", `Int 0)] );
      ]
  in
  match
    Lsp_client.request client ~method_:"callHierarchy/prepare" ~params ()
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

let extract_calls client ~project_dir fn_rows =
  (* Only process exported or documented functions to bound request count *)
  let candidates =
    List.filter
      (fun (row : Lsp_extractor.fn_row) -> row.exported || row.summary <> None)
      fn_rows
  in
  List.concat_map
    (fun row ->
      let items = prepare_call_hierarchy client ~project_dir row in
      List.concat_map (outgoing_calls client ~project_dir) items)
    candidates
