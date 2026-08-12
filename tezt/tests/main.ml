(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

let () =
  Ocaml_shapes.register () ;
  Multilang.register () ;
  Tezt.Test.run ()
