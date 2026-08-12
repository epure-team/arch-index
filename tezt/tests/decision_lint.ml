(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** decision-lint's Parsetree alias environment, and its SMT pipe.

    decision-lint canonicalises [let a = x in a && x] by resolving the alias,
    which is what lets it prove the second conjunct removable. On the Typedtree
    that is safe for free — Ident stamps make shadowing unrepresentable. On the
    PARSETREE there are only names, so an alias is valid exactly as long as
    every name involved still denotes what it denoted when the alias was
    recorded: both the alias name AND every name in its stored right-hand side.

    The direction matters. A missed alias costs recall; a leaked one produces a
    "delete this" verdict about code that does something else. So both sides are
    asserted — every shadowing form must be silent, and the genuine aliases must
    still be found — because otherwise "fixing" a leak by switching resolution
    off entirely would pass. *)

open Arch_tezt

(* Findings are NDJSON on stdout; the (kind, snippet) SET is the assertion.
   Line numbers were the old script's undoing: it checked a line a leak would
   not have reported anyway, so one of its five cases was vacuous. *)
let findings_of output =
  lines output
  |> List.filter_map (fun l ->
         match Yojson.Safe.from_string l with
         | `Assoc f when List.assoc_opt "type" f = Some (`String "finding") -> (
             match (List.assoc_opt "kind" f, List.assoc_opt "snippet" f) with
             | Some (`String k), Some (`String s) -> Some (k, s)
             | _ -> None)
         | _ -> None
         | exception _ -> None)
  |> List.sort_uniq compare

