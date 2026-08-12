(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The edge-kind contract at the query layer, on hand-built databases so the
    shapes under test are exactly the ones a buggy backend would produce.

    [reaches] is an UNDER-approximation over MUST edges: a positive answer is a
    proof, a negative one is not. [unreachable] is the dual — sound only over a
    ⊤-marked graph, which is why it must REFUSE rather than answer whenever the
    marking is missing, incomplete or contradicted. Most of what follows is
    about the refusals, because a wrong refusal costs a question and a wrong
    answer costs the guarantee. *)

open Arch_tezt

let build name sql =
  let db = temp_db name in
  Db.with_db_rw db (fun conn -> Db.exec conn sql) ;
  db

(* clean --MUST--> a --MAY_ENUMERATED--> b ; dirty --MUST--> t --MAY_TOP--> *TOP* ; z isolated *)
let marked () =
  build "contract_marked"
    {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT);
INSERT INTO functions VALUES('clean','x',1),('a','x',0),('b','x',0),('z','x',0),('dirty','x',1),('t','x',0);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES
 ('clean','x','a','x','x:1','MUST'),
 ('a','x','b','x','x:2','MAY_ENUMERATED'),
 ('dirty','x','t','x','x:3','MUST'),
 ('t','x','*TOP*',NULL,'x:4','MAY_TOP');
|}

let register () =
  Test.register ~__FILE__ ~title:"contract: reaches under-approximates, unreachable over-approximates"
    ~tags:["contract"; "query"]
  @@ fun () ->
  let db = marked () in
  Batch.run (fun b ->
      (* reaches: MUST only. *)
      Batch.contains b ~msg:"reaches clean a is a MUST path"
        ~haystack:(query db ["reaches"; "clean"; "a"]) "PATH EXISTS (must-reach)" ;
      Batch.contains b ~msg:"reaches clean b goes through MAY_ENUMERATED, so it is not a MUST path"
        ~haystack:(query db ["reaches"; "clean"; "b"]) "no MUST path" ;
      Batch.contains b ~msg:"reaches clean z has no path at all"
        ~haystack:(query db ["reaches"; "clean"; "z"]) "no MUST path" ;

      (* unreachable: the MUST ∪ MAY_ENUMERATED closure, with ⊤ forcing UNKNOWN. *)
      Batch.contains b ~msg:"unreachable clean b: b is in the closure, so REACHABLE"
        ~haystack:(query db ["unreachable"; "clean"; "b"]) "REACHABLE (may-reach)" ;
      Batch.contains b ~msg:"unreachable clean z: no path and no reachable ⊤, so UNREACHABLE"
        ~haystack:(query db ["unreachable"; "clean"; "z"]) "UNREACHABLE:" ;
      let dirty_z = query db ["unreachable"; "dirty"; "z"] in
      Batch.contains b ~msg:"unreachable dirty z: dirty reaches a ⊤ edge, so UNKNOWN" ~haystack:dirty_z
        "UNKNOWN:" ;
      Batch.not_contains b
        ~msg:"unreachable dirty z must never claim UNREACHABLE while a ⊤ is reachable"
        ~haystack:dirty_z "UNREACHABLE:" ;

      (* escapes: the ⊤ frontier, scoped to what the root can actually reach. *)
      Batch.contains b ~msg:"escapes dirty must list t, the function making the ⊤ edge"
        ~haystack:(query db ["escapes"; "dirty"]) "t" ;
      (* Asserted as an empty ROW SET, not as the absence of the substring "t".
         `escapes clean` prints nothing on this fixture, so `not_contains "t"`
         was vacuously true — it would have kept passing if the command started
         listing every function in the index, as long as none was spelt "t". *)
      Batch.eq_int b
        ~msg:"escapes clean must report an empty ⊤ frontier (t is not reachable from clean)"
        (List.length (lines (query db ["escapes"; "clean"])))
        0 ;

      Batch.contains b ~msg:"stats must report the contract flag"
        ~haystack:(query db ["stats"]) "contract: v1") ;
  Lwt.return_unit

