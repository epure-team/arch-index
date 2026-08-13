(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** docs/curation-workflow.md's ```sql``` blocks are executable reference, not
    prose.

    They are extracted in document order and run against a database created from
    architecture-schema.sql, so a renamed column or a dropped table breaks CI
    instead of leaving the documentation quietly wrong. The assertions after the
    run check the state the doc's own narrative claims its blocks produce. *)

open Arch_tezt

let doc () = locate ~env_var:"ARCH_CURATION_DOC" "docs/curation-workflow.md"

(* Lines between a ```sql fence and its closing fence, in order, with a blank
   line separating blocks so two adjacent blocks cannot fuse into one statement. *)
let extract_sql_blocks contents =
  let lines = String.split_on_char '\n' contents in
  let blocks = ref [] and current = ref [] and inside = ref false in
  List.iter
    (fun line ->
      let trimmed = String.trim line in
      if (not !inside) && trimmed = "```sql" then inside := true
      else if !inside && trimmed = "```" then begin
        blocks := List.rev !current :: !blocks ;
        current := [] ;
        inside := false
      end
      else if !inside then current := line :: !current)
    lines ;
  (* An unterminated fence is a malformed doc, not a block. *)
  List.rev !blocks

let register () =
  Test.register ~__FILE__ ~title:"docs: curation-workflow SQL blocks still run"
    ~tags:["docs"; "sql"; "curation"]
  @@ fun () ->
  let contents = read_file (doc ()) in
  let blocks = extract_sql_blocks contents in
  let script = String.concat "\n\n" (List.map (String.concat "\n") blocks) in

  (* Preconditions, not batched: with no SQL extracted every assertion below
     would pass vacuously, which is the failure this suite exists to prevent. *)
  Check.(
    (List.length blocks >= 4) int
      ~error_msg:
        "expected at least 4 ```sql blocks (gardening_tasks, unsafe_params x2, \
         gardening_log), found %L") ;
  Check.(
    (String.trim script <> "") string
      ~error_msg:"extraction produced no SQL — the fence parser or the doc is broken") ;

  let db_path =
    Fixture.main ~name:"curation_doc"
      ~seed:
        "INSERT INTO modules(path, lines) VALUES ('lib/installer.ml', 50);\n\
         INSERT INTO functions(module_id, name, line_start, line_end) VALUES \
         ((SELECT id FROM modules WHERE path='lib/installer.ml'), 'install_node', 1, 40);"
      ()
  in
  Db.with_db_rw db_path (fun db ->
  Batch.run @@ fun b ->
  (match Db.exec_result db script with
  | Ok () -> ()
  | Error e ->
      Batch.note b
        "the doc's ```sql``` blocks no longer run against a fresh \
         architecture-schema.sql database — doc/schema drift: %s"
        e) ;

  (* The state the doc claims its blocks produce, in order: a task opened for
     issue 214, a param recorded and THEN marked fixed, one log entry. *)
  Batch.eq_int b
    ~msg:"the doc's gardening_tasks INSERT must open exactly one task for issue 214"
    (Db.int db
       "SELECT count(*) FROM gardening_tasks WHERE github_issue=214 AND status='open'")
    1 ;
  Batch.eq_string_opt b
    ~msg:"the doc's unsafe_params INSERT-then-UPDATE must leave instance fixed=1"
    (Db.string_opt db "SELECT fixed FROM unsafe_params WHERE param_name='instance'")
    (Some "1") ;
  Batch.eq_int b
    ~msg:"the doc's gardening_log INSERT must append exactly one entry for PR 217 / issue 214"
    (Db.int db
       "SELECT count(*) FROM gardening_log WHERE pr_number=217 AND issue_number=214")
    1 ;
  Batch.eq_string_opt b
    ~msg:"the doc's gardening_log INSERT must carry contributor='jdoe' (provenance)"
    (Db.string_opt db "SELECT contributor FROM gardening_log WHERE pr_number=217")
    (Some "jdoe") ;

  (* gardening_log is append-only: the doc must not teach mutating it. Checked on
     the extracted SQL rather than on the database, because the claim is about
     what the documentation says, not about what this run happened to execute. *)
  let lowered = String.lowercase_ascii script in
  (* [verb] appears, and gardening_log appears in the same statement — i.e.
     before the next ';'. Scanning every occurrence, not just the first: one
     harmless UPDATE elsewhere in the doc must not mask a later one that does
     target the append-only table. *)
  let mentions verb =
    let rec scan from =
      if from >= String.length lowered then false
      else
        let tail = String.sub lowered from (String.length lowered - from) in
        match index_of ~needle:verb tail with
        | None -> false
        | Some i ->
            let rest = String.sub tail i (String.length tail - i) in
            let stmt =
              match String.index_opt rest ';' with
              | Some j -> String.sub rest 0 j
              | None -> rest
            in
            contains ~needle:"gardening_log" stmt
            || scan (from + i + String.length verb)
    in
    scan 0
  in
  Batch.check b
    ~msg:
      "docs/curation-workflow.md must not contain an UPDATE against \
       gardening_log — it is append-only"
    (not (mentions "update")) ;
  Batch.check b
    ~msg:
      "docs/curation-workflow.md must not contain a DELETE against \
       gardening_log — it is append-only"
    (not (mentions "delete"))) ;
  Lwt.return_unit
