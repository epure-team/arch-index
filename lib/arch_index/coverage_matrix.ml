(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

type status = Covered | Not_analysed | Failed | Partial

let status_to_string = function
  | Covered -> "covered"
  | Not_analysed -> "not_analysed"
  | Failed -> "failed"
  | Partial -> "partial"

type row = {language : string option; analysis : string; status : status; detail : string option}

(* [Unix.access] alone succeeds on a DIRECTORY named e.g. "bin/arch-callgraph-go"
   (a directory's own executable bit means "traversable", which every normal
   directory has) — require it to also be a regular file. *)
let is_executable path =
  match (Unix.stat path).st_kind with
  | Unix.S_REG -> ( match Unix.access path [Unix.X_OK] with () -> true | exception Unix.Unix_error _ -> false)
  | _ -> false
  | exception Unix.Unix_error _ -> false
  | exception Sys_error _ -> false

(* Mirrors every producer wrapper script's own convention in this repo (e.g.
   arch-callgraph-go: "$HERE/bin/arch-callgraph-go") of finding its sibling
   compiled artifact by walking upward from wherever it itself was launched.
   Re-derived here rather than shared with tezt/lib/arch_tezt.ml's identical
   [find_upwards]/[locate] pair: that module depends on Tezt (Test.fail), and
   this is production code — "not found" is a legitimate, expected outcome
   here ([Not_analysed]), not a hard failure. [~exists] is a parameter (not
   hardcoded to [is_executable]) because not every marker this module looks
   for is executable — [architecture-schema.sql] (used by [find_repo_root]
   below) is a plain file, and checking [is_executable] against it would
   never match, walking all the way to filesystem root and reporting
   "no repo root found" even when one genuinely exists two directories up. *)
let rec find_upwards ~exists ~from rel =
  let candidates =
    [Filename.concat from rel; Filename.concat from (Filename.concat "_build/default" rel)]
  in
  match List.find_opt exists candidates with
  | Some _ as found -> found
  | None ->
      let parent = Filename.dirname from in
      if parent = from then None else find_upwards ~exists ~from:parent rel

let find_sibling_tool ~from_dir rel =
  match find_upwards ~exists:is_executable ~from:from_dir rel with
  | Some _ as found -> found
  | None -> find_upwards ~exists:is_executable ~from:(Sys.getcwd ()) rel

