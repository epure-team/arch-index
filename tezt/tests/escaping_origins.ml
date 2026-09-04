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
      \ (modules eo_store eo_leafmod eo_rec)\n\
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
    (* A RECURSIVE root: the edge resolves, and its callee is the root itself.
       This is the second shape that defeats an "outgoing resolved edge" proxy
       while never leaving the root set. *)
    ( "sub/eo_rec.ml",
      {|let rec loop n = if n <= 0 then assert false else loop (n - 1)
|} );
    ( "sub/eo_leafmod.ml",
      {|let a n = assert (n > 0) ; n
let b n = n / 0
let c n = n + 1
|} );
  ]

(* Extract [(nodes_reached, edges_unresolved, top)] from the coverage line.

   MEDIUM-B: nothing pinned these numbers, so mutants that set nodes_reached to
   999, edges_unresolved to 0, or swapped two fields all survived — and the
   edges_unresolved-to-0 mutant reproduces round 1's defect on every input. A
   branch whose thesis is "the coverage line is not optional" needs a test that
   would notice the line becoming a fiction. *)
let coverage out =
  String.split_on_char '\n' out
  |> List.find_opt (fun l ->
         String.length l > 9 && String.sub l 0 9 = "coverage:")
  |> Option.map (fun l ->
         let digits =
           String.split_on_char ' ' l
           |> List.filter_map (fun w -> int_of_string_opt (String.trim w))
         in
         match digits with n :: u :: t :: _ -> (n, u, t) | _ -> (-1, -1, -1))
  |> Option.value ~default:(-1, -1, -1)

