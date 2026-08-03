(** arch-mcp — an MCP server exposing arch-index's SOUND verdicts to agents.

    {1 Why this exists, and why it is deliberately thin}

    The MCP code-intelligence space is crowded: codebase-memory-mcp (158 languages),
    CodeIndexer, Sourcegraph MCP, Claude Context. arch-index cannot compete on breadth —
    two sound backends against 158 heuristic ones — and should not try.

    None of them offers a {b sound verdict}. They do tree-sitter/LSP structural indexing:
    "who calls what", best-effort, with dropped dynamic edges and no way to say {i I don't
    know}. That is exactly the thing an agent most needs and most lacks: an answer it can
    trust, and an explicit admission when there isn't one. An agent asking "can this handler
    reach [os.Exit]?" and getting [UNKNOWN: MAY_TOP frontier at …] is far better served than
    one getting a confident wrong "no".

    So every tool here reports the {b contract stamps} alongside the answer. An agent can then
    tell "UNREACHABLE, proved over a ⊤-marked index" from "UNREACHABLE on an index that never
    marked ⊤ at all" — which are the same three words carrying completely different weight.

    {1 Design decision: this server SHELLS OUT}

    It does not reimplement reachability. Every verdict is produced by the same [arch-query],
    [arch-impact], [arch-rules], [arch-mutants] and [arch-coverage] that a human runs on the
    command line.

    A second implementation of [unreachable] in OCaml would mean two definitions of soundness
    living in one repository, and the first time they disagreed the MCP answer would be the
    one nobody had checked. The cost is a subprocess per call; the benefit is that an agent and
    a reviewer cannot be told different things. Arguments are passed as an argv array — never
    interpolated into a shell string — so a function name containing shell metacharacters is
    data, not code.

    {1 Scope}

    The database and repository root are fixed at startup ([--db], [--repo]). Tools take no
    path arguments: an agent-supplied path would be an arbitrary-file-read surface, and there
    is no reason for a session to roam. *)

(** Immutable, built once from the command line and threaded explicitly.

    An earlier draft held these as three module-level [ref]s, which [decision-lint] then
    reported as [never_assigned]: nothing in the file visibly writes them (only [Arg.Set_string]
    does, through a closure), and they were the only such bindings in the whole repository. That
    is exactly the ref-heaviness this project has been unwinding elsewhere — a reader cannot
    tell when a global is set, and every function silently depends on ambient state. The
    mutation stays confined to {!parse_args}. *)
type config = { db : string; repo : string; tools : string }

(* ------------------------------------------------------------------------ *)
(* subprocess plumbing                                                        *)
(* ------------------------------------------------------------------------ *)

(** Wait for [pid], bounded, killing it if it outlives the deadline. Returns the exit code in
    the same encoding as elsewhere here (128 + signal for a death by signal). *)
let reap ~timeout pid =
  let deadline = Unix.gettimeofday () +. timeout in
  let of_status = function
    | Unix.WEXITED n -> n
    | Unix.WSIGNALED n | Unix.WSTOPPED n -> 128 + n
  in
  let rec poll ~killed =
    match Unix.waitpid [ Unix.WNOHANG ] pid with
    | 0, _ ->
        if Unix.gettimeofday () < deadline then (
          ignore (Unix.select [] [] [] 0.02) ;
          poll ~killed)
        else if not killed then (
          (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) ;
          (* SIGKILL cannot be caught, so one more blocking wait terminates. *)
          match Unix.waitpid [] pid with
          | _, st -> of_status st
          | exception Unix.Unix_error _ -> 128)
        else 128
    | _, st -> of_status st
    | exception Unix.Unix_error (Unix.EINTR, _, _) -> poll ~killed
    | exception Unix.Unix_error _ -> 128
  in
  poll ~killed:false

(** Drain two pipes CONCURRENTLY, with a deadline.

    Reading stdout to EOF and only then stderr deadlocks the moment a tool writes more than a
    pipe buffer (64 KiB on Linux) to stderr: the child blocks writing stderr, the parent blocks
    reading stdout, and neither moves. `arch-rules --format json` on a large index, or any tool
    printing a long refusal, reaches that size — and the failure mode is a hung MCP session with
    no diagnostic at all, which is the worst possible one for an agent.

    The deadline exists for the same reason: a child that neither exits nor closes its pipes
    would otherwise hang the server forever. On timeout the caller kills the child and reports an
    error — the partial output is DISCARDED rather than returned, because half a JSON document
    presented as a result is worse for an agent than a stated failure. (An earlier version of
    this comment said it was "returned, marked", which the code never did.) *)
