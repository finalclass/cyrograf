(* Tooling: compositions of the same analysis, validation and access
   components. CLI command handlers do not re-implement language or I/O
   rules; they select arguments and present results. *)

module Error = Cyrograf.Error
module CC = Cyrograf_compiler
module Workspace_access = Workspace_access
module Artifact_access = Artifact_access

let error code message = Error.make ~code message

let check ~directory ~targets =
  match Workspace_access.capture ~directory with
  | Error errors -> Error errors
  | Ok snapshot -> (
    match CC.compile ~sources:snapshot.Workspace_access.sources with
    | Error errors -> Error errors
    | Ok schema -> (
      match CC.validate ~targets ~schema with
      | Error errors -> Error errors
      | Ok () -> Ok (List.length schema.Cyrograf.Schema.modules)))

let build ?ocaml_profile ?ocaml_library ~directory ~output ~targets ~go_module () =
  match Workspace_access.capture ~directory with
  | Error errors -> Error errors
  | Ok snapshot -> (
    match CC.compile ~sources:snapshot.Workspace_access.sources with
    | Error errors -> Error errors
    | Ok schema -> (
      match
        CC.Generator.generate ?ocaml_profile ?ocaml_library ~go_module ~targets
          ~schema ()
      with
      | Error errors -> Error errors
      | Ok generated ->
        let descriptor =
          { CC.path = "schema.json"; contents = CC.Descriptor.schema_json schema }
        in
        Artifact_access.publish ~directory ~output
          ~artifacts:(generated @ [ descriptor ])))

let format
    ?(access = (module Workspace_access : Workspace_access.FORMAT_ACCESS))
    ~paths ~check () =
  let module Access = (val access : Workspace_access.FORMAT_ACCESS) in
  match Access.capture_native ~paths with
  | Error errors -> Error errors
  | Ok snapshot ->
    let changed = ref [] in
    let edits = ref [] in
    let errors = ref [] in
    List.iter
      (fun (source : Workspace_access.native_source) ->
        match CC.format ~name:source.Workspace_access.name ~text:source.Workspace_access.text with
        | Error source_errors -> errors := source_errors @ !errors
        | Ok formatted ->
          if formatted <> source.Workspace_access.text then begin
            changed := source.Workspace_access.path :: !changed;
            edits := (source.Workspace_access.path, formatted) :: !edits
          end)
      snapshot.Workspace_access.native_sources;
    if !errors <> [] then Error (List.rev !errors)
    else if check then Ok (List.rev !changed)
    else (
      match Access.replace_native snapshot (List.rev !edits) with
      | Error errors -> Error errors
      | Ok () -> Ok (List.rev !changed))

(* ── Editor composition ───────────────────────────────────────────── *)

let all_targets =
  [ CC.Ocaml; CC.Typescript; CC.Go; CC.Dart; CC.Python; CC.Java; CC.Csharp;
    CC.Rust ]

type editor_source = {
  name : string;
  text : string;
}

type editor_location = {
  file : string;
  start_byte : int;
  end_byte : int;
}

type editor_symbol = {
  file : string;
  name : string;
  kind : string;
  start_byte : int;
  end_byte : int;
  decl_start_byte : int;
  decl_end_byte : int;
}

type editor_diagnostic = {
  code : string;
  message : string;
  path : string list;
  file : string option;
  start_byte : int option;
  end_byte : int option;
}

type editor_snapshot = {
  editor_sources : editor_source list;
  editor_analysis : CC.Analysis.result;
}

let editor_open ~directory ~store =
  match Workspace_access.capture_editor ~directory ~store with
  | Error errors -> Error errors
  | Ok sources ->
    Ok
      { editor_sources =
          List.map
            (fun (source : Workspace_access.source) ->
              { name = source.name; text = source.text })
            sources;
        editor_analysis =
          CC.Analysis.analyze
            ~sources:
              (List.map
                 (fun (source : Workspace_access.source) ->
                   { CC.name = source.name; text = source.text })
                 sources) }

let to_diagnostic (value : CC.Analysis.diagnostic) : editor_diagnostic =
  { code = value.code;
    message = value.message;
    path = value.path;
    file = value.file;
    start_byte = value.start_byte;
    end_byte = value.end_byte }

let error_diagnostic (error : Error.t) : editor_diagnostic =
  { code = error.Error.code;
    message = error.Error.message;
    path = error.Error.path;
    file =
      (match error.Error.source with Some source -> Some source.name | None -> None);
    start_byte = None;
    end_byte = None }

let editor_diagnostics snapshot =
  let diagnostics =
    List.map to_diagnostic (CC.Analysis.diagnostics snapshot.editor_analysis)
  in
  match CC.Analysis.schema snapshot.editor_analysis with
  | Error _ -> diagnostics
  | Ok schema -> (
    match CC.validate ~targets:all_targets ~schema with
    | Error errors -> diagnostics @ List.map error_diagnostic errors
    | Ok () -> diagnostics)

let editor_describe snapshot ~file ~offset =
  CC.Analysis.describe snapshot.editor_analysis ~file ~offset

let editor_definition snapshot ~file ~offset =
  match CC.Analysis.definition snapshot.editor_analysis ~file ~offset with
  | None -> None
  | Some location ->
    Some
      { file = location.CC.Analysis.file;
        start_byte = location.start_byte;
        end_byte = location.end_byte }

let editor_symbols snapshot file =
  List.map
    (fun (symbol : CC.Analysis.symbol) ->
      { file = symbol.file;
        name = symbol.name;
        kind = symbol.kind;
        start_byte = symbol.start_byte;
        end_byte = symbol.end_byte;
        decl_start_byte = symbol.decl_start_byte;
        decl_end_byte = symbol.decl_end_byte })
    (CC.Analysis.symbols snapshot.editor_analysis file)

let editor_complete snapshot ~file ~offset =
  CC.Analysis.complete snapshot.editor_analysis ~file ~offset

let editor_format ~name ~text =
  match CC.format ~name ~text with
  | Ok formatted -> Ok formatted
  | Error errors -> Error (List.map error_diagnostic errors)

let migrate ~directory ~output =
  match Workspace_access.capture ~directory with
  | Error errors -> Error errors
  | Ok snapshot -> (
    match CC.migrate ~sources:snapshot.Workspace_access.sources with
    | Error errors -> Error errors
    | Ok migration -> (
      match
        Artifact_access.publish ~directory ~output
          ~artifacts:migration.CC.artifacts
      with
      | Error errors -> Error errors
      | Ok paths -> Ok (paths, migration.CC.comments_moved)))