(* A fixture with origins on TWO channels, same form on both.

   Round 5: the channel filter was disclosed and never verified. The tests
   pinned that the banner NAMES a channel and that an absent one is refused —
   both true of a build with the filter deleted. Neutralising the SQL predicate
   (`AND (o.channel = ? OR 1)`) left all six green, because `fixture_files`
   produces origins on one channel only, so no test COULD discriminate.

   That is round 3 again one level out: the assertion was on a proxy (the
   banner's text) instead of on the claim (which rows come back). Same cause,
   same cure — a fixture that can tell the two apart.

   Both origins are form 'raise' on purpose: if they differed by form, --forms
   alone would separate them and the test would pass with the channel filter
   gone. *)
let two_channel_files =
  [
    Fixture.dune_project;
    ( "dune",
      "(library\n\
      \ (name eo_chan_fixture)\n\
      \ (wrapped false)\n\
      \ (modules eo_chan)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ( "eo_chan.ml",
      {|exception Boom
let ex_origin n = if n > 0 then raise Boom else n
let opt_origin n : int option = if n > 0 then None else Some n
let opt_get n = Option.get (opt_origin n)
let entry n = ex_origin n + opt_get n
|} );
  ]

(* Two modules with the SAME basename in different directories, in two libraries
   because dune requires module names unique per library.

   MEDIUM-A: the whole-module ambiguity refusal had no test. The code was
   demonstrated correct, which is precisely the shape HIGH-A had in round 5 — a
   refusal that works, is announced to the user, and has nothing discriminating
   it. The consequence of a regression here is not an empty table: it is several
   protocol versions UNIONED into one root set, every member of which is then
   MUST. On the Octez tree `lib_protocol/main.ml` names 32 modules. *)
let dup_basename_files =
  [
    Fixture.dune_project;
    ( "pa/dune",
      "(library\n\
      \ (name eo_dup_a)\n\
      \ (wrapped false)\n\
      \ (modules eo_dup)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ("pa/eo_dup.ml", {|let f n = assert (n > 0) ; n
|});
    ( "pb/dune",
      "(library\n\
      \ (name eo_dup_b)\n\
      \ (wrapped false)\n\
      \ (modules eo_dup)\n\
      \ (flags (:standard -w -8-11-21-26-27-32-33-37-39)))\n" );
    ("pb/eo_dup.ml", {|let g n = assert (n < 0) ; n
|});
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
      (* HIGH-1: the CHANNEL restriction must be named in the answer. Origins
         are recorded per error channel and this command reports one of them; on
         proto_alpha only 1219 of 30526 origins are on 'exception', and of the
         29218 rows whose form is 'raise' just 20 are. An unnamed restriction
         turns "86% of what I recorded is not in this answer" into an empty
         table under a plausible header. *)
      Batch.check b
        ~msg:("the scope line names the channel it reports:\n" ^ out)
        (Arch_tezt.contains ~needle:"channel exception" out
        && Arch_tezt.contains ~needle:"NOT reported" out) ;
      (* ...and a channel with no origin in the index is REFUSED, because an
         empty table there reads as "nothing found" when the truth is "nothing
         looked at". *)
      let c_nochan, out_nochan = run db ["--roots"; "eo_a.ml:entry"; "--channel"; "nosuch"] in
      Batch.eq_int b ~msg:"a channel absent from the index is refused (exit 3)" c_nochan 3 ;
      Batch.check b
        ~msg:("...and the refusal lists the channels that ARE present:\n" ^ out_nochan)
        (Arch_tezt.contains ~needle:"Channels present" out_nochan) ;
      (* MEDIUM-D: nothing asserted that a row can be MUST, so a mutant marking
         every row MAY survived. [entry] calls [divider] unconditionally. *)
      Batch.check b
        ~msg:("an unconditionally-reached origin is marked MUST:\n" ^ out)
        (List.exists
           (fun l ->
             Arch_tezt.contains ~needle:"divider" l && Arch_tezt.contains ~needle:"MUST" l)
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
  (* eo_store.ml IS the discriminating fixture, restored. Its [only_here] calls
     [helper], so it HAS a resolved outgoing edge — and that edge's callee is
     already in the root set, so the closure never leaves it. A proxy on
     "has an outgoing resolved edge" says LOWER BOUND here; the delivered
     condition ("did the closure leave the root set") says NOTHING TRAVERSED.

     I discarded this fixture once, asserting its premise was wrong when the
     code was. Kept now precisely because it is the one that is hard to pass. *)
  let _, out_selfcontained = run db ["--roots"; "eo_store.ml:*"] in
  (* Same property through recursion rather than through a sibling call. *)
  let _, out_rec = run db ["--roots"; "eo_rec.ml:*"] in
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
        (not (Arch_tezt.contains ~needle:"LOWER BOUND" out_star)) ;
      Batch.check b
        ~msg:
          ("a SELF-CONTAINED module (resolved edge, callee already a root) never left the \
            root set:\n" ^ out_selfcontained)
        (Arch_tezt.contains ~needle:"NOTHING TRAVERSED" out_selfcontained) ;
      Batch.check b
        ~msg:("a RECURSIVE root never left the root set:\n" ^ out_rec)
        (Arch_tezt.contains ~needle:"NOTHING TRAVERSED" out_rec) ;
      (* THE COVERAGE NUMBERS THEMSELVES, derived from the fixture rather than
         copied from a run. [sub/eo_store.ml] defines exactly three functions,
         so a ':*' root reaches three nodes; the single-function root [leaf]
         reaches one. Pinning both kills a constant mutant, and pinning a case
         where the three values DIFFER (3 / 2 / 0) kills a field swap. *)
      let n_star, u_star, t_star = coverage out_selfcontained in
      Batch.eq_int b ~msg:"':*' over a 3-function module reaches exactly 3 nodes" n_star 3 ;
      Batch.eq_int b ~msg:"...and reports its 2 unresolved edges, not 0" u_star 2 ;
      Batch.eq_int b ~msg:"...and 0 ⊤" t_star 0 ;
      let n_one, _, _ = coverage out in
      Batch.eq_int b ~msg:"a single-function root reaches exactly 1 node" n_one 1 ;
      (* If the three fields were swapped, at least one of the above differs —
         asserted explicitly so the intent survives a future edit. *)
      Batch.check b ~msg:"the three coverage fields are distinguishable in this case"
        (n_star <> u_star && u_star <> t_star)) ;
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
        (* exn_origins IS present here on purpose. Without it the neighbouring
           NOT_ANALYSED guard refuses first and this test passes for the wrong
           reason — two guards producing the same exit 3 are indistinguishable
           from one guard doing both jobs. Asserting the MESSAGE is the other
           half of that. *)
        "CREATE TABLE calls(caller_name TEXT, callee_name TEXT, kind TEXT);\n\
         CREATE TABLE functions(id INTEGER PRIMARY KEY, name TEXT);\n\
         CREATE TABLE exn_origins(id INTEGER PRIMARY KEY, function_id INT, form TEXT,\n\
         exn_path TEXT, escapes INT, line INT, col INT, channel TEXT);\n\
         CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT);\n\
         INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');") ;
  let c_flat, out_flat = run flat_db ["--roots"; "a.ml:entry"] in
  let c, out = run db ["--roots"; "a.ml:f"] in
  Batch.run (fun b ->
      Batch.eq_int b ~msg:"a FLAT index is REFUSED (exit 3), not crashed into" c_flat 3 ;
      Batch.check b
        ~msg:("the flat refusal is the FLAT one, named — not the origin-table guard:\n" ^ out_flat)
        (Arch_tezt.contains ~needle:"flat schema" out_flat) ;
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

let register_channel_filter () =
  Test.register ~__FILE__
    ~title:"escaping-origins: the reported channel is the one queried, both ways"
    ~tags:["cmt"; "query"; "exn"; "origins"; "channel"]
  @@ fun () ->
  with_fixture ~name:"eo_chan" ~files:two_channel_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_chan" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let _, out_default = run db ["--roots"; "eo_chan.ml:*"; "--forms"; "raise"] in
  let _, out_option =
    run db ["--roots"; "eo_chan.ml:*"; "--forms"; "raise"; "--channel"; "option"]
  in
  let _, out_all = run db ["--roots"; "eo_chan.ml:*"; "--forms"; "raise"; "--channel"; "all"] in
  let has n o = Arch_tezt.contains ~needle:n o in
  Batch.run (fun b ->
      (* Premise: the fixture really does record on both channels. Without this
         every exclusion below could hold vacuously. *)
      Batch.check b
        ~msg:"premise: the fixture records origins on BOTH channels"
        (has "ex_origin" out_all && has "opt_origin" out_all) ;
      (* The claim, in both directions. Either half alone survives a mutant that
         neutralises the predicate: only the EXCLUSIONS have teeth. *)
      Batch.check b
        ~msg:("the default channel includes its own origin:\n" ^ out_default)
        (has "ex_origin" out_default) ;
      Batch.check b
        ~msg:("...and EXCLUDES the option-channel origin:\n" ^ out_default)
        (not (has "opt_origin" out_default)) ;
      Batch.check b
        ~msg:("--channel option includes the option origin:\n" ^ out_option)
        (has "opt_origin" out_option) ;
      Batch.check b
        ~msg:("...and EXCLUDES the exception-channel origin:\n" ^ out_option)
        (not (has "ex_origin" out_option)) ;
      (* MEDIUM-1: an exn_origins table that EXISTS but is empty must not let an
         arbitrary channel name through and be echoed back as authoritative. *)
      let empty_db = Arch_tezt.temp_db "eo_chan_empty" in
      if Sys.file_exists empty_db then Sys.remove empty_db ;
      Db.with_db_rw empty_db (fun conn ->
          Db.exec conn
            "CREATE TABLE modules(id INTEGER PRIMARY KEY, path TEXT);\n\
             CREATE TABLE functions(id INTEGER PRIMARY KEY, name TEXT, module_id INT);\n\
             CREATE TABLE calls(caller_id INT, callee_id INT, kind TEXT);\n\
             CREATE TABLE exn_origins(id INTEGER PRIMARY KEY, function_id INT, form TEXT,\n\
             exn_path TEXT, escapes INT, line INT, col INT, channel TEXT);\n\
             CREATE TABLE comment_db_meta(key TEXT PRIMARY KEY, value TEXT);\n\
             INSERT INTO comment_db_meta VALUES('callgraph_contract','v1');\n\
             INSERT INTO modules VALUES(1,'a.ml');\n\
             INSERT INTO functions VALUES(1,'f',1);") ;
      let c_bogus, out_bogus = run empty_db ["--roots"; "a.ml:f"; "--channel"; "totally_bogus"] in
      Batch.eq_int b
        ~msg:"an EMPTY origin table does not wave an arbitrary channel through" c_bogus 3 ;
      Batch.check b
        ~msg:("...and does not echo the bogus channel as authoritative:\n" ^ out_bogus)
        (not (has "channel totally_bogus" out_bogus)) ;
      (* The message must say the table is EMPTY. The round-5 bug rendered an
         empty candidate list as blank — "Channels present:  (or 'all')" — which
         reads as "channels exist, just not yours" on the one input where the
         truth is "nothing was ever recorded". Both wordings exit 3, so only the
         text distinguishes them. *)
      Batch.check b
        ~msg:("...and says the origin table is EMPTY rather than listing nothing:\n" ^ out_bogus)
        (has "exn_origins is empty" out_bogus)) ;
  Lwt.return_unit

let register_module_ambiguity () =
  Test.register ~__FILE__
    ~title:"escaping-origins: an ambiguous WHOLE-MODULE root is refused, never unioned"
    ~tags:["cmt"; "query"; "exn"; "origins"; "ambiguity"; "module"]
  @@ fun () ->
  with_fixture ~name:"eo_dup" ~files:dup_basename_files @@ fun fixture ->
  let db = Arch_tezt.temp_db "eo_dup" in
  let code, output = Arch_tezt.index_raw_into ~db fixture in
  if code <> 0 then Test.fail "index failed (exit %d):\n%s" code output ;
  let c_ambig, out_ambig = run db ["--roots"; "eo_dup.ml:*"] in
  let c_ok, out_ok = run db ["--roots"; "pa/eo_dup.ml:*"] in
  Batch.run (fun b ->
      (* Premise: both modules really are indexed, or the refusal below could
         fire for want of a second candidate rather than because of one. *)
      Batch.check b
        ~msg:"premise: both same-basename modules are in the index"
        (Db.with_db db (fun c ->
             Db.int c "SELECT count(*) FROM modules WHERE path LIKE '%/eo_dup.ml'")
        = 2) ;
      Batch.eq_int b ~msg:"an ambiguous ':*' root is REFUSED (exit 3)" c_ambig 3 ;
      Batch.check b
        ~msg:("...listing BOTH candidate modules, not one:\n" ^ out_ambig)
        (Arch_tezt.contains ~needle:"pa/eo_dup.ml" out_ambig
        && Arch_tezt.contains ~needle:"pb/eo_dup.ml" out_ambig) ;
      (* The teeth: a union would ANSWER, and would answer about both. *)
      Batch.check b
        ~msg:("a union would have reported origins; nothing is reported:\n" ^ out_ambig)
        (not (Arch_tezt.contains ~needle:"|assert|" out_ambig)) ;
      Batch.eq_int b ~msg:"the qualified path is accepted" c_ok 0 ;
      (* ...and answers about that module ALONE — the other library's origin
         must not appear, which is what distinguishes "resolved one" from
         "unioned both and happened to print one". *)
      Batch.check b
        ~msg:("the qualified root reports its own origin:\n" ^ out_ok)
        (Arch_tezt.contains ~needle:"pa/eo_dup.ml" out_ok) ;
      Batch.check b
        ~msg:("...and NOT the same-basename module's:\n" ^ out_ok)
        (not (Arch_tezt.contains ~needle:"pb/eo_dup.ml" out_ok))) ;
  Lwt.return_unit

let register () =
  register_surface () ;
  register_module_ambiguity () ;
  register_channel_filter () ;
  register_root_anchoring () ;
  register_nothing_traversed () ;
  register_not_analysed () ;
  register_form_filter () ;
  register_ambiguous_root ()
