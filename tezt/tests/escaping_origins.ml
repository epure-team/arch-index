(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** [arch-query escaping-origins] — the fatal-origin surface reachable from a
    named root.

    The command answers "what can crash this, and how" by intersecting two
    things that already exist: the [exn_origins] rows whose form is fatal and
    which escape their own function, and the forward closure of a caller-chosen
    root. It invents nothing; the only judgement in the output is which roots
    count as entry points, and that judgement is the caller's.

    What is pinned here is not the row content — that changes with the corpus —
    but the three properties that make the output honest, each of which is a
    defect the command would otherwise reintroduce:

    - the coverage line, without which a LOWER BOUND reads as a complete answer;
    - MUST vs MAY, because [reaches] is MUST-only in this tool and silently
      mixing the two would break that contract;
    - refusal on an ambiguous root, because on the real corpus one bare name
      ([apply_operation]) denotes 60 functions across 32 protocol versions. *)

open Arch_tezt

let fixture_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name eo_fixture)\n\
      \ (wrapped false)\n\
      \ (modules eo_a eo_b)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    (* Two modules defining the SAME function name, which is what makes the
       ambiguity assertion meaningful rather than hypothetical. *)
    ( "eo_b.ml",
      {|let entry n = n + 1
let divider n = 100 / n
|} );
    ( "eo_a.ml",
      {|let asserter n = assert (n > 0) ; n

let divider n = 10 / n

(* reached from [entry] only through a conditional call: MAY, not MUST *)
let maybe n = if n > 3 then asserter n else n

let entry n = maybe (divider n)

(* NOT reachable from [entry] — must not appear in a run rooted at entry. *)
let unrelated n = assert (n < 0) ; n
|} );
  ]

(* [eo_store.ml] is named so that "store.ml" is a strict suffix of it WITHOUT a
   '/' boundary — the exact shape that let an unanchored pattern answer for a
   module nobody named. *)
let anchor_files =
  [
    Fixture.dune_project;
    ( "sub/dune",
      "(library\n\
      \ (name eo_anchor_fixture)\n\
      \ (wrapped false)\n\
      \ (modules eo_store eo_leafmod)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    (* Under sub/ ON PURPOSE: the caller's spec ("eo_store.ml:only_here") must
       then DIFFER from the resolved root ("sub/eo_store.ml:only_here"), which
       is the only shape in which an assertion can tell the echo apart from the
       input. A flat fixture makes the two identical and lets a mutant that
       echoes the spec back pass — the one mutation that would re-hide the
       unanchored-root defect. *)
    ( "sub/eo_store.ml",
      {|let helper n = assert (n > 0) ; n
let only_here n = helper n
let leaf n = n + 1
|} );
    (* THREE functions, NONE calling another: the whole module has no outgoing
       resolved edge. [eo_store.ml] cannot serve here — its [only_here] calls
       [helper], so a ':*' root over it genuinely traverses. The broken guard
       compared node count to ROOT count, and under ':*' the root count is a
       MODULE count, always 1; so it could only fire on a single-function
       module, and only a multi-function leaf distinguishes the fix from it. *)
    ( "sub/eo_leafmod.ml",
      {|let a n = assert (n > 0) ; n
let b n = n / 0
let c n = n + 1
|} );
  ]

let run ?(fmt = "list") db args =
  Arch_tezt.run_command
    ~env:[("ARCH_QUERY_FORMAT", fmt)]
    (Arch_tezt.arch_query ())
    (db :: "escaping-origins" :: args)

