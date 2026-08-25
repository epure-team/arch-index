(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(** An empty index must name its own cause.

    Every LSP call site treated a failed request as "no data for this item" and
    returned [[]] — correct as control flow, silent as diagnostics. A server that
    answers [workspace/symbol] with an error therefore produced an index with
    zero symbols, a run that reported success, and no line anywhere saying why.
    That is the shape that costs hours: the operator sees an empty database and
    has nothing to grep for.

    The instrument is the stub server, as in {!Lsp_readiness}: a bash script on
    PATH under the name of a registered language server, which completes the
    handshake and then answers with a JSON-RPC error carrying a sentinel string.
    The assertion is that the sentinel reaches the operator. *)

open Arch_tezt

let sentinel = "STUB_REFUSED_THE_SYMBOL_QUERY"

(* Answers the handshake, then fails every subsequent request with a JSON-RPC
   error whose message carries the sentinel. Modelled on Lsp_readiness.stub_server;
   the difference is the error arm, which is the whole point of this test. *)
let erroring_server () =
  let dir = Temp.dir "stub_erroring" in
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

n=0
while true; do
  read_msg || exit 0
  case "$BODY" in *'"method":"exit"'*) exit 0;; esac
  id="$(printf '%%s' "$BODY" | grep -oE '"id":[0-9]+' | head -1 | cut -d: -f2)"
  [ -z "$id" ] && continue
  n=$((n+1))
  if [ "$n" -eq 1 ]; then
    # initialize: succeed, so the client gets past the handshake and actually
    # asks the questions this test is about.
    emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"result\":{\"capabilities\":{}}}"
  else
    emit "{\"jsonrpc\":\"2.0\",\"id\":$id,\"error\":{\"code\":-32000,\"message\":\"%s\"}}"
  fi
done
|}
       sentinel) ;
  dir

let register () =
  Test.register
    ~__FILE__
    ~title:"lsp: a refused symbol query names itself in the output"
    ~tags:["lsp"; "diagnostics"]
  @@ fun () ->
  let stub_dir = erroring_server () in
  with_project
    ~name:"erroring"
    ~files:[("go.mod", "module stub\n\ngo 1.21\n"); ("main.go", "package main\n\nfunc main() {}\n")]
  @@ fun project ->
  let path = stub_dir ^ ":" ^ Option.value ~default:"" (Sys.getenv_opt "PATH") in
  let _code, out =
    run_command
      ~env:[("PATH", path); ("EPURE_ARCH_INDEX_TIMEOUT_S", "30")]
      (arch_index_cli ())
      [
        "--project";
        project;
        "--language";
        "go";
        "--output";
        temp_db "erroring";
        "--verbose";
      ]
  in
  Batch.run (fun b ->
    (* One site, one assertion. An earlier version asserted only that the
       sentinel appeared SOMEWHERE, and passed with the workspace/symbol
       diagnostic deleted — the stub refuses every request, so documentSymbol
       surfaced the same sentinel and the test could not tell the two sites
       apart. It passed for the wrong reason; the mutation that removed one
       diagnostic survived it. *)
    Batch.check
      b
      ~msg:
        (Printf.sprintf
           "workspace/symbol failed and said nothing: no line naming that \
            method appears in the output:\n\
            %s"
           out)
      (contains ~needle:"workspace/symbol failed" out) ;
    Batch.check
      b
      ~msg:
        (Printf.sprintf
           "documentSymbol failed and said nothing: no line naming that method \
            appears in the output:\n\
            %s"
           out)
      (contains ~needle:"documentSymbol failed" out) ;
    (* And the server's own words, not just our label — a diagnostic that drops
       the reason is only marginally better than none. *)
    Batch.check
      b
      ~msg:
        (Printf.sprintf
           "the server's own error message (%S) never reaches the operator:\n%s"
           sentinel
           out)
      (contains ~needle:sentinel out) ;
    Batch.check
      b
      ~msg:(Printf.sprintf "the indexer never reported readiness:\n%s" out)
        (contains ~needle:"server readiness:" out)) ;
  Lwt.return_unit
