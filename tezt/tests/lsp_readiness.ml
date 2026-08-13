(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** The readiness wait, driven by STUB servers.

    This exists because the feature had no enforcing test. The only assertion
    that mentioned readiness lived in the Rust language test and was GATED on
    readiness having been reported — so removing the entire wait deleted the
    assertion along with the feature, and the suite stayed green.

    Stubs rather than real servers, for two reasons. A real server's phase
    timing is not controllable, so the interesting case — an inter-phase gap
    longer than the quiet window — cannot be provoked on demand. And these
    assertions should hold on a machine with no language server installed at
    all, since what is under test is the client's protocol handling, not gopls.

    {2 Why the verdict string is not the assertion}

    The first version of this file asserted on the readiness line alone, and was
    worthless: [Reported] is the CORRECT answer for a client that waits out the
    gap and sees the indexing phase close, and the WRONG answer for one that
    mistakes the gap for completion. The same string, opposite meanings. The
    predicate that tried to express this accepted all four strings
    {!Arch_index.Lsp_client.readiness_to_string} can produce — a tautology whose
    message claimed the opposite of what it checked — and mutating the client to
    return [Reported] in the gap left all three tests green.

    So the stub records an ORDERING instead, in a marker file: when each phase
    opened and closed, and when the first post-handshake request arrived. That
    last mark is the observable that says when [await_ready] returned, and the
    invariant is falsifiable:

      if the client says "reported complete", the indexing phase must have
      CLOSED before it resumed.

    A client that returns during the gap marks [post_ready] before the indexing
    phase has even begun, so claiming [Reported] there now fails. *)

open Arch_tezt

(* An LSP server is a process speaking Content-Length framing on stdio. A stub
   answers `initialize`, then emits the progress script it was given, then
   answers everything else with an empty result — enough for the handshake to
   complete and for the readiness loop to see exactly the sequence under test.

   It EXITS on the `exit` notification. Without that the process outlives
   [shutdown]'s wait for it, every test burned the full 30s pipeline timeout
   instead of the ~6s of signal it contains, and the tests would have passed
   identically with [Lsp_client.shutdown] deleted. *)
let stub_server ~name ~script =
  let dir = Temp.dir ("stub_" ^ name) in
  let marker = Filename.concat dir "marks" in
  let path = Filename.concat dir "gopls" in
  write_exec path
    (Printf.sprintf
       {|#!/usr/bin/env bash
MARKS=%s
emit() { printf 'Content-Length: %%d\r\n\r\n%%s' "${#1}" "$1"; }
mark() { printf '%%s\n' "$1" >> "$MARKS"; }

# Read one framed message into BODY. Fails when stdin closes.
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

n=0
while true; do
  read_msg || exit 0
  case "$BODY" in *'"method":"exit"'*) exit 0;; esac
  id="$(printf '%%s' "$BODY" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)"
  # A notification carries no id and expects no reply.
  [ -z "$id" ] && continue
  emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"capabilities\":{}}}"
  n=$((n+1))
  if [ "$n" -eq 1 ]; then
    # BACKGROUNDED, and that is the whole instrument. Run in the read loop, the
    # stub cannot read the client's next request until the script's sleeps are
    # over, so `post_ready` was recorded after the last phase no matter when the
    # client actually resumed — the mark measured the stub, not the client, and
    # every ordering assertion passed by construction.
    (
%s
    ) &
  elif [ "$n" -eq 2 ]; then
    # The first request after the handshake: this is the moment await_ready
    # returned and the indexer resumed.
    mark post_ready
  fi
done
|}
       (Filename.quote marker) script) ;
  (dir, marker)

(* One progress phase: open a token with [title], hold it for [hold] seconds,
   then close it. Written as shell so the stub controls its own timing, and
   marked on both edges so the test can order it against [post_ready]. *)
let phase ~token ~title ~hold =
  Printf.sprintf
    {|    mark "begin:%s"
    emit "{\"jsonrpc\":\"2.0\",\"method\":\"$/progress\",\"params\":{\"token\":\"%s\",\"value\":{\"kind\":\"begin\",\"title\":\"%s\"}}}"
    sleep %s
    emit "{\"jsonrpc\":\"2.0\",\"method\":\"$/progress\",\"params\":{\"token\":\"%s\",\"value\":{\"kind\":\"end\"}}}"
    mark "end:%s"|}
    title token title hold token title

let gap seconds = Printf.sprintf "    sleep %s" seconds

(* Run the indexer against a project, with the stub's directory first on PATH so
   it is found as `gopls`. Returns the readiness line it printed and the marks
   the stub recorded, in the order they happened. *)
let run_indexer ~stub_dir ~marker ~project =
  let path = stub_dir ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") in
  let _, out =
    run_command
      ~env:[("PATH", path); ("EPURE_ARCH_INDEX_TIMEOUT_S", "30")]
      (arch_index_cli ())
      ["--project"; project; "--language"; "go"; "--output"; temp_db "readiness";
       "--verbose"]
  in
  let verdict =
    match field_after ~marker:"server readiness: " out with
    | Some line -> line
    | None -> Test.fail "the indexer printed no readiness line:\n%s" out
  in
  let marks = if Sys.file_exists marker then lines (read_file marker) else [] in
  (verdict, marks)

