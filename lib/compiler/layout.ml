(* Layout: give a syntactically valid native document a fixed shape without
   changing its meaning or losing comments. The same printer serves the CLI
   formatter and the migration of TOML input. It is pure: no file access and no
   dependency on an editor. *)

module Diag = Cyrograf.Error
module S = Syntax

type printer = {
  source : string;
  mutable comments : S.comment list;
  mutable rev_lines : string list;
}

let span_start (span : S.Span.t) = span.S.Span.start_byte
let span_end (span : S.Span.t) = span.S.Span.end_byte

let indent_string indent = String.make (2 * indent) ' '

let trim_trailing text =
  let length = String.length text in
  let rec find index =
    if index <= 0 then 0
    else
      match text.[index - 1] with
      | ' ' | '\t' | '\r' -> find (index - 1)
      | _ -> index
  in
  String.sub text 0 (find length)

let add_line printer line = printer.rev_lines <- line :: printer.rev_lines

let append_last printer suffix =
  match printer.rev_lines with
  | last :: rest -> printer.rev_lines <- (last ^ suffix) :: rest
  | [] -> printer.rev_lines <- [ suffix ]

let peek printer = match printer.comments with c :: _ -> Some c | [] -> None

let pop printer =
  match printer.comments with
  | c :: rest ->
    printer.comments <- rest;
    c
  | [] -> failwith "Layout: no pending comment"

let comment_line (comment : S.comment) = "//" ^ trim_trailing comment.S.text

let rec flush_trailing printer position =
  match peek printer with
  | Some comment when span_start comment.S.span < position && not comment.S.own_line ->
    let comment = pop printer in
    append_last printer (" " ^ comment_line comment);
    flush_trailing printer position
  | _ -> ()

let rec flush_own printer position indent =
  match peek printer with
  | Some comment when span_start comment.S.span < position ->
    let comment = pop printer in
    if comment.S.own_line then
      add_line printer (indent_string indent ^ comment_line comment)
    else append_last printer (" " ^ comment_line comment);
    flush_own printer position indent
  | _ -> ()

let has_comment_between printer start_byte end_byte =
  List.exists
    (fun (comment : S.comment) ->
      let position = span_start comment.S.span in
      position >= start_byte && position < end_byte)
    printer.comments

let is_blank_line line =
  String.for_all (fun c -> c = ' ' || c = '\t' || c = '\r') line

let blank_between text start_byte end_byte =
  if end_byte <= start_byte || start_byte < 0 || end_byte > String.length text then false
  else
    let parts =
      String.split_on_char '\n' (String.sub text start_byte (end_byte - start_byte))
    in
    let count = List.length parts in
    if count < 3 then false
    else
      List.exists is_blank_line
        (List.filteri (fun index _ -> index >= 1 && index <= count - 2) parts)

let indent_first indent lines =
  match lines with
  | [] -> []
  | first :: rest -> (indent_string indent ^ first) :: rest

let append_text lines suffix =
  match List.rev lines with
  | last :: rest -> List.rev ((last ^ " " ^ suffix) :: rest)
  | [] -> [ suffix ]

let rec flush_into printer position indent lines =
  match peek printer with
  | Some comment when span_start comment.S.span < position ->
    let comment = pop printer in
    let text = comment_line comment in
    if comment.S.own_line then lines := !lines @ [ indent_string indent ^ text ]
    else lines := append_text !lines text;
    flush_into printer position indent lines
  | _ -> ()

let rec type_lines printer indent (expr : S.type_expr) =
  match expr.S.desc with
  | S.Named name -> [ name ]
  | S.Qualified (module_name, message) -> [ module_name ^ "." ^ message ]
  | S.List inner ->
    let start_byte = span_start expr.S.span in
    let end_byte = span_end expr.S.span in
    let inner_indent = indent + 1 in
    if not (has_comment_between printer start_byte end_byte) then
      [ "List<" ^ String.concat "\n" (type_lines printer indent inner) ^ ">" ]
    else begin
      let content = ref [] in
      flush_into printer (span_start inner.S.span) inner_indent content;
      content := !content @ indent_first inner_indent (type_lines printer inner_indent inner);
      flush_into printer end_byte inner_indent content;
      [ "List<" ] @ !content @ [ indent_string indent ^ ">" ]
    end

let print_field printer indent (field : S.field) =
  let marker = if field.S.optional then "?" else "" in
  let type_text = String.concat "\n" (type_lines printer indent field.S.type_) in
  add_line printer (indent_string indent ^ field.S.name ^ marker ^ ": " ^ type_text)

let print_constructor printer indent (constructor : S.constructor) =
  match constructor.S.payload with
  | None -> add_line printer (indent_string indent ^ constructor.S.name)
  | Some payload ->
    let payload_text = String.concat "\n" (type_lines printer indent payload) in
    add_line printer
      (indent_string indent ^ constructor.S.name ^ "(" ^ payload_text ^ ")")