let register_surface () =
  Test.register ~__FILE__
    ~title:"escaping-origins: fatal origins in the closure, with coverage and MAY/MUST"
    ~tags:["cmt"; "query"; "exn"; "origins"]
  @@ fun () ->
  with_fixture ~name:"eo_surface" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_surface" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let c, out = run db ["--roots"; "eo_a.ml:entry"] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"escaping-origins exits 0 on a well-formed root" c 0 ;
      if c <> 0 then Batch.note b "output:\n%s" out ;
      (* PROPERTY 1 — the coverage line. A fatal-origin list printed without it
         reads as "these are the ways it can die", when the honest claim is
         "these are the ways it can die THAT I COULD SEE". *)
      Batch.check b
        ~msg:("the coverage line is present and says LOWER BOUND:\n" ^ out)
        (Arch_tezt.contains ~needle:"coverage:" out
        && Arch_tezt.contains ~needle:"LOWER BOUND" out) ;
      (* The closure is real: the assert reached only through [maybe] is found. *)
      Batch.check b
        ~msg:("the transitively-reached assert is reported:\n" ^ out)
        (Arch_tezt.contains ~needle:"asserter" out) ;
      (* PROPERTY 2 — MUST and MAY are distinguished, and this row is MAY: the
         call to [asserter] sits behind [if n > 3]. If every row were stamped
         MUST this assertion is what fails. *)
      Batch.check b
        ~msg:("a conditionally-reached origin is marked MAY:\n" ^ out)
        (List.exists
           (fun l ->
             Arch_tezt.contains ~needle:"asserter" l && Arch_tezt.contains ~needle:"MAY" l)
           (String.split_on_char '\n' out)) ;
      (* Scope: something outside the closure must NOT be reported. Without
         this, a command that ignored --roots entirely would pass every other
         assertion in this test. *)
      Batch.check b
        ~msg:("a function outside the closure is not reported:\n" ^ out)
        (not (Arch_tezt.contains ~needle:"unrelated" out))) ;
  Lwt.return_unit

let register_form_filter () =
  Test.register ~__FILE__
    ~title:"escaping-origins: --forms selects, and an unknown form is refused"
    ~tags:["cmt"; "query"; "exn"; "origins"; "forms"]
  @@ fun () ->
  with_fixture ~name:"eo_forms" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_forms" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let c_div, out_div = run db ["--roots"; "eo_a.ml:entry"; "--forms"; "division"] in
  let c_bad, _ = run db ["--roots"; "eo_a.ml:entry"; "--forms"; "explosion"] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"--forms division exits 0" c_div 0 ;
      Batch.check b
        ~msg:("--forms division keeps the division origin:\n" ^ out_div)
        (Arch_tezt.contains ~needle:"division" out_div) ;
      (* The filter must actually filter — asserts are excluded here. *)
      Batch.check b
        ~msg:("--forms division drops the assert origins:\n" ^ out_div)
        (not (Arch_tezt.contains ~needle:"asserter" out_div)) ;
      (* An unknown form is a caller error, not a silently-empty table: an empty
         result would read as "nothing can crash", the worst possible answer to
         a typo. *)
      Batch.eq_int b ~msg:"an unknown --forms value is refused with exit 2" c_bad 2) ;
  Lwt.return_unit

let register_ambiguous_root () =
  Test.register ~__FILE__
    ~title:"escaping-origins: an ambiguous root is refused, never unioned"
    ~tags:["cmt"; "query"; "exn"; "origins"; "ambiguity"]
  @@ fun () ->
  with_fixture ~name:"eo_ambig" ~files:fixture_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_ambig" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  (* [divider] is defined in BOTH fixture modules. *)
  let c_ambig, out_ambig = run db ["--roots"; "divider"] in
  let c_ok, _ = run db ["--roots"; "eo_a.ml:divider"] in
  let c_missing, _ = run db ["--roots"; "eo_a.ml:no_such_function"] in
  Batch.run (fun b ->
      (* On the real corpus this is not a corner case: [apply_operation] names
         60 functions across 32 protocol versions, and main.ml's is a point-free
         alias of apply.ml's — so a union would also look like the tool
         contradicting itself. *)
      Batch.eq_int b ~msg:"an ambiguous bare-name root is REFUSED (exit 3)" c_ambig 3 ;
      (* A refusal that does not say what to pick instead just moves the work to
         the caller, so the candidates are printed before refusing. *)
      Batch.check b
        ~msg:("the refusal lists the candidate roots:\n" ^ out_ambig)
        (Arch_tezt.contains ~needle:"eo_a.ml:divider" out_ambig
        && Arch_tezt.contains ~needle:"eo_b.ml:divider" out_ambig) ;
      Batch.eq_int b ~msg:"the same name qualified by its module is accepted" c_ok 0 ;
      Batch.eq_int b ~msg:"a root matching nothing is refused (exit 3)" c_missing 3) ;
  Lwt.return_unit

(* The defect this test exists for is NOT the one the ambiguity test covers.
   There, several candidates matched and the command refused. Here EXACTLY ONE
   matches — but it is in a module the caller never named, because the root
   pattern was an unanchored suffix. The refusal never fires, and the command
   answers, exit 0, about the wrong file. On the whole Octez tree the same shape
   answers for the wrong protocol version. *)
