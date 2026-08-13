(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** End-to-end for the producer wire format: a Tier-0 producer's NDJSON through
    [arch-load] into a ⊤-marked database, then [arch-query]'s sound verdicts over
    it.

    Two things are under test and they pull in opposite directions. The loader
    must ACCEPT a well-formed stream and stamp the contract; and it must ABORT,
    without leaving a database behind, on anything it cannot carry faithfully —
    a missing or invalid edge kind, an unknown field, an unknown record type, or
    a stream with no edges at all. A loader that is lenient in the second case
    produces a trust-stamped index in which everything reads UNREACHABLE. *)

open Arch_tezt

(* clean --MUST--> a --MAY_ENUMERATED--> b
   dirty --MUST--> t --MAY_TOP--> *TOP*
   z isolated *)
let good_stream =
  {|{"type":"function","name":"clean","file_path":"x","exported":true}
{"type":"function","name":"a","file_path":"x"}
{"type":"function","name":"b","file_path":"x"}
{"type":"function","name":"z","file_path":"x"}
{"type":"function","name":"dirty","file_path":"x","exported":true}
{"type":"function","name":"t","file_path":"x"}
{"type":"call","caller_name":"clean","caller_file":"x","callee_name":"a","callee_file":"x","call_site":"x:1","kind":"MUST"}
{"type":"call","caller_name":"a","caller_file":"x","callee_name":"b","callee_file":"x","call_site":"x:2","kind":"MAY_ENUMERATED"}
{"type":"call","caller_name":"dirty","caller_file":"x","callee_name":"t","callee_file":"x","call_site":"x:3","kind":"MUST"}
{"type":"call","caller_name":"t","caller_file":"x","callee_name":"*TOP*","callee_file":null,"call_site":"x:4","kind":"MAY_TOP"}
|}

let edge = {|{"type":"call","caller_name":"f","callee_name":"g","kind":"MUST"}|}

(* The loader is expected to fail here, so run_command is used directly rather
   than a helper that turns a non-zero exit into a test failure. *)
let load ?(args = []) ~stdin db = run_command ~stdin (arch_load ()) (args @ [db])

let register () =
  Test.register ~__FILE__ ~title:"load: NDJSON to a contract-marked index"
    ~tags:["load"; "contract"; "ndjson"]
  @@ fun () ->
  let db = temp_db "load_good" in
  let code, output = load ~stdin:good_stream db in
  if code <> 0 then Test.fail "loading a well-formed stream failed (exit %d):\n%s" code output ;
  if not (Sys.file_exists db) then Test.fail "loader produced no database" ;

  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          Batch.eq_string_opt b ~msg:"the loaded index must carry the ⊤-marking contract flag"
            (Db.string_opt conn
               "SELECT value FROM comment_db_meta WHERE key='callgraph_contract'")
            (Some "v1")) ;

      (* The four verdicts the contract exists to make distinguishable. *)
      Batch.contains b ~msg:"clean cannot reach z at all"
        ~haystack:(query db ["unreachable"; "clean"; "z"]) "UNREACHABLE:" ;
      Batch.contains b ~msg:"clean reaches b through a MAY_ENUMERATED edge"
        ~haystack:(query db ["unreachable"; "clean"; "b"]) "REACHABLE (may-reach)" ;
      Batch.contains b ~msg:"dirty reaches a MAY_TOP edge, so z cannot be ruled out"
        ~haystack:(query db ["unreachable"; "dirty"; "z"]) "UNKNOWN:" ;
      Batch.contains b ~msg:"clean -> a is a MUST path"
        ~haystack:(query db ["reaches"; "clean"; "a"]) "PATH EXISTS (must-reach)" ;
      Batch.contains b ~msg:"clean -> b is MAY_ENUMERATED, which is not a MUST path"
        ~haystack:(query db ["reaches"; "clean"; "b"]) "no MUST path" ;
      (* See contract.ml: the needle "t" is satisfied by any output containing a
         lowercase t, including one that names the root as the frontier. *)
      Assert.escapes_frontier b
        ~out:(query db ["escapes"; "dirty"]) ~root:"dirty" ~call_site:"x:4") ;
  Lwt.return_unit