let print_rpc printer indent (method_ : S.method_) =
  let request = String.concat "\n" (type_lines printer indent method_.S.request) in
  let response = String.concat "\n" (type_lines printer indent method_.S.response) in
  add_line printer
    (indent_string indent ^ "rpc " ^ method_.S.name ^ "(" ^ request ^ ") -> " ^ response)

let print_members printer ~indent ~start_byte ~end_byte members member_start member_end print =
  let previous = ref start_byte in
  List.iter
    (fun member ->
      let member_start = member_start member in
      let member_end = member_end member in
      let had_comment = has_comment_between printer !previous member_start in
      flush_trailing printer member_start;
      if (not had_comment) && blank_between printer.source !previous member_start then
        add_line printer "";
      flush_own printer member_start indent;
      print member;
      previous := member_end)
    members;
  flush_trailing printer end_byte;
  flush_own printer end_byte indent

let print_structure printer indent (structure : S.structure) =
  let start_byte = span_start structure.S.span in
  let end_byte = span_end structure.S.span in
  let has_inner_comments = has_comment_between printer start_byte end_byte in
  if structure.S.fields = [] && not has_inner_comments then
    add_line printer (indent_string indent ^ "struct " ^ structure.S.name ^ " {}")
  else begin
    add_line printer (indent_string indent ^ "struct " ^ structure.S.name ^ " {");
    print_members printer ~indent:(indent + 1) ~start_byte ~end_byte structure.S.fields
      (fun (field : S.field) -> span_start field.S.span)
      (fun (field : S.field) -> span_end field.S.span)
      (fun field -> print_field printer (indent + 1) field);
    add_line printer (indent_string indent ^ "}")
  end

let print_variant printer indent (variant : S.variant) =
  let start_byte = span_start variant.S.span in
  let end_byte = span_end variant.S.span in
  let has_inner_comments = has_comment_between printer start_byte end_byte in
  if variant.S.constructors = [] && not has_inner_comments then
    add_line printer (indent_string indent ^ "variant " ^ variant.S.name ^ " {}")
  else begin
    add_line printer (indent_string indent ^ "variant " ^ variant.S.name ^ " {");
    print_members printer ~indent:(indent + 1) ~start_byte ~end_byte
      variant.S.constructors
      (fun (constructor : S.constructor) -> span_start constructor.S.span)
      (fun (constructor : S.constructor) -> span_end constructor.S.span)
      (fun constructor -> print_constructor printer (indent + 1) constructor);
    add_line printer (indent_string indent ^ "}")
  end

let print_declaration printer indent declaration =
  match declaration with
  | S.Struct structure -> print_structure printer indent structure
  | S.Variant variant -> print_variant printer indent variant
  | S.Rpc method_ -> print_rpc printer indent method_

let finalize printer =
  let lines = List.rev printer.rev_lines in
  let rec drop_trailing = function
    | "" :: rest -> drop_trailing rest
    | lines -> lines
  in
  let lines = List.rev (drop_trailing (List.rev lines)) in
  if lines = [] then "" else String.concat "\n" lines ^ "\n"

let format_document (document : S.document) =
  let printer =
    { source = document.S.text;
      comments =
        List.stable_sort
          (fun (a : S.comment) b ->
            compare (span_start a.S.span) (span_start b.S.span))
          document.S.comments;
      rev_lines = [] }
  in
  let rec loop first = function
    | [] -> ()
    | declaration :: rest ->
      let span = S.declaration_span declaration in
      let start_byte = span_start span in
      flush_trailing printer start_byte;
      if not first then add_line printer "";
      flush_own printer start_byte 0;
      print_declaration printer 0 declaration;
      loop false rest
  in
  loop true document.S.declarations;
  flush_trailing printer max_int;
  flush_own printer max_int 0;
  finalize printer

let print_declarations ~comments declarations =
  let printer = { source = ""; comments = []; rev_lines = [] } in
  List.iter
    (fun (comment : S.comment) ->
      add_line printer (comment_line { comment with S.own_line = true }))
    comments;
  (match declarations with
   | [] -> ()
   | first :: rest ->
     if comments <> [] then add_line printer "";
     print_declaration printer 0 first;
     List.iter
       (fun declaration ->
         add_line printer "";
         print_declaration printer 0 declaration)
       rest);
  finalize printer

let format_source ~name ~text =
  if not (Native_parser.valid_utf8 text) then
    Error
      [ Diag.make ~path:[] ~code:Diag.Code.invalid_source_encoding
          "the source is not valid UTF-8" ]
  else
    let document, diagnostics = Native_parser.parse ~name ~text in
    if diagnostics <> [] then
      Error
        (List.map
           (fun (diagnostic : Diagnostic.t) -> diagnostic.Diagnostic.error)
           diagnostics)
    else Ok (format_document document)