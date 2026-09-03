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

let compute ~project_dir ~repo_root ?lcov () =
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
  List.concat
    [
      callgraph_rows; effects_rows; cfg_rows; types_rows;
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
let has_gap rows =
  List.exists
    (fun r ->
      r.language <> None
      && match r.status with Not_analysed | Failed | Partial -> true | Covered -> false)
    rows
