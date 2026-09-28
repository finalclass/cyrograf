(* The language server adapter.

   It maps JSON-RPC frames to the shared [Tooling] editor composition. It owns
   no parser, validator or formatter: diagnostics, hover, definition, symbols,
   completion and formatting all read the same analysis and [Layout] as the
   CLI. stdout carries protocol frames only; nothing is logged there. *)

module Jsonrpc = Jsonrpc
module Utf16 = Utf16
module Tooling = Cyrograf_tooling.Tooling
module WA = Cyrograf_tooling.Workspace_access

let parse_error = -32700
let invalid_request = -32600
let method_not_found = -32601
let server_not_initialized = -32002
let request_failed = -32803

type document = {
  uri : string;
  path : string;
  version : int;
  language_id : string;
  mutable text : string;
}

type state = {
  oc : out_channel;
  overlays : WA.overlay_store;
  documents : (string, document) Hashtbl.t;
  mutable initialized : bool;
  mutable shutdown_requested : bool;
  server_version : string;
}

let send state json = Jsonrpc.write_message state.oc json

let send_result state id result = send state (Jsonrpc.response id result)

let send_error state id code message =
  send state (Jsonrpc.error_response id code message)

let position line character =
  `Assoc [ ("line", `Int line); ("character", `Int character) ]

let range_of_bytes text start_byte end_byte =
  let start_line, start_character = Utf16.position_of_offset text start_byte in
  let end_line, end_character = Utf16.position_of_offset text end_byte in
  `Assoc
    [ ("start", position start_line start_character);
      ("end", position end_line end_character) ]

let empty_range =
  `Assoc [ ("start", position 0 0); ("end", position 0 0) ]

(* ── URIs ─────────────────────────────────────────────────────────── *)

let hex_value c =
  match c with
  | '0' .. '9' -> Some (Char.code c - Char.code '0')
  | 'a' .. 'f' -> Some (Char.code c - Char.code 'a' + 10)
  | 'A' .. 'F' -> Some (Char.code c - Char.code 'A' + 10)
  | _ -> None

let percent_decode value =
  let buffer = Buffer.create (String.length value) in
  let index = ref 0 in
  while !index < String.length value do
    if value.[!index] = '%' && !index + 2 < String.length value then
      match (hex_value value.[!index + 1], hex_value value.[!index + 2]) with
      | Some high, Some low ->
        Buffer.add_char buffer (Char.chr ((high * 16) + low));
        index := !index + 3
      | _ ->
        Buffer.add_char buffer value.[!index];
        incr index
    else begin
      Buffer.add_char buffer value.[!index];
      incr index
    end
  done;
  Buffer.contents buffer

let is_unreserved c =
  match c with
  | 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '-' | '.' | '_' | '~' | '/' -> true
  | _ -> false

let percent_encode value =
  let buffer = Buffer.create (String.length value) in
  String.iter
    (fun c ->
      if is_unreserved c then Buffer.add_char buffer c
      else Buffer.add_string buffer (Printf.sprintf "%%%02X" (Char.code c)))
    value;
  Buffer.contents buffer

let path_of_uri uri =
  let prefix = "file://" in
  if
    String.length uri < String.length prefix
    || String.sub uri 0 (String.length prefix) <> prefix
  then Error "only file: URIs are supported"
  else
    let rest =
      String.sub uri (String.length prefix) (String.length uri - String.length prefix)
    in
    let rest =
      if String.length rest >= 10 && String.sub rest 0 10 = "localhost/" then
        "/" ^ String.sub rest 10 (String.length rest - 10)
      else rest
    in
    Ok (percent_decode rest)

let uri_of_path path = "file://" ^ percent_encode path

(* ── Snapshot helpers ─────────────────────────────────────────────── *)

let documents_in_directory state directory =
  Hashtbl.fold
    (fun _ (document : document) acc ->
      if Filename.dirname document.path = directory then document :: acc else acc)
    state.documents []
  |> List.sort (fun (a : document) b -> String.compare a.uri b.uri)

let source_text snapshot name =
  match
    List.find_opt
      (fun (source : Tooling.editor_source) -> source.name = name)
      snapshot.Tooling.editor_sources
  with
  | Some source -> source.text
  | None -> ""

let diagnostic_json text (diagnostic : Tooling.editor_diagnostic) =
  let range =
    match (diagnostic.Tooling.start_byte, diagnostic.Tooling.end_byte) with
    | Some start_byte, Some end_byte -> range_of_bytes text start_byte end_byte
    | _ -> empty_range
  in
  `Assoc
    [ ("range", range);
      ("severity", `Int 1);
      ("code", `String diagnostic.Tooling.code);
      ("source", `String "cyrograf");
      ("message", `String diagnostic.Tooling.message) ]

let publish_diagnostics state directory =
  match Tooling.editor_open ~directory ~store:state.overlays with
  | Error _ -> ()
  | Ok snapshot ->
    let module_files = Hashtbl.create 16 in
    List.iter
      (fun (source : Tooling.editor_source) ->
        List.iter
          (fun (symbol : Tooling.editor_symbol) ->
            if symbol.Tooling.kind = "module" then
              Hashtbl.replace module_files symbol.Tooling.name symbol.Tooling.file)
          (Tooling.editor_symbols snapshot source.Tooling.name))
      snapshot.Tooling.editor_sources;
    let diagnostics = Tooling.editor_diagnostics snapshot in
    List.iter
      (fun (document : document) ->
        let file = Filename.basename document.path in
        let text = source_text snapshot file in
        let relevant =
          List.filter
            (fun (diagnostic : Tooling.editor_diagnostic) ->
              match diagnostic.Tooling.file with
              | Some name -> name = file
              | None -> (
                match diagnostic.Tooling.path with
                | module_ :: _ -> Hashtbl.find_opt module_files module_ = Some file
                | [] -> false))
            diagnostics
        in
        send state
          (Jsonrpc.notification "textDocument/publishDiagnostics"
             (`Assoc
               [ ("uri", `String document.uri);
                 ("version", `Int document.version);
                 ("diagnostics", `List (List.map (diagnostic_json text) relevant)) ])))
      (documents_in_directory state directory)