let register_root_anchoring () =
  Test.register ~__FILE__
    ~title:"escaping-origins: a root suffix must align on a path boundary"
    ~tags:["cmt"; "query"; "exn"; "origins"; "ambiguity"; "anchoring"]
  @@ fun () ->
  with_fixture ~name:"eo_anchor" ~files:anchor_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_anchor" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  (* [eo_store.ml] exists; [store.ml] does NOT. A suffix match without a '/'
     boundary would find eo_store.ml, uniquely, and answer for it. *)
  let c_sfx, _ = run db ["--roots"; "store.ml:only_here"] in
  (* '_' is a LIKE metacharacter: unescaped it matches any character, so this
     would match eo_store.ml one character at a time. *)
  let c_meta, _ = run db ["--roots"; "eo_stor_.ml:only_here"] in
  let c_ok, out_ok = run db ["--roots"; "eo_store.ml:only_here"] in
  Batch.run (fun b ->
      Batch.eq_int b
        ~msg:"a suffix that does not align on '/' is REFUSED, not answered" c_sfx 3 ;
      Batch.eq_int b
        ~msg:"a LIKE metacharacter in the root is escaped, not honoured" c_meta 3 ;
      Batch.eq_int b ~msg:"the correctly-named module is still accepted" c_ok 0 ;
      (* The answer must say what it rooted ON, so a mismatch is legible in the
         output and not only in the exit code. *)
      (* The echo must be the RESOLVED root, not the caller's spec — hence the
         "sub/" prefix, which the caller never typed. *)
      Batch.check b
        ~msg:("the preamble echoes the RESOLVED root, directory included:\n" ^ out_ok)
        (Arch_tezt.contains ~needle:"root: " out_ok
        && Arch_tezt.contains ~needle:"sub/eo_store.ml:only_here" out_ok) ;
      (* Producer identity, not just corpus size: a reviewer measured a
         different count with a byte-identical scope line because the producer
         differed. *)
      Batch.check b
        ~msg:("the scope line carries schema and contract identity:\n" ^ out_ok)
        (Arch_tezt.contains ~needle:"schema " out_ok
        && Arch_tezt.contains ~needle:"contract " out_ok) ;
      (* ...AND THE VALUES FOLLOW THE INDEX. This line exists because a
         byte-identical scope line once hid a 21-vs-37 discrepancy whose real
         variable was the producer version. Grepping the literal "schema "
         passes against two hard-coded constants, and would not have caught the
         thing the line was added for. So: change the stored version, and the
         preamble must change with it. *)
      Db.with_db_rw db (fun conn ->
          Db.exec conn
            "INSERT OR REPLACE INTO comment_db_meta(key,value) VALUES('schema_version','9.99')") ;
      let _, out_bumped = run db ["--roots"; "eo_store.ml:only_here"] in
      Batch.check b
        ~msg:("the schema stamp is READ from the index, not hard-coded:\n" ^ out_bumped)
        (Arch_tezt.contains ~needle:"schema 9.99" out_bumped) ;
      Batch.check b ~msg:"changing the stored version changes the preamble"
        (out_ok <> out_bumped)) ;
  Lwt.return_unit

(* A root with no outgoing resolved edge printed "0 edges unresolved · 0 ⊤" and
   an empty table — the strongest completeness signal the format can emit, for
   an analysis that traversed nothing. It needs its own word. *)
