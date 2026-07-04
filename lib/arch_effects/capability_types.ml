(** Phase-2 capability attribute types — implementation. *)

type reachability_class =
  | Validate
  | Apply
  | InternalOp
  | Rpc
  | ExternalOp
  | NodeLocal
  | Init
  | Unknown

let reachability_class_to_string = function
  | Validate   -> "validate"
  | Apply      -> "apply"
  | InternalOp -> "internal_op"
  | Rpc        -> "rpc"
  | ExternalOp -> "external_op"
  | NodeLocal  -> "node_local"
  | Init       -> "init"
  | Unknown    -> "unknown"

let reachability_class_of_string = function
  | "validate"    -> Some Validate
  | "apply"       -> Some Apply
  | "internal_op" -> Some InternalOp
  | "rpc"         -> Some Rpc
  | "external_op" -> Some ExternalOp
  | "node_local"  -> Some NodeLocal
  | "init"        -> Some Init
  | "unknown"     -> Some Unknown
  | _             -> None

type value_touch = {
  vt_kind      : string;
  vt_direction : string;
}

type capability_record = {
  cap_function_name   : string;
  cap_file_path       : string option;
  cap_reachability    : reachability_class option;
  cap_actor_role      : string option;
  cap_temporal_class  : string option;
  cap_gating          : string option;
  cap_value_touched   : value_touch list;
  cap_precondition    : string option;
  cap_source          : string;
}

type edge_type =
  | Sequence
  | RemovesGuard
  | SharesResource
  | ActorDistinct

type attack_edge = {
  ae_from      : string;
  ae_from_path : string option;
  ae_to        : string;
  ae_to_path   : string option;
  ae_type      : edge_type;
  ae_evidence  : string option;
  ae_source    : string;
}

let edge_type_to_string = function
  | Sequence      -> "sequence"
  | RemovesGuard  -> "removes_guard"
  | SharesResource -> "shares_resource"
  | ActorDistinct -> "actor_distinct"

let edge_type_of_string = function
  | "sequence"        -> Some Sequence
  | "removes_guard"   -> Some RemovesGuard
  | "shares_resource" -> Some SharesResource
  | "actor_distinct"  -> Some ActorDistinct
  | _                 -> None
