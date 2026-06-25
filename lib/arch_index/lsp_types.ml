(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** OCaml type definitions for LSP 3.17 protocol messages. *)

type position = {line : int; character : int}

type range = {start : position; end_ : position}

type location = {uri : string; range : range}

type symbol_kind =
  | File
  | Module
  | Namespace
  | Package
  | Class
  | Method
  | Property
  | Field
  | Constructor
  | Enum
  | Interface
  | Function
  | Variable
  | Constant
  | String
  | Number
  | Boolean
  | Array
  | Object
  | Key
  | Null
  | EnumMember
  | Struct
  | Event
  | Operator
  | TypeParameter
  | Unknown

type symbol_information = {
  name : string;
  kind : symbol_kind;
  location : location;
  container_name : string option;
}

type document_symbol = {
  name : string;
  kind : symbol_kind;
  range : range;
  selection_range : range;
  children : document_symbol list;
}

type call_hierarchy_item = {
  name : string;
  kind : symbol_kind;
  uri : string;
  range : range;
  selection_range : range;
}

type call_hierarchy_outgoing_call = {
  to_ : call_hierarchy_item;
  from_ranges : range list;
}

(* -------------------------------------------------------------------------- *)
(* Yojson decoders                                                            *)
(* -------------------------------------------------------------------------- *)

let position_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some (`Int n) -> Ok n
        | Some (`Float f) -> Ok (int_of_float f)
        | _ -> Error (Printf.sprintf "position_of_yojson: missing field %s" k)
      in
      let ( let* ) = Result.bind in
      let* line = get "line" in
      let* character = get "character" in
      Ok {line; character}
  | _ -> Error "position_of_yojson: expected object"

let range_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some v -> Ok v
        | None -> Error (Printf.sprintf "range_of_yojson: missing field %s" k)
      in
      let ( let* ) = Result.bind in
      let* start_j = get "start" in
      let* end_j = get "end" in
      let* start = position_of_yojson start_j in
      let* end_ = position_of_yojson end_j in
      Ok {start; end_}
  | _ -> Error "range_of_yojson: expected object"

let location_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some v -> Ok v
        | None ->
            Error (Printf.sprintf "location_of_yojson: missing field %s" k)
      in
      let ( let* ) = Result.bind in
      let* uri_j = get "uri" in
      let* uri =
        match uri_j with
        | `String s -> Ok s
        | _ -> Error "location_of_yojson: uri not a string"
      in
      let* range_j = get "range" in
      let* range = range_of_yojson range_j in
      Ok {uri; range}
  | _ -> Error "location_of_yojson: expected object"

let symbol_kind_of_int = function
  | 1 -> File
  | 2 -> Module
  | 3 -> Namespace
  | 4 -> Package
  | 5 -> Class
  | 6 -> Function
  | 7 -> Variable
  | 8 -> Field
  | 9 -> Constructor
  | 10 -> Enum
  | 11 -> Interface
  | 12 -> Method
  | 13 -> Property
  | 14 -> Constant
  | 15 -> String
  | 16 -> Number
  | 17 -> Boolean
  | 18 -> Array
  | 19 -> Object
  | 20 -> Key
  | 21 -> Null
  | 22 -> EnumMember
  | 23 -> Struct
  | 24 -> Event
  | 25 -> Operator
  | 26 -> TypeParameter
  | _ -> Unknown

let symbol_kind_of_yojson json =
  match json with
  | `Int n -> Ok (symbol_kind_of_int n)
  | `Float f -> Ok (symbol_kind_of_int (int_of_float f))
  | _ -> Error "symbol_kind_of_yojson: expected integer"

let symbol_information_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some v -> Ok v
        | None ->
            Error
              (Printf.sprintf
                 "symbol_information_of_yojson: missing field %s"
                 k)
      in
      let ( let* ) = Result.bind in
      let* name_j = get "name" in
      let* name =
        match name_j with
        | `String s -> Ok s
        | _ -> Error "symbol_information_of_yojson: name not a string"
      in
      let* kind_j = get "kind" in
      let* kind = symbol_kind_of_yojson kind_j in
      let* location_j = get "location" in
      let* location = location_of_yojson location_j in
      let container_name =
        match List.assoc_opt "containerName" fields with
        | Some (`String s) -> Some s
        | _ -> None
      in
      Ok {name; kind; location; container_name}
  | _ -> Error "symbol_information_of_yojson: expected object"

let rec document_symbol_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some v -> Ok v
        | None ->
            Error
              (Printf.sprintf "document_symbol_of_yojson: missing field %s" k)
      in
      let ( let* ) = Result.bind in
      let* name_j = get "name" in
      let* name =
        match name_j with
        | `String s -> Ok s
        | _ -> Error "document_symbol_of_yojson: name not a string"
      in
      let* kind_j = get "kind" in
      let* kind = symbol_kind_of_yojson kind_j in
      let* range_j = get "range" in
      let* range = range_of_yojson range_j in
      let* sel_j = get "selectionRange" in
      let* selection_range = range_of_yojson sel_j in
      let children =
        match List.assoc_opt "children" fields with
        | Some (`List lst) ->
            List.filter_map
              (fun j ->
                match document_symbol_of_yojson j with
                | Ok s -> Some s
                | Error _ -> None)
              lst
        | _ -> []
      in
      Ok {name; kind; range; selection_range; children}
  | _ -> Error "document_symbol_of_yojson: expected object"

let call_hierarchy_item_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some v -> Ok v
        | None ->
            Error
              (Printf.sprintf
                 "call_hierarchy_item_of_yojson: missing field %s"
                 k)
      in
      let ( let* ) = Result.bind in
      let* name_j = get "name" in
      let* name =
        match name_j with
        | `String s -> Ok s
        | _ -> Error "call_hierarchy_item_of_yojson: name not a string"
      in
      let* kind_j = get "kind" in
      let* kind = symbol_kind_of_yojson kind_j in
      let* uri_j = get "uri" in
      let* uri =
        match uri_j with
        | `String s -> Ok s
        | _ -> Error "call_hierarchy_item_of_yojson: uri not a string"
      in
      let* range_j = get "range" in
      let* range = range_of_yojson range_j in
      let* sel_j = get "selectionRange" in
      let* selection_range = range_of_yojson sel_j in
      Ok {name; kind; uri; range; selection_range}
  | _ -> Error "call_hierarchy_item_of_yojson: expected object"

let call_hierarchy_outgoing_call_of_yojson json =
  match json with
  | `Assoc fields ->
      let get k =
        match List.assoc_opt k fields with
        | Some v -> Ok v
        | None ->
            Error
              (Printf.sprintf
                 "call_hierarchy_outgoing_call_of_yojson: missing field %s"
                 k)
      in
      let ( let* ) = Result.bind in
      let* to_j = get "to" in
      let* to_ = call_hierarchy_item_of_yojson to_j in
      let from_ranges =
        match List.assoc_opt "fromRanges" fields with
        | Some (`List lst) ->
            List.filter_map
              (fun j ->
                match range_of_yojson j with Ok r -> Some r | Error _ -> None)
              lst
        | _ -> []
      in
      Ok {to_; from_ranges}
  | _ -> Error "call_hierarchy_outgoing_call_of_yojson: expected object"
