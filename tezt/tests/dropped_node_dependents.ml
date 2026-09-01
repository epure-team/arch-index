(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** What the indexer does with the rows that hang off a row it could not store.

    A rejected insert is not a lost row, it is a lost SUBTREE. A refused
    [modules] row takes every function, type, dep and call of that compilation
    unit with it; a refused [types] row takes its fields and constructors; a
    refused [functions] row takes its type usages and its calls. The indexer
    drops them deliberately — the alternative, filing them under whatever
    [last_insert_rowid] happens to hold, is silent misattribution — and that
    discipline is what these tests pin.

    They also pin the consequence nobody sees at the drop site. A dropped
    function is absent from the [functions] table, and so is [Stdlib.map]: to
    the call resolver the two look identical. It answers "external" and emits a
    MUST edge to a leaf, which for [Stdlib.map] is honest and for a dropped
    in-project body is a false claim — that body exists, nothing it calls is in
    the graph, and an [arch-query reaches] that stops there returns UNREACHABLE
    on evidence it does not have. Every dropped node is therefore recorded, and
    a callee known to be dropped resolves to MAY_TOP: the ⊤ frontier, which
    turns that verdict into UNKNOWN.

    {2 How a rejection is forced}

    In a real run these paths are latent. Neither corpus reaches them: the
    arch-index self-index reports zero rejections at every scope, and an Octez
    index (10 033 modules) reports rejections only in [type_usage]. [modules]
    can only refuse on its [path TEXT UNIQUE NOT NULL], which needs two
    compilation units claiming one relative source path, and [functions] is
    [INSERT OR REPLACE], which replaces rather than refuses.

    So the rejection is injected where the database decides it: the CLI takes
    [--schema-path], and the schema handed to it here is the real
    [architecture-schema.sql] plus one [BEFORE INSERT ... RAISE(ABORT)] trigger
    naming the row to refuse. Everything upstream of the refusal — the .cmt
    files, the walk, the insert order, the resolver — is the production path,
    unmodified and unaware. That is the property being tested: what the indexer
    does when an insert comes back refused, whatever refused it. *)

open Arch_tezt

(* The fixture: [b.ml] owns the bodies that get dropped, [cg.ml] calls them
   across a module boundary so the resolution path under test is the qualified
   one ([Head_qualified], the branch that emitted the MUST leaf). [kept] and
   [kept_ty] are the control: whatever the trigger refuses, they must survive,
   or a test would pass just as well against an indexer that dropped
   everything. *)
let fixture_files =
  [
    Fixture.dune_project;
    ("dune", "(library (name corpus) (modules b cg))\n");
    ( "b.ml",
      {|let ghost_target (x : int) : int = x
let kept (x : int) : int = x

type dropped_ty = {fa : int; fb : int}
type kept_ty = {ka : int}
type dropped_variant = Da | Db | Dc
type kept_variant = Ka
|} );
    ( "cg.ml",
      {|let entry (x : int) : int = B.ghost_target x
let control (x : int) : int = B.kept x
|} );
  ]

(* The real schema plus one abort trigger. Read from the repo's own
   [architecture-schema.sql] rather than from a copy, so the fixture cannot
   drift away from the schema the indexer is actually run against. *)
let schema_with_trigger ~name ~trigger =
  let path = Temp.file (name ^ "-schema.sql") in
  write_file path (read_file (schema ()) ^ "\n" ^ trigger ^ "\n") ;
  path

(* [Arch_tezt.index] fails the test on a non-zero exit, and a non-zero exit is
   the CORRECT behaviour here: the CLI's completeness gate exits 1 whenever a
   row was rejected, which is the whole premise. So the run is driven directly,
   and the exit code is asserted rather than assumed — a rejection that somehow
   exited 0 would mean the gate had regressed, and every assertion below would
   then be reading a database nobody was warned about. *)
let index_with_schema ~name ~schema_path fixture =
  let db = temp_db name in
  let code, output =
    run_command
      (callgraph_ocaml ())
      [
        "--build-dir";
        fixture.build_dir;
        "--db-path";
        db;
        "--schema-path";
        schema_path;
      ]
  in
  if code <> 1 then
    Test.fail
      "expected exit 1 from the completeness gate (a row WAS rejected), got \
       %d:\n\
       %s"
      code
      output ;
  (db, output)

let count conn sql =
  Db.rows conn sql |> Db.first_column ~sql |> function
  | None -> Test.fail "no row from: %s" sql
  | Some v -> Db.to_int ~sql v

let text conn sql =
  Db.rows conn sql |> Db.first_column ~sql |> function
  | None -> Test.fail "no row from: %s" sql
  | Some v -> Db.to_string ~sql v

(* ────────────────────────────────────────────────────────────────────────── *)
(* A dropped function must not be indexed as an external leaf                 *)
(* ────────────────────────────────────────────────────────────────────────── *)