let register_enforcement () =
  Test.register ~__FILE__ ~title:"load: refuses what it cannot carry faithfully"
    ~tags:["load"; "contract"; "ndjson"]
  @@ fun () ->
  Batch.run (fun b ->
      (* Each case gets its own path: the assertion "no database was produced" is
         meaningless if a previous case already created one there. *)
      let refuses ~msg ?args ~stdin name =
        let db = temp_db name in
        (* temp_db only reserves the name; the loader is what may create it. *)
        if Sys.file_exists db then Sys.remove db ;
        Batch.exit_code b ~msg ~expected:2 (load ?args ~stdin db) ;
        Batch.check b ~msg:(msg ^ ": a database must NOT be left behind")
          (not (Sys.file_exists db))
      in
      refuses ~msg:"a call edge with no kind must abort the load"
        ~stdin:{|{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1"}|}
        "load_nokind" ;
      refuses ~msg:"an invalid kind value must abort the load"
        ~stdin:
          {|{"type":"call","caller_name":"f","callee_name":"g","call_site":"x:1","kind":"garbage"}|}
        "load_badkind" ;
      (* A producer that fails silently emits functions and no edges; loading
         that yields a trust-stamped index where everything reads UNREACHABLE. *)
      refuses ~msg:"a stream with zero call edges must abort the load"
        ~stdin:{|{"type":"function","name":"solo","file_path":"x"}|}
        "load_empty" ;
      refuses ~msg:"arch-load: an unknown field must abort the load"
        ~stdin:({|{"type":"function","name":"f","mutation_sites":3}|} ^ "\n" ^ edge)
        "load_unknown_field" ;
      refuses ~msg:"an unknown record type must abort the load"
        ~stdin:({|{"type":"widget","name":"f"}|} ^ "\n" ^ edge)
        "load_unknown_type" ;

      (* --allow-empty is the explicit opt-in for a genuinely call-free input. *)
      let empty_ok = temp_db "load_allow_empty" in
      if Sys.file_exists empty_ok then Sys.remove empty_ok ;
      let code, output =
        load ~args:["--allow-empty"]
          ~stdin:{|{"type":"function","name":"solo","file_path":"x"}|}
          empty_ok
      in
      Batch.exit_code b ~msg:"--allow-empty must accept a call-free input" ~expected:0
        (code, output) ;

      (* x_-prefixed fields are the escape hatch that keeps a new producer field
         from being a breaking change. *)
      let xdb = temp_db "load_xprefix" in
      if Sys.file_exists xdb then Sys.remove xdb ;
      let code, output =
        load ~stdin:({|{"type":"function","name":"f","x_private":3}|} ^ "\n" ^ edge) xdb
      in
      Batch.exit_code b ~msg:"an x_-prefixed producer extension must be accepted" ~expected:0
        (code, output) ;

      (* decision_contract is stamped only when decision records were actually
         supplied, so a consumer can tell "computed nothing" from "computed
         nothing to report". *)
      let ddb = temp_db "load_decision" in
      if Sys.file_exists ddb then Sys.remove ddb ;
      let code, output =
        load
          ~stdin:
            (edge ^ "\n"
            ^ {|{"type":"decision","file_path":"x.go","line":42,"form":"if","verdict":"DEAD_SUBTERM","decided_by":"enumeration"}|}
            )
          ddb
      in
      if code <> 0 then Batch.note b "loading decision records failed:\n%s" output
      else
        Db.with_db ddb (fun conn ->
            Batch.eq_string_opt b
              ~msg:"decision_contract must be stamped when decision records are supplied"
              (Db.string_opt conn
                 "SELECT value FROM comment_db_meta WHERE key='decision_contract'")
              (Some "v1")) ;
      if Sys.file_exists xdb then
        Db.with_db xdb (fun conn ->
            Batch.eq_string_opt b
              ~msg:"decision_contract must NOT be stamped when no decision records are supplied"
              (Db.string_opt conn
                 "SELECT value FROM comment_db_meta WHERE key='decision_contract'")
              None)) ;
  Lwt.return_unit
