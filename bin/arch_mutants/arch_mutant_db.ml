(** Persisting an executed mutation campaign.

    Split out for the same reason [arch_cov_write.ml] is: it is the only part of
    arch-mutants that opens the database read-WRITE. {!Arch_tools.Arch_db.open_ro} is
    read-only by design, so a query tool cannot mutate the index it reports on.

    The DDL is not retyped here. It is the migration file itself, embedded at compile time
    through ppx_blob — the same mechanism [Arch_index_db.schema_sql] uses for
    [architecture-schema.sql]. A second, hand-copied CREATE TABLE in OCaml is how a schema
    file and the code that writes it drift apart: the copy keeps working while the
    migration is edited, and nobody finds out until a database built by one is read by the
    other. There is one text. *)

let ddl : string = [%blob "../../mutants-schema-migration.sql"]

(* -------------------------------------------------------------------------- *)
(* The two closed vocabularies a schema CHECK declares.                        *)
(*                                                                            *)
(* They are OCaml variants, not strings, and every consumer matches on them    *)
(* TOTALLY — no [| _ ->] arm anywhere. A value added to a CHECK-declared       *)
(* vocabulary without updating its consumer is dropped with no error at all:   *)
(* no crash, no log, only a smaller answer. Measured precedents in this        *)
(* repository: calls.top_reason gained 'ambiguous_unit' at schema 1.9 and      *)
(* exn_origins.form gained 'inferred_bind' at 1.8. A variant makes the         *)
(* compiler fail on the next addition instead.                                 *)
(* -------------------------------------------------------------------------- *)

type provenance =
  | Proved_superset  (** closed test cone AND a soundness contract *)
  | Top_bounded  (** a ⊤ edge inside the test cone: the selection may have missed a test *)
  | No_contract  (** the index carries no soundness contract at all (EC-5) *)

let provenance_to_string = function
  | Proved_superset -> "proved_superset"
  | Top_bounded -> "top_bounded"
  | No_contract -> "no_contract"

(** How a survivor found under [p] must be described in words. The published VERDICT is
    slice 2's business; this is only the shortfall, named. *)
let provenance_caveat = function
  | Proved_superset ->
      "the executed set is provably a superset of every test that reaches the mutant"
  | Top_bounded ->
      "a ⊤ edge inside the test cone: the selection MAY have missed a covering test"
  | No_contract ->
      "this index carries no soundness contract, so no claim can be made about the selection"

type status = Killed | Survived | Timeout | Errored

let status_to_string = function
  | Killed -> "KILLED"
  | Survived -> "SURVIVED"
  | Timeout -> "TIMEOUT"
  | Errored -> "ERROR"

(** [None] rather than a default: an unrecognised engine status must ABORT at the call
    site, because guessing one inverts a verdict — a survived mutant read as killed is a
    defect silently deleted, which is exactly the refusal [load_mutaml] already makes. *)
let status_of_string s =
  match String.uppercase_ascii (String.trim s) with
  | "KILLED" -> Some Killed
  | "SURVIVED" -> Some Survived
  | "TIMEOUT" -> Some Timeout
  | "ERROR" -> Some Errored
  | _ -> None

type attribution = Singleton_executed_set | Engine_named

let attribution_to_string = function
  | Singleton_executed_set -> "singleton_executed_set"
  | Engine_named -> "engine_named"

(* -------------------------------------------------------------------------- *)
(* Connection                                                                  *)
(* -------------------------------------------------------------------------- *)

exception Write_failed of string

let fail fmt = Printf.ksprintf (fun s -> raise (Write_failed s)) fmt

let exec db sql =
  match Sqlite3.exec db sql with
  | Sqlite3.Rc.OK -> ()
  | rc -> fail "%s: %s\n%s" (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db) sql

let step_done db ~what stmt =
  let rc = Sqlite3.step stmt in
  ignore (Sqlite3.reset stmt : Sqlite3.Rc.t) ;
  match rc with
  | Sqlite3.Rc.DONE -> ()
  | rc -> fail "writing to %s: %s: %s" what (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db)

let text v = Sqlite3.Data.TEXT v
let int v = Sqlite3.Data.INT (Int64.of_int v)
let opt_text = function None -> Sqlite3.Data.NULL | Some v -> text v
let opt_int = function None -> Sqlite3.Data.NULL | Some v -> int v

let bind_all db stmt values =
  List.iteri
    (fun i v ->
      match Sqlite3.bind stmt (i + 1) v with
      | Sqlite3.Rc.OK -> ()
      | rc -> fail "bind %d: %s: %s" (i + 1) (Sqlite3.Rc.to_string rc) (Sqlite3.errmsg db))
    values

let run db ~what sql values =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t))
    (fun () ->
      bind_all db stmt values ;
      step_done db ~what stmt)