(* FIX (review, CRITICAL): an earlier draft computed [repo_root] in
   [bin/arch_coverage_matrix/arch_coverage_matrix.ml] as a single
   [Filename.dirname Sys.executable_name] hop — under a normal dune/tezt
   build, [Sys.executable_name] resolves to the FULLY-RESOLVED path
   [.../_build/default/bin/arch_coverage_matrix/arch_coverage_matrix.exe],
   so one [dirname] hop landed inside [_build/default/bin/...], never the
   actual repository root three levels further up. [go_callgraph_row]/
   [rust_callgraph_row] below did a single direct path check against that
   wrong root with no upward search of their own, so they silently reported
   [Not_analysed] in EVERY real invocation of the compiled binary regardless
   of whether the Go/Rust drivers were actually built — invisible to a test
   suite whose only Go/Rust fixture happened to test the driver-NOT-built
   case, which looks identical. [find_repo_root] walks upward (the same
   convention as everything else in this module) for
   [architecture-schema.sql] — a file that exists at this repo's root and
   nowhere else relevant, already used as exactly this kind of anchor
   elsewhere (tezt/lib/arch_tezt.ml's own [schema ()] locator) — so the
   caller no longer has to compute [repo_root] by hand at all. *)
(* A plain, single-candidate upward search — NOT [find_upwards], whose
   [_build/default/rel] second candidate exists for finding COMPILED
   artifacts a shorter source path maps to. [architecture-schema.sql] is a
   SOURCE file dune also mirrors into [_build/default/] (it is a
   [preprocessor_deps] dependency of [lib/arch_index/dune]), so the dual
   candidate check found and returned that copy — one directory short of
   the true repo root — long before reaching the genuine source file, a
   false-positive caught only by this search actually being run against a
   real build tree, not by reasoning about the code alone. *)
(* FIX (second pass, same review round): the first fix still returned
   [_build/default] itself, one directory short of the true root — dune
   mirrors EVERY source file it depends on into [_build/default/] as part
   of its own build sandbox (verified: [_build/default/architecture-schema.sql]
   is a real, separate file dune creates, not a symlink), so a plain
   "does architecture-schema.sql exist here" walk starting from inside
   [_build/default/bin/...] hits dune's OWN COPY of the marker before ever
   reaching the source tree's copy one level further up. A directory
   containing a [_build] subdirectory alongside the marker is unambiguously
   the source root — [_build/default] itself has no [_build] subdirectory of
   its own (dune does not recursively stage its own build output), so
   requiring both conditions together cannot match the mirror. *)
let rec find_repo_root_from ~from =
  let marker = Filename.concat from "architecture-schema.sql" in
  let build_dir = Filename.concat from "_build" in
  if Sys.file_exists marker && Sys.file_exists build_dir && Sys.is_directory build_dir then Some from
  else
    let parent = Filename.dirname from in
    if parent = from then None else find_repo_root_from ~from:parent

let find_repo_root ~from_dir =
  match find_repo_root_from ~from:from_dir with
  | Some _ as found -> found
  | None -> find_repo_root_from ~from:(Sys.getcwd ())

(* FIX (review, CRITICAL): a dangling symlink or a symlink cycle under
   [_build/default] (which dune builds are dense with) crashed this whole
   binary with an uncaught [Sys_error] — [Sys.is_directory] raises on a
   broken link, and the walk had no depth bound to stop a cycle. [Unix.lstat]
   (which does NOT follow the final symlink, unlike [Sys.is_directory]) lets
   a symlink be skipped outright rather than followed into either failure
   mode; [max_depth] bounds the cost of the walk on an Octez-scale tree the
   same way, independent of whether a cycle exists. *)
let has_cmt_files dir =
  let max_depth = 12 in
  let rec walk d depth =
    if depth > max_depth then false
    else
      match Sys.readdir d with
      | exception Sys_error _ -> false
      | entries ->
          Array.exists
            (fun e ->
              let p = Filename.concat d e in
              match Unix.lstat p with
              | exception Unix.Unix_error _ -> false
              | {st_kind = Unix.S_LNK; _} -> false
              | {st_kind = Unix.S_DIR; _} -> walk p (depth + 1)
              | _ -> Filename.check_suffix p ".cmt" || Filename.check_suffix p ".cmti")
            entries
  in
  walk dir 0

let ocaml_callgraph_row ~project_dir =
  let build_dir = Filename.concat project_dir "_build/default" in
  if not (Sys.file_exists build_dir && Sys.is_directory build_dir) then
    {
      language = Some "ocaml";
      analysis = "callgraph";
      status = Not_analysed;
      detail = Some "project not built — run `dune build` first (the CMT-based OCaml producer reads .cmt/.cmti files under _build/default)";
    }
  else if has_cmt_files build_dir then
    {language = Some "ocaml"; analysis = "callgraph"; status = Covered; detail = None}
  else
    {
      language = Some "ocaml";
      analysis = "callgraph";
      status = Partial;
      detail = Some "_build/default exists but contains no .cmt/.cmti files";
    }

let ocaml_effects_row ~repo_root =
  match find_sibling_tool ~from_dir:repo_root "bin/arch_effects_ocaml/arch_effects_ocaml.exe" with
  | Some _ -> {language = Some "ocaml"; analysis = "effects"; status = Covered; detail = None}
  | None ->
      {
        language = Some "ocaml";
        analysis = "effects";
        status = Not_analysed;
        detail = Some "arch_effects_ocaml not built — run `dune build bin/arch_effects_ocaml`";
      }

(* Go's effects producer (callgraph-go/effects/main.go, built as
   arch-effects-go by tezt/lib/arch_tezt.ml's own [build_go] helper) exists
   only as test-harness infrastructure — there is no shipped, installed
   binary a normal checkout produces, unlike arch-callgraph-go which at least
   has a repo-root wrapper script. Reporting [Covered] here would be a lie:
   nothing outside the test suite can actually run it. *)
let go_effects_row =
  {
    language = Some "go";
    analysis = "effects";
    status = Not_analysed;
    detail = Some "Go effects producer exists only as test-harness infrastructure today, not a shipped/installed binary";
  }

(* Go/Rust callgraph producers are tools THIS arch-index installation ships
   (repo-root wrapper scripts), not something the TARGET project provides —
   availability is a property of [repo_root], never [project_dir]. The
   WRAPPER script itself (e.g. `arch-callgraph-go`) is checked into git and
   is therefore always present regardless of whether the DRIVER it gates is
   built — checking the wrapper's own existence would report `Covered` on
   every checkout, including one where the wrapper's first line is `exit 2`.
   These functions instead check the exact driver path(s) each wrapper
   itself probes internally, so "covered" here means the same thing running
   the real producer would. *)
let go_callgraph_row ~repo_root =
  match is_executable (Filename.concat repo_root "bin/arch-callgraph-go") with
  | true -> {language = Some "go"; analysis = "callgraph"; status = Covered; detail = None}
  | false ->
      {
        language = Some "go";
        analysis = "callgraph";
        status = Not_analysed;
        detail = Some "arch-callgraph-go not built — run: cd arch-index && ./build.sh go";
      }

(* FIX (review, HIGH): the wrapper script has a SECOND hard gate beyond the
   driver itself — unless ARCH_CG_RUST_NO_MERGE=1, it also requires the merge
   pass (bin/arch_callgraph_rust_merge) to be built, and exits 2 if it is not
   (see arch-callgraph-rust's own script, "merge pass not built" branch). A
   checkout with the cargo driver built but the merge pass not built would
   otherwise be reported [Covered] while the real wrapper actually exits 2 —
   checking only the first of two gates is the same class of lie as checking
   the wrapper's own existence instead of the driver. *)
let rust_callgraph_row ~repo_root =
  let cargo_target_dir = Sys.getenv_opt "CARGO_TARGET_DIR" in
  let driver_candidates =
    List.filter_map
      (fun x -> x)
      [
        Some (Filename.concat repo_root "callgraph-rust/target/release/arch-callgraph-rust");
        Some (Filename.concat repo_root "callgraph-rust/target/debug/arch-callgraph-rust");
        Option.map (fun d -> Filename.concat d "release/arch-callgraph-rust") cargo_target_dir;
        Option.map (fun d -> Filename.concat d "debug/arch-callgraph-rust") cargo_target_dir;
      ]
  in
  let merge_pass =
    Filename.concat repo_root "_build/default/bin/arch_callgraph_rust_merge/arch_callgraph_rust_merge.exe"
  in
  let driver_built = List.exists is_executable driver_candidates in
  let merge_built = is_executable merge_pass in
  if driver_built && merge_built then
    {language = Some "rust"; analysis = "callgraph"; status = Covered; detail = None}
  else if driver_built && not merge_built then
    {
      language = Some "rust";
      analysis = "callgraph";
      status = Not_analysed;
      detail = Some "arch_callgraph_rust_merge not built — run: dune build bin/arch_callgraph_rust_merge";
    }
  else
    {
      language = Some "rust";
      analysis = "callgraph";
      status = Not_analysed;
      detail = Some "arch-callgraph-rust driver not built — run: cd callgraph-rust && cargo build --release";
    }

let lsp_row ~registry ~language ~project_dir =
  match Language_registry.lookup registry ~language ~project_dir with
  | Ok _ -> {language = Some language; analysis = "callgraph"; status = Covered; detail = None}
  | Error msg ->
      let install =
        match Language_registry.lsp_install_instruction ~language with
        | Some cmd -> Printf.sprintf "%s — install with: %s" msg cmd
        | None -> msg
      in
      {language = Some language; analysis = "callgraph"; status = Not_analysed; detail = Some install}

(* [cfg]/[types] are not independently invoked producers — they are facts
   the callgraph producer for a language already emits as part of its own
   output (post-dominance/CFG; the [types] table). Their coverage mirrors
   whatever the callgraph row for that same language found, rather than
   being probed a second time. *)
let derived_rows ~from:callgraph_row analysis =
  {
    callgraph_row with
    analysis;
    detail =
      (match callgraph_row.detail with
      | Some d -> Some (Printf.sprintf "derived from the %s callgraph producer: %s" (Option.value callgraph_row.language ~default:"?") d)
      | None -> Some (Printf.sprintf "derived from the %s callgraph producer" (Option.value callgraph_row.language ~default:"?")));
  }

let coverage_row ~repo_root ~lcov =
  let not_analysed detail =
    {language = None; analysis = "coverage"; status = Not_analysed; detail = Some detail}
  in
  match lcov with
  | None -> not_analysed "requires an externally-supplied LCOV tracefile — not auto-discoverable"
  | Some path when not (Sys.file_exists path) ->
      not_analysed (Printf.sprintf "--lcov %s does not exist" path)
  | Some _ -> (
      match find_sibling_tool ~from_dir:repo_root "bin/arch_coverage/arch_coverage.exe" with
      | Some _ -> {language = None; analysis = "coverage"; status = Covered; detail = None}
      | None -> not_analysed "arch_coverage not built — run `dune build bin/arch_coverage`")

let decisions_row =
  {
    language = None;
    analysis = "decisions";
    status = Not_analysed;
    detail = Some "poc/decision-lint is a proof-of-concept, not yet integrated into the main dune build";
  }

(* Roadmap 3.4-bis. Whether the error-channel analysis ran is a fact about a
   PRODUCER, so the row is per-language like [callgraph], not a single global
   row: "OCaml analysed three channels" and "the Go producer cannot analyse
   any" are different answers and must not be flattened into one.

   Two sources, in order of strength. [comment_db_meta.error_contract] is
   EVIDENCE — what a producer actually emitted into this database, spelled
   "v1:exception,result,option". The build probe is only CAPABILITY — what a
   producer could emit if run. Prefer evidence; fall back to capability when
   the target database carries no contract (it may be a fresh file this run is
   about to create).

   The [error_channels] row never reports [Partial]. An earlier version of this
   comment claimed the opposite — that a database carrying only [exception] is
   not one carrying all three, so collapsing them into [Covered] would overstate
   the analysis. That reasoning was inverted by review and the code follows the
   correction (see [error_channels_row]): a corpus that uses neither [result]
   nor [option] legitimately produces a SHORTER contract, so fewer channels
   means less to analyse, not less analysis, and calling it a gap made the
   ratchet fire on correctly analysed projects. WHICH channels ran stays visible
   in the row's detail, which is where that distinction belongs. This list is
   therefore the vocabulary the detail is rendered from, not a completeness
   target. *)
let builtin_channels = ["exception"; "result"; "option"]

(* The producers that can emit error-channel rows at all. ONE list, consulted
   by every site that needs the answer, so the two cannot drift apart — a
   review found the language literal spelled separately in two places, where
   the day a second producer gains the capability nothing would have fired.
   Adding a language here is the whole change; the test "capability is read
   from the list, not hard-coded" below fails if a call site stops consulting
   it. *)
let error_channel_producers = ["ocaml"]

(* The analysis name, spelled ONCE. It was spelled literally at three sites —
   the row constructor, the capability fallback, and [fixable_by_this_run]'s
   exemption — and the exemption is the one that decides the exit code. If any
   one spelling drifted, the exemption would silently stop matching and the
   gate would go back to firing unconditionally on every polyglot repository,
   with nothing to catch it: both [has_gap] tests build the literal themselves,
   so they would agree with the drift rather than detect it. Same remedy as
   [error_channel_producers] above, for the same reason. *)
let error_channels_analysis = "error_channels"

let emits_error_channels = function
  | Some lang -> List.mem lang error_channel_producers
  | None -> false

(* What the target database tells us about the error-channel analysis.

   Three cases, because two would conflate the situation the fallback exists
   for with the one it must not cover. [No_database] is a file that was never
   indexed — the matrix may then answer from CAPABILITY, since this run is
   about to create it. [Indexed_without_contract] is a database that HAS been
   indexed and still carries no contract: an older producer, or a run that did
   not reach the point where the contract is written. Answering from capability
   there would report an analysis that demonstrably did not happen. *)
type contract_evidence =
  | No_database
  | Indexed_without_contract
  | Contract of string

(* Reads the contract from a target database if there is one to read. Any
   failure — no file, no table, no key, an unreadable value — is [None], i.e.
   "no evidence", never an exception: the matrix must still produce a verdict
   for a database that does not exist yet. *)
let read_error_contract ~db_path =
  let scalar db sql =
    let out = ref None in
    (try
       let stmt = Sqlite3.prepare db sql in
       Fun.protect
         ~finally:(fun () -> ignore (Sqlite3.finalize stmt))
         (fun () ->
           match Sqlite3.step stmt with
           | Sqlite3.Rc.ROW -> (
               match Sqlite3.column stmt 0 with
               | Sqlite3.Data.TEXT v -> out := Some v
               | Sqlite3.Data.INT i -> out := Some (Int64.to_string i)
               | _ -> ())
           | _ -> ())
     with _ -> ()) ;
    !out
  in
  match db_path with
  | None -> No_database
  | Some path when not (Sys.file_exists path) -> No_database
  | Some path -> (
      match Sqlite3.db_open ~mode:`READONLY path with
      | exception _ -> No_database
      | db ->
          let contract = scalar db "SELECT value FROM comment_db_meta WHERE key = 'error_contract'" in
          let indexed =
            match scalar db "SELECT count(*) FROM functions" with
            | Some n -> (try int_of_string n > 0 with _ -> false)
            | None -> false
          in
          ignore (Sqlite3.db_close db) ;
          match (contract, indexed) with
          | Some c, _ -> Contract c
          | None, true -> Indexed_without_contract
          | None, false -> No_database)

(* "v1:exception,result,option" -> ["exception"; "result"; "option"] *)
(* "v1:exception,result,option" -> Some ["exception"; "result"; "option"].
   [None] means the string is not a contract this version understands — an
   unknown version, or no version prefix at all. A review found both parsed as
   v1 and an unversioned string reported as "lists no channel" while listing
   three; guessing at an unrecognised format is exactly the silent
   misinterpretation this table exists to avoid. *)
let channels_of_contract contract =
  match String.index_opt contract ':' with
  | None -> None
  | Some i ->
      let version = String.sub contract 0 i in
      if version <> "v1" then None
      else
        Some
          (String.sub contract (i + 1) (String.length contract - i - 1)
          |> String.split_on_char ','
          |> List.filter_map (fun s ->
                 let s = String.trim s in
                 if s = "" then None else Some s))

(* Detail text goes to stdout as one matrix row, so a value read out of a
   database must not be able to break that line or flood it. Contract values
   come from a file on disk, not from a trusted caller. *)
let sanitise_detail s =
  let s = String.map (function '\n' | '\r' | '\t' -> ' ' | c -> c) s in
  if String.length s <= 120 then s else String.sub s 0 117 ^ "..."

let error_channels_row ?(producers = error_channel_producers) ~contract ~from:callgraph_row () =
  let language = callgraph_row.language in
  let capable = match language with Some l -> List.mem l producers | None -> false in
  let row status detail = {language; analysis = error_channels_analysis; status; detail} in
  (* The contract describes ONE producer's output, and only a capable producer
     writes it, so it informs that producer's row and no other. Caught by
     running it: applying an OCaml-written contract to every detected language
     reported `rust error_channels: covered` on a database no Rust producer had
     ever touched. *)
  match (if capable then contract else No_database) with
  | Contract c -> (
      match channels_of_contract c with
      | None ->
          row Not_analysed
            (Some (Printf.sprintf "unrecognised error_contract format, not read: %S" (sanitise_detail c)))
      | Some [] ->
          row Not_analysed
            (Some (Printf.sprintf "error_contract lists no channel: %S" (sanitise_detail c)))
      | Some chans ->
          (* COVERED, not partial-when-shorter. specs/error-channels.md is
             explicit that a built-in channel whose carrier type does not occur
             in the corpus is deliberately OMITTED — "the honest outcome". So a
             library using neither `result` nor `option` legitimately produces
             `v1:exception`, and calling that a gap made the ratchet fire on a
             correctly analysed project with nothing the user could do about it.
             Fewer channels does not mean less analysis: the status answers "did
             it run", the detail says on what. *)
          let missing = List.filter (fun b -> not (List.mem b chans)) builtin_channels in
          (* Only a built-in absent from a contract that DOES carry the frozen
             [exception] channel is evidence of "no such carrier here"; a
             contract missing [exception] is not something a capable producer
             emits, so do not narrate it as a corpus fact. *)
          let well_formed = List.mem "exception" chans in
          row Covered
            (Some
               (sanitise_detail
                  (match (missing, well_formed) with
                  | [], _ -> String.concat "," chans
                  | _, true ->
                      Printf.sprintf
                        "%s (no %s carrier in this corpus)"
                        (String.concat "," chans)
                        (String.concat "/" missing)
                  | _, false -> String.concat "," chans))))
  | Indexed_without_contract ->
      (* FIX (review round 2, HIGH): this used to fall through to the
         capability probe, which reports what a producer COULD emit. On an
         already-indexed database with no contract that is a claim about an
         analysis which demonstrably did not record itself. *)
      row Not_analysed
        (Some
           "this database was indexed, but carries no error_contract — an older producer, or a \
            run that did not complete; re-index to record one")
  | No_database when capable ->
      (* Nothing indexed yet: the matrix legitimately answers from capability,
         since this run is about to create the database. *)
      derived_rows ~from:callgraph_row error_channels_analysis
  | No_database ->
      row Not_analysed
        (Some
           "no producer for this language emits error-channel rows yet — the NDJSON record types \
            do not exist (see docs/error-channels-porting.md); a Flat-schema database answers \
            NOT_ANALYSED, which is the correct answer, not a bug to work around")

let compute ~project_dir ~repo_root ?lcov ?db_path () =
  let registry = Language_registry.default () in
  let languages = Language_registry.detect_language_roots ~project_dir in
  let callgraph_rows =
    List.map
      (fun (language, root) ->
        match language with
        | "ocaml" -> ocaml_callgraph_row ~project_dir:root
        | "go" -> go_callgraph_row ~repo_root
        | "rust" -> rust_callgraph_row ~repo_root
        | other -> lsp_row ~registry ~language:other ~project_dir:root)
      languages
  in
  (* FIX (review, HIGH): a prior draft used [List.filter_map] to emit NO row
     at all for a language with no effects producer — silence for exactly
     the languages/analyses this table exists to stop being silent about.
     Every detected language now gets an [effects] row, [Not_analysed] with
     an honest reason when no producer covers it — matching this function's
     own documented contract in the .mli. *)
  let effects_rows =
    List.map
      (fun (language, _root) ->
        match language with
        | "ocaml" -> ocaml_effects_row ~repo_root
        | "go" -> go_effects_row
        | other ->
            {
              language = Some other;
              analysis = "effects";
              status = Not_analysed;
              detail = Some (Printf.sprintf "no effects producer ships for %s" other);
            })
      languages
  in
  let cfg_rows = List.map (fun r -> derived_rows ~from:r "cfg") callgraph_rows in
  let types_rows = List.map (fun r -> derived_rows ~from:r "types") callgraph_rows in
  (* Read once, not per language: the contract describes the database, and one
     database is written by one producer run. *)
  let contract = read_error_contract ~db_path in
  let error_channels_rows =
    List.map (fun r -> error_channels_row ~contract ~from:r ()) callgraph_rows
  in
  List.concat
    [
      callgraph_rows; effects_rows; cfg_rows; types_rows; error_channels_rows;
      [coverage_row ~repo_root ~lcov; decisions_row];
    ]

(* FIX (review, MEDIUM): every bind result was [ignore]d, and the whole
   DELETE-then-INSERT sequence ran outside a transaction — a mid-run
   [failwith] left the table with the OLD snapshot destroyed and the new one
   partial, worse than either the before or after state, and [Sqlite3.reset]
   without [clear_bindings] between rows meant a failed bind on one column
   could silently retain the PREVIOUS row's value for it rather than NULL.
   [BEGIN IMMEDIATE]/[COMMIT] makes the replace atomic; [ROLLBACK] on any
   failure restores the prior snapshot instead of leaving a half-written
   one; every bind is checked; [clear_bindings] runs before each row. *)
let write_coverage db rows =
  let exec_exn sql =
    match Sqlite3.exec db sql with
    | Sqlite3.Rc.OK -> ()
    | rc -> failwith (Printf.sprintf "SQLite error %s for: %s" (Sqlite3.Rc.to_string rc) sql)
  in
  let bind_exn stmt idx data =
    match Sqlite3.bind stmt idx data with
    | Sqlite3.Rc.OK -> ()
    | rc -> failwith (Printf.sprintf "SQLite bind error %s at column %d" (Sqlite3.Rc.to_string rc) idx)
  in
  exec_exn "BEGIN IMMEDIATE" ;
  match
    exec_exn "DELETE FROM analysis_coverage" ;
    let stmt =
      Sqlite3.prepare db "INSERT INTO analysis_coverage (language, analysis, status, detail) VALUES (?, ?, ?, ?)"
    in
    List.iter
      (fun row ->
        ignore (Sqlite3.clear_bindings stmt) ;
        bind_exn
          stmt
          1
          (match row.language with Some l -> Sqlite3.Data.TEXT l | None -> Sqlite3.Data.NULL) ;
        bind_exn stmt 2 (Sqlite3.Data.TEXT row.analysis) ;
        bind_exn stmt 3 (Sqlite3.Data.TEXT (status_to_string row.status)) ;
        bind_exn
          stmt
          4
          (match row.detail with Some d -> Sqlite3.Data.TEXT d | None -> Sqlite3.Data.NULL) ;
        (match Sqlite3.step stmt with
        | Sqlite3.Rc.DONE -> ()
        | rc -> failwith (Printf.sprintf "SQLite error inserting analysis_coverage row: %s" (Sqlite3.Rc.to_string rc))) ;
        ignore (Sqlite3.reset stmt))
      rows ;
    ignore (Sqlite3.finalize stmt)
  with
  | () -> exec_exn "COMMIT"
  | exception exn ->
      (try exec_exn "ROLLBACK" with _ -> ()) ;
      raise exn

(* FIX (review, MEDIUM): [decisions] is unconditionally [Not_analysed] (a
   proof-of-concept outside the main dune build — nothing a run of THIS tool
   can fix) and [coverage] without [--lcov] is [Not_analysed] by construction
   (an external tracefile was never supplied, not withheld by a broken
   producer). Counting either toward the gap made every invocation without
   --allow-partial exit 1 unconditionally — a gate that always fires carries
   no signal. Only the four language-scoped, per-run-invocable analyses
   (callgraph/effects/cfg/types) can meaningfully gap or not gap from one run
   to the next, so only rows with [language <> None] count. [Partial] now
   counts too (review, MEDIUM): _build/default present but empty is the
   OCaml producer about to silently index nothing — exactly issue #23, not a
   pass. *)
(* The rule the comment above states, written down once instead of inferred
   from [language <> None] at each call site.

   [error_channels] forced the issue. It is genuinely per-language — whether
   error channels were analysed is a fact about a producer — so it carries a
   [language], which under the old predicate would have counted toward the
   gap. But NO non-OCaml producer can emit error-channel rows yet (the NDJSON
   record types do not exist), so such a row is [Not_analysed] permanently, and
   counting it would make this tool exit 1 on every polyglot repository until
   that feature ships: exactly the always-firing gate the comment above rejects
   for [decisions] and [coverage]. The row is still EMITTED — silence is the
   failure this table exists to prevent — it simply does not pretend the run
   could have fixed it. *)
let fixable_by_this_run r =
  r.language <> None
  && not (r.analysis = error_channels_analysis && not (emits_error_channels r.language))

let has_gap rows =
  List.exists
    (fun r ->
      fixable_by_this_run r
      && match r.status with Not_analysed | Failed | Partial -> true | Covered -> false)
    rows

(* ---- error-channel rows: the rules worth pinning ----------------------- *)

let%test "channels_of_contract: parses the v1 spelling" =
  channels_of_contract "v1:exception,result,option" = Some ["exception"; "result"; "option"]

let%test "channels_of_contract: a v1 contract with no channels is an empty list" =
  channels_of_contract "v1:" = Some []

let%test "channels_of_contract: an UNKNOWN version is not guessed at" =
  channels_of_contract "v2:exception,result" = None && channels_of_contract "v10:x" = None

let%test "channels_of_contract: no version prefix is not a contract" =
  channels_of_contract "exception,result" = None && channels_of_contract ":x" = None

let cg lang = {language = Some lang; analysis = "callgraph"; status = Covered; detail = None}

let%test "a complete contract is covered, detail listing the channels" =
  match error_channels_row ~contract:(Contract "v1:exception,result,option") ~from:(cg "ocaml") () with
  | {status = Covered; detail = Some d; _} -> d = "exception,result,option"
  | _ -> false

let%test "a SHORTER contract is still covered, and says why it is shorter" =
  match error_channels_row ~contract:(Contract "v1:exception") ~from:(cg "ocaml") () with
  | {status = Covered; detail = Some d; _} ->
      d = "exception (no result/option carrier in this corpus)"
  | _ -> false

let%test "a shorter contract does NOT fire the ratchet" =
  let rows = [cg "ocaml"; error_channels_row ~contract:(Contract "v1:exception") ~from:(cg "ocaml") ()] in
  has_gap rows = false

let%test "a contract without the frozen exception channel narrates no corpus fact" =
  (* `v1:bogus` is not something a capable producer emits; reporting "no
     exception carrier in this corpus" would state an impossibility as fact. *)
  match error_channels_row ~contract:(Contract "v1:bogus") ~from:(cg "ocaml") () with
  | {status = Covered; detail = Some d; _} -> d = "bogus"
  | _ -> false

let%test "an unrecognised contract format is not_analysed, never guessed" =
  match error_channels_row ~contract:(Contract "v2:exception") ~from:(cg "ocaml") () with
  | {status = Not_analysed; _} -> true
  | _ -> false

let%test "a detail read from a database cannot break or flood the output line" =
  match
    error_channels_row ~contract:(Contract ("v9:" ^ String.make 4000 'x' ^ "\nrogue")) ~from:(cg "ocaml") ()
  with
  | {status = Not_analysed; detail = Some d; _} ->
      (* The 4000-char value must not reach stdout; the exact bound allows for
         the message prefix and %S's quoting on top of the 120-char truncation. *)
      String.length d <= 200 && not (String.contains d '\n')
  | _ -> false

let%test "an INDEXED database with no contract is not_analysed, not capability" =
  (* The inverse risk of making a shorter contract Covered: a producer that
     died before recording the contract must not be reported from what it
     COULD have done. *)
  match error_channels_row ~contract:Indexed_without_contract ~from:(cg "ocaml") () with
  | {status = Not_analysed; detail = Some d; _} ->
      d <> "" && has_gap [cg "ocaml"; error_channels_row ~contract:Indexed_without_contract ~from:(cg "ocaml") ()]
  | _ -> false

let%test "the contract never speaks for a producer that did not write it" =
  match error_channels_row ~contract:(Contract "v1:exception,result,option") ~from:(cg "rust") () with
  | {status = Not_analysed; _} -> true
  | _ -> false

let%test "an un-indexed database ⇒ a capable producer falls back to the probe" =
  match error_channels_row ~contract:No_database ~from:(cg "ocaml") () with
  | {status = Covered; _} -> true
  | _ -> false

let%test "a non-capable producer's error_channels gap does NOT fire the ratchet" =
  has_gap
    [cg "ocaml"; {language = Some "go"; analysis = "error_channels"; status = Not_analysed; detail = None}]
  = false

let%test "a capable producer's error_channels gap DOES fire the ratchet" =
  has_gap
    [cg "ocaml"; {language = Some "ocaml"; analysis = "error_channels"; status = Not_analysed; detail = None}]
  = true

(* PINNED RESIDUAL, deliberate — not a passing test looking for a bug.

   A database file that was CREATED but never indexed reports
   [error_channels: covered], with [functions = 0], and keeps reporting it
   indefinitely. That is a green for a reason other than the one the word
   "covered" suggests, which is the exact shape this table exists to prevent;
   it is recorded as an executable assertion rather than a comment, because a
   comment does not stop the next reader from taking the green as evidence —
   they will read the row, not the note.

   Why it is not simply fixed here: [cfg] and [types] answer from capability
   for the same reason and neither has any evidence available to answer from,
   so for them the fallback IS the best available answer. Tightening
   [No_database] would change all three, which is a semantic change and not
   this change's business.

   The asymmetry is the reason to revisit it: [error_channels] is the only one
   of the three with real evidence obtainable (the contract key), so for it the
   fallback is a substitute where an answer exists. The day someone tightens
   [No_database], THIS test fails and makes them decide knowingly, instead of
   believing they are fixing a bug. That is the whole point of pinning it. *)
let%test "a never-indexed database reports covered from capability alone — pinned, not endorsed" =
  match error_channels_row ~contract:No_database ~from:(cg "ocaml") () with
  | {status = Covered; language = Some "ocaml"; _} -> true
  | _ -> false

let%test "capability is read from the list, not hard-coded" =
  (* A REAL detector now, not the documentation anchor this used to be: the
     producer set is injected, so a hard-coded language comparison ignores it
     and fails here. Reviewer's suggestion — worth the five lines. *)
  (match error_channels_row ~producers:["go"] ~contract:No_database ~from:(cg "go") () with
   | {status = Covered; _} -> true
   | _ -> false)
  && (match error_channels_row ~producers:["go"] ~contract:(Contract "v1:exception") ~from:(cg "ocaml") () with
     | {status = Not_analysed; _} -> true
     | _ -> false)
