(** arch-effects-ocaml — CMT typedtree effects extractor.

    Usage: arch-effects-ocaml --build-dir <dir> [--source-root <dir>]

    Walks all .cmt files under --build-dir, detects direct mutations
    (HeapRef, FieldAccess, ArrayElem, HashTbl, BytesBuf, IoSideEffect,
    EnvVar, FileSystem, Network, GlobalVar), and emits one NDJSON record
    per detected effect to stdout.  Pipe into arch_effects_load to load
    into an arch-index SQLite database.

    Example:
      arch-effects-ocaml --build-dir _build/default/src/lib_protocol \
        --source-root . \
        | arch_effects_load campaign.db --migration effects-schema-migration.sql
*)

open Cmdliner
open Arch_effects.Extractor_intf
open Arch_effects.Ocaml_effects_extractor

let emit_json r =
  let kind_s = value_kind_to_string r.er_value_kind in
  let soundness_s = soundness_to_string r.er_soundness in
  let fp_json = match r.er_file_path with
    | None -> "null"
    | Some s -> Printf.sprintf "%S" s
  in
  let target_json = match r.er_target with
    | None -> "null"
    | Some s -> Printf.sprintf "%S" s
  in
  Printf.printf
    "{\"type\":\"effect\",\"function_name\":%S,\"file_path\":%s,\
     \"value_kind\":%S,\"target\":%s,\"soundness\":%S,\"producer\":%S}\n"
    r.er_function_name
    fp_json
    kind_s
    target_json
    soundness_s
    r.er_producer

let run build_dir source_root =
  let root = match source_root with
    | Some r -> r
    | None   -> Filename.dirname build_dir
  in
  let records = extract_effects ~source_root:root ~build_dir:(Some build_dir) in
  List.iter emit_json records;
  flush stdout;
  Printf.eprintf "arch-effects-ocaml: emitted %d effect records from %s\n%!"
    (List.length records) build_dir

let build_dir_arg =
  let doc = "Path to the dune build directory containing .cmt files \
             (e.g., _build/default/src/proto_025_PsUshuai/lib_protocol)." in
  Arg.(required & opt (some dir) None & info ["build-dir"; "b"] ~docv:"DIR" ~doc)

let source_root_arg =
  let doc = "Source tree root used to make file paths relative. \
             Defaults to the parent of --build-dir." in
  Arg.(value & opt (some string) None & info ["source-root"; "r"] ~docv:"DIR" ~doc)

let cmd =
  let doc = "Extract OCaml mutation effects from CMT files and emit NDJSON." in
  let info = Cmd.info "arch_effects_ocaml" ~doc in
  Cmd.v info Term.(const run $ build_dir_arg $ source_root_arg)

let () = exit (Cmd.eval cmd)
