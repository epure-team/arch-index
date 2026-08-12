(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

let () =
  Ocaml_shapes.register () ;
  Multilang.register () ;
  Curation_doc.register () ;
  Load.register () ;
  Load.register_enforcement () ;
  Health.register () ;
  Health.register_refusal () ;
  Contract.register () ;
  Contract.register_refusals () ;
  Contract.register_unknown_names () ;
  Contract.register_io_errors () ;
  Duplicates.register () ;
  Duplicates.register_unverifiable () ;
  Duplicates.register_refusals () ;
  Curation.register_load () ;
  Curation.register_write () ;
  Mutants.register_plan () ;
  Mutants.register_cone_escape () ;
  Mutants.register_allowlist () ;
  Mutants.register_attribution () ;
  Mutants.register_mutaml () ;
  Mutants.register_soundness_flag () ;
  Decision_lint.register_aliases () ;
  Decision_lint.register_smt_noise () ;
  Decision_lint.register_smt_mute () ;
  Decision_lint.register_smt_absent () ;
  Coverage.register_buckets () ;
  Coverage.register_tracefile_refusals () ;
  Coverage.register_every_covered_fn_lands_somewhere () ;
  Coverage.register_mutant_pairing () ;
  Coverage.register_ambiguity () ;
  Coverage.register_write () ;
  Coverage.register_soundness_flag () ;
  Serve.register_refusal () ;
  Serve.register_routes () ;
  Tezt.Test.run ()
