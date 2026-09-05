(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [exported:] against a FLAT-schema index — roadmap 4.4.

    {1 The gap this closes}

    The two schemas spell the API-surface flag differently: MAIN's column is
    [functions.exposed], FLAT's is [functions.exported]. {!Arch_graph.load_nodes} has one
    query per schema and reads both into the single field [node.exported], which is what lets
    [exported:] go through the node instead of through SQL and keeps that reconciliation in
    one place.

    That normalisation is asserted in three documents — [docs/fitness-functions.md], the
    module doc of {!module:Arch_sel}, and the CHANGELOG — and, until this file, executed by no
    test. Every [exported:] assertion in the suite ran against a MAIN index. **Asserted
    everywhere, verified nowhere** is the shape #85 spent five review rounds correcting in its
    own prose; a test is a stronger fix than prose that happens to be right, because it keeps
    being true.

    {1 Why the fixture is built by hand}

    A FLAT index is what [arch-load] and the LSP producer emit; there is no [.cmt] path to it.
    Raw SQL is how the rest of the suite constructs one (see [tezt/tests/contract.ml]), and it
    is the honest choice here: the subject is the READER's two queries, not any producer.

    {1 The three modes this can fail in, and why the fixture separates them}

    The reachability is INVERTED against the exposure on purpose — the UNEXPORTED function is
    the one that reaches the excluded target:

    - the FLAT branch reads the wrong column name → [no such column], a crash;
    - it does not read the column at all → nothing is exported → [exported:**] selects the
      empty set → the rule is VACUOUS, not a proof;
    - it defaults every node to exported → [exported:**] selects EVERYTHING, including
      [flat_hidden] → the first rule returns a VIOLATION where a proof belongs.

    The third is the dangerous one: no crash, no empty set, a confident answer about the wrong
    population. It is visible only because the unexported function is the one with the path,
    which is the whole reason for the inversion. Three modes, three distinct signatures; none
    can be mistaken for another. *)

open Arch_tezt

let rules args = run_command (arch_rules ()) args

let rule_file name contents =
  let path = Temp.file (name ^ ".rules") in
  write_file path contents ;
  path

(* [flat_entry] is exported and reaches [flat_danger2]; [flat_hidden] is NOT exported and is
   the only route to [flat_danger]. Column spellings are FLAT's throughout: [exported], and
   [calls.caller_name] rather than [caller_id]. *)
let fixture_sql =
  {|
CREATE TABLE comment_db_meta(key TEXT, value TEXT);
INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');
CREATE TABLE functions(name TEXT, file_path TEXT, exported INT, line_start INT, line_end INT);
INSERT INTO functions VALUES
 ('flat_entry','api.ml',1,1,2),
 ('flat_hidden','api.ml',0,3,4),
 ('flat_danger','vuln.ml',0,1,2),
 ('flat_danger2','vuln.ml',0,3,4);
CREATE TABLE calls(caller_name TEXT, caller_file TEXT, callee_name TEXT, callee_file TEXT, call_site TEXT, kind TEXT);
INSERT INTO calls VALUES
 ('flat_hidden','api.ml','flat_danger','vuln.ml','api.ml:3','MUST'),
 ('flat_entry','api.ml','flat_danger2','vuln.ml','api.ml:1','MUST');
|}

let summary out =
  String.split_on_char '\n' out
  |> List.find_opt (fun l -> contains ~needle:"rule(s):" l)
  |> Option.value ~default:"(no summary line in output)"

let register () =
  Test.register ~__FILE__
    ~title:"exported selector: the FLAT schema's own column is read (4.4)"
    ~tags:["rules"; "reach"; "selector"; "exported"; "flat"; "schema"]
  @@ fun () ->
  let db = Arch_tezt.temp_db "flat_exported" in
  Db.with_db_rw db (fun c -> Db.exec c fixture_sql) ;
  let run body =
    rules [ db; rule_file "flat_exp" (Printf.sprintf "rule \"p\"\n  %s\n" body) ]
  in
  Batch.run (fun b ->
      (* PREMISE 0 — THE DISCRIMINATOR. Without this the whole file can pass while proving
         nothing about FLAT: [Arch_db.open_ro] picks its schema by
         [has_col_conn conn "calls" "caller_name"], so a fixture that accidentally satisfied
         the MAIN predicate would be read through the already-tested branch. Asserted on the
         column that MAKES the choice, not on the fixture text that is supposed to produce it. *)
      Batch.eq_int b ~msg:"premise: calls.caller_name exists, so open_ro selects the FLAT branch"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('calls') WHERE name='caller_name'"))
        1 ;
      Batch.eq_int b ~msg:"premise: and calls.caller_id does NOT, so MAIN is not selectable"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('calls') WHERE name='caller_id'"))
        0 ;
      (* PREMISE 1 — the FLAT spelling, which is the subject. If this fixture carried MAIN's
         [exposed] instead, the FLAT query would read a column that is not there. *)
      Batch.eq_int b ~msg:"premise: functions.exported exists (FLAT's spelling)"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('functions') WHERE name='exported'"))
        1 ;
      Batch.eq_int b ~msg:"premise: functions.exposed does NOT (that is MAIN's spelling)"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM pragma_table_info('functions') WHERE name='exposed'"))
        0 ;
      (* PREMISE 2 — the population really splits, or "filtered" and "matched nothing" are the
         same observation. *)
      Batch.eq_int b ~msg:"premise: exactly one function is exported"
        (Db.with_db db (fun c -> Db.int c "SELECT count(*) FROM functions WHERE exported = 1"))
        1 ;
      (* PREMISE 3 — the excluded target is REACHABLE, through a real call path from a source
         disjoint from it. Without this, "not reached" would be a fact about the fixture. *)
      let _, ctrl = run "forbid reach from fn:flat_hidden to fn:flat_danger" in
      Batch.check b
        ~msg:(Printf.sprintf "premise: flat_danger IS reachable, via the unexported route:\n%s" ctrl)
        (contains ~needle:"1 violation" (summary ctrl)) ;
      (* ASSERTION 1 — the filter EXCLUDES. Only [flat_hidden] reaches [flat_danger] and it is
         not on the API surface, so restricting the source to [exported:] must prove it
         unreachable. A FLAT branch defaulting everything to exported answers VIOLATION here. *)
      let _, excl = run "forbid reach from exported:** to fn:flat_danger" in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "no FLAT entry point reaches flat_danger — the exported flag is being read:\n%s" excl)
        (contains ~needle:"1 violation, " (summary excl) = false) ;
      Batch.check b
        ~msg:(Printf.sprintf "…and it is a proof, not vacuity (an unread column gives 0 vacuous \
                              only if the cone is non-empty):\n%s" excl)
        (contains ~needle:"1 proved" (summary excl)) ;
      (* ASSERTION 2 — the filter CATCHES. [flat_entry] is exported and does reach
         [flat_danger2]; a selector that quietly matched nothing would report a proof here too,
         which is what separates this line from the one above. *)
      let _, catch = run "forbid reach from exported:** to fn:flat_danger2" in
      Batch.check b
        ~msg:
          (Printf.sprintf
             "an exported FLAT function that really reaches the target is caught:\n%s" catch)
        (contains ~needle:"1 violation" (summary catch))) ;
  Lwt.return_unit
