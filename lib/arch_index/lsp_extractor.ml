(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Symbol extraction from LSP server. *)

type fn_row = {
  name : string;
  file_path : string;
  line_start : int;
  line_end : int;
  exported : bool;
  signature : string option;
  summary : string option;
}

(** [is_function_kind k] returns true for function/method/constructor kinds. *)
let is_function_kind = function
  | Lsp_types.Function | Lsp_types.Method | Lsp_types.Constructor -> true
  | _ -> false

(** [strip_file_uri uri] removes the "file://" prefix from a URI. *)
let strip_file_uri uri =
  if String.length uri > 7 && String.sub uri 0 7 = "file://" then
    String.sub uri 7 (String.length uri - 7)
  else uri

(** [relative_path ~project_dir abs_path] makes [abs_path] relative to
    [project_dir]. Returns [abs_path] unchanged if not a prefix. *)
let relative_path ~project_dir abs_path =
  let plen = String.length project_dir in
  if
    String.length abs_path > plen
    && String.sub abs_path 0 plen = project_dir
    && abs_path.[plen] = '/'
  then String.sub abs_path (plen + 1) (String.length abs_path - plen - 1)
  else abs_path

(** [is_exported name] returns true if [name] does not start with underscore. *)
let is_exported name = String.length name = 0 || name.[0] <> '_'

(** [extract_from_workspace_symbol client ~project_dir] fetches all symbols
    via workspace/symbol and filters to function kinds. *)
let extract_from_workspace_symbol client ~project_dir =
  let params = `Assoc [("query", `String "")] in
  match Lsp_client.request client ~method_:"workspace/symbol" ~params () with
  | Error _ -> []
  | Ok `Null -> []
  | Ok (`List symbols) ->
      List.filter_map
        (fun sym_json ->
          match Lsp_types.symbol_information_of_yojson sym_json with
          | Error _ -> None
          | Ok sym ->
              if not (is_function_kind sym.kind) then None
              else
                let abs_path = strip_file_uri sym.location.uri in
                let file_path = relative_path ~project_dir abs_path in
                let line_start = sym.location.range.start.line in
                let line_end = sym.location.range.end_.line in
                Some
                  {
                    name = sym.name;
                    file_path;
                    line_start;
                    line_end;
                    exported = is_exported sym.name;
                    signature = None;
                    summary = None;
                  })
        symbols
  | Ok _ -> []

(** [flatten_document_symbols ~file_path syms] flattens a document symbol tree
    into fn_rows, keeping only function-kind symbols. *)
let rec flatten_document_symbols ~file_path = function
  | [] -> []
  | sym :: rest ->
      let children_rows =
        flatten_document_symbols ~file_path sym.Lsp_types.children
      in
      let self_rows =
        if is_function_kind sym.kind then
          [
            {
              name = sym.name;
              file_path;
              line_start = sym.range.start.line;
              line_end = sym.range.end_.line;
              exported = is_exported sym.name;
              signature = None;
              summary = None;
            };
          ]
        else []
      in
      self_rows @ children_rows @ flatten_document_symbols ~file_path rest

