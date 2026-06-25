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

val position_of_yojson : Yojson.Safe.t -> (position, string) result

val range_of_yojson : Yojson.Safe.t -> (range, string) result

val location_of_yojson : Yojson.Safe.t -> (location, string) result

val symbol_kind_of_yojson : Yojson.Safe.t -> (symbol_kind, string) result

val symbol_kind_of_int : int -> symbol_kind

val symbol_information_of_yojson :
  Yojson.Safe.t -> (symbol_information, string) result

val document_symbol_of_yojson :
  Yojson.Safe.t -> (document_symbol, string) result

val call_hierarchy_item_of_yojson :
  Yojson.Safe.t -> (call_hierarchy_item, string) result

val call_hierarchy_outgoing_call_of_yojson :
  Yojson.Safe.t -> (call_hierarchy_outgoing_call, string) result