let refresh_directory state directory = publish_diagnostics state directory

let clear_diagnostics state (document : document) =
  send state
    (Jsonrpc.notification "textDocument/publishDiagnostics"
       (`Assoc
         [ ("uri", `String document.uri);
           ("diagnostics", `List []) ]))

(* ── Capabilities ─────────────────────────────────────────────────── *)

let capabilities _state =
  `Assoc
    [ ("positionEncoding", `String "utf-16");
      ( "textDocumentSync",
        `Assoc
          [ ("openClose", `Bool true);
            ("change", `Int 1);
            ("save", `Bool true) ] );
      ("hoverProvider", `Bool true);
      ("definitionProvider", `Bool true);
      ("documentSymbolProvider", `Bool true);
      ("completionProvider", `Assoc []);
      ("documentFormattingProvider", `Bool true) ]

(* ── Requests ─────────────────────────────────────────────────────── *)

let text_document_uri params =
  Jsonrpc.string (Jsonrpc.member "uri" (Jsonrpc.member "textDocument" params))

let request_position params =
  let value = Jsonrpc.member "position" params in
  (Jsonrpc.int (Jsonrpc.member "line" value),
   Jsonrpc.int (Jsonrpc.member "character" value))

let snapshot_for state (document : document) =
  Tooling.editor_open ~directory:(Filename.dirname document.path)
    ~store:state.overlays

let handle_hover state id params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> send_result state id `Null
  | Some document ->
    let line, character = request_position params in
    let offset = Utf16.offset_of_position document.text ~line ~character in
    let file = Filename.basename document.path in
    (match snapshot_for state document with
     | Error _ -> send_result state id `Null
     | Ok snapshot -> (
       match Tooling.editor_describe snapshot ~file ~offset with
       | Some value ->
         send_result state id
           (`Assoc
             [ ("contents",
                 `Assoc [ ("kind", `String "plaintext"); ("value", `String value) ]) ])
       | None -> send_result state id `Null))

let handle_definition state id params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> send_result state id `Null
  | Some document ->
    let line, character = request_position params in
    let offset = Utf16.offset_of_position document.text ~line ~character in
    let file = Filename.basename document.path in
    let directory = Filename.dirname document.path in
    (match snapshot_for state document with
     | Error _ -> send_result state id `Null
     | Ok snapshot -> (
       match Tooling.editor_definition snapshot ~file ~offset with
       | None -> send_result state id `Null
       | Some location ->
         let text = source_text snapshot location.Tooling.file in
         let target = Filename.concat directory location.Tooling.file in
         send_result state id
           (`Assoc
             [ ("uri", `String (uri_of_path target));
               ( "range",
                 range_of_bytes text location.Tooling.start_byte
                   location.Tooling.end_byte ) ])))

