(** Implementation of the extractor interface shared types. *)

type value_kind =
  | GlobalVar
  | FieldAccess
  | ArrayElem
  | HashTbl
  | BytesBuf
  | HeapRef
  | IoSideEffect
  | EnvVar
  | FileSystem
  | Network
  | UnknownMut

let value_kind_to_string = function
  | GlobalVar    -> "GlobalVar"
  | FieldAccess  -> "FieldAccess"
  | ArrayElem    -> "ArrayElem"
  | HashTbl      -> "HashTbl"
  | BytesBuf     -> "BytesBuf"
  | HeapRef      -> "HeapRef"
  | IoSideEffect -> "IoSideEffect"
  | EnvVar       -> "EnvVar"
  | FileSystem   -> "FileSystem"
  | Network      -> "Network"
  | UnknownMut   -> "UnknownMut"

let value_kind_of_string = function
  | "GlobalVar"    -> Some GlobalVar
  | "FieldAccess"  -> Some FieldAccess
  | "ArrayElem"    -> Some ArrayElem
  | "HashTbl"      -> Some HashTbl
  | "BytesBuf"     -> Some BytesBuf
  | "HeapRef"      -> Some HeapRef
  | "IoSideEffect" -> Some IoSideEffect
  | "EnvVar"       -> Some EnvVar
  | "FileSystem"   -> Some FileSystem
  | "Network"      -> Some Network
  | "UnknownMut"   -> Some UnknownMut
  | _              -> None

type soundness = Sound | Candidate | Manual

let soundness_to_string = function
  | Sound     -> "sound"
  | Candidate -> "candidate"
  | Manual    -> "manual"

type effect_record = {
  er_function_name : string;
  er_file_path     : string option;
  er_value_kind    : value_kind;
  er_target        : string option;
  er_soundness     : soundness;
  er_producer      : string;
}

type root_spec =
  | Exported
  | Named of string list

type dead_code_entry = {
  dc_function_name : string;
  dc_file_path     : string option;
  dc_soundness     : soundness;
}

module type S = sig
  val extract_effects
    :  source_root:string
    -> build_dir:string option
    -> effect_record list
  val producer_id : string
  val soundness_tier : soundness
end
