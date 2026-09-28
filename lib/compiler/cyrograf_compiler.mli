(** Compiler frontend and code generators for [ocaml-contract].

    The compiler works on in-memory sources. It never reads or writes files;
    a build system, editor or CLI client supplies the text and stores the
    resulting artifacts. Both the native [.cyrograf] language and the TOML
    compatibility frontend feed one shared analysis. *)

type source = {
  name : string;
  text : string;
}

type target =
  | Ocaml
  | Typescript
  | Go
  | Dart
  | Python
  | Java
  | Csharp
  | Rust

(** OCaml [Int] representation profile. [Native] keeps the host [int]; [Js]
    uses [int64] for js_of_ocaml. The Drut text is identical in both. *)
type ocaml_profile =
  | Native
  | Js

type artifact = {
  path : string;
  contents : string;
}

(** [compile ~sources] parses and validates the sources into a schema.
    [source.name] chooses the frontend by extension: [.cyrograf] is the native
    language, [.toml] is the compatibility input. *)
val compile :
  sources:source list ->
  (Cyrograf.Schema.t, Cyrograf.Error.t list) result

(** [generate ~targets ~schema] produces artifacts for the selected targets.
    An error in one target invalidates the whole result. Paths are relative,
    without [..] and without a source directory prefix. [ocaml_profile]
    selects the OCaml [Int] representation and defaults to [Native];
    [ocaml_library] selects the generated OCaml data library name and defaults
    to [generated_contracts]. *)
val generate :
  ?ocaml_profile:ocaml_profile ->
  ?ocaml_library:string ->
  targets:target list ->
  schema:Cyrograf.Schema.t ->
  unit ->
  (artifact list, Cyrograf.Error.t list) result

(** [validate ~targets ~schema] checks only the target-specific rules, notably
    name collisions, without emitting any artifact. *)
val validate :
  targets:target list ->
  schema:Cyrograf.Schema.t ->
  (unit, Cyrograf.Error.t list) result

(** [format ~name ~text] reformats one syntactically valid native document and
    returns its canonical text. A syntax or encoding error blocks the result;
    semantic errors, such as a missing reference, do not. The function is pure
    and uses the same [Layout] as the editor adapter. *)
val format : name:string -> text:string -> (string, Cyrograf.Error.t list) result

type migration = {
  artifacts : artifact list;
  comments_moved : bool;
}

(** [migrate ~sources] turns TOML input into native sources, copies native
    sources unchanged and validates that the whole result has the same schema
    and generates the same artifacts. It never writes files. *)
val migrate : sources:source list -> (migration, Cyrograf.Error.t list) result

(** Analysis and editor queries shared by the CLI and the editor adapter. *)
module Analysis : sig
  type result

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

  val analyze : sources:source list -> result

  (** The full schema, or every diagnostic; never a partial schema. *)
  val schema : result -> (Cyrograf.Schema.t, diagnostic list) Stdlib.result

  val diagnostics : result -> diagnostic list

  val symbols : result -> string -> symbol list

  val definition : result -> file:string -> offset:int -> location option

  val describe : result -> file:string -> offset:int -> string option

  val complete : result -> file:string -> offset:int -> string list
end

(** Lower-level generation entry point used by the CLI, allowing the Go module
    path to be selected. *)
module Generator : sig
  val generate :
    ?go_module:string ->
    ?ocaml_profile:ocaml_profile ->
    ?ocaml_library:string ->
    targets:target list ->
    schema:Cyrograf.Schema.t ->
    unit ->
    (artifact list, Cyrograf.Error.t list) result
end

(** Pure projection of canonical schema names onto target-specific generated
    symbols, field/method normalization and relative data artifact paths. It
    lets an integrator build adapters without importing the private [Naming]
    module; it adds no conversion entry point. *)
module Info : sig
  val target_name : target -> string

  (** Generated module-level symbol for the canonical module name. *)
  val module_symbol : target -> module_name:string -> string

  (** Generated message-level symbol (a nested module, class or type name). *)
  val message_symbol : target -> message_name:string -> string

  (** Qualified reference of a message in the target language. *)
  val qualified_message :
    target -> module_name:string -> message_name:string -> string

  (** Normalization of a field name for the target, before keyword escaping. *)
  val normalize_field : target -> string -> string

  (** Normalization of a method name for the target. *)
  val normalize_method : target -> string -> string

  (** Relative path of the data artifact that declares a module's messages. *)
  val data_artifact : target -> module_name:string -> string
end

(** Descriptor and manifest serialization for the CLI output. *)
module Descriptor : sig
  val schema_json : Cyrograf.Schema.t -> string
  val manifest_json : string list -> string
end