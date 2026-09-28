(* TOML compatibility frontend.

   It parses the TOML subset described in [docs/toml.md] into the shared
   [Syntax] model. It validates TOML notation only: unknown keys, malformed
   inline tables, a bad signature string, a message declaring both struct and
   variant. Name rules, type meaning, references and ordering are shared with
   the native frontend and live in [Semantics]. *)

module Diag = Cyrograf.Error
module S = Syntax

type frontend = {
  name : string;
  mutable diagnostics : Diagnostic.t list;
}

let diagnostic frontend ?(path = []) ~code message =
  frontend.diagnostics <- Diagnostic.make ~path ~code message :: frontend.diagnostics

let is_upper_ident = S.is_upper_ident
let is_lower_ident = S.is_lower_ident

let name_of_string s =
  match String.split_on_char '.' s with
  | [ module_name; message_name ] when is_upper_ident module_name && is_upper_ident message_name ->
    { S.desc = S.Qualified (module_name, message_name); span = S.Span.empty }
  | _ ->
    let canonical =
      match S.canonical_primitive_name s with Some name -> name | None -> s
    in
    { S.desc = S.Named canonical; span = S.Span.empty }

let allowed_type_keys = [ "type"; "of"; "optional" ]

let parse_type_value frontend ~path ~allow_optional (value : Otoml.t) =
  match value with
  | Otoml.TomlString s -> (name_of_string s, false)
  | Otoml.TomlInlineTable pairs ->
    let optional = ref false in
    List.iter
      (fun (key, _) ->
        if not (List.mem key allowed_type_keys) then
          diagnostic frontend ~path ~code:Diag.Code.unknown_key
            (Printf.sprintf "unknown key %S in a type declaration" key))
      pairs;
    (match List.assoc_opt "optional" pairs with
     | Some (Otoml.TomlBoolean value) when allow_optional -> optional := value
     | Some (Otoml.TomlBoolean _) ->
       diagnostic frontend ~path ~code:Diag.Code.invalid_optional
         "optional is a struct field modifier, not a payload modifier"
     | Some _ ->
       diagnostic frontend ~path ~code:Diag.Code.invalid_optional
         "optional must be a boolean"
     | None -> ());
    let type_string =
      match List.assoc_opt "type" pairs with
      | Some (Otoml.TomlString s) -> Some s
      | Some _ ->
        diagnostic frontend ~path ~code:Diag.Code.invalid_type
          "type must be a string";
        None
      | None ->
        diagnostic frontend ~path ~code:Diag.Code.invalid_type
          "a type declaration requires a type key";
        None
    in
    let desc =
      match type_string with
      | None -> { S.desc = S.Named ""; span = S.Span.empty }
      | Some "list" ->
        (match List.assoc_opt "of" pairs with
         | Some (Otoml.TomlString element) ->
           { S.desc = S.List (name_of_string element); span = S.Span.empty }
         | Some _ ->
           diagnostic frontend ~path ~code:Diag.Code.invalid_type
             "of must be a string";
           { S.desc = S.Named ""; span = S.Span.empty }
         | None ->
           diagnostic frontend ~path ~code:Diag.Code.missing_of
             "a list declaration requires an of key";
           { S.desc = S.Named ""; span = S.Span.empty })
      | Some s ->
        if s <> "list" && List.mem_assoc "of" pairs then
          diagnostic frontend ~path ~code:Diag.Code.unknown_key
            "of is only valid with type = \"list\"";
        name_of_string s
    in
    (desc, !optional)
  | _ ->
    diagnostic frontend ~path ~code:Diag.Code.invalid_type
      "a type must be a string or an inline table";
    ({ S.desc = S.Named ""; span = S.Span.empty }, false)

let table_pairs frontend ~path ~what = function
  | Otoml.TomlTable pairs | Otoml.TomlInlineTable pairs -> Some pairs
  | _ ->
    diagnostic frontend ~path ~code:Diag.Code.invalid_type
      (Printf.sprintf "%s must be a table" what);
    None

let parse_field frontend ~path (name, value) =
  let type_, optional = parse_type_value frontend ~path:(path @ [ name ]) ~allow_optional:true value in
  { S.name;
    name_span = S.Span.empty;
    type_;
    optional;
    span = S.Span.empty }

let parse_constructor frontend ~path (name, value) =
  let payload, _ = parse_type_value frontend ~path:(path @ [ name ]) ~allow_optional:false value in
  { S.name;
    name_span = S.Span.empty;
    payload = Some payload;
    span = S.Span.empty }

let parse_message frontend ~path (name, value) =
  match table_pairs frontend ~path ~what:"a message" value with
  | None -> None
  | Some pairs ->
    List.iter
      (fun (key, _) ->
        if key <> "struct" && key <> "variant" then
          diagnostic frontend ~path ~code:Diag.Code.unknown_key
            (Printf.sprintf "unknown key %S in message %S" key name))
      pairs;
    let struct_value = List.assoc_opt "struct" pairs in
    let variant_value = List.assoc_opt "variant" pairs in
    if struct_value <> None && variant_value <> None then
      diagnostic frontend ~path ~code:Diag.Code.struct_and_variant
        (Printf.sprintf "message %S declares both struct and variant" name);
    match (struct_value, variant_value) with
    | Some struct_value, None ->
      (match table_pairs frontend ~path:(path @ [ "struct" ]) ~what:"struct" struct_value with
       | None -> None
       | Some fields ->
         Some
           (S.Struct
              { name;
                name_span = S.Span.empty;
                span = S.Span.empty;
                fields =
                  List.map
                    (parse_field frontend ~path:(path @ [ "struct" ]))
                    fields }))
    | None, Some variant_value ->
      (match table_pairs frontend ~path:(path @ [ "variant" ]) ~what:"variant" variant_value with
       | None -> None
       | Some constructors ->
         if constructors = [] then begin
           diagnostic frontend ~path:(path @ [ "variant" ])
             ~code:Diag.Code.empty_variant
             (Printf.sprintf "variant %S has no constructors" name);
           None
         end
         else
           Some
             (S.Variant
                { name;
                  name_span = S.Span.empty;
                  span = S.Span.empty;
                  constructors =
                    List.map
                      (parse_constructor frontend ~path:(path @ [ "variant" ]))
                      constructors }))
    | None, None ->
      diagnostic frontend ~path ~code:Diag.Code.missing_kind
        (Printf.sprintf "message %S has neither struct nor variant" name);
      None
    | Some _, Some _ -> None

