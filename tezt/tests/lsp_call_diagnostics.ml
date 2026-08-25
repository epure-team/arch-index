(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** A refused call-hierarchy request must be named once per file — not never,
    and not once per attempt.

    Two properties are under test here, and they pull in opposite directions.
    Silence is the defect this branch exists to remove: a server that refuses
    [callHierarchy/*] yields an empty call graph, and before these diagnostics
    existed nothing said why. Volume is the defect the fix for silence
    introduced: the call sites sit inside the warm-up retry loop ([attempt 20]),
    so the identical line was emitted up to 21 times per function — 126 lines on
    this fixture, ~9000 on this repo — which destroys the one thing the count is
    good for, telling "one document refused" from "all of them".

    So the assertion is a COUNT, not a containment. [contains] cannot distinguish
    3 from 126, and a containment-only assertion is what let the previous
    diagnostics test pass with a diagnostic deleted.

    The stub refuses [prepareCallHierarchy] for one function per file and
    refuses [outgoingCalls] for the other. That is deliberate: it makes BOTH
    methods fail on the SAME path, which is the only arrangement under which a
    memo keyed on the path alone (dropping the method) is observably wrong. *)

open Arch_tezt

let sentinel = "STUB_REFUSED_THE_CALL_QUERY"

(* Counts lines carrying [needle]. The whole point of this test is the number,
   so it is computed rather than eyeballed. *)
let count_lines ~needle output =
  List.length (List.filter (fun l -> contains ~needle l) (lines output))

(* Answers the handshake, answers workspace/symbol with nothing and
   documentSymbol with two functions per file, then splits the call-hierarchy
   surface: the function at line 1 gets a prepare result whose outgoingCalls is
   refused, the function at line 5 has its prepare refused outright. Both
   refusals therefore land on the same file. *)
let splitting_server () =
  let dir = Temp.dir "stub_calls" in
  let path = Filename.concat dir "gopls" in
  write_exec
    path
    (Printf.sprintf
       {|#!/usr/bin/env bash
emit() { printf 'Content-Length: %%d\r\n\r\n%%s' "${#1}" "$1"; }

BODY=""
read_msg() {
  local len=0 line
  while IFS= read -r line; do
    line="${line%%$'\r'}"
    [ -z "$line" ] && break
    case "$line" in Content-Length:*) len="${line#Content-Length: }";; esac
  done
  [ "$len" -eq 0 ] && return 1
  BODY="$(head -c "$len")"
  return 0
}

err() { emit "{\"jsonrpc\":\"2.0\",\"id\":$1,\"error\":{\"code\":-32000,\"message\":\"%s\"}}"; }

# A function at line 1 and a function at line 5, so the client's prepare
# position tells the stub which of the two it is being asked about.
sym() {
  printf '%%s' "[{\"name\":\"alpha\",\"kind\":12,\"range\":{\"start\":{\"line\":1,\"character\":5},\"end\":{\"line\":3,\"character\":1}},\"selectionRange\":{\"start\":{\"line\":1,\"character\":5},\"end\":{\"line\":1,\"character\":10}}},{\"name\":\"beta\",\"kind\":12,\"range\":{\"start\":{\"line\":5,\"character\":5},\"end\":{\"line\":7,\"character\":1}},\"selectionRange\":{\"start\":{\"line\":5,\"character\":5},\"end\":{\"line\":5,\"character\":9}}}]"
}

while true; do
  read_msg || exit 0
  case "$BODY" in *'"method":"exit"'*) exit 0;; esac
  id="$(printf '%%s' "$BODY" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)"
  [ -z "$id" ] && continue
  uri="$(printf '%%s' "$BODY" | grep -oE '"uri":"[^"]*"' | head -1 | cut -d'"' -f4)"
  case "$BODY" in
    *'"method":"initialize"'*)
      emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"capabilities\":{}}}" ;;
    *'"method":"workspace/symbol"'*)
      emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":[]}" ;;
    *'"method":"textDocument/documentSymbol"'*)
      emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":$(sym)}" ;;
    *'"method":"textDocument/prepareCallHierarchy"'*)
      # beta (line 5) is refused; alpha (line 1) is prepared, so that its
      # outgoingCalls can be refused on the very same file.
      case "$BODY" in
        *'"line":5'*) err "$id" ;;
        *) emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":[{\"name\":\"alpha\",\"kind\":12,\"uri\":\"$uri\",\"range\":{\"start\":{\"line\":1,\"character\":5},\"end\":{\"line\":3,\"character\":1}},\"selectionRange\":{\"start\":{\"line\":1,\"character\":5},\"end\":{\"line\":1,\"character\":10}}}]}" ;;
      esac ;;
    *'"method":"callHierarchy/outgoingCalls"'*)
      err "$id" ;;
    *)
      emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":null}" ;;
  esac
done
|}
       sentinel) ;
  dir

let files =
  [
    ("go.mod", "module stub\n\ngo 1.21\n");
    ("a.go", "package main\n\nfunc alpha() {}\n\n\nfunc beta() {}\n");
    ("b.go", "package main\n\nfunc alpha2() {}\n\n\nfunc beta2() {}\n");
    ("c.go", "package main\n\nfunc alpha3() {}\n\n\nfunc beta3() {}\n");
  ]

let source_files = 3

let register () =
  Test.register
    ~__FILE__
    ~title:"lsp: a refused call query is named once per file, not per attempt"
    ~tags:["lsp"; "diagnostics"; "slow"]
  @@ fun () ->
  let stub_dir = splitting_server () in
  with_project ~name:"calls" ~files @@ fun project ->
  let path = stub_dir ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") in
  let _code, out =
    run_command
      ~env:[("PATH", path); ("EPURE_ARCH_INDEX_TIMEOUT_S", "60")]
      (arch_index_cli ())
      ~cwd:(Filename.dirname project)
      [
        "--project";
        Filename.basename project;
        "--language";
        "go";
        "--output";
        temp_db "calls";
        "--verbose";
      ]
  in
  let prepare = count_lines ~needle:"prepareCallHierarchy failed" out in
  let outgoing = count_lines ~needle:"outgoingCalls failed" out in
  Batch.run (fun b ->
      (* Silence. Deleting either diagnostic leaves an empty call graph with no
         stated reason — the defect this branch exists to remove. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "a refused prepareCallHierarchy said nothing: no line names that \
              method:\n\
              %s"
             out)
        (prepare > 0) ;
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "a refused outgoingCalls said nothing: no line names that \
              method:\n\
              %s"
             out)
        (outgoing > 0) ;
      (* Volume. One line per (method, file): 3 and 3 here. Without the memo
         each is emitted once per warm-up attempt — 21 sweeps, 63 lines each —
         and the count stops meaning anything. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "prepareCallHierarchy diagnostics are not bounded to one per file: \
              expected %d, got %d (unbounded would be ~%d, one per sweep)"
             source_files
             prepare
             (source_files * 21))
        (prepare = source_files) ;
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "outgoingCalls diagnostics are not bounded to one per file: \
              expected %d, got %d"
             source_files
             outgoing)
        (outgoing = source_files) ;
      (* The method belongs in the memo key. Both refusals land on the same
         three files, so a key that drops the method suppresses one of the two
         and the totals above collapse from 3+3 to 3+0 or 0+3. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "the two methods share a memo entry: both must be reported for the \
              same file, got prepare=%d outgoing=%d"
             prepare
             outgoing)
        (prepare = source_files && outgoing = source_files) ;
      (* The diagnostic names a FILE. Keying the outgoingCalls site on the
         function name printed "failed for alpha" and bounded per function
         instead of per file — one line per function, 432 on this repo. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "the diagnostics do not name their source files (a.go/b.go/c.go \
              absent):\n\
              %s"
             out)
        (contains ~needle:"a.go" out && contains ~needle:"b.go" out
        && contains ~needle:"c.go" out) ;
      (* And the server's own words, not only our label. *)
      Batch.check
        b
        ~msg:
          (Printf.sprintf
             "the server's own error message (%S) never reaches the operator:\n%s"
             sentinel
             out)
        (contains ~needle:sentinel out)) ;
  Lwt.return_unit
