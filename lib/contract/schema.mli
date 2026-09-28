(** The contract schema: declared messages, their ordered fields and the
    declarative method signatures. This module never performs the operations
    described by a contract. *)

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

val qualified_name : qualified -> string

val primitive_name : primitive -> string

(** [find_module schema name] is the module with the given bare name. *)
val find_module : t -> string -> module_ option

(** [find_message schema qualified] is the declared message, if any. *)
val find_message : t -> qualified -> message option

(** [all_references schema] enumerates every reference used by the schema. *)
val all_references : t -> qualified list