let drain_both ~timeout out_fd err_fd =
  let bufs = [ (out_fd, Buffer.create 4096); (err_fd, Buffer.create 1024) ] in
  let open_fds = ref [ out_fd; err_fd ] in
  let chunk = Bytes.create 65536 in
  let deadline = Unix.gettimeofday () +. timeout in
  let timed_out = ref false in
  while !open_fds <> [] && not !timed_out do
    let left = deadline -. Unix.gettimeofday () in
    if left <= 0. then timed_out := true
    else
      match Unix.select !open_fds [] [] (min left 1.0) with
      | exception Unix.Unix_error (Unix.EINTR, _, _) -> ()
      | [], _, _ -> if Unix.gettimeofday () >= deadline then timed_out := true
      | ready, _, _ ->
          List.iter
            (fun fd ->
              let n = try Unix.read fd chunk 0 (Bytes.length chunk) with Unix.Unix_error _ -> 0 in
              if n = 0 then open_fds := List.filter (fun f -> f <> fd) !open_fds
              else Buffer.add_subbytes (List.assoc fd bufs) chunk 0 n)
            ready
  done ;
  (Buffer.contents (List.assoc out_fd bufs), Buffer.contents (List.assoc err_fd bufs), !timed_out)

(** [run tool args] executes [tool_dir/tool] with [args] as a literal argv.

    Returns [Ok (stdout, exit_code)] — a non-zero exit is NOT folded into [Error], because
    several of these tools use exit codes as verdicts ([arch-query unreachable] exits 3 to
    REFUSE, [arch-rules] exits 1 on a violation). Collapsing that into a failure would turn a
    meaningful refusal into "the tool broke". *)
let run cfg tool args =
  let exe = Filename.concat cfg.tools tool in
  if not (Sys.file_exists exe) then
    Error
      (Printf.sprintf
         "%s not found in --tools-dir %s. This server drives the command-line tools rather \
          than reimplementing them; point --tools-dir at the arch-index checkout."
         tool cfg.tools)
  else
    let argv = Array.of_list (exe :: args) in
    (* `arch-query` defaults to sqlite3's -box output: Unicode table art, correct for a human at
       a terminal and actively harmful here — a one-line verdict would reach the agent wrapped in
       ~400 box-drawing characters, spending its context on borders. Ask for the plain form. *)
    (* REPLACE, do not append: with a duplicate name in the environment glibc's getenv returns
       the FIRST match, so appending left a pre-existing ARCH_QUERY_FORMAT=box in charge and the
       agent got the table art anyway. *)
    let env =
      let keep =
        Array.to_list (Unix.environment ())
        |> List.filter (fun kv ->
               not (String.length kv >= 18 && String.sub kv 0 18 = "ARCH_QUERY_FORMAT="))
      in
      Array.of_list (keep @ [ "ARCH_QUERY_FORMAT=list" ])
    in
    let out_r, out_w = Unix.pipe ~cloexec:false () in
    let err_r, err_w = Unix.pipe ~cloexec:false () in
    (* `Sys.file_exists` above is not evidence that the file can be EXECUTED: a directory, a
       non-executable file, or a shebang naming a missing interpreter all pass it and make
       create_process raise. An uncaught Unix_error here escapes the tool handler and takes down
       the session — the agent sees the transport die rather than a tool error it can report. *)
    match Unix.create_process_env exe argv env Unix.stdin out_w err_w with
    | exception Unix.Unix_error (e, _, _) ->
        List.iter (fun fd -> try Unix.close fd with Unix.Unix_error _ -> ()) [ out_r; out_w; err_r; err_w ] ;
        Error (Printf.sprintf "cannot execute %s: %s" exe (Unix.error_message e))
    | pid ->
        Unix.close out_w;
        Unix.close err_w;
        (* 120 s: long enough for a whole-repo arch-impact or arch-rules run on a large index,
           short enough that a wedged child surfaces as an error rather than a dead session. *)
        let out, err, timed_out = drain_both ~timeout:120. out_r err_r in
        (try Unix.close out_r with Unix.Unix_error _ -> ()) ;
        (try Unix.close err_r with Unix.Unix_error _ -> ()) ;
        if timed_out then (try Unix.kill pid Sys.sigkill with Unix.Unix_error _ -> ()) ;
        (* The drain deadline covers the PIPES, not the process. A child that closes stdout and
           stderr and then never exits — a daemonising tool, a wedged cleanup handler — leaves
           both fds at EOF while `waitpid` blocks forever, which is the same hung session the
           drain deadline exists to prevent, reached by a different route. So the reap is bounded
           too, and a child still alive at the end of it is killed. *)
        let code = reap ~timeout:10. pid in
        if timed_out then
          Error
            (Printf.sprintf "%s did not finish within 120s and was killed; %d byte(s) of output discarded"
               tool (String.length out))
        else Ok (out, err, code)

