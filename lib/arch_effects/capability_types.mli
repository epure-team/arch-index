(** Shared types for Phase-2 capability attributes.

    These types represent the Phase-2 attack-surface layer: each function/action
    in the index can carry a capability record describing WHO calls it, WHEN it
    runs, WHAT gates it, and WHAT protocol values it touches.

    Static derivability
    -------------------
    Some attributes can be derived from source file paths or call patterns in the
    CMT data; others require agent or human annotation (sidecar YAML).

    Statically derivable:
      - [reachability_class] — from file path suffix (validate.ml → Validate, etc.)
      - [gating]             — from call-site patterns (check_*/assert_manager/Signature.check)

    Require sidecar annotation:
      - [actor_role]      — requires protocol semantics; not derivable from syntax
      - [temporal_class]  — requires protocol state machine knowledge
      - [precondition]    — requires invariant knowledge
      - [value_touched]   — partially derivable (effects table) but semantic labelling needs sidecar

    The sidecar YAML format is documented in docs/attack-surface-capability.md. *)

(** Which processing phase (or subsystem) a function belongs to.  The classes
    are heuristic labels inferred from the source file path; on a codebase that
    does not use these conventions the class is simply [Unknown]. *)
type reachability_class =
  | Validate       (** validation phase — checks before state-mutating work *)
  | Apply          (** state-mutating apply phase *)
  | InternalOp     (** internally-triggered operation handler *)
  | Rpc            (** RPC / request handler — external-facing *)
  | ExternalOp     (** externally-triggered operation handler *)
  | NodeLocal      (** node-local infrastructure (networking, storage layer) *)
  | Init           (** initialization / bootstrap *)
  | Unknown        (** could not be determined from file path *)

val reachability_class_to_string : reachability_class -> string
val reachability_class_of_string : string -> reachability_class option

(** A single value-flow touch: which value kind and which direction. *)
type value_touch = {
  vt_kind      : string;  (** free-form, e.g. balance | resource | quota | supply *)
  vt_direction : string;  (** debit | credit | mint | burn *)
}

(** Full capability record for one function/action.
    NULL-tolerant: use [None] for attributes that cannot be statically derived.
    The sidecar loader merges sidecar facts by overwriting [None] fields. *)
type capability_record = {
  cap_function_name   : string;
      (** Must match the key in [function_effects.function_name]. *)
  cap_file_path       : string option;
  cap_reachability    : reachability_class option;
      (** Statically derivable from file path. *)
  cap_actor_role      : string option;
      (** Comma-separated, free-form. Example vocabulary: any | user | admin |
          operator | service | external.  Needs sidecar. *)
  cap_temporal_class  : string option;
      (** Comma-separated tags, free-form. Example vocabulary: init_time |
          validate_time | apply_time | window_open | boundary.  Needs sidecar. *)
  cap_gating          : string option;
      (** Pattern: flag(foo) | auth(key) | cost(resource) | none.
          Statically derivable from call patterns. *)
  cap_value_touched   : value_touch list;
      (** Value flows.  Partially derivable (from effects table) but semantic
          labelling requires sidecar. *)
  cap_precondition    : string option;
      (** Typed state predicate.  Needs sidecar. *)
  cap_source          : string;
      (** Who produced this record: 'static' | 'sidecar' | 'manual'. *)
}

(** An attack-graph edge between two actions.

    [ae_from_path] / [ae_to_path] are optional source-file / component
    discriminators for the endpoints (gap G2): when set, they disambiguate
    cross-component edges whose endpoint names could collide across language
    extractors (e.g. a bare Rust kernel [timeout] vs a qualified OCaml name). *)
type attack_edge = {
  ae_from      : string;
  ae_from_path : string option;
  ae_to        : string;
  ae_to_path   : string option;
  ae_type      : edge_type;
  ae_evidence  : string option;
  ae_source    : string;   (** 'static' | 'sidecar' | 'manual' *)
}

and edge_type =
  | Sequence       (** action A is typically followed by action B *)
  | RemovesGuard   (** action A removes a gate/lock that B requires *)
  | SharesResource (** A and B share a mutable resource (P13 pruning) *)
  | ActorDistinct  (** A and B are meaningful when performed by different actors *)

val edge_type_to_string : edge_type -> string
val edge_type_of_string : string -> edge_type option