let query_int db sql values =
  let stmt = Sqlite3.prepare db sql in
  Fun.protect
    ~finally:(fun () -> ignore (Sqlite3.finalize stmt : Sqlite3.Rc.t))
    (fun () ->
      bind_all db stmt values ;
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> (
          match Sqlite3.column stmt 0 with
          | Sqlite3.Data.INT i -> Some (Int64.to_int i)
          | _ -> None)
      | _ -> None)

(** Open the index read-write and apply the additive migration.

    The migration is applied on every run, not once: it is [IF NOT EXISTS] throughout, so
    re-applying is a no-op, and a database that predates it would otherwise fail with
    "no such table" — which reads as a bug in the driver rather than as a missing
    migration. *)
let open_and_migrate db_path =
  if not (Sys.file_exists db_path) then fail "no such db: %s" db_path ;
  let db = Sqlite3.db_open db_path in
  exec db ddl ;
  db

let close db = ignore (Sqlite3.db_close db : bool)

(* -------------------------------------------------------------------------- *)
(* Writes                                                                      *)
(* -------------------------------------------------------------------------- *)

(** The campaign row, written with [completed_at] NULL and left that way until the
    campaign genuinely finishes. An interrupted campaign is a VALID, readable record: its
    completed mutants keep their rows and the rest are PENDING by the absence of theirs.

    Called only AFTER the engine has been resolved: an unresolvable engine writes no
    campaign row at all, because an empty campaign must never read as "no survivors". *)
let insert_campaign db ~engine ~engine_version ~seed ~producer_run_id ~engine_path
    ~test_runner_path ~profile ~granularity =
  run db ~what:"mutant_campaigns"
    "INSERT INTO mutant_campaigns(engine, engine_version, seed, producer_run_id, \
     engine_path, test_runner_path, profile, granularity) VALUES (?,?,?,?,?,?,?,?)"
    [ text engine; opt_text engine_version; opt_text seed; opt_int producer_run_id;
      text engine_path; text test_runner_path; opt_text profile; text granularity ] ;
  Int64.to_int (Sqlite3.last_insert_rowid db)

(** The site row. [INSERT OR IGNORE] then read the id back, so a re-run over unchanged
    code adds no [mutants] rows (C-5, AC-5) while still resolving every id.

    Reading the id back with a SELECT rather than [last_insert_rowid] is deliberate:
    [last_insert_rowid] is per-CONNECTION and is NOT cleared by an ignored insert, so on
    the second campaign it would hand back whatever unrelated row was last written — the
    silent-misattribution failure [Arch_index_db.exec_stmt_rowid] exists to prevent. *)
let insert_mutant db ~file_path ~line ~col_start ~col_end ~replacement ~source_hash
    ~function_id ~function_name =
  let key =
    [ text file_path; int line; int col_start; int col_end; text replacement;
      text source_hash ]
  in
  run db ~what:"mutants"
    "INSERT OR IGNORE INTO mutants(file_path, line, col_start, col_end, replacement, \
     source_hash, function_id, function_name) VALUES (?,?,?,?,?,?,?,?)"
    (key @ [ opt_int function_id; opt_text function_name ]) ;
  match
    query_int db
      "SELECT id FROM mutants WHERE file_path=? AND line=? AND col_start=? AND col_end=? \
       AND replacement=? AND source_hash=?"
      key
  with
  | Some id -> id
  | None -> fail "the mutant site row for %s:%d could not be read back" file_path line

let insert_run db ~campaign_id ~mutant_id ~engine_mutant_id ~status ~provenance ~intended
    ~executed ~superset =
  run db ~what:"mutant_runs"
    "INSERT INTO mutant_runs(campaign_id, mutant_id, engine_mutant_id, engine_status, \
     selection_provenance, intended_tests, executed_tests, executed_superset) VALUES \
     (?,?,?,?,?,?,?,?)"
    [ int campaign_id; int mutant_id; opt_text engine_mutant_id;
      text (status_to_string status); text (provenance_to_string provenance);
      int intended; int executed; int (if superset then 1 else 0) ]

let insert_kill db ~campaign_id ~mutant_id ~test_name ~attribution =
  run db ~what:"mutant_kills"
    "INSERT OR IGNORE INTO mutant_kills(campaign_id, mutant_id, test_name, attribution) \
     VALUES (?,?,?,?)"
    [ int campaign_id; int mutant_id; text test_name;
      text (attribution_to_string attribution) ]

(** Stamp [completed_at]. Called ONLY when every catalogued mutant got a run row and the
    engine exited cleanly — anything less leaves it NULL, which is what makes the campaign
    readable as partial rather than as a clean sheet. *)
let complete_campaign db ~campaign_id =
  run db ~what:"mutant_campaigns"
    "UPDATE mutant_campaigns SET completed_at = CURRENT_TIMESTAMP WHERE id = ?"
    [ int campaign_id ]
