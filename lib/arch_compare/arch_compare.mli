(** Metrics regression gate engine (specs/arch-metrics-gate.md).

    Compares a current flat metrics JSON against a committed baseline, applying
    the [.metrics-accept] reviewed-waiver policy. Pure: no DB access. *)

module Metric_map : sig
  include Map.S with type key = string

  val of_list : (string * 'a) list -> 'a t
end

type metric_change = {metric : string; baseline : float; current : float}

type comparison_result = {
  regressions : metric_change list;
  improvements : metric_change list;
  unchanged : (string * float) list;
  missing : (string * float) list;  (** tracked, in baseline, absent from current *)
}

type acceptance_entry = {metric : string; bound : float; reason : string; line : int}

type acceptance_error = {metric : string; line : int; message : string}

type acceptance_file = {
  accepted : acceptance_entry list;
  invalid_entries : acceptance_error list;
}

type gate_result = {
  comparison : comparison_result;
  blocking_regressions : metric_change list;
  accepted_regressions : (metric_change * acceptance_entry) list;
  invalid_acceptances : acceptance_error list;
}

val is_tracked_metric : string -> bool

val acceptance_operator : string -> string
(** ["<="] for worse-when-higher metrics, [">="] for worse-when-lower. *)

val parse_metrics_json_string : string -> (float Metric_map.t, string) result
(** Strict: input must be a flat [{string: number}] JSON object (FR-009). *)

val parse_metrics_json : string -> (float Metric_map.t, string) result
(** [parse_metrics_json path] — error messages are prefixed with [path]. *)

val parse_accept_file_string : string -> acceptance_file

val load_accept_file : string -> acceptance_file
(** Absent file = empty policy, no error (FR-016). *)

val compare_metrics :
  baseline:float Metric_map.t -> current:float Metric_map.t -> comparison_result

val evaluate :
  acceptance:acceptance_file ->
  baseline:float Metric_map.t ->
  current:float Metric_map.t ->
  gate_result

val render_report :
  baseline_path:string -> current_path:string -> gate_result -> string

val has_failures : gate_result -> bool
(** True iff blocking regressions, missing tracked metrics, or invalid
    [.metrics-accept] entries exist (FR-007). *)
