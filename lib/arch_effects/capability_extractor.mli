(** Capability extractor for Phase-2 attack-surface attributes.

    Capability records are populated from a sidecar YAML file ([load_sidecar]):
    an agent- or human-supplied annotation file named
    [<component>.capabilities.yaml].  See docs/attack-surface-capability.md for
    the format.

    [load_sidecar] fills only the fields the sidecar provides; the rest stay
    [None] / [[]].  [None] means "not yet determined"; downstream tools treat
    it as an over-approximation (any). *)

open Capability_types

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
