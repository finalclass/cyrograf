(* Orchestration of the frontend and the per-target generators. *)

module Kernel = Kernel
module Schema = Cyrograf.Schema
module Naming = Naming
module Descriptor = Descriptor
module Codegen_ocaml = Codegen_ocaml
module Codegen_python = Codegen_python
module Codegen_java = Codegen_java
module Codegen_csharp = Codegen_csharp
module Codegen_rust = Codegen_rust

type source = Kernel.source = {
  name : string;
  text : string;
}

type target = Kernel.target =
  | Ocaml
  | Typescript
  | Go
  | Dart
  | Python
  | Java
  | Csharp
  | Rust

type format = Kernel.format = Wire_v1

type ocaml_profile = Kernel.ocaml_profile =
  | Native
  | Js

type artifact = Kernel.artifact = {
  path : string;
  contents : string;
}

let compile ~sources = Analysis.compile_sources ~sources

let target_name = function
  | Ocaml -> "ocaml"
  | Typescript -> "typescript"
  | Go -> "go"
  | Dart -> "dart"
  | Python -> "python"
  | Java -> "java"
  | Csharp -> "csharp"
  | Rust -> "rust"

let normalize_for = function
  | Ocaml -> Naming.ocaml_field
  | Typescript -> Naming.ts_camel_case
  | Go -> Naming.go_public_name
  | Dart -> Naming.dart_camel_case
  | Python -> Naming.python_field
  | Java -> Naming.java_field
  | Csharp -> Naming.csharp_field
  | Rust -> Naming.rust_field

let file_for = function
  | Ocaml -> Naming.ocaml_file
  | Typescript -> Naming.ts_file
  | Go -> Naming.go_file
  | Dart -> Naming.dart_file
  | Python -> Naming.python_file
  | Java -> Naming.java_file
  | Csharp -> Naming.csharp_file
  | Rust -> Naming.rust_file

let python_reserved_members = [ "to_drut"; "from_drut"; "_to_value"; "_from_value" ]

let python_member_errors module_ =
  let error scope name =
    Cyrograf.Error.make ~path:[ module_.Schema.name; scope ]
      ~code:Cyrograf.Error.Code.name_collision
      (Printf.sprintf
         "python target member %S collides with generated API in %s.%s" name
         module_.Schema.name scope)
  in
  let struct_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        match message.kind with
        | Schema.Struct fields ->
          List.filter_map
            (fun (field : Schema.field) ->
              if List.mem field.name python_reserved_members then
                Some (error message.name field.name)
              else None)
            fields
        | Schema.Variant _ -> [])
      module_.messages
  in
  let exported =
    List.concat_map
      (fun (message : Schema.message) ->
        match message.kind with
        | Schema.Struct _ -> [ message.name ]
        | Schema.Variant constructors ->
          message.name
          :: List.map (fun (constructor : Schema.constructor) -> message.name ^ constructor.name)
               constructors)
      module_.messages
  in
  let name_errors =
    Naming.collisions ~normalize:Fun.id exported
    |> List.map (fun (key, first, second) ->
        Cyrograf.Error.make ~path:[ module_.Schema.name; "python" ]
          ~code:Cyrograf.Error.Code.name_collision
          (Printf.sprintf
             "python target normalizes %S and %S to the same exported name %S"
             first second key))
  in
  struct_errors @ name_errors

let java_reserved_types =
  [ "String"; "Object"; "Optional"; "List"; "Map"; "Void"; "Long"; "Double";
    "Boolean"; "Integer"; "Number"; "Wire"; "CyrografException" ]

let java_reserved_members =
  [ "toDrut"; "fromDrut"; "encodeValue"; "decodeValue"; "getClass"; "hashCode";
    "equals"; "toString"; "clone"; "finalize"; "notify"; "notifyAll"; "wait" ]

