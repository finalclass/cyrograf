(* The schema descriptor and manifest written by a build client. *)

module Schema = Cyrograf.Schema

let rec type_json (type_ : Schema.type_) : Yojson.Safe.t =
  match type_ with
  | Schema.Primitive primitive ->
    `Assoc
      [ ("kind", `String "primitive");
        ("name", `String (Schema.primitive_name primitive)) ]
  | Schema.Reference qualified ->
    `Assoc
      [ ("kind", `String "reference");
        ("name", `String (Schema.qualified_name qualified)) ]
  | Schema.List inner ->
    `Assoc [ ("kind", `String "list"); ("element", type_json inner) ]
  | Schema.Optional inner ->
    `Assoc [ ("kind", `String "optional"); ("element", type_json inner) ]

let field_json (field : Schema.field) : Yojson.Safe.t =
  `Assoc [ ("name", `String field.name); ("type", type_json field.type_) ]

let constructor_json (constructor : Schema.constructor) : Yojson.Safe.t =
  `Assoc [ ("name", `String constructor.name); ("type", type_json constructor.payload) ]

let message_json (message : Schema.message) : Yojson.Safe.t =
  match message.kind with
  | Schema.Struct fields ->
    `Assoc
      [ ("name", `String message.name);
        ("kind", `String "struct");
        ("fields", `List (List.map field_json fields)) ]
  | Schema.Variant constructors ->
    `Assoc
      [ ("name", `String message.name);
        ("kind", `String "variant");
        ("constructors", `List (List.map constructor_json constructors)) ]

let method_json (method_ : Schema.method_) : Yojson.Safe.t =
  `Assoc
    [ ("name", `String method_.name);
      ("request", `String (Schema.qualified_name method_.request));
      ("response", `String (Schema.qualified_name method_.response)) ]

let module_json (module_ : Schema.module_) : Yojson.Safe.t =
  let messages =
    List.sort
      (fun (a : Schema.message) b -> String.compare a.name b.name)
      module_.messages
  in
  let methods =
    List.sort
      (fun (a : Schema.method_) b -> String.compare a.name b.name)
      module_.methods
  in
  `Assoc
    [ ("name", `String module_.name);
      ("messages", `List (List.map message_json messages));
      ("methods", `List (List.map method_json methods)) ]

let schema_json (schema : Schema.t) : string =
  let modules =
    List.sort
      (fun (a : Schema.module_) b -> String.compare a.name b.name)
      schema.modules
  in
  Yojson.Safe.to_string
    (`Assoc
      [ ("format", `Int 1);
        ("modules", `List (List.map module_json modules)) ])

let manifest_json paths : string =
  Yojson.Safe.to_string (`List (List.map (fun path -> `String path) paths))