type primitive =
  | String
  | Int
  | Float
  | Bool
  | Void
  | Date
  | Record

type qualified = {
  module_name : string;
  message_name : string;
}

type type_ =
  | Primitive of primitive
  | Reference of qualified
  | List of type_
  | Optional of type_

type field = {
  name : string;
  type_ : type_;
}

type constructor = {
  name : string;
  payload : type_;
}

type kind =
  | Struct of field list
  | Variant of constructor list

type message = {
  name : string;
  kind : kind;
}

type method_ = {
  name : string;
  request : qualified;
  response : qualified;
}

type module_ = {
  name : string;
  messages : message list;
  methods : method_ list;
}

type t = {
  modules : module_ list;
}

let qualified_name { module_name; message_name } =
  module_name ^ "." ^ message_name

let primitive_name = function
  | String -> "string"
  | Int -> "int"
  | Float -> "float"
  | Bool -> "bool"
  | Void -> "void"
  | Date -> "date"
  | Record -> "record"

let find_module schema name =
  List.find_opt (fun (module_ : module_) -> module_.name = name) schema.modules

let find_message schema qualified =
  match find_module schema qualified.module_name with
  | None -> None
  | Some module_ ->
    List.find_opt
      (fun (message : message) -> message.name = qualified.message_name)
      module_.messages

let rec add_type_references acc = function
  | Primitive _ -> acc
  | Reference qualified -> qualified :: acc
  | List inner -> add_type_references acc inner
  | Optional inner -> add_type_references acc inner

let all_references schema =
  let add_message acc (message : message) =
    match message.kind with
    | Struct fields ->
      List.fold_left
        (fun acc (field : field) -> add_type_references acc field.type_)
        acc fields
    | Variant constructors ->
      List.fold_left
        (fun acc (constructor : constructor) ->
          add_type_references acc constructor.payload)
        acc constructors
  in
  List.fold_left
    (fun acc (module_ : module_) ->
      List.fold_left add_message acc module_.messages)
    [] schema.modules