let split_once needle haystack =
  let needle_length = String.length needle in
  let haystack_length = String.length haystack in
  let rec search i =
    if i + needle_length > haystack_length then None
    else if String.sub haystack i needle_length = needle then
      Some
        (String.sub haystack 0 i,
         String.sub haystack (i + needle_length) (haystack_length - i - needle_length))
    else search (i + 1)
  in
  search 0

let parse_rpc frontend ~path signature =
  match split_once "->" signature with
  | None ->
    diagnostic frontend ~path ~code:Diag.Code.invalid_rpc
      (Printf.sprintf "malformed RPC signature %S, expected \"Request -> Response\"" signature);
    None
  | Some (request, response) ->
    let request = String.trim request in
    let response = String.trim response in
    if request = "" || response = "" then begin
      diagnostic frontend ~path ~code:Diag.Code.invalid_rpc
        (Printf.sprintf "malformed RPC signature %S, expected \"Request -> Response\"" signature);
      None
    end
    else
      Some
        { S.name = "";
          name_span = S.Span.empty;
          span = S.Span.empty;
          request = name_of_string request;
          response = name_of_string response }

let parse_service frontend ~path (value : Otoml.t) =
  match table_pairs frontend ~path ~what:"service" value with
  | None -> []
  | Some pairs ->
    List.iter
      (fun (key, _) ->
        if key <> "rpc" then
          diagnostic frontend ~path ~code:Diag.Code.unknown_key
            (Printf.sprintf "unknown key %S in service" key))
      pairs;
    (match List.assoc_opt "rpc" pairs with
     | None -> []
     | Some rpc_value ->
       (match table_pairs frontend ~path:(path @ [ "rpc" ]) ~what:"service.rpc" rpc_value with
        | None -> []
        | Some method_pairs ->
          List.filter_map
            (fun (name, signature) ->
              match signature with
              | Otoml.TomlString s ->
                (match parse_rpc frontend ~path:(path @ [ "rpc"; name ]) s with
                 | Some method_ -> Some { method_ with S.name }
                 | None -> None)
              | _ ->
                diagnostic frontend ~path:(path @ [ "rpc"; name ])
                  ~code:Diag.Code.invalid_rpc
                  "an RPC signature must be a string";
                None)
            method_pairs))

let bom_length text =
  if String.length text >= 3 && String.sub text 0 3 = "\xEF\xBB\xBF" then 3 else 0

let scan_comments text =
  let length = String.length text in
  let comments = ref [] in
  let index = ref (bom_length text) in
  let in_string = ref false in
  let own_line = ref true in
  while !index < length do
    let start = !index in
    (match text.[start] with
     | '"' -> in_string := not !in_string
     | '\\' when !in_string && start + 1 < length -> incr index
     | '#' when not !in_string ->
       let content_start = start + 1 in
       let stop = ref content_start in
       while !stop < length && text.[!stop] <> '\n' && text.[!stop] <> '\r' do
         incr stop
       done;
       comments :=
         { S.text = String.sub text content_start (!stop - content_start);
           span = S.Span.make start !stop;
           own_line = !own_line }
         :: !comments;
       index := !stop
     | _ -> ());
    (match text.[start] with
     | '\n' | '\r' -> own_line := true
     | ' ' | '\t' -> ()
     | _ -> own_line := false);
    incr index
  done;
  List.rev !comments

let parse ~name ~text =
  let frontend = { name; diagnostics = [] } in
  let comments = scan_comments text in
  let declarations =
    match Otoml.Parser.from_string_result text with
    | Error message ->
      diagnostic frontend ~code:Diag.Code.invalid_toml
        (Printf.sprintf "%s: %s" name message);
      []
    | Ok (Otoml.TomlTable pairs) ->
      let declarations = ref [] in
      List.iter
        (fun (key, value) ->
          match key with
          | "msg" ->
            (match table_pairs frontend ~path:[ "msg" ] ~what:"msg" value with
             | None -> ()
             | Some msg_pairs ->
               List.iter
                 (fun (message_name, msg_value) ->
                   match
                     parse_message frontend ~path:[ "msg"; message_name ]
                       (message_name, msg_value)
                   with
                   | Some declaration -> declarations := declaration :: !declarations
                   | None -> ())
                 msg_pairs)
          | "service" ->
            List.iter
              (fun method_ -> declarations := S.Rpc method_ :: !declarations)
              (parse_service frontend ~path:[ "service" ] value)
          | "actor" ->
            diagnostic frontend ~path:[ "actor" ]
              ~code:Diag.Code.unsupported_extension
              "actor tables belong to a future cell adapter"
          | _ ->
            diagnostic frontend ~path:[]
              ~code:Diag.Code.unknown_key
              (Printf.sprintf "unknown top-level key %S" key))
        pairs;
      List.rev !declarations
    | Ok _ ->
      diagnostic frontend ~code:Diag.Code.invalid_toml
        (Printf.sprintf "%s: the TOML root must be a table" name);
      []
  in
  ({ S.name; text; declarations; comments }, List.rev frontend.diagnostics)