(* ------------------------------------------------------------------------ *)
(* index provenance — the whole point of this server                          *)
(* ------------------------------------------------------------------------ *)

type provenance = {
  callgraph_contract : string option;
  decision_contract : string option;
  built_by : string option;
}

let provenance cfg =
  let get db key =
    let stmt =
      Sqlite3.prepare db "SELECT value FROM comment_db_meta WHERE key = ? LIMIT 1"
    in
    ignore (Sqlite3.bind_text stmt 1 key);
    let v =
      match Sqlite3.step stmt with
      | Sqlite3.Rc.ROW -> (
          match Sqlite3.column stmt 0 with Sqlite3.Data.TEXT s -> Some s | _ -> None)
      | _ -> None
    in
    ignore (Sqlite3.finalize stmt);
    v
  in
  match Sqlite3.db_open ~mode:`READONLY cfg.db with
  | exception _ ->
      { callgraph_contract = None; decision_contract = None; built_by = None }
  | db ->
      let p =
        try
          {
            callgraph_contract = get db "callgraph_contract";
            decision_contract = get db "decision_contract";
            built_by = get db "built_by";
          }
        with _ -> { callgraph_contract = None; decision_contract = None; built_by = None }
      in
      ignore (Sqlite3.db_close db);
      p

let opt_json = function None -> `Null | Some s -> `String s

(** Attached to EVERY structured result. An agent that ignores it gets the same answer as any
    other tool; an agent that reads it can tell a proof from an absence of evidence. *)
let provenance_json cfg =
  let p = provenance cfg in
  `Assoc
    [
      ("db", `String cfg.db);
      ("callgraph_contract", opt_json p.callgraph_contract);
      ("decision_contract", opt_json p.decision_contract);
      ("built_by", opt_json p.built_by);
      ( "reachability_is_sound",
        `Bool (match p.callgraph_contract with Some _ -> true | None -> false) );
      ( "caveat",
        `String
          (match p.callgraph_contract with
          | Some _ ->
              "This index is ⊤-marked: an UNREACHABLE verdict is a proof in a closed \
               universe, and UNKNOWN is reported explicitly wherever the analysis loses \
               track."
          | None ->
              "This index is NOT ⊤-marked. A 'no path' answer may merely hide a \
               silently-dropped dynamic edge, so it is NOT evidence of unreachability. \
               Treat every negative as UNKNOWN.") );
    ]

(* ------------------------------------------------------------------------ *)
(* tool construction                                                          *)
(* ------------------------------------------------------------------------ *)

let trim s = String.trim s

(** The leading all-caps word of the first non-empty line.

    `arch-query unreachable` under ARCH_QUERY_FORMAT=list prints exactly one line, and that line
    BEGINS with its verdict: "UNREACHABLE: …", "REACHABLE (may-reach): …", "UNKNOWN: …". *)
let leading_verdict out =
  let lines = String.split_on_char '\n' out in
  match List.find_opt (fun l -> String.trim l <> "") lines with
  | None -> ""
  | Some line ->
      let line = String.trim line in
      let n = String.length line in
      let rec stop i = if i < n && (line.[i] = '_' || (line.[i] >= 'A' && line.[i] <= 'Z')) then stop (i + 1) else i in
      String.sub line 0 (stop 0)

(** Classify [arch-query unreachable] output into the verdict vocabulary an agent should
    branch on. The raw text is always carried through as well: a classifier that silently
    swallowed an unrecognised answer would be the one bug this server cannot afford.

    Anchored on the leading word, NOT a substring scan of the whole output. The verdict line
    embeds the two function names, so scanning for "UNREACHABLE" anywhere inverted the answer
    for any question about a function whose own name contains it — `mark_UNREACHABLE` turned a
    REACHABLE verdict into UNREACHABLE, which is the single most dangerous way this server can
    be wrong. An unrecognised shape is UNPARSED with the raw text attached, never a guess. *)
let classify_reachability out err code =
  if code = 3 then ("REFUSED", trim err)
  else
    match leading_verdict out with
    | "UNREACHABLE" -> ("UNREACHABLE", trim out)
    | "REACHABLE" -> ("REACHABLE", trim out)
    | "UNKNOWN" -> ("UNKNOWN", trim out)
    | _ -> ("UNPARSED", trim (out ^ err))

let result_of ~text ~structured =
  {
    Mcp_kit.Tool.content = [ Mcp_kit.Tool.Text text ];
    is_error = false;
    structured_content = Some structured;
  }

let str = Mcp_kit.Schema.string
let obj = Mcp_kit.Schema.object_

(* Every tool advertises `provenance` in its output schema, so an agent inspecting
   tools/list can see up front that verdicts arrive with their trust level attached. *)
let with_provenance props =
  obj ~properties:(props @ [ ("provenance", obj ()) ]) ()

let tool_reachability cfg =
  Mcp_kit.Tool.make
    ~description:
      "Can FROM reach TO? Returns REACHABLE | UNREACHABLE | UNKNOWN | REFUSED. UNREACHABLE \
       is a proof in a closed universe, only available on a ⊤-marked index; UNKNOWN means \
       the analysis lost track at an unresolvable edge and is NOT a 'no'. Check \
       provenance.reachability_is_sound before treating a negative as evidence."
    ~input_schema:
      (obj
         ~properties:
           [ ("from", str ~description:"caller function name" ());
             ("to", str ~description:"callee function name" ()) ]
         ~required:[ "from"; "to" ] ())
    ~output_schema:
      (with_provenance
         [ ("verdict", str ()); ("detail", str ()); ("must_path", str ()) ])
    "reachability"
    (fun args ->
      match
        (Mcp_kit.Tool.Arg.string "from" args, Mcp_kit.Tool.Arg.string "to" args)
      with
      | Error e, _ | _, Error e -> Error e
      | Ok f, Ok t -> (
          match run cfg "arch-query" [ cfg.db; "unreachable"; f; t ] with
          | Error e -> Error e
          | Ok (out, err, code) ->
              let verdict, detail = classify_reachability out err code in
              (* The MUST-only query is a separate, stronger question: a positive there is
                 must-reach ground truth rather than a may-reach over-approximation. Both are
                 reported because an agent deciding whether to act needs to know which it
                 has. *)
              let must =
                match run cfg "arch-query" [ cfg.db; "reaches"; f; t ] with
                | Ok (o, _, _) -> trim o
                | Error e -> e
              in
              Ok
                (result_of
                   ~text:(Printf.sprintf "%s\n%s" detail must)
                   ~structured:
                     (`Assoc
                       [ ("verdict", `String verdict);
                         ("detail", `String detail);
                         ("must_path", `String must);
                         ("provenance", provenance_json cfg) ]))))

exception Bad_argument of string
(** Raised by an [argv_of] that will not build a command line from what the agent supplied. It is
    a refusal, reported to the agent as a tool error — never a silent repair of the argument. *)

(** A repo-relative path an agent supplied, checked rather than rewritten.

    This used to be [Filename.concat cfg.repo (Filename.basename p)], which is not a check: it
    silently turned "docs/arch-rules.txt" into "<repo>/arch-rules.txt" and evaluated a DIFFERENT
    rules file than the one asked for, reporting its verdicts as the answer. Escaping the repo is
    refused for the same reason every tool here takes no path arguments — but the fix for a
    traversal attempt is to say no, not to quietly point somewhere else. *)
let repo_relative cfg what p =
  if p = "" then raise (Bad_argument (Printf.sprintf "%s is empty" what)) ;
  if Filename.is_relative p = false then
    raise (Bad_argument (Printf.sprintf "%s must be relative to the repo root, got %S" what p)) ;
  if List.mem ".." (String.split_on_char '/' p) then
    raise
      (Bad_argument
         (Printf.sprintf "%s must stay inside the repo — %S contains '..'" what p)) ;
  let full = Filename.concat cfg.repo p in
  if not (Sys.file_exists full) then
    raise (Bad_argument (Printf.sprintf "%s: no such file under the repo root: %s" what p)) ;
  full

let simple_tool cfg name description ?(args = []) argv_of output_props =
  Mcp_kit.Tool.make ~description
    ~input_schema:
      (obj ~properties:(List.map (fun (n, d) -> (n, str ~description:d ())) args)
         ~required:(List.map fst args) ())
    ~output_schema:(with_provenance output_props)
    name
    (fun a ->
      let rec collect acc = function
        | [] -> Ok (List.rev acc)
        | (n, _) :: rest -> (
            match Mcp_kit.Tool.Arg.string n a with
            | Error e -> Error e
            | Ok v -> collect (v :: acc) rest)
      in
      match collect [] args with
      | Error e -> Error e
      | Ok vals -> (
          match (try Ok (argv_of vals) with Bad_argument m -> Error m) with
          | Error m -> Error m
          | Ok (tool, argv) -> (
          match run cfg tool argv with
          | Error e -> Error e
          | Ok (out, err, code) ->
              let body = if trim out = "" then trim err else trim out in
              Ok
                (result_of ~text:body
                   ~structured:
                     (`Assoc
                       [ ("output", `String body);
                         ("exit_code", `Int code);
                         ("provenance", provenance_json cfg) ])))))