let java_member_errors module_ =
  let error scope name =
    Cyrograf.Error.make ~path:[ module_.Schema.name; scope ]
      ~code:Cyrograf.Error.Code.name_collision
      (Printf.sprintf
         "java target member %S collides with generated API in %s.%s" name
         module_.Schema.name scope)
  in
  let type_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        let struct_errors =
          if List.mem (Naming.java_class_name message.name) java_reserved_types
          then [ error message.name message.name ]
          else []
        in
        let case_errors =
          match message.kind with
          | Schema.Struct _ -> []
          | Schema.Variant constructors ->
            List.filter_map
              (fun (constructor : Schema.constructor) ->
                if List.mem (Naming.java_class_name constructor.name) java_reserved_types
                then Some (error message.name constructor.name)
                else None)
              constructors
        in
        struct_errors @ case_errors)
      module_.messages
  in
  let member_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        match message.kind with
        | Schema.Struct fields ->
          List.filter_map
            (fun (field : Schema.field) ->
              if List.mem (Naming.java_field field.name) java_reserved_members then
                Some (error message.name field.name)
              else None)
            fields
        | Schema.Variant _ -> [])
      module_.messages
  in
  type_errors @ member_errors

let csharp_reserved_types =
  [ "Wire"; "CyrografException"; "CyrografUnit"; "List"; "Dictionary";
    "JsonElement"; "JsonDocument"; "Func"; "Exception"; "Object"; "String";
    "Array"; "Nullable"; "ValueType"; "Enum" ]

let csharp_reserved_members =
  [ "ToDrut"; "FromDrut"; "EncodeValue"; "DecodeValue"; "EqualityContract";
    "GetHashCode"; "Equals"; "ToString"; "Clone"; "MemberwiseClone"; "GetType";
    "Deconstruct"; "PrintMembers"; "ReferenceEquals" ]

let csharp_member_errors module_ =
  let error scope name =
    Cyrograf.Error.make ~path:[ module_.Schema.name; scope ]
      ~code:Cyrograf.Error.Code.name_collision
      (Printf.sprintf
         "csharp target member %S collides with generated API in %s.%s" name
         module_.Schema.name scope)
  in
  let type_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        let struct_errors =
          if List.mem (Naming.csharp_type_name message.name) csharp_reserved_types
          then [ error message.name message.name ]
          else []
        in
        let case_errors =
          match message.kind with
          | Schema.Struct _ -> []
          | Schema.Variant constructors ->
            List.filter_map
              (fun (constructor : Schema.constructor) ->
                let name = Naming.csharp_type_name constructor.name in
                if List.mem name csharp_reserved_types
                   || List.mem name csharp_reserved_members
                then Some (error message.name constructor.name)
                else None)
              constructors
        in
        struct_errors @ case_errors)
      module_.messages
  in
  let member_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        match message.kind with
        | Schema.Struct fields ->
          List.filter_map
            (fun (field : Schema.field) ->
              let name = Naming.csharp_field field.name in
              if List.mem name csharp_reserved_members then
                Some (error message.name field.name)
              else None)
            fields
        | Schema.Variant _ -> [])
      module_.messages
  in
  type_errors @ member_errors

let rust_reserved_types =
  [ "String"; "Vec"; "Option"; "Result"; "Box"; "CyrografError"; "Value";
    "Map"; "Self"; "Ok"; "Err"; "Some"; "None"; "Wire" ]

let rust_reserved_members =
  [ "to_drut"; "from_drut"; "encode_value"; "decode_value" ]

let rust_member_errors module_ =
  let error scope name =
    Cyrograf.Error.make ~path:[ module_.Schema.name; scope ]
      ~code:Cyrograf.Error.Code.name_collision
      (Printf.sprintf
         "rust target member %S collides with generated API in %s.%s" name
         module_.Schema.name scope)
  in
  let module_errors =
    if List.mem (Naming.rust_module_name module_.Schema.name)
         [ "wire"; "error"; "lib" ]
    then [ error module_.Schema.name module_.Schema.name ]
    else []
  in
  let type_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        if List.mem (Naming.rust_type_name message.name) rust_reserved_types then
          [ error message.name message.name ]
        else [])
      module_.messages
  in
  let member_errors =
    List.concat_map
      (fun (message : Schema.message) ->
        match message.kind with
        | Schema.Struct fields ->
          List.filter_map
            (fun (field : Schema.field) ->
              if List.mem (Naming.rust_field field.name) rust_reserved_members then
                Some (error message.name field.name)
              else None)
            fields
        | Schema.Variant _ -> [])
      module_.messages
  in
  module_errors @ type_errors @ member_errors

