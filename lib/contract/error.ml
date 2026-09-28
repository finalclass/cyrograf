type source = {
  name : string;
  line : int option;
  column : int option;
}

type t = {
  code : string;
  message : string;
  path : string list;
  source : source option;
}

let make ?source ?(path = []) ~code message =
  { code; message; path; source }

let with_segment segment error =
  { error with path = segment :: error.path }

let with_source source error =
  match error.source with
  | Some _ -> error
  | None -> { error with source = Some source }

let string_of_source (source : source) =
  let position =
    match (source.line, source.column) with
    | None, _ -> ""
    | Some line, None -> Printf.sprintf ":%d" line
    | Some line, Some column -> Printf.sprintf ":%d:%d" line column
  in
  source.name ^ position

let to_string (error : t) =
  let location =
    match error.source with
    | Some source -> string_of_source source ^ ": "
    | None -> ""
  in
  let path =
    match error.path with
    | [] -> ""
    | segments -> " (" ^ String.concat "." segments ^ ")"
  in
  Printf.sprintf "%s[%s]%s %s" location error.code path error.message

module Code = struct
  let invalid_toml = "InvalidToml"
  let invalid_syntax = "InvalidSyntax"
  let invalid_source_encoding = "InvalidSourceEncoding"
  let unsupported_source_format = "UnsupportedSourceFormat"
  let source_changed = "SourceChanged"
  let invalid_json = "InvalidJson"
  let duplicate_key = "DuplicateKey"
  let non_finite = "NonFiniteNumber"
  let unknown_type = "UnknownType"
  let unknown_key = "UnknownKey"
  let missing_kind = "MissingMessageKind"
  let missing_of = "MissingListElement"
  let invalid_optional = "InvalidOptional"
  let invalid_type = "InvalidType"
  let invalid_name = "InvalidName"
  let invalid_rpc = "InvalidRpc"
  let empty_variant = "EmptyVariant"
  let struct_and_variant = "StructAndVariant"
  let duplicate = "DuplicateDeclaration"
  let unresolved_reference = "UnresolvedReference"
  let cycle = "CyclicReference"
  let unsupported_framework_type = "UnsupportedFrameworkType"
  let unsupported_extension = "UnsupportedExtension"
  let name_collision = "NameCollision"
  let empty_sources = "EmptySources"
  let empty_targets = "EmptyTargets"
  let duplicate_target = "DuplicateTarget"
  let type_mismatch = "TypeMismatch"
  let unexpected_length = "UnexpectedLength"
  let int_out_of_range = "IntOutOfRange"
  let invalid_int = "InvalidInt"
  let invalid_float = "InvalidFloat"
  let unknown_variant_tag = "UnknownVariantTag"
  let invalid_variant = "InvalidVariant"
  let migration_mismatch = "MigrationMismatch"
  let io_error = "IoError"
  let foreign_file = "ForeignOutputFile"
  let unknown_target = "UnknownTarget"
  let usage = "Usage"
end