let symbol_kind = function
  | "struct" -> 23
  | "variant" -> 10
  | "field" -> 8
  | "constructor" -> 9
  | "method" -> 6
  | _ -> 0

let handle_document_symbol state id params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> send_result state id (`List [])
  | Some document ->
    let file = Filename.basename document.path in
    (match snapshot_for state document with
     | Error _ -> send_result state id (`List [])
     | Ok snapshot ->
       let text = source_text snapshot file in
       let items =
         List.filter_map
           (fun (symbol : Tooling.editor_symbol) ->
             let kind = symbol_kind symbol.Tooling.kind in
             if kind = 0 || symbol.Tooling.decl_end_byte <= symbol.Tooling.decl_start_byte
             then None
             else
               Some
                 (`Assoc
                   [ ("name", `String symbol.Tooling.name);
                     ("kind", `Int kind);
                     ( "range",
                       range_of_bytes text symbol.Tooling.decl_start_byte
                         symbol.Tooling.decl_end_byte );
                     ( "selectionRange",
                       range_of_bytes text symbol.Tooling.start_byte
                         symbol.Tooling.end_byte ) ]))
           (Tooling.editor_symbols snapshot file)
       in
       send_result state id (`List items))

let handle_completion state id params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> send_result state id (`Assoc [ ("isIncomplete", `Bool false); ("items", `List []) ])
  | Some document ->
    let line, character = request_position params in
    let offset = Utf16.offset_of_position document.text ~line ~character in
    let file = Filename.basename document.path in
    (match snapshot_for state document with
     | Error _ ->
       send_result state id (`Assoc [ ("isIncomplete", `Bool false); ("items", `List []) ])
     | Ok snapshot ->
       let names = Tooling.editor_complete snapshot ~file ~offset in
       let items =
         List.map (fun name -> `Assoc [ ("label", `String name) ]) names
       in
       send_result state id
         (`Assoc [ ("isIncomplete", `Bool false); ("items", `List items) ]))

let handle_formatting state id params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> send_result state id (`List [])
  | Some document ->
    let file = Filename.basename document.path in
    if not (Filename.check_suffix file ".cyrograf") then
      send_error state id request_failed
        "the formatter accepts native .cyrograf sources only"
    else
      match Tooling.editor_format ~name:file ~text:document.text with
      | Error errors ->
        let message =
          match errors with
          | [] -> "the document cannot be formatted"
          | first :: _ ->
            Printf.sprintf "%s: %s" first.Tooling.code first.Tooling.message
        in
        send_error state id request_failed message
      | Ok formatted ->
        if formatted = document.text then send_result state id (`List [])
        else
          let length = String.length document.text in
          let edit =
            `Assoc
              [ ( "range",
                  range_of_bytes document.text 0 length );
                ("newText", `String formatted) ]
          in
          send_result state id (`List [ edit ])

let handle_request state id meth params =
  if not state.initialized then
    send_error state id server_not_initialized "server not initialized"
  else if state.shutdown_requested then
    send_error state id invalid_request "server is shutting down"
  else
    match meth with
    | "textDocument/hover" -> handle_hover state id params
    | "textDocument/definition" -> handle_definition state id params
    | "textDocument/documentSymbol" -> handle_document_symbol state id params
    | "textDocument/completion" -> handle_completion state id params
    | "textDocument/formatting" -> handle_formatting state id params
    | _ -> send_error state id method_not_found (Printf.sprintf "unknown request %S" meth)

(* ── Notifications ────────────────────────────────────────────────── *)

let show_message state message =
  send state
    (Jsonrpc.notification "window/showMessage"
       (`Assoc [ ("type", `Int 1); ("message", `String message) ]))

let handle_did_open state params =
  let document = Jsonrpc.member "textDocument" params in
  let uri = Jsonrpc.string (Jsonrpc.member "uri" document) in
  match path_of_uri uri with
  | Error message -> show_message state (Printf.sprintf "%s: %s" uri message)
  | Ok path ->
    let version = Jsonrpc.int (Jsonrpc.member "version" document) in
    let language_id = Jsonrpc.string (Jsonrpc.member "languageId" document) in
    let text = Jsonrpc.string (Jsonrpc.member "text" document) in
    ignore (WA.apply_overlay state.overlays ~path ~version ~text);
    Hashtbl.replace state.documents uri
      { uri; path; version; language_id; text };
    refresh_directory state (Filename.dirname path)

let handle_did_change state params =
  let document = Jsonrpc.member "textDocument" params in
  let uri = Jsonrpc.string (Jsonrpc.member "uri" document) in
  match Hashtbl.find_opt state.documents uri with
  | None -> ()
  | Some current ->
    let version = Jsonrpc.int (Jsonrpc.member "version" document) in
    if version <= current.version then ()
    else begin
      let changes = Jsonrpc.list (Jsonrpc.member "contentChanges" params) in
      let text =
        match List.rev changes with
        | last :: _ -> Jsonrpc.string (Jsonrpc.member "text" last)
        | [] -> current.text
      in
      ignore (WA.apply_overlay state.overlays ~path:current.path ~version ~text);
      current.text <- text;
      Hashtbl.replace state.documents uri { current with version; text };
      refresh_directory state (Filename.dirname current.path)
    end

let handle_did_save state params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> ()
  | Some document -> refresh_directory state (Filename.dirname document.path)

let handle_did_close state params =
  let uri = text_document_uri params in
  match Hashtbl.find_opt state.documents uri with
  | None -> ()
  | Some document ->
    clear_diagnostics state document;
    Hashtbl.remove state.documents uri;
    WA.close_overlay state.overlays ~path:document.path;
    refresh_directory state (Filename.dirname document.path)

let handle_watched_files state =
  let directories =
    Hashtbl.fold
      (fun _ (document : document) acc ->
        let directory = Filename.dirname document.path in
        if List.mem directory acc then acc else directory :: acc)
      state.documents []
  in
  List.iter (refresh_directory state) directories

let handle_notification state meth params =
  match meth with
  | "initialized" -> ()
  | "textDocument/didOpen" -> handle_did_open state params
  | "textDocument/didChange" -> handle_did_change state params
  | "textDocument/didSave" -> handle_did_save state params
  | "textDocument/didClose" -> handle_did_close state params
  | "workspace/didChangeWatchedFiles" -> handle_watched_files state
  | _ -> ()

(* ── Dispatch and run loop ────────────────────────────────────────── *)

let run ~version ~ic ~oc () =
  let state =
    { oc;
      overlays = WA.create_overlay_store ();
      documents = Hashtbl.create 16;
      initialized = false;
      shutdown_requested = false;
      server_version = version }
  in
  let handle_initialize id =
    if state.initialized then
      send_error state id invalid_request "the server is already initialized"
    else begin
      state.initialized <- true;
      send_result state id
        (`Assoc
          [ ("capabilities", capabilities state);
            ( "serverInfo",
              `Assoc
                [ ("name", `String "cyrograf");
                  ("version", `String state.server_version) ] ) ])
    end
  in
  let rec loop () =
    match Jsonrpc.read_message ic with
    | Jsonrpc.Eof -> 0
    | Jsonrpc.Parse_error message ->
      send_error state `Null parse_error message;
      loop ()
    | Jsonrpc.Message json ->
      let meth = Jsonrpc.string (Jsonrpc.member "method" json) in
      let id = Jsonrpc.member "id" json in
      let params = Jsonrpc.member "params" json in
      let is_request = match id with `Null -> false | _ -> true in
      if meth = "" then loop ()
      else if meth = "exit" then if state.shutdown_requested then 0 else 1
      else if meth = "initialize" then begin
        if is_request then handle_initialize id;
        loop ()
      end
      else if not state.initialized then begin
        if is_request then
          send_error state id server_not_initialized "server not initialized";
        loop ()
      end
      else if meth = "shutdown" then begin
        state.shutdown_requested <- true;
        send_result state id `Null;
        loop ()
      end
      else if state.shutdown_requested then begin
        if is_request then
          send_error state id invalid_request "server is shutting down";
        loop ()
      end
      else if is_request then begin
        handle_request state id meth params;
        loop ()
      end
      else begin
        handle_notification state meth params;
        loop ()
      end
  in
  loop ()