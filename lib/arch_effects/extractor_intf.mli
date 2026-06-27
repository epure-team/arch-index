(** Extractor interface contract for per-language effect/mutation analysis.

    Phase 1 defines Capability A (effects/mutators-of) and Capability C
    (dead-code / unreachable-from-roots).

    Design principles
    -----------------
    - Language-agnostic core: this module type is the contract every per-language
      extractor must satisfy.  Adding a new language = implement this signature.
    - Soundness label discipline: a Tier-1 extractor (OCaml CMT, Rust MIR, Go SSA)
      should mark its results 'sound'; a Tier-0 (LSP/tree-sitter) extractor marks
      them 'candidate'.  The query layer propagates the weakest label in a transitive
      closure.
    - Extension points for future capabilities:
        B  yield-race: add [yield_point] field to {effect_record}
        D  error-sink: add [is_error_path] field to {effect_record}
      Both are annotated with "Ext-B" / "Ext-D" comments below.
*)

(** The standard value-kind taxonomy.  Each constructor corresponds to a row in
    the [value_kinds] table seeded by the migration DDL.

    Extension note: to add a value kind for capability B (yield-race) or D
    (error-sink), add a constructor here and a seed row in the migration. *)
type value_kind =
  | GlobalVar     (** Module-level mutable ref / global variable *)
  | FieldAccess   (** Mutable record field write *)
  | ArrayElem     (** Array element write *)
  | HashTbl       (** Hashtbl mutation *)
  | BytesBuf      (** Bytes / Buffer mutation *)
  | HeapRef       (** ref dereference-and-assign (:=) / &mut pointer write *)
  | IoSideEffect  (** Print / write / flush *)
  | EnvVar        (** Environment variable mutation *)
  | FileSystem    (** File-system mutation *)
  | Network       (** Network I/O *)
  | UnknownMut    (** Opaque / unclassifiable mutation *)

val value_kind_to_string : value_kind -> string
val value_kind_of_string : string -> value_kind option

(** Soundness label for an extracted effect record. *)
type soundness =
  | Sound     (** Tier-1: CMT / MIR / SSA — sound over-approximation *)
  | Candidate (** Tier-0: LSP / tree-sitter — may under-approximate *)
  | Manual    (** Human-annotated *)

val soundness_to_string : soundness -> string

(** A single direct mutation attributed to a function.
    "Direct" means the function body itself contains the mutation;
    transitive mutations (via callees) are computed at query time. *)
type effect_record = {
  er_function_name : string;
      (** Qualified function name; must match the key in [functions.name] /
          [calls.caller_name] for the call-graph join to work. *)
  er_file_path     : string option;
      (** Source file of the function (relative to project root). *)
  er_value_kind    : value_kind;
      (** What kind of state the function mutates. *)
  er_target        : string option;
      (** Optional detail: field name, global variable name, param position…
          NULL = unknown / not applicable. *)
  er_soundness     : soundness;
      (** How was this record derived? *)
  er_producer      : string;
      (** Identifies the extractor: e.g. "arch-effects-ocaml-cmt". *)

  (* Ext-B (yield-race): add:
       er_yield_before : bool;
         (** true iff the mutation occurs after a yield / await in the same body. *)
  *)
  (* Ext-D (error-sink): add:
       er_is_error_path : bool;
         (** true iff the mutation is only reachable on an error/failure branch. *)
  *)
}

(** Roots for dead-code analysis.
    A "root" is a function considered reachable a-priori (entrypoint, public API,
    test harness, etc.).  Functions not reachable from any root over
    MUST∪MAY_ENUMERATED∪MAY_TOP edges are candidate dead code.

    For sound producers (OCaml CMT, Go SSA, Rust MIR) unreachable-from-roots
    equals sound dead-code.  For Tier-0 (LSP under-approx) it is candidate only. *)
type root_spec =
  | Exported   (** All functions with [exported = 1] in the [functions] table *)
  | Named of string list
      (** Explicit list of function names (qualified, same key as [functions.name]) *)

(** Result of a dead-code query.
    Each unreachable function carries the soundness label of the producer that
    built the call graph underlying this verdict. *)
type dead_code_entry = {
  dc_function_name : string;
  dc_file_path     : string option;
  dc_soundness     : soundness;
      (** Soundness of the verdict: 'sound' only when the call-graph producer
          is Tier-1 (CMT/MIR/SSA) and the callgraph_contract flag is present. *)
}

(** Extractor interface: every per-language extractor must satisfy this type.
    The interface is intentionally narrow — extractors emit data; the query
    layer consumes it.  An extractor does NOT need to open or understand the
    main [architecture.db]; it writes to the effects tables via [Effects_db]. *)
module type S = sig

  (** [extract_effects ~source_root ~build_dir] analyses the compiled artefacts
      in [build_dir] (or the source tree at [source_root], depending on language)
      and returns the list of direct effect records.

      Tier-1 extractors should return [soundness = Sound].
      Tier-0 / partial extractors return [soundness = Candidate].

      Errors during per-function analysis MUST be logged and skipped — a single
      un-parseable function must not abort the whole extraction.  Loud-fail (raise)
      only on total build failure. *)
  val extract_effects
    :  source_root:string
    -> build_dir:string option
    -> effect_record list

  (** The producer identifier written into [function_effects.producer]. *)
  val producer_id : string

  (** The soundness tier for this extractor. *)
  val soundness_tier : soundness

end
