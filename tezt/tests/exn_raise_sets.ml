(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** Exception-identity may-raise sets (spec: specs/exn-raise-sets.md).

    The producer records, per function node, every raise origin (with the
    resolved constructor path), every handler scope (with its caught set) and
    the scope enclosing each call; the query computes the transitive set with
    handler subtraction at CALL sites and honest ⊤ reasons. Scenario numbers
    below are the spec's (US-N.M). *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name testexn)\n\
      \ (wrapped false)\n\
      \ (modules exn_a exn_b)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "exn_a.ml",
      {|exception E

module M = struct
  exception E2 of int
end

exception Alias = Not_found

(* US-1.1 *)
let f () = raise Not_found

(* US-1.2 / US-2.1 : the call site is closed by g's own try *)
let g () = try f () with Not_found -> 0

(* Failure origin *)
let fw v = if v > 0 then failwith "x" else v

(* US-1.3 / US-2.6 : the raise belongs to the lambda; h's try covers the
   List.iter edge and the occurrence edge, not the lambda body *)
let h l = try List.iter (fun x -> if x < 0 then raise Exit) l with Exit -> ()

(* US-1.4 / US-2.7 : non-closing arm (re-raise) *)
let r () = try f () with e -> ignore e ; raise e

(* US-1.5 : guarded arm does not catch *)
let guarded c = try f () with Not_found when c -> 0

(* US-1.6 / US-2.8 : match-with-exception covers the scrutinee only *)
let mx () = match f () with exception Not_found -> 0 | v -> fw v

(* US-2.3 : transitive via f, direct Failure *)
let k () = ignore (f ()) ; failwith "x"

(* US-1.7 : assert and partial match, and a root [function] *)
let assert_fn x =
  assert (x > 0) ;
  match x with 1 -> () | 2 -> ()

let p = function 1 -> ()

(* US-1.8 : local exception and rebinding *)
let q () = let exception Local in raise Local

let al () = raise Alias

(* MAY_TOP edge through a parameter *)
let cb c = c ()

(* US-2.2 : a catch-all closes ⊤ *)
let g2 () = try cb (fun () -> 0) with _ -> 0

(* US-2.4 : mutual recursion converges *)
let rec a () = ignore (b ()) ; raise E
and b () = ignore (a ()) ; raise (M.E2 1)

(* US-2.5 : external callee *)
let m xs = List.hd xs

(* US-1.9 origin half : canonical path across units *)
let raise_m () = raise (M.E2 2)

(* US-1.10 : a non-Stdlib %raise IS a raise head ... *)
external my_raise : exn -> 'a = "%raise"

let shadowed () = my_raise Not_found

(* ... and a non-Stdlib failwith is NOT an origin *)
let failwith (_ : string) = 0

let notorigin () = failwith "x"
|} );
    ( "exn_b.ml",
      {|(* US-1.9 handler half : must agree with Exn_a's origin string *)
let catch_it () = try Exn_a.raise_m () with Exn_a.M.E2 _ -> 0

(* US-2.1-style cross-unit closure *)
let leak () = Exn_a.raise_m ()
|} );
  ]

let fn_id conn name =
  Db.int conn (Printf.sprintf "SELECT id FROM functions WHERE name = '%s'" name)

let origins conn name =
  Db.strings conn
    (Printf.sprintf
       "SELECT form || ':' || COALESCE(exn_path,'NULL') || ':' || escapes FROM exn_origins \
        WHERE function_id = %d ORDER BY line, col"
       (fn_id conn name))

let register () =
  Test.register ~__FILE__
    ~title:"exn: producer records origins, scopes and call scopes per node"
    ~tags:["cmt"; "exn"; "producer"]
  @@ fun () ->
  with_fixture ~name:"exn_producer" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  Batch.run (fun b ->
      Db.with_db db (fun conn ->
          (* contract flag *)
          Batch.eq_string_opt b ~msg:"exn_contract meta is set by the CMT producer"
            (Db.string_opt conn "SELECT value FROM comment_db_meta WHERE key='exn_contract'")
            (Some "v1") ;
          (* US-1.1 *)
          Batch.eq_string b ~msg:"US-1.1 f raises Not_found, escaping, no scope"
            (String.concat "," (origins conn "f")) "raise:Not_found:1" ;
          Batch.eq_int b ~msg:"US-1.1 f's origin has no scope"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_origins WHERE function_id=%d AND scope_id IS NULL"
                  (fn_id conn "f")))
            1 ;
          (* US-1.2 *)
          let g = fn_id conn "g" in
          Batch.eq_int b ~msg:"US-1.2 g has one try scope, not catch-all"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scopes WHERE function_id=%d AND form='try' AND \
                   catch_all=0 AND parent_id IS NULL"
                  g))
            1 ;
          Batch.eq_int b ~msg:"US-1.2 g's scope catches Not_found"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scope_catches c JOIN exn_scopes s ON s.id=c.scope_id \
                   WHERE s.function_id=%d AND c.exn_path='Not_found'"
                  g))
            1 ;
          Batch.eq_int b ~msg:"US-1.2 the call g->f is linked to g's scope"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN call_exn_scopes l ON l.call_id=c.id JOIN \
                   exn_scopes s ON s.id=l.scope_id WHERE c.caller_id=%d AND c.callee_name='f' \
                   AND s.function_id=%d"
                  g g))
            1 ;
          (* US-1.3 *)
          Batch.eq_int b ~msg:"US-1.3 the Exit origin belongs to h's lambda node, unscoped"
            (Db.int conn
               "SELECT count(*) FROM exn_origins o JOIN functions f ON f.id=o.function_id WHERE \
                f.name LIKE 'h.<fun:%' AND o.exn_path='Stdlib.Exit' AND o.scope_id IS NULL AND \
                o.escapes=1")
            1 ;
          Batch.eq_int b ~msg:"US-1.3 h itself has no origin"
            (Db.int conn
               (Printf.sprintf "SELECT count(*) FROM exn_origins WHERE function_id=%d"
                  (fn_id conn "h")))
            0 ;
          Batch.eq_int b ~msg:"US-1.3 both of h's edges (List.iter and the lambda occurrence) carry h's scope"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN call_exn_scopes l ON l.call_id=c.id WHERE \
                   c.caller_id=%d"
                  (fn_id conn "h")))
            2 ;
          (* US-1.4 *)
          let r = fn_id conn "r" in
          Batch.eq_int b ~msg:"US-1.4 re-raise arm: scope not catch-all, empty caught set"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scopes s LEFT JOIN exn_scope_catches c ON \
                   c.scope_id=s.id WHERE s.function_id=%d AND s.catch_all=0 AND c.exn_path IS NULL"
                  r))
            1 ;
          Batch.eq_string b ~msg:"US-1.4 the raise e site is a reraise origin"
            (String.concat "," (origins conn "r")) "reraise:NULL:1" ;
          (* US-1.5 *)
          Batch.eq_int b ~msg:"US-1.5 guarded arm catches nothing"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scope_catches c JOIN exn_scopes s ON s.id=c.scope_id \
                   WHERE s.function_id=%d"
                  (fn_id conn "guarded")))
            0 ;
          (* US-1.6 *)
          let mx = fn_id conn "mx" in
          Batch.eq_int b ~msg:"US-1.6 match_exception scope covers f only"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM calls c JOIN call_exn_scopes l ON l.call_id=c.id JOIN \
                   exn_scopes s ON s.id=l.scope_id WHERE c.caller_id=%d AND s.form='match_exception' \
                   AND c.callee_name='f'"
                  mx))
            1 ;
          Batch.eq_int b ~msg:"US-1.6 the fw edge has no scope"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM calls c LEFT JOIN call_exn_scopes l ON l.call_id=c.id \
                   WHERE c.caller_id=%d AND c.callee_name='fw' AND l.call_id IS NULL"
                  mx))
            1 ;
          (* US-1.7 *)
          Batch.eq_string b ~msg:"US-1.7 assert then partial match"
            (String.concat "," (origins conn "assert_fn"))
            "assert:Assert_failure:1,partial_match:Match_failure:1" ;
          Batch.eq_string b ~msg:"US-1.7 root function partial match belongs to p"
            (String.concat "," (origins conn "p")) "partial_match:Match_failure:1" ;
          (* US-1.8 *)
          Batch.contains b ~msg:"US-1.8 let exception is a local: path"
            ~haystack:(String.concat "," (origins conn "q")) "raise:local:Local" ;
          Batch.eq_string_opt b ~msg:"US-1.8 rebinding recorded"
            (Db.string_opt conn "SELECT target_path FROM exn_rebinds WHERE alias_path='Exn_a.Alias'")
            (Some "Not_found") ;
          (* US-1.9 *)
          Batch.eq_string b ~msg:"US-1.9 origin path in the declaring unit"
            (String.concat "," (origins conn "raise_m")) "raise:Exn_a.M.E2:1" ;
          Batch.eq_int b ~msg:"US-1.9 handler path in the other unit agrees byte for byte"
            (Db.int conn
               (Printf.sprintf
                  "SELECT count(*) FROM exn_scope_catches c JOIN exn_scopes s ON s.id=c.scope_id \
                   WHERE s.function_id=%d AND c.exn_path='Exn_a.M.E2'"
                  (fn_id conn "catch_it")))
            1 ;
          (* US-1.10 *)
          Batch.eq_string b ~msg:"US-1.10 a non-Stdlib %raise external is a raise head"
            (String.concat "," (origins conn "shadowed")) "raise:Not_found:1" ;
          Batch.eq_int b ~msg:"US-1.10 a non-Stdlib failwith is not an origin"
            (Db.int conn
               (Printf.sprintf "SELECT count(*) FROM exn_origins WHERE function_id=%d"
                  (fn_id conn "notorigin")))
            0)) ;
  Lwt.return_unit

