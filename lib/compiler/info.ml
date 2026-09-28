(* Public projection of generated names and artifact paths for integrators.

   An adapter (for example Well binding a schema to generated symbols) needs the
   canonical schema names together with the target-specific symbol and file for
   the generated module. This projection is pure: it performs no I/O, emits no
   artifact and does not extend the public conversion API of a message beyond
   [to_drut]/[from_drut]. It reuses the same naming rules as the generators
   instead of exposing the private [Naming] module. *)

type target = Kernel.target =
  | Ocaml
  | Typescript
  | Go
  | Dart
  | Python
  | Java
  | Csharp
  | Rust

let target_name = function
  | Ocaml -> "ocaml"
  | Typescript -> "typescript"
  | Go -> "go"
  | Dart -> "dart"
  | Python -> "python"
  | Java -> "java"
  | Csharp -> "csharp"
  | Rust -> "rust"

let module_symbol target ~module_name =
  match target with
  | Ocaml -> Naming.ocaml_module_ref module_name
  | Typescript -> module_name
  | Go -> Naming.go_package_name module_name
  | Dart -> Naming.snake_case module_name
  | Python -> Naming.python_module_name module_name
  | Java -> Naming.java_class_name module_name
  | Csharp -> Naming.csharp_type_name module_name
  | Rust -> Naming.rust_module_name module_name

let message_symbol target ~message_name =
  match target with
  | Ocaml | Typescript | Dart | Python -> message_name
  | Go -> Naming.go_public_name message_name
  | Java -> Naming.java_class_name message_name
  | Csharp -> Naming.csharp_type_name message_name
  | Rust -> Naming.rust_type_name message_name

(** The target-specific qualified reference of a message, built from
    [module_symbol] and [message_symbol] where the target nests messages. *)
let qualified_message target ~module_name ~message_name =
  let message = message_symbol target ~message_name in
  match target with
  | Ocaml | Typescript -> module_symbol target ~module_name ^ "." ^ message
  | Go -> module_symbol target ~module_name ^ "." ^ message
  | Dart -> module_symbol target ~module_name ^ "." ^ message
  | Python -> module_symbol target ~module_name ^ "." ^ message
  | Java -> module_symbol target ~module_name ^ "." ^ message
  | Csharp -> "GeneratedContracts." ^ module_symbol target ~module_name ^ "." ^ message
  | Rust -> module_symbol target ~module_name ^ "::" ^ message

let normalize_field target =
  match target with
  | Ocaml -> Naming.ocaml_field
  | Typescript -> Naming.ts_camel_case
  | Go -> Naming.go_public_name
  | Dart -> Naming.dart_camel_case
  | Python -> Naming.python_field
  | Java -> Naming.java_field
  | Csharp -> Naming.csharp_field
  | Rust -> Naming.rust_field

let normalize_method = normalize_field

let data_artifact target ~module_name =
  match target with
  | Ocaml -> "ocaml/" ^ Naming.ocaml_file module_name
  | Typescript -> "typescript/" ^ Naming.ts_file module_name
  | Go ->
    let package = Naming.go_package_name module_name in
    "go/" ^ package ^ "/" ^ package ^ ".go"
  | Dart -> "dart/" ^ Naming.dart_file module_name
  | Python -> "python/generated_contracts/" ^ Naming.python_file module_name
  | Java ->
    "java/src/main/java/generated_contracts/"
    ^ Naming.java_class_name module_name ^ ".java"
  | Csharp ->
    "csharp/GeneratedContracts." ^ Naming.csharp_type_name module_name ^ ".cs"
  | Rust -> "rust/src/" ^ Naming.rust_file module_name