let collision_errors target (schema : Schema.t) =
  let name = target_name target in
  let normalize = normalize_for target in
  let per_module =
    List.concat_map
      (Naming.name_collision_errors ~target:name ~normalize)
      schema.Schema.modules
  in
  let target_specific =
    match target with
    | Python -> List.concat_map python_member_errors schema.Schema.modules
    | Java -> List.concat_map java_member_errors schema.Schema.modules
    | Csharp -> List.concat_map csharp_member_errors schema.Schema.modules
    | Rust -> List.concat_map rust_member_errors schema.Schema.modules
    | _ -> []
  in
  let file_collisions =
    Naming.collisions ~normalize:Fun.id
      (List.map (fun (module_ : Schema.module_) -> file_for target module_.name)
         schema.Schema.modules)
    |> List.map (fun (key, first, second) ->
        Cyrograf.Error.make ~code:Cyrograf.Error.Code.name_collision
          (Printf.sprintf "%s target file name collision: %S and %S map to %S"
             name first second key))
  in
  per_module @ target_specific @ file_collisions

let check_targets ~targets ~schema =
  let duplicates =
    Naming.collisions ~normalize:Fun.id (List.map target_name targets)
  in
  if targets = [] then
    Error
      [ Cyrograf.Error.make ~code:Cyrograf.Error.Code.empty_targets
          "the target list must not be empty" ]
  else if duplicates <> [] then
    Error
      (List.map
         (fun (name, _, _) ->
           Cyrograf.Error.make ~code:Cyrograf.Error.Code.duplicate_target
             (Printf.sprintf "duplicate target %S" name))
         duplicates)
  else
    let errors =
      List.concat_map (fun target -> collision_errors target schema) targets
    in
    if errors <> [] then Error errors else Ok ()

let validate ~targets ~schema =
  match check_targets ~targets ~schema with
  | Ok () -> Ok ()
  | Error errors -> Error errors

let artifacts_for ~go_module ~ocaml_profile ~ocaml_library target (schema : Schema.t) =
  let modules = schema.Schema.modules in
  match target with
  | Ocaml ->
    Codegen_ocaml.runtime_artifact ~profile:ocaml_profile
    :: List.concat_map
      (fun (module_ : Schema.module_) ->
        [ { path = "ocaml/" ^ Naming.ocaml_file module_.name;
            contents = Codegen_ocaml.generate_module ~profile:ocaml_profile module_ };
          { path = "ocaml/" ^ Naming.snake_case module_.name ^ ".mli";
            contents = Codegen_ocaml.generate_signature ~profile:ocaml_profile module_ } ])
      modules
    @ [ { path = "ocaml/dune"; contents = Codegen_ocaml.dune_file ~library:ocaml_library } ]
  | Typescript ->
    Codegen_ts.generate ~modules
  | Go ->
    Codegen_go.generate ~go_module ~modules
  | Dart ->
    Codegen_dart.generate ~modules
  | Python ->
    Codegen_python.generate ~modules
  | Java ->
    Codegen_java.generate ~modules
  | Csharp ->
    Codegen_csharp.generate ~modules
  | Rust ->
    Codegen_rust.generate ~modules

let generate ?(go_module = "generated_contracts")
    ?(ocaml_profile = Native) ?(ocaml_library = "generated_contracts")
    ~targets ~schema () =
  match check_targets ~targets ~schema with
  | Error errors -> Error errors
  | Ok () ->
    let artifacts =
      List.concat_map
        (fun target ->
          artifacts_for ~go_module ~ocaml_profile ~ocaml_library target schema)
        targets
    in
    Ok (List.sort (fun a b -> String.compare a.path b.path) artifacts)