let census_solver output =
  lines output
  |> List.find_map (fun l ->
         match Yojson.Safe.from_string l with
         | `Assoc f when List.assoc_opt "type" f = Some (`String "smt") -> (
             match List.assoc_opt "solver" f with Some (`String s) -> Some s | _ -> None)
         | _ -> None
         | exception _ -> None)

let smt_findings output =
  findings_of output |> List.filter (fun (k, _) -> has_prefix ~prefix:"SMT_" k)

let shadow_ml =
  {|(* ---- GENUINE aliases: nothing is rebound, so these MUST still be reported ---- *)
let genuine_and (p : bool) =
  let a = p in
  a && p

let genuine_rel (q : int) =
  let b = q in
  b > 0 && q > 0

(* ---- the alias NAME is rebound ---- *)
let relet (p : bool) (q : bool) =
  let a = p in
  let a = q in
  a && p

let arm (p : bool) (q : bool) =
  let a = p in
  ignore a ;
  match q with
  | a -> a && p

let param (p : bool) (q : bool) =
  let a = p in
  ignore a ;
  let k = fun a -> a && p in
  k q

(* An object binds `val a` for every method, and no pattern in the file shows it. *)
let obj (p : bool) (q : bool) =
  let a = p in
  ignore a ;
  let o = object
    val a = q
    method m = a && p
  end in
  o#m

(* `open` can rebind a name to M.<name> with no pattern at all. *)
module M = struct let a = false end
let opened (p : bool) =
  let a = p in
  ignore a ;
  let open M in
  a && p

(* ---- the alias's RIGHT-HAND SIDE is rebound (the alias name is untouched) ---- *)
(* Chasing: x -> y -> 5 through the CURRENT env turns a live decision into `if 5 > 0`. *)
let chase (y : int) =
  let x = y in
  let y = 5 in
  ignore y ;
  x > 0

(* Merging: both atoms print to the key "y" and one reads as removable. *)
let merge (y : bool) (f : unit -> bool) =
  let x = y in
  let y = f () in
  x && y
|}

let register_aliases () =
  Test.register ~__FILE__ ~title:"decision-lint: an alias dies with any name it depends on"
    ~tags:["decision_lint"; "alias"]
  @@ fun () ->
  with_project ~name:"declint_shadow" ~files:[("shadow.ml", shadow_ml)] @@ fun src ->
  let _, output = run_command (decision_lint ()) [src] in
  let got = findings_of output in
  let want =
    List.sort_uniq compare
      [("DEAD_SUBTERM", "a && p"); ("DEAD_SUBTERM", "(b > 0) && (q > 0)")]
  in
  let show l = String.concat ", " (List.map (fun (k, s) -> Printf.sprintf "%s:%S" k s) l) in
  Batch.run (fun b ->
      let missing = List.filter (fun x -> not (List.mem x got)) want in
      let extra = List.filter (fun x -> not (List.mem x want)) got in
      (* Reported as two separate assertions on purpose: they fail for opposite
         reasons and a single "sets differ" would hide which. Missing means
         resolution stopped working at all, and would make every guard below
         vacuous; extra means an alias survived a construct that rebound
         something it depends on. *)
      Batch.check b
        ~msg:
          (Printf.sprintf
             "the genuine aliases were not resolved (missing: %s) — every shadowing guard here \
              would then be vacuous"
             (show missing))
        (missing = []) ;
      Batch.check b
        ~msg:
          (Printf.sprintf "an alias survived a rebinding of a name it depends on (extra: %s)"
             (show extra))
        (extra = [])) ;
  Lwt.return_unit

(* The SMT tier, against stub solvers.

   z3 answers a (check-sat) with one verdict, but it also writes (error "…") to
   STDOUT for a malformed assertion, and some builds print a banner. Taking
   literally the next line reported the error as unknown and left the real
   verdict buffered, where it became the answer to the NEXT query — every later
   result shifted by one, silently, with no way to notice from outside.

   The commit that fixed that claimed verification against a stub solver; the
   stub was not in the tree, so the claim was a commit message rather than an
   artefact. Here it is. *)
let rel_ml =
  {|(* Relational atoms the enumeration tier cannot settle, so the SMT tier is reached. *)
let a (x : int) = if x > 0 && x > 1 then 1 else 2
let b (x : int) (y : int) = if x > y && y > x then 1 else 2
let c (x : int) = if x >= 3 && x >= 1 then 1 else 2
|}

let with_rel k =
  with_project ~name:"declint_rel" ~files:[("rel/rel.ml", rel_ml)] @@ fun src ->
  k (Filename.concat src "rel")

let register_smt_noise () =
  Test.register ~__FILE__ ~title:"decision-lint: solver noise must not shift the verdict stream"
    ~tags:["decision_lint"; "smt"]
  @@ fun () ->
  with_rel @@ fun rel ->
  let stub_dir = Temp.dir "declint_stub_noisy" in
  (* A banner at startup, then (error …) before every verdict. Every answer is
     `sat` — satisfiable, which proves nothing — so a correct reader emits no SMT
     finding at all. A desynced reader attaches verdicts to the wrong queries and
     can manufacture one. *)
  write_exec (Filename.concat stub_dir "z3")
    {|#!/usr/bin/env bash
echo "Z3 version 4.99 - synthetic stub"
while IFS= read -r line; do
  case "$line" in
    *"(check-sat)"*) echo '(error "line 1: synthetic noise")'; echo "sat";;
  esac
done
|} ;
  let path = stub_dir ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") in
  let code, output = run_command ~env:[("PATH", path)] "timeout" ["60"; decision_lint (); rel] in
  Batch.run (fun b ->
      Batch.exit_code b
        ~msg:
          "a solver that prefixes every verdict with a banner and an (error …) line must not hang \
           or crash the run"
        ~expected:0 (code, output) ;
      Batch.eq_string_opt b ~msg:"the probe must skip the banner and accept the solver"
        (census_solver output) (Some "z3") ;
      let smt = smt_findings output in
      Batch.eq_int b
        ~msg:
          "every stub answer was `sat`, which proves nothing — any SMT finding here means the \
           reads desynced"
        (List.length smt) 0) ;
  Lwt.return_unit

let register_smt_mute () =
  Test.register ~__FILE__ ~title:"decision-lint: a solver that goes silent must not hang the run"
    ~tags:["decision_lint"; "smt"]
  @@ fun () ->
  with_rel @@ fun rel ->
  let stub_dir = Temp.dir "declint_stub_mute" in
  (* Answers the probe, then never again. The reader's fuel bounds the LINES it
     reads, not the waiting, so without a deadline on the read this hangs
     forever. *)
  write_exec (Filename.concat stub_dir "z3")
    {|#!/usr/bin/env bash
first=1
while IFS= read -r line; do
  case "$line" in
    *"(check-sat)"*)
      if [ $first -eq 1 ]; then echo "sat"; first=0; fi ;;
  esac
done
|} ;
  let path = stub_dir ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") in
  let code, output = run_command ~env:[("PATH", path)] "timeout" ["60"; decision_lint (); rel] in
  (* 124 is what `timeout` reports when it had to kill the process. *)
  Batch.run (fun b ->
      Batch.check b
        ~msg:
          (Printf.sprintf
             "a solver that answers the probe then goes silent must not hang the analysis (no \
              deadline on the read); timeout killed it:\n%s"
             output)
        (code <> 124)) ;
  Lwt.return_unit

let register_smt_absent () =
  Test.register ~__FILE__ ~title:"decision-lint: a missing solver is reported absent, not dead"
    ~tags:["decision_lint"; "smt"]
  @@ fun () ->
  with_rel @@ fun rel ->
  (* open_process spawns a shell, which succeeds even when z3 does not exist, so
     "absent" and "present but silently dead" are easy to confuse. An empty PATH
     is what tells them apart. *)
  let empty = Temp.dir "declint_empty_path" in
  (* Resolved BEFORE PATH is emptied, or the wrapper itself is what goes
     missing and the run fails 127 without ever reaching the solver probe. *)
  let timeout_bin = which "timeout" in
  let code, output =
    run_command ~env:[("PATH", empty)] timeout_bin ["60"; decision_lint (); rel]
  in
  Batch.run (fun b ->
      Batch.exit_code b ~msg:"a missing z3 must degrade to UNKNOWN, not kill the process"
        ~expected:0 (code, output) ;
      Batch.eq_string_opt b ~msg:"with no z3 on PATH the run must report solver=absent"
        (census_solver output) (Some "absent")) ;
  Lwt.return_unit
