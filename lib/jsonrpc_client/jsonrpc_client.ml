(******************************************************************************)
(*                                                                            *)
(* Copyright (c) 2026 Epure Team                                              *)
(* All rights reserved.                                                       *)
(*                                                                            *)
(******************************************************************************)

(* --- Protocol types ------------------------------------------------------ *)

type params =
  | Positional of Yojson.Safe.t list
  | Named of (string * Yojson.Safe.t) list

type rpc_error = {code : int; message : string; data : Yojson.Safe.t option}

type response = {id : Yojson.Safe.t; result : Yojson.Safe.t}

type transport_error =
  | Connection_failed of string
  | Timeout
  | Http_error of {status : int; body : string}
  | Transport_other of string

type error =
  | Transport_error of transport_error
  | Rpc_error of rpc_error
  | Parse_error of string
  | Protocol_error of string

(* --- ID generation ------------------------------------------------------- *)

let id_counter = Atomic.make 0

let next_id () =
  let id = Atomic.fetch_and_add id_counter 1 in
  `Int id

let reset_id_counter () = Atomic.set id_counter 0

(* --- Encoding ------------------------------------------------------------ *)

let params_to_json = function
  | Positional args -> `List args
  | Named fields -> `Assoc fields

let encode_request ~method_ ?params ?id () =
  let fields = [("jsonrpc", `String "2.0"); ("method", `String method_)] in
  let fields =
    match params with
    | None -> fields
    | Some p -> fields @ [("params", params_to_json p)]
  in
  let fields =
    match id with None -> fields | Some id_val -> fields @ [("id", id_val)]
  in
  `Assoc fields

let encode_batch requests = `List requests

(* --- Decoding ------------------------------------------------------------ *)

let member_opt key = function
  | `Assoc fields -> List.assoc_opt key fields
  | _ -> None

let decode_rpc_error json =
  match (member_opt "code" json, member_opt "message" json) with
  | Some (`Int code), Some (`String message) ->
      let data = member_opt "data" json in
      {code; message; data}
  | _ -> {code = -32600; message = "Malformed error object"; data = Some json}

let decode_response json =
  match json with
  | `Assoc _ -> (
      (* Validate jsonrpc field (Story #15) *)
      match member_opt "jsonrpc" json with
      | None -> Error (Protocol_error "Missing 'jsonrpc' field in response")
      | Some (`String "2.0") -> (
          let id =
            match member_opt "id" json with Some v -> v | None -> `Null
          in
          match (member_opt "result" json, member_opt "error" json) with
          | Some result, None -> Ok {id; result}
          | None, Some err_json -> Error (Rpc_error (decode_rpc_error err_json))
          | Some _, Some _ ->
              Error
                (Protocol_error
                   "Response contains both 'result' and 'error' fields")
          | None, None ->
              Error
                (Protocol_error
                   "Response contains neither 'result' nor 'error' field"))
      | Some (`String v) ->
          Error
            (Protocol_error
               (Printf.sprintf
                  "Invalid jsonrpc version: expected \"2.0\", got %S"
                  v))
      | Some _ -> Error (Protocol_error "Field 'jsonrpc' must be a string"))
  | _ -> Error (Parse_error "Response is not a JSON object")

let decode_batch_response json =
  match json with
  | `List items ->
      List.map
        (fun item ->
          let id =
            match item with `Assoc _ -> member_opt "id" item | _ -> None
          in
          (decode_response item, id))
        items
  | _ -> [(Error (Parse_error "Batch response is not a JSON array"), None)]

(* --- Transport abstraction ----------------------------------------------- *)

type transport = string -> (string, transport_error) result

type config = {transport : transport}

(* --- Client API ---------------------------------------------------------- *)

let call config ~method_ ?params () =
  let id = next_id () in
  let request = encode_request ~method_ ?params ~id () in
  let payload = Yojson.Safe.to_string request in
  match config.transport payload with
  | Error te -> Error (Transport_error te)
  | Ok raw_response -> (
      match Yojson.Safe.from_string raw_response with
      | exception Yojson.Json_error msg ->
          Error (Parse_error (Printf.sprintf "Malformed JSON: %s" msg))
      | json -> (
          match decode_response json with
          | Ok resp ->
              if resp.id <> id then
                Error
                  (Protocol_error
                     (Printf.sprintf
                        "Response ID %s does not match request ID %s"
                        (Yojson.Safe.to_string resp.id)
                        (Yojson.Safe.to_string id)))
              else Ok resp
          | Error _ as e -> e))

let notify config ~method_ ?params () =
  let request = encode_request ~method_ ?params () in
  let payload = Yojson.Safe.to_string request in
  match config.transport payload with
  | Error te -> Error (Transport_error te)
  | Ok _ -> Ok ()

let batch config requests =
  match requests with
  | [] ->
      Error (Protocol_error "Empty batch request is invalid per JSON-RPC 2.0")
  | _ -> (
      let encoded =
        List.map
          (fun (method_, params) ->
            let id = next_id () in
            (id, encode_request ~method_ ?params ~id ()))
          requests
      in
      let ids = List.map fst encoded in
      let json_requests = List.map snd encoded in
      let payload = Yojson.Safe.to_string (encode_batch json_requests) in
      match config.transport payload with
      | Error te -> Error (Transport_error te)
      | Ok raw_response -> (
          match Yojson.Safe.from_string raw_response with
          | exception Yojson.Json_error msg ->
              Error
                (Parse_error (Printf.sprintf "Malformed JSON in batch: %s" msg))
          | json ->
              let decoded = decode_batch_response json in
              (* Build a map from response ID to result, using only the first
                 occurrence of each ID to avoid silent misassignment when the
                 server returns duplicate IDs. *)
              let id_map = Hashtbl.create (List.length decoded) in
              List.iter
                (fun (result, resp_id_opt) ->
                  match resp_id_opt with
                  | Some resp_id ->
                      if not (Hashtbl.mem id_map resp_id) then
                        Hashtbl.replace id_map resp_id result
                  | None -> ())
                decoded ;
              let results =
                List.map
                  (fun id ->
                    match Hashtbl.find_opt id_map id with
                    | Some result -> result
                    | None ->
                        Error
                          (Protocol_error
                             (Printf.sprintf
                                "No response for request ID %s"
                                (Yojson.Safe.to_string id))))
                  ids
              in
              Ok results))
