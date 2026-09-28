(* The shared notation model produced by every contract frontend.

   A syntax document carries declarations, comments and byte ranges only; it
   does not resolve names, types or ordering. Both the native frontend and the
   TOML compatibility frontend produce this model, and [Semantics] is the single
   place that interprets it. *)

module Schema = Cyrograf.Schema

module Span = struct
  type t = {
    start_byte : int;
    end_byte : int;
  }

  let make start_byte end_byte = { start_byte; end_byte }
  let empty = { start_byte = 0; end_byte = 0 }

  let contains span offset =
    span.start_byte <= offset && offset < span.end_byte

  let le a b = a.start_byte <= b.start_byte && a.end_byte <= b.end_byte
end

type comment = {
  text : string;
  span : Span.t;
  own_line : bool;
}

type type_expr = {
  desc : type_desc;
  span : Span.t;
}

and type_desc =
  | Named of string
  | Qualified of string * string
  | List of type_expr

type field = {
  name : string;
  name_span : Span.t;
  type_ : type_expr;
  optional : bool;
  span : Span.t;
}

type constructor = {
  name : string;
  name_span : Span.t;
  payload : type_expr option;
  span : Span.t;
}

type structure = {
  name : string;
  name_span : Span.t;
  span : Span.t;
  fields : field list;
}

type variant = {
  name : string;
  name_span : Span.t;
  span : Span.t;
  constructors : constructor list;
}

type method_ = {
  name : string;
  name_span : Span.t;
  span : Span.t;
  request : type_expr;
  response : type_expr;
}

type declaration =
  | Struct of structure
  | Variant of variant
  | Rpc of method_

type document = {
  name : string;
  text : string;
  declarations : declaration list;
  comments : comment list;
}

let declaration_name = function
  | Struct structure -> structure.name
  | Variant variant -> variant.name
  | Rpc method_ -> method_.name

let declaration_span = function
  | Struct structure -> structure.span
  | Variant variant -> variant.span
  | Rpc method_ -> method_.span

let declaration_name_span = function
  | Struct structure -> structure.name_span
  | Variant variant -> variant.name_span
  | Rpc method_ -> method_.name_span

let is_upper_ident s =
  s <> ""
  && (match s.[0] with 'A' .. 'Z' -> true | _ -> false)
  && String.for_all
       (function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true | _ -> false)
       s

let is_lower_ident s =
  s <> ""
  && (match s.[0] with 'a' .. 'z' -> true | _ -> false)
  && String.for_all
       (function 'A' .. 'Z' | 'a' .. 'z' | '0' .. '9' | '_' -> true | _ -> false)
       s

let is_snake_case s =
  s <> ""
  && (match s.[0] with 'a' .. 'z' -> true | _ -> false)
  && List.for_all
       (fun segment ->
         segment <> ""
         && String.for_all
              (function 'a' .. 'z' | '0' .. '9' -> true | _ -> false)
              segment)
       (String.split_on_char '_' s)

let is_reserved_type_name = function
  | "String" | "Int" | "Float" | "Bool" | "Void" | "Date" | "Record" | "List" ->
    true
  | _ -> false

let primitive_of_string = function
  | "String" -> Some Schema.String
  | "Int" -> Some Schema.Int
  | "Float" -> Some Schema.Float
  | "Bool" -> Some Schema.Bool
  | "Void" -> Some Schema.Void
  | "Date" -> Some Schema.Date
  | "Record" -> Some Schema.Record
  | _ -> None

let canonical_primitive_name = function
  | "string" -> Some "String"
  | "int" -> Some "Int"
  | "float" -> Some "Float"
  | "bool" -> Some "Bool"
  | "void" -> Some "Void"
  | "date" -> Some "Date"
  | "record" -> Some "Record"
  | _ -> None

let module_name_of_file file =
  let base = Filename.basename file in
  String.capitalize_ascii (Filename.remove_extension base)

let extension file = Filename.extension file

let line_starts text =
  let starts = ref [ 0 ] in
  String.iteri
    (fun index c -> if c = '\n' then starts := (index + 1) :: !starts)
    text;
  Array.of_list (List.rev !starts)

let line_of_offset text offset =
  let starts = line_starts text in
  let rec search low high =
    if low > high then high
    else
      let middle = (low + high) / 2 in
      if starts.(middle) <= offset then search (middle + 1) high
      else search low (middle - 1)
  in
  search 0 (Array.length starts - 1) + 1

let column_of_offset text offset =
  let line = line_of_offset text offset in
  let starts = line_starts text in
  let start = starts.(line - 1) in
  let scalars = ref 0 in
  for index = start to offset - 1 do
    let byte = Char.code text.[index] in
    if byte land 0xC0 <> 0x80 then incr scalars
  done;
  !scalars + 1
