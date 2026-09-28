(* OCaml generator: plain algebraic types and Drut conversion, no ppx, no Well.

   The generated library ships its own private [Drut_runtime]; message modules
   expose exactly the text conversions [to_drut]/[from_drut]. Internal
   value-level helpers are shared across modules of the generated library and
   are not a public Drut/Codec surface. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let rec ocaml_type ~profile ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive Schema.String -> "string"
  | Schema.Primitive Schema.Int ->
    (match profile with Kernel.Native -> "int" | Kernel.Js -> "int64")
  | Schema.Primitive Schema.Float -> "float"
  | Schema.Primitive Schema.Bool -> "bool"
  | Schema.Primitive Schema.Void -> "unit"
  | Schema.Primitive Schema.Date -> "string"
  | Schema.Primitive Schema.Record -> "Drut_runtime.value"
  | Schema.Reference qualified -> reference_path ~local qualified ^ ".t"
  | Schema.List inner -> "(" ^ ocaml_type ~profile ~local inner ^ ") list"
  | Schema.Optional inner -> "(" ^ ocaml_type ~profile ~local inner ^ ") option"

and reference_path ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name
  else
    Naming.ocaml_module_ref qualified.module_name ^ "." ^ qualified.message_name

let paren expr = "(" ^ expr ^ ")"

let rec encode_expr ~local expr (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive Schema.String ->
    Printf.sprintf "Drut_runtime.enc_string %s" expr
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "Drut_runtime.enc_int %s" expr
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "Drut_runtime.enc_float %s" expr
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "Drut_runtime.enc_bool %s" expr
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "(let _ = %s in Drut_runtime.enc_void ())" expr
  | Schema.Primitive Schema.Date ->
    Printf.sprintf "Drut_runtime.enc_string %s" expr
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "Drut_runtime.enc_record %s" expr
  | Schema.Reference qualified ->
    Printf.sprintf
      "(match %s.to_drut %s with Ok text -> Drut_runtime.of_string text | Error _ as error -> error)"
      (reference_path ~local qualified) (paren expr)
  | Schema.List inner ->
    Printf.sprintf "Drut_runtime.enc_list (fun x -> %s) %s"
      (encode_expr ~local "x" inner) (paren expr)
  | Schema.Optional inner ->
    Printf.sprintf "Drut_runtime.enc_option (fun x -> %s) %s"
      (encode_expr ~local "x" inner) (paren expr)

let rec decode_expr ~local expr (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive Schema.String ->
    Printf.sprintf "Drut_runtime.dec_string %s" expr
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "Drut_runtime.dec_int %s" expr
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "Drut_runtime.dec_float %s" expr
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "Drut_runtime.dec_bool %s" expr
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "Drut_runtime.dec_void %s" expr
  | Schema.Primitive Schema.Date ->
    Printf.sprintf "Drut_runtime.dec_string %s" expr
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "Drut_runtime.dec_record %s" expr
  | Schema.Reference qualified ->
    Printf.sprintf "%s.from_drut (Drut_runtime.to_string %s)"
      (reference_path ~local qualified) (paren expr)
  | Schema.List inner ->
    Printf.sprintf "Drut_runtime.dec_list (fun x -> %s) %s"
      (decode_expr ~local "x" inner) (paren expr)
  | Schema.Optional inner ->
    Printf.sprintf "Drut_runtime.dec_option (fun x -> %s) %s"
      (decode_expr ~local "x" inner) (paren expr)

let text_conversions buffer =
  let p fmt = Printf.bprintf buffer fmt in
  let prefix = "" in
  p "\n";
  p "  let to_drut (v : t) : (string, Cyrograf.Error.t) result =\n";
  p "    match %s v with\n" (prefix ^ "encode_value");
  p "    | Ok wire -> Ok (Drut_runtime.to_string wire)\n";
  p "    | Error _ as error -> error\n\n";
  p "  let from_drut (text : string) : (t, Cyrograf.Error.t) result =\n";
  p "    match Drut_runtime.of_string text with\n";
  p "    | Ok wire -> %s wire\n" (prefix ^ "decode_value");
  p "    | Error _ as error -> error\n"

let struct_module ~profile ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  p "module %s = struct\n" message.name;
  (match fields with
   | [] ->
     p "  type t = unit\n\n";
     p "  let make () = ()\n\n";
     p "  let encode_value () : (Drut_runtime.value, Cyrograf.Error.t) result =\n";
     p "    Ok (`List [])\n\n";
     p "  let decode_value (wire : Drut_runtime.value) : (t, Cyrograf.Error.t) result =\n";
     p "    let open! Drut_runtime.Syntax in\n";
     p "    let* _ = Drut_runtime.dec_struct 0 wire in\n";
     p "    Ok ()\n"
   | fields ->
     p "  type t = {\n";
     List.iter
       (fun (field : Schema.field) ->
p "    %s : %s;\n" (Naming.ocaml_field field.name)
           (ocaml_type ~profile ~local field.type_))
       fields;
      p "  }\n\n";
      p "  let make";
     List.iter
       (fun (field : Schema.field) ->
         match field.type_ with
         | Schema.Optional _ -> p " ?%s" (Naming.ocaml_field field.name)
         | _ -> p " ~%s" (Naming.ocaml_field field.name))
       fields;
     p " () =\n    {";
     List.iter
       (fun (field : Schema.field) ->
         p " %s = %s;" (Naming.ocaml_field field.name)
           (Naming.ocaml_field field.name))
       fields;
     p " }\n\n";
     p "  let encode_value (v : t) : (Drut_runtime.value, Cyrograf.Error.t) result =\n";
     p "    let open! Drut_runtime.Syntax in\n";
     List.iteri
       (fun index (field : Schema.field) ->
         p "    let* f%d = Drut_runtime.field %S (%s) in\n" index field.name
           (encode_expr ~local
              ("v." ^ Naming.ocaml_field field.name)
              field.type_))
       fields;
     p "    Ok (`List [";
     List.iteri (fun index _ -> if index > 0 then p "; "; p "f%d" index) fields;
     p "])\n\n";
     p "  let decode_value (wire : Drut_runtime.value) : (t, Cyrograf.Error.t) result =\n";
     p "    let open! Drut_runtime.Syntax in\n";
     p "    let* arr = Drut_runtime.dec_struct %d wire in\n" (List.length fields);
     List.iteri
       (fun index (field : Schema.field) ->
         p "    let* %s = Drut_runtime.field %S (%s) in\n"
           (Naming.ocaml_field field.name) field.name
           (decode_expr ~local (Printf.sprintf "arr.(%d)" index) field.type_))
       fields;
     p "    Ok {";
     List.iter
       (fun (field : Schema.field) ->
         p " %s = %s;" (Naming.ocaml_field field.name)
           (Naming.ocaml_field field.name))
       fields;
     p " }\n");
  text_conversions buffer;
  p "end\n";
  Buffer.contents buffer

let variant_module ~profile ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let payload_type (constructor : Schema.constructor) =
    match constructor.payload with
    | Schema.Primitive Schema.Void -> None
    | type_ -> Some (ocaml_type ~profile ~local type_)
  in
  p "module %s = struct\n" message.name;
  p "  type t =\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match payload_type constructor with
      | None -> p "    | %s\n" constructor.name
      | Some type_ -> p "    | %s of %s\n" constructor.name type_)
    constructors;
  p "\n";
  p "  let encode_value (v : t) : (Drut_runtime.value, Cyrograf.Error.t) result =\n";
  p "    let open! Drut_runtime.Syntax in\n";
  p "    match v with\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "    | %s -> Ok (`List [ `String %S; `Null ])\n" constructor.name
          constructor.name
      | type_ ->
        p "    | %s payload ->\n" constructor.name;
        p "      let* p = %s in\n"
          (encode_expr ~local "payload" type_);
        p "      Ok (`List [ `String %S; p ])\n" constructor.name)
    constructors;
  p "\n";
  p "  let decode_value (wire : Drut_runtime.value) : (t, Cyrograf.Error.t) result =\n";
  p "    let open! Drut_runtime.Syntax in\n";
  p "    match wire with\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "    | `List [ `String %S; `Null ] -> Ok %s\n" constructor.name
          constructor.name
      | type_ ->
        p "    | `List [ `String %S; payload ] ->\n" constructor.name;
        p "      let* p = %s in\n"
          (decode_expr ~local "payload" type_);
        p "      Ok (%s p)\n" constructor.name)
    constructors;
  p "    | _ ->\n";
  p "      Drut_runtime.error ~code:Cyrograf.Error.Code.invalid_variant\n";
  p "        %S\n" (message.name ^ ": unexpected Drut variant");
  p "\n";
  text_conversions buffer;
  p "end\n";
  Buffer.contents buffer

let message_module ~profile ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_module ~profile ~module_name message fields
  | Schema.Variant constructors -> variant_module ~profile ~module_name message constructors

let struct_signature ~profile ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 256 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  p "module %s : sig\n" message.name;
  (match fields with
   | [] -> p "  type t = unit\n"
   | fields ->
     p "  type t = {\n";
     List.iter
       (fun (field : Schema.field) ->
p "    %s : %s;\n" (Naming.ocaml_field field.name)
           (ocaml_type ~profile ~local field.type_))
       fields;
      p "  }\n");
  p "\n  val make :";
  List.iter
    (fun (field : Schema.field) ->
      match field.type_ with
      | Schema.Optional inner ->
        p " ?%s:%s ->" (Naming.ocaml_field field.name) (ocaml_type ~profile ~local inner)
      | _ ->
        p " %s:%s ->" (Naming.ocaml_field field.name)
          (ocaml_type ~profile ~local field.type_))
    fields;
  p " unit -> t\n";
  p "  val to_drut : t -> (string, Cyrograf.Error.t) result\n";
  p "  val from_drut : string -> (t, Cyrograf.Error.t) result\n";
  p "end\n";
  Buffer.contents buffer

let variant_signature ~profile ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 256 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  p "module %s : sig\n" message.name;
  p "  type t =\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void -> p "    | %s\n" constructor.name
      | type_ -> p "    | %s of %s\n" constructor.name (ocaml_type ~profile ~local type_))
    constructors;
  p "  val to_drut : t -> (string, Cyrograf.Error.t) result\n";
  p "  val from_drut : string -> (t, Cyrograf.Error.t) result\n";
  p "end\n";
  Buffer.contents buffer

let message_signature ~profile ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_signature ~profile ~module_name message fields
  | Schema.Variant constructors -> variant_signature ~profile ~module_name message constructors

let generate_module ~profile (module_ : Schema.module_) =
  let buffer = Buffer.create 2048 in
  let p fmt = Printf.bprintf buffer fmt in
  p "(* Generated by Cyrograf. Do not edit. *)\n";
  p "[@@@warning \"-32\"]\n\n";
  Naming.topo_sort module_
  |> List.iter (fun message -> p "%s\n" (message_module ~profile ~module_name:module_.name message));
  Buffer.contents buffer

let generate_signature ~profile (module_ : Schema.module_) =
  let buffer = Buffer.create 2048 in
  Buffer.add_string buffer "(* Generated by Cyrograf. Do not edit. *)\n\n";
  let p fmt = Printf.bprintf buffer fmt in
  Naming.topo_sort module_
  |> List.iter (fun message ->
      p "%s\n" (message_signature ~profile ~module_name:module_.name message));
  Buffer.contents buffer

let dune_file ~library =
  Printf.sprintf "(library\n\
  \ (name %s)\n\
  \ (libraries cyrograf yojson))\n" library

let runtime_artifact ~profile =
  { Kernel.path = "ocaml/drut_runtime.ml"; contents = Ocaml_runtime.source ~profile }