let out_props = [ ("output", str ()); ("exit_code", Mcp_kit.Schema.integer ()) ]

let tools cfg =
  [
    tool_reachability cfg;
    simple_tool cfg "escapes"
      "The ⊤ (unresolvable) edges reachable from FROM — the exact boundary that forces an \
       UNKNOWN verdict. Ask this whenever `reachability` answers UNKNOWN: it names what the \
       analysis could not see."
      ~args:[ ("from", "function name") ]
      (fun v -> ("arch-query", [ cfg.db; "escapes"; List.nth v 0 ]))
      out_props;
    simple_tool cfg "callers_of" "Direct callers of a function (one hop)."
      ~args:[ ("name", "function name") ]
      (fun v -> ("arch-query", [ cfg.db; "callers-of"; List.nth v 0 ]))
      out_props;
    simple_tool cfg "callees_of" "Direct callees of a function (one hop)."
      ~args:[ ("name", "function name") ]
      (fun v -> ("arch-query", [ cfg.db; "callees-of"; List.nth v 0 ]))
      out_props;
    simple_tool cfg "useless_branches"
      "Decisions with an actionable dead-logic verdict: conditions that cannot change the \
       outcome, contradictory guards, identical arms. Each is a proof that code is useless, \
       not a heuristic smell."
      (fun _ -> ("arch-query", [ cfg.db; "useless-branches" ]))
      out_props;
    simple_tool cfg "dead_blocks"
      "Call sites in CFG-unreachable blocks — statically dead code."
      (fun _ -> ("arch-query", [ cfg.db; "dead-blocks" ]))
      out_props;
    simple_tool cfg "mutation_density"
      "Functions ranked by mutation sites. A diagnostic signal, never a gate."
      (fun _ -> ("arch-query", [ cfg.db; "mutation-density" ]))
      out_props;
    simple_tool cfg "change_impact"
      "Change-impact briefing for a git range: touched functions, affected exported API, \
       blast radius, ⊤ frontier, reaching tests, and findings on touched lines. Counts are \
       LOWER bounds in both directions — ⊤ edges are dropped to make them computable."
      ~args:[ ("diff", "git range, e.g. main...HEAD") ]
      (fun v ->
        ( "arch-impact",
          [ cfg.db; "--diff"; List.nth v 0; "--repo"; cfg.repo; "--format"; "json" ] ))
      out_props;
    simple_tool cfg "architecture_rules"
      "Evaluate an architecture rules file. Verdicts are VIOLATION | POSSIBLE | UNKNOWN | \
       PASS: unlike declared-import checkers, a PASS here is a proof and an UNKNOWN is \
       reported rather than shown as a green tick."
      ~args:[ ("rules_file", "path to a rules file, relative to the repo root") ]
      (fun v ->
        ( "arch-rules",
          [ cfg.db; repo_relative cfg "rules_file" (List.nth v 0); "--format"; "json" ] ))
      out_props;
    simple_tool cfg "mutation_plan"
      "What is worth mutating (test-reachable code only) and which tests must rerun for each \
       target. Says explicitly whether the unreached list is a proof or a candidate list."
      ~args:[ ("tests", "selector for test roots, e.g. file:test/**") ]
      (fun v ->
        ( "arch-mutants",
          [ "plan"; cfg.db; "--tests"; List.nth v 0; "--format"; "json" ] ))
      out_props;
    simple_tool cfg "index_status"
      "What this index is, and what it can and cannot answer: contract stamps, producing \
       backend, and row counts. Call this FIRST — every other verdict's weight depends on it."
      (fun _ -> ("arch-query", [ cfg.db; "stats" ]))
      out_props;
  ]