let register_refusals () =
  Test.register ~__FILE__ ~title:"contract: refuses rather than answering unsoundly"
    ~tags:["contract"; "query"]
  @@ fun () ->
  (* A legacy index: no contract flag, no kind column. *)
  let legacy =
    build "contract_legacy"
      {|
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT);
INSERT INTO functions VALUES('p','x',1),('qq','x',0);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT);
INSERT INTO calls VALUES('p','x','qq','x','x:1');
|}
  in
  (* The shared adversarial fixture: see Arch_tezt.Fixture.malformed_contract
     for why every consumer of the contract is measured against the same one. *)
  let malformed = Fixture.malformed_contract ~name:"contract_malformed" in
  (* Flag set, but the kind column does not exist at all. *)
  let no_kind =
    build "contract_nokind"
      {|
CREATE TABLE comment_db_meta(key TEXT,value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT,file_path TEXT,exported INT);
CREATE TABLE calls(caller_name TEXT,caller_file TEXT,callee_name TEXT,callee_file TEXT,call_site TEXT);
INSERT INTO calls VALUES('A','x','b','x','x:1');
|}
  in
  let refuses b ~msg db args = Batch.exit_code b ~msg ~expected:3 (query_raw db args) in
  Batch.run (fun b ->
      refuses b ~msg:"unreachable on a legacy (un-⊤-marked) index must REFUSE" legacy
        ["unreachable"; "p"; "qq"] ;
      refuses b ~msg:"escapes on a legacy index must REFUSE" legacy ["escapes"; "p"] ;
      (* reaches is still answerable there: treating every edge as MUST is an
         under-approximation, which is the safe direction for a positive claim. *)
      Batch.contains b ~msg:"reaches on a legacy index still finds the path"
        ~haystack:(query legacy ["reaches"; "p"; "qq"]) "PATH EXISTS (must-reach)" ;

      let ((_, out) as res) = query_raw malformed ["unreachable"; "A"; "sink"] in
      Batch.exit_code b ~msg:"a NULL-kind edge on a real path must REFUSE despite the flag being set"
        ~expected:3 res ;
      Batch.not_contains b ~msg:"a malformed ⊤-marked index must never yield a false-sound UNREACHABLE"
        ~haystack:out "UNREACHABLE:" ;

      refuses b ~msg:"the flag set with no kind column at all must REFUSE" no_kind
        ["unreachable"; "A"; "b"]) ;
  Lwt.return_unit

(* On the flat schema a node need not have a `functions` row — an unresolved
   callee exists only as calls.callee_name — so `functions` alone is not the
   universe. The guard used to run on the main schema only, which left a typo'd
   name on a flat index coming back "UNREACHABLE … sound": a proof about a
   function that does not exist. *)
let register_unknown_names () =
  Test.register ~__FILE__ ~title:"contract: an unknown name is refused on the flat schema too"
    ~tags:["contract"; "query"]
  @@ fun () ->
  (* Its own stream rather than the shared minimal one: this test needs a callee
     that exists ONLY as an edge endpoint, which is the whole point below. *)
  let db =
    Fixture.flat ~name:"contract_flat"
      {|{"type":"function","name":"a","file_path":"x","exported":true}
{"type":"function","name":"b","file_path":"x"}
{"type":"call","caller_name":"a","caller_file":"x","callee_name":"b","callee_file":"x","call_site":"x:1","kind":"MUST"}
{"type":"call","caller_name":"b","caller_file":"x","callee_name":"ext_only","callee_file":null,"call_site":"x:2","kind":"MAY_ENUMERATED"}
|}
  in
  Batch.run (fun b ->
      let refuses ~msg args = Batch.exit_code b ~msg ~expected:3 (query_raw db args) in
      refuses ~msg:"an unknown SOURCE must REFUSE, never answer UNREACHABLE"
        ["unreachable"; "no_such"; "a"] ;
      refuses ~msg:"an unknown TARGET must REFUSE — no path to a name that does not exist is not a proof"
        ["unreachable"; "a"; "no_such"] ;
      refuses ~msg:"escapes on an unknown root must REFUSE, not report an empty ⊤ frontier"
        ["escapes"; "no_such"] ;
      (* The mirror image: a callee that exists only as an edge endpoint IS a
         node, or the guard would refuse legitimate questions about unresolved
         callees. *)
      Batch.contains b
        ~msg:"a callee with no functions row is still a node and must not be refused"
        ~haystack:(query db ["unreachable"; "a"; "ext_only"]) "REACHABLE") ;
  Lwt.return_unit

(* Exit 3 means "this index cannot answer that soundly", and callers — the MCP
   server, CI gates — are told to report it as a considered result. A file that
   could not be read is not a result, so it must never wear that code. *)
let register_io_errors () =
  Test.register ~__FILE__ ~title:"contract: an unreadable index exits 2, never 3"
    ~tags:["contract"; "query"]
  @@ fun () ->
  let corrupt = Temp.file "contract_corrupt.db" in
  write_file corrupt (String.init 512 (fun i -> Char.chr ((i * 7) land 0xff))) ;
  Batch.run (fun b ->
      let exits_2 ~msg db args = Batch.exit_code b ~msg ~expected:2 (query_raw db args) in
      exits_2 ~msg:"an unreadable database must exit 2" corrupt ["stats"] ;
      exits_2 ~msg:"an unreadable database must exit 2 even where the refusal code IS 3" corrupt
        ["unreachable"; "a"; "b"] ;
      exits_2 ~msg:"a missing database must exit 2" "/nonexistent/nope.db" ["stats"]) ;
  Lwt.return_unit