let register_nothing_traversed () =
  Test.register ~__FILE__
    ~title:"escaping-origins: an unentered closure says so, rather than reading as clean"
    ~tags:["cmt"; "query"; "exn"; "origins"; "coverage"]
  @@ fun () ->
  with_fixture ~name:"eo_leaf" ~files:anchor_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_leaf" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let _, out = run db ["--roots"; "eo_store.ml:leaf"] in
  (* THE ':*' CASE IS THE ONE THAT REGRESSED THROUGH ROUND 1. The first guard
     compared the node count to the ROOT count, and under ':*' the root count is
     a MODULE count — always 1 after the ambiguity check — so it could only ever
     fire on a module with at most one function. A singleton fixture passes
     against that broken guard, which is precisely why the defect survived. This
     module has three functions and no outgoing edge. *)
  let _, out_star = run db ["--roots"; "eo_leafmod.ml:*"] in
  Batch.run (fun b ->
      Batch.check b
        ~msg:("a root with no outgoing edge is reported as NOTHING TRAVERSED:\n" ^ out)
        (Arch_tezt.contains ~needle:"NOTHING TRAVERSED" out) ;
      Batch.check b
        ~msg:("...and does NOT claim a lower bound over a closure it never entered:\n" ^ out)
        (not (Arch_tezt.contains ~needle:"LOWER BOUND" out)) ;
      Batch.check b
        ~msg:
          ("a WHOLE-MODULE root with several functions and no outgoing edge says so too:\n"
         ^ out_star)
        (Arch_tezt.contains ~needle:"NOTHING TRAVERSED" out_star) ;
      Batch.check b
        ~msg:("...and the ':*' form does not claim a lower bound either:\n" ^ out_star)
        (not (Arch_tezt.contains ~needle:"LOWER BOUND" out_star))) ;
  Lwt.return_unit

(* An index with no exception analysis at all must refuse BEFORE printing a
   header. Previously it printed scope: and coverage:, then dumped a raw sqlite
   error and the whole query — a consumer reading stdout saw a plausible header
   and an empty table. *)
let register_not_analysed () =
  Test.register ~__FILE__
    ~title:"escaping-origins: an index with no origin table is refused before any output"
    ~tags:["cmt"; "query"; "exn"; "origins"; "refusal"]
  @@ fun () ->
  let db = Arch_tezt.temp_db "eo_noexn" in
  if Sys.file_exists db then Sys.remove db ;
  Db.with_db_rw db (fun conn ->
      Db.exec conn
        "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT);\n\
         CREATE TABLE functions(id INTEGER PRIMARY KEY, name TEXT, module_id INT);\n\
         CREATE TABLE calls(caller_id INT, callee_id INT, kind TEXT);\n\
         CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT);\n\
         INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');\n\
         INSERT INTO modules VALUES(1,'a.ml');\n\
         INSERT INTO functions VALUES(1,'f',1);") ;
  (* The FLAT schema is the other half of this finding, and round 1 removed the
     symptom (an unused [flat] flag) without removing the defect: on a flat index
     the command still leaked a raw sqlite error and the whole query, exit 2 —
     while [reaches] answered and [unreachable]/[exn-stats] refused cleanly on
     the SAME database. Being the only one of four that crashes is a missing
     guard, not a schema question. *)
  let flat_db = Arch_tezt.temp_db "eo_flat" in
  if Sys.file_exists flat_db then Sys.remove flat_db ;
  Db.with_db_rw flat_db (fun conn ->
      Db.exec conn
        "CREATE TABLE calls(caller_name TEXT, callee_name TEXT, kind TEXT);\n\
         CREATE TABLE functions(id INTEGER PRIMARY KEY, name TEXT);\n\
         CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT);\n\
         INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');") ;
  let c_flat, out_flat = run flat_db ["--roots"; "a.ml:entry"] in
  let c, out = run db ["--roots"; "a.ml:f"] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"a FLAT index is REFUSED (exit 3), not crashed into" c_flat 3 ;
      Batch.check b
        ~msg:("the flat refusal leaks no SQL:\n" ^ out_flat)
        (not (Arch_tezt.contains ~needle:"SELECT" out_flat)) ;
      Batch.check b
        ~msg:("the flat refusal prints no coverage header:\n" ^ out_flat)
        (not (Arch_tezt.contains ~needle:"coverage:" out_flat)) ;
      Batch.eq_int b ~msg:"an index with no exn_origins is REFUSED (exit 3)" c 3 ;
      Batch.check b
        ~msg:("the refusal comes BEFORE any coverage header:\n" ^ out)
        (not (Arch_tezt.contains ~needle:"coverage:" out)) ;
      Batch.check b
        ~msg:("no raw SQL is leaked to the caller:\n" ^ out)
        (not (Arch_tezt.contains ~needle:"WITH RECURSIVE" out))) ;
  Lwt.return_unit

let register () =
  register_surface () ;
  register_root_anchoring () ;
  register_nothing_traversed () ;
  register_not_analysed () ;
  register_form_filter () ;
  register_ambiguous_root ()
