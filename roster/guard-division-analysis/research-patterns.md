# Pattern research: Q1 and Q5

## Scope correction

The initial inspection was performed in `/home/mathias/dev/arch-index`, not in
the assigned worktree. This report was re-verified in
`/home/mathias/dev/arch-index-worktrees/guard-division-analysis`; all
file:line citations below refer to that worktree.

## Q1 — OCaml CLI components and test organization

- CLI binaries are directory-local Dune executables. For example,
  `bin/arch_callgraph_ocaml/dune:1-4` contains:

  ```lisp
  (executable
   (name arch_callgraph_ocaml)
   (public_name arch_callgraph_ocaml)
   (libraries arch_index eio_posix cmdliner))
  ```

- `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml:3-18` delegates to the
  library and prints its stored-row counters:

  ```ocaml
  let result =
    Arch_index.run ?db_path ?schema_path ?errors_config ?errors_profile
      ~errors_strict ~build_dir ()
  in
  Printf.printf "Indexed: %d modules, %d functions, %d types, %d calls\\n%!" ...
  ```

  `bin/arch_callgraph_ocaml/arch_callgraph_ocaml.ml:19-47` exits `1` when
  `n_statement_failures > 0`, after emitting table-level rejected-row details.

- `lib/arch_index/dune:1-25` defines public library `arch_index`, depends on
  `compiler-libs.common`, and lists `arch_index_cmt` among private modules:

  ```lisp
  (library
   (name arch_index)
   (public_name arch-index)
   (libraries ... compiler-libs.common sqlite3 ...)
   (private_modules arch_index_db arch_index_cmt ...))
  ```

- `lib/arch_index/arch_index_cmt.ml:8-11` describes processing `.cmt/.cmti`
  to extract modules, functions, types, calls, and dependencies. Its
  `iter_structure_items` takes `Typedtree.structure` and recursively handles
  `Tstr_module`, `Tstr_recmodule`, and `Tstr_include`
  (`lib/arch_index/arch_index_cmt.ml:178-198`):

  ```ocaml
  let iter_structure_items ~f (structure : Typedtree.structure) =
    ...
    match it.str_desc with
    | Tstr_module mb -> binding ~prefix mb
    | Tstr_recmodule mbs -> List.iter (binding ~prefix) mbs
    | Tstr_include incl -> module_expr ~prefix incl.incl_mod
  ```

- The `poc/decision-lint` executable is separate from the primary `bin/`
  tree. `poc/decision-lint/bin/dune:1-3` defines it with compiler-libs, Unix,
  and SQLite; `poc/decision-lint/test/dune:1-5` defines a `fixture_lib` whose
  `fixture` module is built with warnings disabled. The source calls itself a
  Parsetree frontend and says it emits NDJSON on stdout
  (`poc/decision-lint/bin/decision_lint.ml:16-22`).

- Tezt test support builds listed CLI paths through a generated rule.
  `tezt/lib/dune:71-92` lists, among others,
  `arch_callgraph_ocaml.exe`, `arch_rules.exe`,
  `arch_coverage_matrix.exe`, and `decision_lint.exe` as dependencies.

## Q5 — diagnostics, provenance, coverage, verdicts, allowances, and references

- Rule results have a fixed record shape carrying `rule`, `kind`, `verdict`,
  detail/detail total, note, sizes, exactness, witness, top reasons, and origin
  contexts (`lib/arch_tools/arch_rule_eval.ml:522-551`):

  ```ocaml
  type result = {
    rule : string; kind : string; verdict : string;
    detail : string list; detail_total : int; note : string option;
    sizes : (int * int) option; exact : bool; witness : string list;
    top_reasons : string list; origin_contexts : Yojson.Safe.t list;
    context_total : int; context_omitted : int;
  }
  ```

- Origin allowances have a `(string * int)` entry list and a common identity
  renderer (`lib/arch_tools/arch_rule_eval.ml:117-123`). Allow-file parsing is
  performed before evaluation (`lib/arch_tools/arch_rule_eval.ml:125-129`), and
  duplicate identities are rejected (`lib/arch_tools/arch_rule_eval.ml:199-217`).