(* ------------------------------------------------------------------------ *)

let contract_resource =
  Mcp_kit.Resource.make ~uri:"arch-index://contract" ~name:"edge-kind contract"
    ~description:
      "How to read a verdict from this server: what MUST / MAY_ENUMERATED / MAY_TOP mean, \
       and why an UNKNOWN is more informative than a confident negative."
    ~mime_type:"text/markdown"
    [ Mcp_kit.Resource.Text
        {
          uri = "arch-index://contract";
          mime_type = Some "text/markdown";
          text =
            "# Reading an arch-index verdict\n\n\
             Every call edge carries a kind:\n\n\
             - `MUST` — a uniquely-resolved static call. A path built only from MUST edges is \
             ground truth: it *will* happen on that path.\n\
             - `MAY_ENUMERATED` — a dynamic call bounded to a finite candidate set. Used for \
             over-approximation.\n\
             - `MAY_TOP` (⊤) — unresolvable: reflection, FFI, plugin loading. It means \"could \
             call anything\", and it is never dropped.\n\n\
             Consequently:\n\n\
             - `REACHABLE` over MUST ∪ MAY_ENUMERATED means a path may exist.\n\
             - `UNREACHABLE` is a **proof**, and only available when the source cone contains no \
             ⊤ edge and the index is ⊤-marked (`callgraph_contract` is set).\n\
             - `UNKNOWN` means no path was found **and none can be ruled out** — the cone \
             escapes through a ⊤ edge. It is not a 'no'. Call `escapes` to see exactly where.\n\n\
             If `provenance.reachability_is_sound` is false, the index is not ⊤-marked: a \
             dropped dynamic edge is indistinguishable from an absent one, so treat every \
             negative as UNKNOWN regardless of the word used.\n";
        } ]