let register_dropped_function () =
  Test.register
    ~__FILE__
    ~title:
      "indexer: a call to a function whose row was rejected is MAY_TOP, not a \
       MUST external leaf"
    ~tags:["indexer"; "consistency"; "rejections"; "soundness"]
  @@ fun () ->
  with_fixture ~name:"dropped_function" ~files:fixture_files @@ fun fixture ->
  let schema_path =
    schema_with_trigger
      ~name:"dropped_function"
      ~trigger:
        "CREATE TRIGGER reject_ghost_fn BEFORE INSERT ON functions WHEN \
         NEW.name = 'ghost_target' BEGIN SELECT RAISE(ABORT, 'test trigger: \
         functions row refused'); END;"
  in
  let db, output =
    index_with_schema ~name:"dropped_function" ~schema_path fixture
  in
  Db.with_db db (fun conn ->
      Batch.run (fun b ->
          (* The premise: exactly one row refused, and it was a [functions]
             row. Without this the test could pass on a run where the trigger
             never fired and nothing was ever dropped. *)
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the trigger must have refused exactly one functions row; \
                  indexer said:\n\
                  %s"
                 output)
            (contains ~needle:"functions: 1 row(s) rejected" output) ;
          Batch.eq_int
            b
            ~msg:"the dropped function must have no row"
            (count conn "SELECT COUNT(*) FROM functions WHERE name='ghost_target'")
            0 ;
          (* The headline. [Corpus.B.ghost_target] is unresolvable because its
             row was refused — the same shape a genuine external presents — so
             before the dropped-node registry this edge was recorded MUST with
             a NULL callee: a claim that reachability legitimately stops at a
             body the indexer read and threw away. *)
          Batch.eq_string
            b
            ~msg:
              "the edge to the dropped callee must be MAY_TOP (⊤ frontier), \
               not a MUST external leaf"
            (text
               conn
               "SELECT kind FROM calls WHERE callee_name LIKE '%ghost_target'")
            "MAY_TOP" ;
          Batch.eq_int
            b
            ~msg:"the dropped callee resolves to no id, MAY_TOP or not"
            (count
               conn
               "SELECT COUNT(*) FROM calls WHERE callee_name LIKE \
                '%ghost_target' AND callee_id IS NOT NULL")
            0 ;
          (* The control, in the same database and the same run: a callee that
             was stored still resolves, and still resolves as MUST. A guard
             that answered MAY_TOP for everything unresolved — or for
             everything, full stop — would satisfy the assertion above and
             destroy the index. *)
          Batch.eq_string
            b
            ~msg:"a stored callee must still be a resolved MUST edge"
            (text conn "SELECT kind FROM calls WHERE callee_name LIKE '%.kept'")
            "MUST" ;
          Batch.eq_int
            b
            ~msg:"the stored callee must still resolve to its id"
            (count
               conn
               "SELECT COUNT(*) FROM calls WHERE callee_name LIKE '%.kept' AND \
                callee_id IS NOT NULL")
            1)) ;
  Lwt.return_unit

(* ────────────────────────────────────────────────────────────────────────── *)
(* A dropped compilation unit                                                 *)
(* ────────────────────────────────────────────────────────────────────────── *)

let register_dropped_module () =
  Test.register
    ~__FILE__
    ~title:
      "indexer: a rejected modules row indexes nothing from that unit, and its \
       callers go to MAY_TOP"
    ~tags:["indexer"; "consistency"; "rejections"; "soundness"]
  @@ fun () ->
  with_fixture ~name:"dropped_module" ~files:fixture_files @@ fun fixture ->
  let schema_path =
    schema_with_trigger
      ~name:"dropped_module"
      ~trigger:
        "CREATE TRIGGER reject_b_module BEFORE INSERT ON modules WHEN NEW.path \
         LIKE '%b.ml' BEGIN SELECT RAISE(ABORT, 'test trigger: modules row \
         refused'); END;"
  in
  let db, output =
    index_with_schema ~name:"dropped_module" ~schema_path fixture
  in
  Db.with_db db (fun conn ->
      Batch.run (fun b ->
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the trigger must have refused exactly one modules row; \
                  indexer said:\n\
                  %s"
                 output)
            (contains ~needle:"modules: 1 row(s) rejected" output) ;
          (* One refused statement, a whole unit gone. The tally says "1", so
             the extent of the loss has to be said somewhere an operator will
             read it — otherwise a report of one rejected row stands in for
             thousands of dropped ones. *)
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the run must name the dropped compilation unit, not leave \
                  the loss as a count of 1; indexer said:\n\
                  %s"
                 output)
            (contains ~needle:"Dropped compilation unit" output
            && contains ~needle:"b.ml" output) ;
          (* Nothing from the unit: no module row, and therefore no function,
             type, field or constructor of it filed under a neighbour. There is
             no [module_id] of its own to hang them from, and the only id
             available is somebody else's. *)
          Batch.eq_int
            b
            ~msg:"the rejected module must have no row"
            (count conn "SELECT COUNT(*) FROM modules WHERE path LIKE '%b.ml'")
            0 ;
          Batch.eq_int
            b
            ~msg:
              "no function of the dropped unit may be indexed — under a \
               neighbouring module or at all"
            (count
               conn
               "SELECT COUNT(*) FROM functions WHERE name IN \
                ('ghost_target','kept')")
            0 ;
          Batch.eq_int
            b
            ~msg:"no type of the dropped unit may be indexed"
            (count
               conn
               "SELECT COUNT(*) FROM types WHERE name IN \
                ('dropped_ty','kept_ty','dropped_variant','kept_variant')")
            0 ;
          Batch.eq_int
            b
            ~msg:"and so no field or constructor of them either"
            (count conn "SELECT COUNT(*) FROM type_fields")
            0 ;
          Batch.eq_int
            b
            ~msg:"and so no constructor of them either"
            (count conn "SELECT COUNT(*) FROM type_constructors")
            0 ;
          (* The surviving unit is indexed normally: the drop is scoped to the
             unit that was refused. *)
          Batch.eq_int
            b
            ~msg:"the other compilation unit must be indexed as usual"
            (count conn "SELECT COUNT(*) FROM functions WHERE name IN \
                         ('entry','control')")
            2 ;
          (* Both calls now point into a unit that was never read. Neither is a
             leaf — the bodies exist — so both are ⊤. *)
          Batch.eq_int
            b
            ~msg:
              "every call into the dropped unit must be MAY_TOP, including the \
               one whose callee would otherwise have resolved"
            (count
               conn
               "SELECT COUNT(*) FROM calls WHERE kind='MAY_TOP' AND \
                callee_name LIKE '%ghost_target' OR kind='MAY_TOP' AND \
                callee_name LIKE '%.kept'")
            2 ;
          Batch.eq_int
            b
            ~msg:"no call into the dropped unit may claim MUST"
            (count
               conn
               "SELECT COUNT(*) FROM calls WHERE kind='MUST' AND callee_name \
                LIKE 'Corpus.B.%'")
            0)) ;
  Lwt.return_unit