(** [read_file_text uri] reads the file at [uri] (a file:// URI) and returns
    its content, or [""] on error. *)
let read_file_text uri =
  let path =
    if String.length uri > 7 && String.sub uri 0 7 = "file://" then
      String.sub uri 7 (String.length uri - 7)
    else uri
  in
  try
    let ic = open_in path in
    let n = in_channel_length ic in
    let s = Bytes.create n in
    really_input ic s 0 n ;
    close_in ic ;
    Bytes.to_string s
  with _ -> ""

(** [language_id_of_uri uri] infers the LSP languageId from the file extension. *)
let language_id_of_uri uri =
  let path = strip_file_uri uri in
  let ext = Filename.extension path in
  match ext with ".tsx" -> "typescriptreact" | _ -> "typescript"

(** [extract_from_document_symbols client ~project_dir ~file_uri] opens the
    file via [textDocument/didOpen] then fetches document symbols. *)
let extract_from_document_symbols client ~project_dir ~file_uri =
  (* Open the file so the LSP server indexes it before we query symbols. *)
  let text = read_file_text file_uri in
  let lang = language_id_of_uri file_uri in
  Lsp_client.notify
    client
    ~method_:"textDocument/didOpen"
    ~params:
      (`Assoc
         [
           ( "textDocument",
             `Assoc
               [
                 ("uri", `String file_uri);
                 ("languageId", `String lang);
                 ("version", `Int 1);
                 ("text", `String text);
               ] );
         ])
    () ;
  let params = `Assoc [("textDocument", `Assoc [("uri", `String file_uri)])] in
  match
    Lsp_client.request client ~method_:"textDocument/documentSymbol" ~params ()
  with
  | Error _ -> []
  | Ok `Null -> []
  | Ok (`List lst) ->
      let abs_path = strip_file_uri file_uri in
      let file_path = relative_path ~project_dir abs_path in
      (* Try as document symbols first, fallback to symbol_information *)
      let syms =
        List.filter_map
          (fun j ->
            match Lsp_types.document_symbol_of_yojson j with
            | Ok s -> Some s
            | Error _ -> None)
          lst
      in
      if syms <> [] then flatten_document_symbols ~file_path syms
      else
        List.filter_map
          (fun j ->
            match Lsp_types.symbol_information_of_yojson j with
            | Error _ -> None
            | Ok sym ->
                if not (is_function_kind sym.kind) then None
                else
                  Some
                    {
                      name = sym.name;
                      file_path;
                      line_start = sym.location.range.start.line;
                      line_end = sym.location.range.end_.line;
                      exported = is_exported sym.name;
                      signature = None;
                      summary = None;
                    })
          lst
  | Ok _ -> []

(** [collect_file_uris rows] collects unique file URIs from workspace symbol
    rows (reconstructing URIs from relative paths). *)
let collect_file_uris ~project_dir rows =
  let seen = Hashtbl.create 64 in
  List.filter_map
    (fun row ->
      let abs = Filename.concat project_dir row.file_path in
      let uri = "file://" ^ abs in
      if Hashtbl.mem seen uri then None
      else begin
        Hashtbl.add seen uri () ;
        Some uri
      end)
    rows

(** [scan_ts_files ~project_dir] walks [project_dir] recursively and returns
    file:// URIs for all [.ts]/[.tsx] files, excluding [node_modules/],
    [dist/], [build/], [.d.ts] declaration files, and hidden directories. *)
let scan_ts_files ~project_dir =
  let uris = ref [] in
  let excluded_dirs = ["node_modules"; "dist"; "build"; ".git"] in
  let rec walk dir =
    try
      let entries = Sys.readdir dir in
      Array.iter
        (fun entry ->
          let path = Filename.concat dir entry in
          if Sys.is_directory path then begin
            if (not (List.mem entry excluded_dirs)) && entry.[0] <> '.' then
              walk path
          end
          else begin
            let ext = Filename.extension entry in
            let is_ts_src =
              (ext = ".ts" || ext = ".tsx")
              && not
                   (String.length entry > 5
                   && String.sub entry (String.length entry - 5) 5 = ".d.ts")
            in
            if is_ts_src then uris := ("file://" ^ path) :: !uris
          end)
        entries
    with _ -> ()
  in
  walk project_dir ;
  !uris

(** [merge_rows ws_rows doc_rows] merges workspace rows with document-symbol
    rows, preferring document-symbol rows (better line ranges) when available. *)
let merge_rows ws_rows doc_rows =
  (* Build lookup from (file_path, name) to doc_row *)
  let tbl = Hashtbl.create (List.length doc_rows) in
  List.iter
    (fun row -> Hashtbl.replace tbl (row.file_path, row.name) row)
    doc_rows ;
  (* For each ws_row, use doc_row if present *)
  let merged =
    List.map
      (fun row ->
        match Hashtbl.find_opt tbl (row.file_path, row.name) with
        | Some better -> better
        | None -> row)
      ws_rows
  in
  (* Also include doc_rows not in ws_rows *)
  let ws_keys =
    List.map (fun r -> (r.file_path, r.name)) ws_rows |> List.sort_uniq compare
  in
  let extra =
    List.filter (fun r -> not (List.mem (r.file_path, r.name) ws_keys)) doc_rows
  in
  merged @ extra

let extract_symbols client ~project_dir =
  (* Step 1: workspace-wide symbol list *)
  let ws_rows = extract_from_workspace_symbol client ~project_dir in
  (* Step 2: determine which files to query for document symbols.
     When workspace/symbol returns nothing (e.g. TypeScript monorepos with
     project references where tsserver doesn't index sub-packages), fall back
     to scanning the filesystem for source files directly. *)
  let file_uris =
    if ws_rows <> [] then collect_file_uris ~project_dir ws_rows
    else scan_ts_files ~project_dir
  in
  let doc_rows =
    List.concat_map
      (fun uri ->
        extract_from_document_symbols client ~project_dir ~file_uri:uri)
      file_uris
  in
  merge_rows ws_rows doc_rows