(* Position of a mark, so the assertions can talk about ORDER rather than
   presence. A mark that never happened has no position, and every ordering
   claim about it is reported as such rather than passing by default. *)
let position marks m =
  let rec go i = function
    | [] -> None
    | x :: _ when x = m -> Some i
    | _ :: tl -> go (i + 1) tl
  in
  go 0 marks

let ordered b ~msg ~marks before after =
  match (position marks before, position marks after) with
  | Some i, Some j when i < j -> ()
  | Some i, Some j ->
      Batch.note b "%s: %S (at %d) did not precede %S (at %d); marks: %s" msg before i
        after j (String.concat "," marks)
  | None, _ -> Batch.note b "%s: %S never happened; marks: %s" msg before (String.concat "," marks)
  | _, None -> Batch.note b "%s: %S never happened; marks: %s" msg after (String.concat "," marks)

let go_project =
  [("go.mod", "module stub\ngo 1.21\n"); ("main.go", "package main\n\nfunc main() {}\n")]

let register_indexing_token_is_authoritative () =
  Test.register ~__FILE__ ~title:"readiness: a closed indexing phase is reported as such"
    ~tags:["lsp"; "readiness"]
  @@ fun () ->
  with_project ~name:"readiness_ok" ~files:go_project @@ fun project ->
  let stub_dir, marker =
    stub_server ~name:"indexing"
      ~script:(phase ~token:"stub/cachePriming" ~title:"Indexing" ~hold:"0.2")
  in
  let verdict, marks = run_indexer ~stub_dir ~marker ~project in
  Batch.run (fun b ->
      Batch.eq_string b ~msg:"a token titled Indexing closing is the authoritative signal"
        verdict "reported complete" ;
      (* And it must have waited for the close, not merely for the open. *)
      ordered b ~msg:"the indexing phase must close before the indexer resumes" ~marks
        "end:Indexing" "post_ready") ;
  Lwt.return_unit

(* The defect a review proved: rust-analyzer runs startup as a SEQUENCE of
   phases and closes each before opening the next, so a gap longer than the
   quiet window looks exactly like completion. *)
let register_interphase_gap_is_not_completion () =
  Test.register ~__FILE__
    ~title:"readiness: a gap between phases is not the server reporting completion"
    ~tags:["lsp"; "readiness"]
  @@ fun () ->
  with_project ~name:"readiness_gap" ~files:go_project @@ fun project ->
  let stub_dir, marker =
    stub_server ~name:"gap"
      ~script:
        (String.concat "\n"
           [
             phase ~token:"stub/fetching" ~title:"Fetching" ~hold:"0.2";
             (* Longer than the default 2s quiet window: this is the gap that
                used to be mistaken for completion. *)
             gap "4";
             phase ~token:"stub/cachePriming" ~title:"Indexing" ~hold:"0.2";
           ])
  in
  let verdict, marks = run_indexer ~stub_dir ~marker ~project in
  Batch.run (fun b ->
      (* THE assertion. Two outcomes are acceptable and they are told apart by
         WHEN the indexer resumed, not by what it printed:

         - it waited out the gap, saw Indexing close, and says so — then
           `end:Indexing` precedes `post_ready`;
         - it gave up on the heuristic and says `quiescent`, which claims
           nothing about the index.

         What is forbidden is the third: resuming during the gap while
         REPORTING completion. That is a false fact about the index, and it is
         exactly what quiescence-as-readiness produces here. *)
      if verdict = "reported complete" then
        ordered b
          ~msg:
            "the indexer claims the server reported completion, so the indexing phase must \
             have closed before it resumed — claiming it during the inter-phase gap is a \
             false fact about the index"
          ~marks "end:Indexing" "post_ready"
      else if has_prefix ~prefix:"quiescent" verdict then
        Log.warn
          "readiness fell back to the quiescence heuristic across the gap: honest, but the \
           indexing phase was missed"
      else
        Batch.note b
          "a gap between phases must end in either the indexing phase being seen or an \
           honest quiescence fallback, got %S"
          verdict ;
      (* Independently of the verdict: the first phase really did open and close,
         so the gap under test actually began. Without this the branch above
         would be vacuous against a stub that died before emitting anything.

         Deliberately NOT asserted: that the second phase was reached. Whether
         `begin:Indexing` ever happens is the question, not a precondition — a
         client that resumes during the gap ends the run and terminates the
         server before it, and that is the honest quiescence outcome. *)
      ordered b ~msg:"the stub must have opened and closed the first phase" ~marks
        "begin:Fetching" "end:Fetching") ;
  Lwt.return_unit

(* A server with nothing to report must not cost the whole budget: grace bounds
   the wait for the FIRST progress notification. *)
let register_silent_server () =
  Test.register ~__FILE__ ~title:"readiness: a server that reports no progress says so"
    ~tags:["lsp"; "readiness"]
  @@ fun () ->
  with_project ~name:"readiness_silent" ~files:go_project @@ fun project ->
  let stub_dir, marker = stub_server ~name:"silent" ~script:"    :" in
  let verdict, _ = run_indexer ~stub_dir ~marker ~project in
  Batch.run (fun b ->
      Batch.eq_string b
        ~msg:"a server that never opens a progress token must report no progress" verdict
        "not reported (server sent no progress)") ;
  Lwt.return_unit