(* ────────────────────────────────────────────────────────────────────────── *)
(* A dropped type                                                             *)
(* ────────────────────────────────────────────────────────────────────────── *)

let register_dropped_type () =
  Test.register
    ~__FILE__
    ~title:
      "indexer: a rejected types row drops its fields and constructors rather \
       than filing them under another type"
    ~tags:["indexer"; "consistency"; "rejections"]
  @@ fun () ->
  with_fixture ~name:"dropped_type" ~files:fixture_files @@ fun fixture ->
  let schema_path =
    schema_with_trigger
      ~name:"dropped_type"
      ~trigger:
        "CREATE TRIGGER reject_types BEFORE INSERT ON types WHEN NEW.name IN \
         ('dropped_ty','dropped_variant') BEGIN SELECT RAISE(ABORT, 'test \
         trigger: types row refused'); END;"
  in
  let db, output =
    index_with_schema ~name:"dropped_type" ~schema_path fixture
  in
  Db.with_db db (fun conn ->
      Batch.run (fun b ->
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the trigger must have refused exactly two types rows; \
                  indexer said:\n\
                  %s"
                 output)
            (contains ~needle:"types: 2 row(s) rejected" output) ;
          Batch.eq_int
            b
            ~msg:"the rejected types must have no row"
            (count
               conn
               "SELECT COUNT(*) FROM types WHERE name IN \
                ('dropped_ty','dropped_variant')")
            0 ;
          (* The point. [dropped_ty] has two labels and [dropped_variant] three
             constructors; with no id of their own the only parent available is
             [kept_ty]'s or [kept_variant]'s, and a foreign key is perfectly
             happy with that. Exact counts, not "not more than": the surviving
             types must keep exactly their own. *)
          Batch.eq_int
            b
            ~msg:
              "only the surviving record's single field may exist — the \
               dropped record's two must not be filed under it"
            (count conn "SELECT COUNT(*) FROM type_fields")
            1 ;
          Batch.eq_string
            b
            ~msg:"and it must belong to the surviving record"
            (text
               conn
               "SELECT t.name FROM type_fields f JOIN types t ON t.id = \
                f.type_id")
            "kept_ty" ;
          Batch.eq_int
            b
            ~msg:
              "only the surviving variant's single constructor may exist — the \
               dropped variant's three must not be filed under it"
            (count conn "SELECT COUNT(*) FROM type_constructors")
            1 ;
          Batch.eq_string
            b
            ~msg:"and it must belong to the surviving variant"
            (text
               conn
               "SELECT t.name FROM type_constructors c JOIN types t ON t.id = \
                c.type_id")
            "kept_variant" ;
          (* One refused statement per type, five dependent rows gone. Say so,
             per type, or the exit report's "2 row(s) rejected" is the only
             trace of a seven-row loss. *)
          Batch.check
            b
            ~msg:
              (Printf.sprintf
                 "the run must name each dropped type and how many dependents \
                  went with it; indexer said:\n\
                  %s"
                 output)
            (contains ~needle:"Dropped type dropped_ty" output
            && contains ~needle:"Dropped type dropped_variant" output))) ;
  Lwt.return_unit
