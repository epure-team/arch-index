(** Capability extractor for Phase-2 attack-surface attribute derivation.

    Two sources populate capability records:

    - Static derivation: from file path patterns and CMT call-site patterns.
      Produces [cap_source = "static"]. Fields populated:
      [cap_reachability] from file path suffix;
      [cap_gating] from call-site patterns (check_*/assert_manager/Signature.check).

    - Sidecar YAML ([load_sidecar]): agent-supplied annotation file.
      Format: component.capabilities.yaml.
      See docs/attack-surface-capability.md for the sidecar format.
      Produces [cap_source = "sidecar"] for new records; merges into static records
      (sidecar wins on non-None fields).

    The two sources are merged by [merge_records]: sidecar values override
    statically-derived values on a per-field basis.

    Neither source fills all fields; that is intentional.  [None] means
    "not yet determined"; downstream tools (Quint generator) treat [None]
    as an over-approximation (any). *)

open Capability_types

(** [derive_reachability_class file_path] infers the reachability class from
    the source file path.

    Heuristics (in priority order):
    - Contains "validate" component or suffix → Validate
    - Contains "apply" component or suffix → Apply
    - Contains "rpc" anywhere in path → Rpc
    - Contains "internal_operation" or "internal_op" → InternalOp
    - Contains "init" or "genesis" → Init
    - Contains "mempool" or "p2p" or "node" → NodeLocal
    - Anything else that looks like an operation handler → ExternalOp
    - Cannot determine → None *)
val derive_reachability_class : string -> reachability_class option

(** [derive_gating_from_calls callee_names] scans a list of callee names
    (e.g. from the CMT call graph) and returns a gating annotation if a
    recognisable gating pattern is present.

    Patterns detected:
    - check_*_enabled / *_feature_enabled / assert_feature_enabled → flag(X)
    - assert_manager / check_manager / check_source → auth(manager_key)
    - Signature.check / Bls.check / check_signature → auth(signature)
    - Gas.check / Fees.check_fees / assert_gas → cost(gas)
    - No matching callee → None (caller may have "none" set by sidecar)

    Returns the FIRST match only; multiple gates are not expressed here. *)
val derive_gating_from_calls : string list -> string option

(** [make_static_record ~function_name ~file_path ~callees] produces a
    [capability_record] using only statically-derivable information.
    [callees] is the list of direct callee names from the call graph.
    Fields that cannot be derived are [None] / [[]]. *)
val make_static_record
  :  function_name:string
  -> file_path:string option
  -> callees:string list
  -> capability_record

(** [merge_records ~base ~override] merges two [capability_record]s for the
    same function.  [override] wins on every non-None field; [base] values
    are kept where [override] has None.  The [cap_source] of [override] is
    kept so the provenance reflects the last writer. *)
val merge_records
  :  base:capability_record
  -> override:capability_record
  -> capability_record

(* ── sidecar loader ─────────────────────────────────────────────────────── *)

(** Result of parsing a sidecar file. *)
type sidecar_result = {
  sc_capabilities : capability_record list;
  sc_edges        : attack_edge list;
  sc_errors       : string list;  (** non-fatal parse warnings *)
}

(** [load_sidecar path] parses a [<component>.capabilities.yaml] sidecar file
    and returns the capability records and attack edges it contains.

    YAML format (see docs/attack-surface-capability.md):
    {v
      capabilities:
        - fn: "Module.function_name"
          file_path: "src/proto/module.ml"      # optional component discriminator (G2)
          actor_role: ["user", "admin"]
          temporal_class: ["validate_time", "window_open"]
          precondition: "state.account_registered = true"
          gating: "auth(manager_key)"
          value_touched: [{"kind": "balance", "direction": "debit"}]
      attack_edges:
        - from: "Module.fn_a"
          from_path: "src/proto/module.ml"       # optional endpoint discriminator (G2)
          to: "Module.fn_b"
          to_path: "kernel/src/other.rs"          # optional endpoint discriminator (G2)
          edge_type: "removes_guard"
          evidence: "fn_a sets flag X that fn_b requires"
    v}

    Parsing notes:
    - [value_touched] is an inline JSON-ish list of [{kind, direction}] objects;
      [kind] in balance|ticket|stake|supply, [direction] in debit|credit|mint|burn.
      Objects missing either field are skipped.
    - Inline ` # ...` comments on value lines are stripped (a [#] inside a
      single- or double-quoted span is preserved).
    - [file_path] / [from_path] / [to_path] are optional discriminators that
      disambiguate cross-component endpoints whose bare names could collide.

    Parse errors on individual items are accumulated in [sc_errors] and those
    items are skipped; the call never raises. *)
val load_sidecar : string -> sidecar_result