- Origin sites are sorted, then output as `[new]` or `[was ×N]` based on their
  allowance (`lib/arch_tools/arch_rule_eval.ml:1016-1032`):

  ```ocaml
  let sites = Hashtbl.fold (fun k n acc -> (k, n) :: acc) tbl [] |> List.sort compare in
  ...
  | None -> Some (id, Printf.sprintf "[new]          %s | ×%d" id n)
  | Some k ->
      if n > k then
        Some (id, Printf.sprintf "[was ×%d]       %s | ×%d" k id n)
  ```

- Each origin-rule outcome constructs a coverage message including cone nodes,
  origin count, sites, allow-file entries, and entries matching nothing
  (`lib/arch_tools/arch_rule_eval.ml:1046-1053`).

- The origin-rule tests assert both count-bounded allowances and coverage
  wording: `×1` does not cover two origins
  (`tezt/tests/rules_origin.ml:263-274`), while output contains `coverage:`,
  cone-size wording, and `matching nothing`
  (`tezt/tests/rules_origin.ml:645-669`).

- Main-schema provenance uses `producer_runs` and `producer_run_id`. The test
  seed inserts producer/version/invocation digest/soundness
  (`tezt/tests/provenance.ml:24-39`), and a real-CMT test checks joins yielding
  producer `arch_index_cmt` and soundness `sound_with_top`
  (`tezt/tests/provenance.ml:58-91`).

- Coverage-matrix records use the following status and row shapes
  (`lib/arch_index/coverage_matrix.ml:8-16`):

  ```ocaml
  type status = Covered | Not_analysed | Failed | Partial
  type row = {language : string option; analysis : string; status : status; detail : string option}
  ```

  Its CLI exits `1` for gaps unless `--allow-partial` is supplied
  (`bin/arch_coverage_matrix/arch_coverage_matrix.ml:70-74`).

- `scripts/origin-consumer.js` independently validates a reference object’s
  version, modules, totals, groups, and summed origins (`scripts/origin-consumer.js:63-80`).
  It compares reference/current totals, origin-group counts, indexed modules,
  and source modules (`scripts/origin-consumer.js:89-107`):

  ```js
  for (const key of ['modules', 'functions', 'calls', 'origins']) {
    const delta = current.totals[key] - reference.totals[key];
    if (delta !== 0) deltas.push({metric: key, reference: reference.totals[key], current: current.totals[key], delta});
  }
  ...
  if (missing.length || extra.length) deltas.push({metric: 'module_population', missing, extra});
  ```

- The consumer stores the coverage comparison under `run.coverage`, validates
  gate/report/SARIF/HTML evidence, and derives `policy-failed`,
  `coverage-drift`, or `held` status (`scripts/origin-consumer.js:216-235`):

  ```js
  run.coverage = {reference_revision: reference.revision, current, deltas, indexed_modules: indexedModules};
  const result = validateEvidence(gateJson, report, sarif, html);
  run.status = policyFailed ? 'policy-failed' : deltas.length ? 'coverage-drift' : 'held';
  exit = policyFailed || deltas.length ? 1 : 0;
  ```

- `validateEvidence` checks a single computed, contracted gate result; census
  and policy consistency; report/SARIF equality; alert equality; and HTML
  inclusion (`scripts/origin-consumer.js:122-144`). It writes `diagnostics.txt`
  and `run.json` in its finalization (`scripts/origin-consumer.js:265-268`).
  `scripts/origin-consumer-artifacts.js:9-22` requires those files and accepts
  statuses `held`, `policy-failed`, `coverage-drift`, and `error`.

## Observed scope/gaps

- The generic coverage matrix sets its `decisions` row to `Not_analysed` with
  detail stating that `poc/decision-lint` is not integrated into the main Dune
  build (`lib/arch_index/coverage_matrix.ml:323-329`).
- Its LCOV coverage row is `Not_analysed` without an externally supplied trace
  file (`lib/arch_index/coverage_matrix.ml:310-321`).
- The last path-based search for consumer-related files searched `scripts/` and
  `test/`; it excluded `checks/` and `tezt/`. It therefore does not establish
  whether consumer tests exist elsewhere.
