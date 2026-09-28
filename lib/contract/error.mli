(** Diagnostics for schema compilation and Wire coding. *)

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

val make :
  ?source:source -> ?path:string list -> code:string -> string -> t

(** [with_segment segment error] prepends a declaration/value segment to the
    error path, keeping the outer error otherwise unchanged. *)
val with_segment : string -> t -> t

(** [with_source source error] attaches the source location when the error does
    not carry one yet. *)
val with_source : source -> t -> t

val to_string : t -> string

(** Stable diagnostic codes. The string values are part of the public
    diagnostics. *)
module Code : sig
  val invalid_toml : string
  val invalid_syntax : string
  val invalid_source_encoding : string
  val unsupported_source_format : string
  val source_changed : string
  val invalid_json : string
  val duplicate_key : string
  val non_finite : string
  val unknown_type : string
  val unknown_key : string
  val missing_kind : string
  val missing_of : string
  val invalid_optional : string
  val invalid_type : string
  val invalid_name : string
  val invalid_rpc : string
  val empty_variant : string
  val struct_and_variant : string
  val duplicate : string
  val unresolved_reference : string
  val cycle : string
  val unsupported_framework_type : string
  val unsupported_extension : string
  val name_collision : string
  val empty_sources : string
  val empty_targets : string
  val duplicate_target : string
  val type_mismatch : string
  val unexpected_length : string
  val int_out_of_range : string
  val invalid_int : string
  val invalid_float : string
  val unknown_variant_tag : string
  val invalid_variant : string
  val migration_mismatch : string
  val io_error : string
  val foreign_file : string
  val unknown_target : string
  val usage : string
end