let register_query () =
  Test.register ~__FILE__
    ~title:"exn: raises / raisers-of / exn-stats are handler-aware and ⊤-honest"
    ~tags:["cmt"; "exn"; "query"]
  @@ fun () ->
  with_fixture ~name:"exn_query" ~files:fixture_files @@ fun fixture ->
  let db = index fixture in
  let raises ?(flag = false) fn =
    query db (("raises" :: (if flag then ["--assume-externals-pure"] else [])) @ [fn])
  in
  Batch.run (fun b ->
      (* US-2.1 *)
      Batch.contains b ~msg:"US-2.1 g closes Not_found at the call site"
        ~haystack:(raises "g") "BOUNDED: {}" ;
      let f = raises "f" in
      Batch.contains b ~msg:"US-2.1 f raises Not_found" ~haystack:f "BOUNDED: {Not_found}" ;
      Batch.contains b ~msg:"US-2.1 f's row is direct" ~haystack:f "direct" ;
      (* US-2.2 *)
      Batch.contains b ~msg:"US-2.2 catch-all closes ⊤" ~haystack:(raises "g2") "BOUNDED: {}" ;
      let cb = raises "cb" in
      Batch.contains b ~msg:"US-2.2 cb is unbounded" ~haystack:cb "UNBOUNDED" ;
      Batch.contains b ~msg:"US-2.2 reason may_top_edge" ~haystack:cb "may_top_edge" ;
      (* US-2.3 *)
      let k = raises "k" in
      Batch.contains b ~msg:"US-2.3 k's set" ~haystack:k "BOUNDED: {Failure, Not_found}" ;
      Batch.contains b ~msg:"US-2.3 Not_found via f, transitive" ~haystack:k "transitive" ;
      (* US-2.4 *)
      Batch.contains b ~msg:"US-2.4 mutual recursion converges (a)" ~haystack:(raises "a")
        "BOUNDED: {Exn_a.E, Exn_a.M.E2}" ;
      Batch.contains b ~msg:"US-2.4 mutual recursion converges (b)" ~haystack:(raises "b")
        "BOUNDED: {Exn_a.E, Exn_a.M.E2}" ;
      (* US-2.5 *)
      let m = raises "m" in
      Batch.contains b ~msg:"US-2.5 external callee is ⊤" ~haystack:m "UNBOUNDED" ;
      Batch.contains b ~msg:"US-2.5 reason names the external" ~haystack:m "external Stdlib.List.hd" ;
      Batch.contains b ~msg:"US-2.5 hypothesis flag" ~haystack:(raises ~flag:true "m")
        "BOUNDED_UNDER_HYP(externals_pure): {}" ;
      (* US-2.6 *)
      Batch.contains b ~msg:"US-2.6 h is ⊤ through List.iter" ~haystack:(raises "h")
        "external Stdlib.List.iter" ;
      Batch.contains b ~msg:"US-2.6 under the hypothesis the lambda's Exit is closed by h's try"
        ~haystack:(raises ~flag:true "h") "BOUNDED_UNDER_HYP(externals_pure): {}" ;
      (* the flag never hides a MAY_TOP edge *)
      Batch.contains b ~msg:"flag does not hide may_top_edge" ~haystack:(raises ~flag:true "cb")
        "UNBOUNDED" ;
      (* US-2.7 *)
      Batch.contains b ~msg:"US-2.7 re-raise arm forwards" ~haystack:(raises "r")
        "BOUNDED: {Not_found}" ;
      (* US-2.8 *)
      Batch.contains b ~msg:"US-2.8 match-exception closes f's Not_found, not fw's Failure"
        ~haystack:(raises "mx") "BOUNDED: {Failure}" ;
      (* guarded arm catches nothing *)
      Batch.contains b ~msg:"guarded arm leaves Not_found" ~haystack:(raises "guarded")
        "BOUNDED: {Not_found}" ;
      (* cross-unit *)
      Batch.contains b ~msg:"cross-unit handler closes Exn_a.M.E2" ~haystack:(raises "catch_it")
        "BOUNDED: {}" ;
      Batch.contains b ~msg:"cross-unit leak" ~haystack:(raises "leak")
        "BOUNDED: {Exn_a.M.E2}" ;
      (* rebinding canonicalised *)
      Batch.contains b ~msg:"rebound alias reads as its target" ~haystack:(raises "al")
        "BOUNDED: {Not_found}" ;
      (* US-2.9 / US-2.10 *)
      let code, _ = query_raw db ["raises"; "nosuch"] in
      Batch.eq_int b ~msg:"US-2.9 unknown function refused with exit 3" code 3 ;
      (* US-3.1 *)
      let ro = query db ["raisers-of"; "Not_found"] in
      Batch.contains b ~msg:"US-3.1 f is a direct raiser" ~haystack:ro "f" ;
      Batch.contains b ~msg:"US-3.1 k is a transitive raiser" ~haystack:ro "k" ;
      Batch.contains b ~msg:"US-3.1 ⊤ nodes listed separately" ~haystack:ro "cb" ;
      (* US-3.2 *)
      let st = query db ["exn-stats"] in
      List.iter
        (fun needle -> Batch.contains b ~msg:("US-3.2 exn-stats has " ^ needle) ~haystack:st needle)
        ["nodes"; "bounded"; "unbounded"; "may_top_edge"; "external"; "origins"; "scopes"]) ;
  (* US-3.3 : a Flat DB is NOT_ANALYSED *)
  let flat = Fixture.flat ~name:"exn_flat" Fixture.minimal_flat_stream in
  let code, out = query_raw flat ["raises"; "f"] in
  if code <> 3 || not (Batch.has_substring ~needle:"NOT_ANALYSED" out) then
    Test.fail "US-3.3 expected exit 3 with NOT_ANALYSED on a flat DB, got %d:\n%s" code out ;
  (* US-3.4 : a main-schema DB without the producer's flag is NOT_ANALYSED *)
  let bare =
    Fixture.main ~name:"exn_bare"
      ~seed:
        "INSERT INTO modules(path,lines) VALUES ('x.ml',1); INSERT INTO functions(module_id,name) \
         VALUES (1,'f'); INSERT OR REPLACE INTO comment_db_meta(key,value) VALUES \
         ('callgraph_contract','v1');"
      ()
  in
  let code, out = query_raw bare ["raises"; "f"] in
  if code <> 3 || not (Batch.has_substring ~needle:"NOT_ANALYSED" out) then
    Test.fail "US-3.4 expected exit 3 with NOT_ANALYSED on a pre-feature DB, got %d:\n%s" code out ;
  Lwt.return_unit

let register () =
  register () ;
  register_query ()
