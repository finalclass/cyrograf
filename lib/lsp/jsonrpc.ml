(* JSON-RPC 2.0 framing and small JSON accessors for the language server.

   Frames are read with [Content-Length] counted in UTF-8 bytes. The reader
   accepts an incomplete frame followed by another read and several frames in
   one stream; it never interprets the body as text. Only the protocol writer
   touches stdout. *)

type read =
  | Message of Yojson.Safe.t
  | Parse_error of string
  | Eof

let member key = function
  | `Assoc fields -> (
    match List.assoc_opt key fields with Some value -> value | None -> `Null)
  | _ -> `Null

let string_opt = function `String value -> Some value | _ -> None
let string value = match string_opt value with Some value -> value | None -> ""
let int_opt = function
  | `Int value -> Some value
  | `Intlit value -> (try Some (int_of_string value) with _ -> None)
  | `Float value -> Some (int_of_float value)
  | _ -> None
let int value = match int_opt value with Some value -> value | None -> 0
let list = function `List items -> items | _ -> []
let bool = function `Bool value -> value | _ -> false

let response id result =
  `Assoc [ ("jsonrpc", `String "2.0"); ("id", id); ("result", result) ]

let error_response id code message =
  `Assoc
    [ ("jsonrpc", `String "2.0");
      ("id", id);
      ( "error",
        `Assoc [ ("code", `Int code); ("message", `String message) ] ) ]

let notification meth params =
  `Assoc
    [ ("jsonrpc", `String "2.0"); ("method", `String meth); ("params", params) ]

let write_message oc json =
  let body = Yojson.Safe.to_string json in
  output_string oc
    (Printf.sprintf "Content-Length: %d\r\n\r\n" (String.length body));
  output_string oc body;
  flush oc

let strip_cr line =
  let length = String.length line in
  if length > 0 && line.[length - 1] = '\r' then String.sub line 0 (length - 1)
  else line

let read_message ic =
  let rec headers content_length =
    match input_line ic with
    | exception End_of_file -> `Eof
    | line ->
      let line = strip_cr line in
      if line = "" then begin
        match content_length with
        | Some length -> `Body length
        | None -> `Parse_error "missing Content-Length header"
      end
      else begin
        match String.index_opt line ':' with
        | None -> headers content_length
        | Some colon ->
          let key = String.trim (String.sub line 0 colon) in
          let value =
            String.trim (String.sub line (colon + 1) (String.length line - colon - 1))
          in
          if String.lowercase_ascii key = "content-length" then begin
            match int_of_string_opt value with
            | Some length -> headers (Some length)
            | None -> `Parse_error "invalid Content-Length header"
          end
          else headers content_length
      end
  in
  match headers None with
  | `Eof -> Eof
  | `Parse_error message -> Parse_error message
  | `Body length ->
    (match (try Ok (really_input_string ic length) with End_of_file -> Error ()) with
     | Error () -> Eof
     | Ok body -> (
       try Message (Yojson.Safe.from_string body) with Yojson.Json_error message ->
         Parse_error message))