let build_server cfg =
  let s =
    Mcp_kit.Server.create ~name:"arch-index" ~version:"0.2.0"
      ~instructions:
        "arch-index answers call-graph questions with a SOUND verdict and an explicit \
         UNKNOWN. Call `index_status` first: if `callgraph_contract` is unset, negative \
         answers are not evidence. When `reachability` returns UNKNOWN, call `escapes` to \
         find out what the analysis could not see rather than guessing."
      ()
  in
  let s =
    match Mcp_kit.Server.add_tools s (tools cfg) with
    | Ok s -> s
    | Error (Mcp_kit.Server.Duplicate_tool n) -> failwith ("duplicate tool: " ^ n)
    | Error _ -> failwith "duplicate declaration"
  in
  match Mcp_kit.Server.add_resource s contract_resource with
  | Ok s -> s
  | Error _ -> failwith "duplicate resource"

let usage =
  "arch-mcp --db <index.db> [--repo <dir>] [--tools-dir <dir>]\n\n\
   Serves arch-index's sound verdicts over MCP (stdio, line-delimited JSON-RPC).\n\
   The database and repo root are fixed here rather than passed per call: an \
   agent-supplied path would be an arbitrary-file-read surface."

(** The one place mutation lives. [Stdlib.Arg] has to write somewhere, so it writes into locals
    that die at the end of this function; everything downstream receives an immutable
    {!config}. *)
let parse_args () =
  let db = ref "" and repo = ref "." and tools = ref "." in
  let specs =
    [
      ("--db", Arg.Set_string db, "PATH  the arch-index SQLite database (required)");
      ("--repo", Arg.Set_string repo, "DIR   repository root (default: .)");
      ( "--tools-dir",
        Arg.Set_string tools,
        "DIR   directory holding arch-query / arch-impact / … (default: .)" );
    ]
  in
  Arg.parse specs (fun a -> raise (Arg.Bad ("unexpected argument: " ^ a))) usage;
  { db = !db; repo = !repo; tools = !tools }

let () =
  let cfg = parse_args () in
  if cfg.db = "" then (
    prerr_endline "arch-mcp: --db is required";
    prerr_endline usage;
    exit 2);
  if not (Sys.file_exists cfg.db) then (
    Printf.eprintf "arch-mcp: no such database: %s\n" cfg.db;
    exit 2);
  (* Refusing to start on an unusable index beats answering every question with an error:
     an agent has no way to distinguish "the server is broken" from "the answer is no". *)
  Mcp_kit_stdio.run_channels (build_server cfg) stdin stdout
