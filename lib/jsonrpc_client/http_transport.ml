(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

type config = {
  base_url : string;
  headers : (string * string) list;
  timeout_s : float;
}

let default_config ~base_url ?(extra_headers = []) () =
  let base_headers = [("Content-Type", "application/json")] in
  let merged =
    List.fold_left
      (fun acc (k, v) ->
        if
          List.exists
            (fun (k', _) ->
              String.lowercase_ascii k' = String.lowercase_ascii k)
            acc
        then acc
        else acc @ [(k, v)])
      base_headers
      extra_headers
  in
  {base_url; headers = merged; timeout_s = 30.0}

let make ~sw ~env config =
  let https_handler =
    let () = Mirage_crypto_rng_unix.use_default () in
    let authenticator =
      match Ca_certs.authenticator () with
      | Ok a -> a
      | Error (`Msg msg) -> failwith ("CA certificate error: " ^ msg)
    in
    let tls_config =
      match Tls.Config.client ~authenticator () with
      | Ok c -> c
      | Error (`Msg msg) -> failwith ("TLS config error: " ^ msg)
    in
    fun uri raw_flow ->
      let host =
        Uri.host uri
        |> Option.map (fun h -> Domain_name.(of_string_exn h |> host_exn))
      in
      (Tls_eio.client_of_flow tls_config ?host raw_flow
        :> [> Eio.Resource.close_ty] Eio.Flow.two_way)
  in
  let net = Eio.Stdenv.net env in
  let client = Cohttp_eio.Client.make ~https:(Some https_handler) net in
  let clock = Eio.Stdenv.clock env in
  fun payload ->
    let uri = Uri.of_string config.base_url in
    let headers = Cohttp.Header.of_list config.headers in
    let body = Cohttp_eio.Body.of_string payload in
    match
      Eio.Time.with_timeout_exn clock config.timeout_s (fun () ->
          let resp, resp_body =
            Cohttp_eio.Client.post ~sw client ~headers ~body uri
          in
          let status = Cohttp.Response.status resp in
          let status_code = Cohttp.Code.code_of_status status in
          let body_str =
            Eio.Buf_read.(
              of_flow ~max_size:(10 * 1024 * 1024) resp_body |> take_all)
          in
          (status_code, body_str))
    with
    | status_code, body_str ->
        if status_code >= 200 && status_code < 300 then Ok body_str
        else
          Error
            (Jsonrpc_client.Http_error {status = status_code; body = body_str})
    | exception Eio.Time.Timeout -> Error Jsonrpc_client.Timeout
    | exception exn ->
        Error (Jsonrpc_client.Connection_failed (Printexc.to_string exn))
