module Generator = Generator
module Descriptor = Descriptor
module Info = Info
module Internal = Analysis
module Error = Cyrograf.Error

type source = Generator.source = {
  name : string;
  text : string;
}

type target = Generator.target =
  | Ocaml
  | Typescript
  | Go
  | Dart
  | Python
  | Java
  | Csharp
  | Rust

type ocaml_profile = Generator.ocaml_profile =
  | Native
  | Js

type artifact = Generator.artifact = {
  path : string;
  contents : string;
}

let compile = Generator.compile

let generate ?ocaml_profile ?ocaml_library ~targets ~schema () =
  Generator.generate ?ocaml_profile ?ocaml_library ~targets ~schema ()

let validate ~targets ~schema = Generator.validate ~targets ~schema

type migration = {
  artifacts : artifact list;
  comments_moved : bool;
}

let output_name source_name = Syntax.module_name_of_file source_name ^ ".cyrograf"

let format ~name ~text = Layout.format_source ~name ~text

let migrate ~sources =
  match compile ~sources with
  | Error errors -> Error errors
  | Ok schema_in ->
    let comments_moved = ref false in
    let conversion_errors = ref [] in
    let artifacts =
      List.filter_map
        (fun (source : source) ->
          match Syntax.extension source.name with
          | ".cyrograf" ->
            Some { path = output_name source.name; contents = source.text }
          | ".toml" ->
            let document, diagnostics =
              Toml_frontend.parse ~name:source.name ~text:source.text
            in
            let frontend_errors =
              List.map (fun (d : Diagnostic.t) -> d.Diagnostic.error) diagnostics
            in
            if frontend_errors <> [] then begin
              conversion_errors := frontend_errors @ !conversion_errors;
              None
            end
            else begin
              if document.Syntax.comments <> [] then comments_moved := true;
              let text =
                Layout.print_declarations
                  ~comments:document.Syntax.comments
                  document.Syntax.declarations
              in
              Some { path = output_name source.name; contents = text }
            end
          | _ ->
            conversion_errors :=
              Error.make ~code:Error.Code.unsupported_source_format
                (Printf.sprintf "%s is not a contract source" source.name)
              :: !conversion_errors;
            None)
        sources
    in
    if !conversion_errors <> [] then Error (List.rev !conversion_errors)
    else begin
      let artifacts =
        List.sort
          (fun (a : artifact) b -> String.compare a.path b.path)
          artifacts
      in
      let output_sources =
        List.map (fun (a : artifact) -> { name = a.path; text = a.contents }) artifacts
      in
      match compile ~sources:output_sources with
      | Error errors -> Error errors
      | Ok schema_out ->
        if schema_in <> schema_out then
          Error
            [ Error.make ~code:Error.Code.migration_mismatch
                "the migrated project does not have the same schema" ]
        else begin
          let targets =
            [ Ocaml; Typescript; Go; Dart; Python; Java; Csharp; Rust ]
          in
          match
            ( generate ~targets ~schema:schema_in (),
              generate ~targets ~schema:schema_out () )
          with
          | Ok before, Ok after when before = after ->
            Ok { artifacts; comments_moved = !comments_moved }
          | Ok _, Ok _ ->
            Error
              [ Error.make ~code:Error.Code.migration_mismatch
                  "the migrated project generates different artifacts" ]
          | Error errors, _ | _, Error errors -> Error errors
        end
    end

module Analysis = struct
  type result = Internal.analysis

  type location = {
    file : string;
    start_byte : int;
    end_byte : int;
  }

  type diagnostic = {
    code : string;
    message : string;
    path : string list;
    file : string option;
    start_byte : int option;
    end_byte : int option;
  }

  type symbol = {
    file : string;
    name : string;
    kind : string;
    start_byte : int;
    end_byte : int;
    decl_start_byte : int;
    decl_end_byte : int;
  }

  let analyze = Internal.analyze

  let location file span =
    { file; start_byte = span.Syntax.Span.start_byte; end_byte = span.end_byte }

  let diagnostic (value : Diagnostic.t) =
    let file, start_byte, end_byte =
      match value.range with
      | Some range -> (Some range.source, Some range.start_byte, Some range.end_byte)
      | None ->
        ( (match value.error.source with Some source -> Some source.name | None -> None),
          None,
          None )
    in
    { code = value.error.code;
      message = value.error.message;
      path = value.error.path;
      file;
      start_byte;
      end_byte }

  let diagnostics result = List.map diagnostic (Internal.diagnostics result)

  let schema result =
    match Internal.schema result with
    | Ok schema -> Ok schema
    | Error errors -> Error (List.map diagnostic errors)

  let kind_text = function
    | Semantics.Module -> "module"
    | Semantics.Struct -> "struct"
    | Semantics.Variant -> "variant"
    | Semantics.Field -> "field"
    | Semantics.Constructor -> "constructor"
    | Semantics.Method -> "method"
    | Semantics.Type_ref -> "type_ref"
    | Semantics.Rpc_ref -> "rpc_ref"

  let symbol (value : Semantics.symbol) =
    { file = value.file;
      name = value.name;
      kind = kind_text value.kind;
      start_byte = value.name_span.Syntax.Span.start_byte;
      end_byte = value.name_span.end_byte;
      decl_start_byte = value.decl_span.Syntax.Span.start_byte;
      decl_end_byte = value.decl_span.end_byte }

  let symbols result file = List.map symbol (Internal.symbols result file)

  let definition result ~file ~offset =
    match Internal.definition result ~file ~offset with
    | None -> None
    | Some (file, span) -> Some (location file span)

  let describe = Internal.describe
  let complete = Internal.complete
end