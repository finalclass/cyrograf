(* The public analysis facade.

   It selects the frontend by file extension, attaches source names to
   frontend diagnostics and runs the single shared [Semantics] activity. Editor
   queries read the same index; no adapter re-implements language rules. *)

module Kernel = Kernel
module Diag = Cyrograf.Error
module S = Syntax

type source = Kernel.source = {
  name : string;
  text : string;
}

type analysis = {
  documents : S.document list;
  semantics : Semantics.result;
}

let parse_source { name; text } =
  match S.extension name with
  | ".cyrograf" -> Native_parser.parse ~name ~text
  | ".toml" -> Toml_frontend.parse ~name ~text
  | _ ->
    ({ S.name; text; declarations = []; comments = [] },
     [ Diagnostic.make ~code:Diag.Code.unsupported_source_format
         (Printf.sprintf "%s is not a contract source" name) ])

let with_source name diagnostic =
  match (diagnostic.Diagnostic.range, diagnostic.error.source) with
  | Some _, _ -> diagnostic
  | None, Some _ -> diagnostic
  | None, None ->
    { diagnostic with
      error = Diag.with_source { Diag.name; line = None; column = None } diagnostic.error }

let module_files documents =
  let table = Hashtbl.create 16 in
  List.iter
    (fun document ->
      let module_name = S.module_name_of_file document.S.name in
      if not (Hashtbl.mem table module_name) then
        Hashtbl.add table module_name document.S.name)
    documents;
  table

let attach_semantic_sources documents diagnostics =
  let table = module_files documents in
  let fallback =
    match documents with [ document ] -> Some document.S.name | _ -> None
  in
  List.map
    (fun diagnostic ->
      match (diagnostic.Diagnostic.range, diagnostic.error.source) with
      | Some _, _ | None, Some _ -> diagnostic
      | None, None ->
        let from_path =
          match diagnostic.error.path with
          | segment :: _ -> Hashtbl.find_opt table segment
          | [] -> None
        in
        let name = match from_path with Some name -> Some name | None -> fallback in
        (match name with
         | Some name -> with_source name diagnostic
         | None -> diagnostic))
    diagnostics

let analyze ~sources =
  if sources = [] then
    { documents = [];
      semantics =
        { Semantics.schema = { Cyrograf.Schema.modules = [] };
          diagnostics =
            [ Diagnostic.make ~code:Diag.Code.empty_sources "no source files" ];
          index = [] } }
  else begin
    let parsed = List.map parse_source sources in
    let documents = List.map fst parsed in
    let frontend_diagnostics =
      List.concat
        (List.map2
           (fun ({ name; _ } : source) (_, diagnostics) ->
             List.map (with_source name) diagnostics)
           sources parsed)
    in
    let semantic = Semantics.analyze documents in
    let semantic_diagnostics =
      attach_semantic_sources documents semantic.Semantics.diagnostics
    in
    { documents;
      semantics =
        { semantic with
          Semantics.diagnostics = frontend_diagnostics @ semantic_diagnostics } }
  end

let schema result =
  if result.semantics.Semantics.diagnostics = [] then Ok result.semantics.Semantics.schema
  else Error result.semantics.Semantics.diagnostics

let compile_sources ~sources =
  let result = analyze ~sources in
  match schema result with
  | Ok schema -> Ok schema
  | Error diagnostics ->
    let texts = Hashtbl.create 16 in
    List.iter (fun (source : source) -> Hashtbl.replace texts source.name source.text) sources;
    Error
      (List.map
         (fun diagnostic ->
           let text =
             Option.bind (Diagnostic.source_name diagnostic)
               (fun name -> Hashtbl.find_opt texts name)
           in
           Diagnostic.to_error ?text diagnostic)
         diagnostics)

let diagnostics result = result.semantics.Semantics.diagnostics
let documents result = result.documents
let index result = result.semantics.Semantics.index

let symbols result file = Semantics.symbols_for result.semantics file

let definition result ~file ~offset =
  Semantics.definition result.semantics file offset

let describe result ~file ~offset = Semantics.describe result.semantics file offset

let declared_names result =
  List.filter_map
    (fun (symbol : Semantics.symbol) ->
      match (symbol.self, symbol.kind) with
      | Some qualified, (Semantics.Struct | Semantics.Variant) ->
        Some (Cyrograf.Schema.qualified_name qualified)
      | _ -> None)
    result.semantics.Semantics.index

let complete result ~file ~offset =
  match List.find_opt (fun document -> document.S.name = file) result.documents with
  | None -> []
  | Some document ->
    let is_ident_char c =
      (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z')
      || (c >= '0' && c <= '9') || c = '_'
    in
    let dot_prefix =
      let text = document.S.text in
      if offset <= 0 || offset > String.length text then None
      else if text.[offset - 1] <> '.' then None
      else begin
        let index = ref (offset - 2) in
        while !index >= 0 && is_ident_char text.[!index] do
          decr index
        done;
        let start = !index + 1 in
        if start >= offset - 1 then None
        else Some (String.sub text start (offset - 1 - start))
      end
    in
    (match dot_prefix with
     | Some prefix ->
       let expected = prefix ^ "." in
       let messages =
         List.filter_map
           (fun qualified ->
             if String.length qualified > String.length expected
                && String.sub qualified 0 (String.length expected) = expected
             then
               Some
                 (String.sub qualified (String.length expected)
                    (String.length qualified - String.length expected))
             else None)
           (declared_names result)
       in
       List.sort_uniq String.compare messages
     | None ->
    let inside_type = ref false in
    let inside_declaration = ref false in
    let contains span = S.Span.contains span offset in
    List.iter
      (fun declaration ->
        if contains (S.declaration_span declaration) then inside_declaration := true;
        match declaration with
        | S.Struct structure ->
          List.iter
            (fun (field : S.field) -> if contains field.type_.S.span then inside_type := true)
            structure.fields
        | S.Variant variant ->
          List.iter
            (fun (constructor : S.constructor) ->
              match constructor.payload with
              | Some payload when contains payload.S.span -> inside_type := true
              | _ -> ())
            variant.constructors
        | S.Rpc method_ ->
          if contains method_.request.S.span || contains method_.response.S.span then
            inside_type := true)
      document.S.declarations;
    if !inside_type then begin
      let primitives =
        [ "String"; "Int"; "Float"; "Bool"; "Void"; "Date"; "Record"; "List" ]
      in
      let module_name = S.module_name_of_file file in
      let local, qualified =
        List.fold_left
          (fun (local, qualified) name ->
            if String.length name > String.length module_name
               && String.sub name 0 (String.length module_name + 1) = module_name ^ "."
            then
              let short = String.sub name (String.length module_name + 1)
                  (String.length name - String.length module_name - 1) in
              (short :: local, name :: qualified)
            else (local, name :: qualified))
          ([], []) (declared_names result)
      in
      let names = List.sort_uniq String.compare (local @ qualified) in
      List.sort_uniq String.compare (primitives @ names)
    end
    else if not !inside_declaration then [ "struct"; "variant"; "rpc" ]
    else [])