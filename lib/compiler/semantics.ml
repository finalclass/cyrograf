(* The single semantic activity shared by every frontend.

   It resolves references, validates names, duplicates, optionality and method
   signatures, detects cycles and builds the editor index. The TOML and native
   frontends only supply notation; both go through this module. *)

module Schema = Cyrograf.Schema
module Diag = Cyrograf.Error
module S = Syntax

type symbol_kind =
  | Module
  | Struct
  | Variant
  | Field
  | Constructor
  | Method
  | Type_ref
  | Rpc_ref

type symbol = {
  file : string;
  name : string;
  kind : symbol_kind;
  name_span : S.Span.t;
  decl_span : S.Span.t;
  target : Schema.qualified option;
  self : Schema.qualified option;
  detail : string option;
}

let primitive_label = function
  | Schema.String -> "String"
  | Schema.Int -> "Int"
  | Schema.Float -> "Float"
  | Schema.Bool -> "Bool"
  | Schema.Void -> "Void"
  | Schema.Date -> "Date"
  | Schema.Record -> "Record"

let rec string_of_type (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive primitive -> primitive_label primitive
  | Schema.Reference qualified -> Schema.qualified_name qualified
  | Schema.List inner -> "List<" ^ string_of_type inner ^ ">"
  | Schema.Optional inner -> string_of_type inner

let rec type_of_expr (expr : S.type_expr) =
  match expr.desc with
  | S.Named name -> name
  | S.Qualified (module_name, message) -> module_name ^ "." ^ message
  | S.List inner -> "List<" ^ type_of_expr inner ^ ">"

type index = symbol list

type result = {
  schema : Schema.t;
  diagnostics : Diagnostic.t list;
  index : index;
}

type context = {
  file : string;
  text : string;
}

let range_in file span =
  { Diagnostic.source = file;
    start_byte = span.S.Span.start_byte;
    end_byte = span.S.Span.end_byte }

let diagnostic ~context ~path ?span ?(related = []) ~code message =
  let range =
    match span with
    | Some span when span.S.Span.end_byte > span.S.Span.start_byte ->
      Some (range_in context.file span)
    | _ -> None
  in
  let related =
    List.filter (fun (range, _) -> range.Diagnostic.end_byte > range.start_byte) related
  in
  Diagnostic.make ?range ~related ~path ~code message

(* ── Reference resolution ─────────────────────────────────────────── *)

let rec resolve_type ~emit ~context ~module_name ~declared ~path expr =
  let open Syntax in
  let reference refs name span target = refs := (name, span, target) :: !refs in
  match expr.desc with
  | Named name ->
    (match S.primitive_of_string name with
     | Some primitive -> (Some (Schema.Primitive primitive), [])
     | None ->
       if name = "ctx" then begin
         emit
           (diagnostic ~context ~path ~span:expr.span
              ~code:Diag.Code.unsupported_framework_type
              "ctx is not a primitive of this library; declare the context data \
               explicitly or use a framework adapter");
         (None, [])
       end
       else if S.is_upper_ident name then begin
         let qualified = { Schema.module_name; message_name = name } in
         let refs = ref [] in
         if Hashtbl.mem declared (Schema.qualified_name qualified) then
           reference refs name expr.span (Some qualified)
         else begin
           reference refs name expr.span None;
           emit
             (diagnostic ~context ~path ~span:expr.span
                ~code:Diag.Code.unresolved_reference
                (Printf.sprintf "unknown message reference %S" name))
         end;
         (Some (Schema.Reference qualified), List.rev !refs)
       end
       else begin
         emit
           (diagnostic ~context ~path ~span:expr.span ~code:Diag.Code.unknown_type
              (Printf.sprintf "unknown type %S" name));
         (None, [])
       end)
  | Qualified (module_part, message_part) ->
    if S.is_upper_ident module_part && S.is_upper_ident message_part then begin
      let qualified = { Schema.module_name = module_part; message_name = message_part } in
      let refs = ref [] in
      let written = module_part ^ "." ^ message_part in
      if Hashtbl.mem declared (Schema.qualified_name qualified) then
        reference refs written expr.span (Some qualified)
      else begin
        reference refs written expr.span None;
        emit
          (diagnostic ~context ~path ~span:expr.span
             ~code:Diag.Code.unresolved_reference
             (Printf.sprintf "unknown message reference %S" written))
      end;
      (Some (Schema.Reference qualified), List.rev !refs)
    end
    else begin
      emit
        (diagnostic ~context ~path ~span:expr.span ~code:Diag.Code.unknown_type
           (Printf.sprintf "malformed qualified reference %S"
              (module_part ^ "." ^ message_part)));
      (None, [])
    end
  | List inner ->
    let resolved, refs =
      resolve_type ~emit ~context ~module_name ~declared ~path inner
    in
    (match resolved with
     | Some inner -> (Some (Schema.List inner), refs)
     | None -> (None, refs))

(* ── Ordering and cycles ──────────────────────────────────────────── *)

let detect_cycles ~decl_spans modules =
  let graph = Hashtbl.create 64 in
  List.iter
    (fun (module_ : Schema.module_) ->
      List.iter
        (fun (message : Schema.message) ->
          let key =
            Schema.qualified_name
              { Schema.module_name = module_.name; message_name = message.name }
          in
          let references =
            match message.kind with
            | Schema.Struct fields ->
              List.concat_map
                (fun (field : Schema.field) ->
                  let rec collect = function
                    | Schema.Reference qualified -> [ Schema.qualified_name qualified ]
                    | Schema.List inner -> collect inner
                    | Schema.Optional inner -> collect inner
                    | Schema.Primitive _ -> []
                  in
                  collect field.type_)
                fields
            | Schema.Variant constructors ->
              List.concat_map
                (fun (constructor : Schema.constructor) ->
                  let rec collect = function
                    | Schema.Reference qualified -> [ Schema.qualified_name qualified ]
                    | Schema.List inner -> collect inner
                    | Schema.Optional inner -> collect inner
                    | Schema.Primitive _ -> []
                  in
                  collect constructor.payload)
                constructors
          in
          Hashtbl.replace graph key references)
        module_.messages)
    modules;
  let diagnostics = ref [] in
  let state = Hashtbl.create 64 in
  let rec visit path name =
    match Hashtbl.find_opt state name with
    | Some `Black -> ()
    | Some `Gray ->
      let module_name =
        match String.split_on_char '.' name with
        | module_name :: _ -> module_name
        | [] -> name
      in
      let span = Hashtbl.find_opt decl_spans name in
      let file, span =
        match span with
        | Some (file, span) -> (file, Some span)
        | None -> (module_name ^ ".cyrograf", None)
      in
      let context = { file; text = "" } in
      diagnostics :=
        diagnostic ~context ~path:[ module_name ] ?span ~code:Diag.Code.cycle
          (Printf.sprintf "cyclic message reference: %s"
             (String.concat " -> " (List.rev (name :: path))))
        :: !diagnostics
    | None ->
      Hashtbl.replace state name `Gray;
      let dependencies =
        match Hashtbl.find_opt graph name with Some dependencies -> dependencies | None -> []
      in
      List.iter (fun dependency -> visit (name :: path) dependency) dependencies;
      Hashtbl.replace state name `Black
  in
  Hashtbl.iter (fun name _ -> visit [] name) graph;
  List.rev !diagnostics

(* ── Main entry point ─────────────────────────────────────────────── *)

let declared_name module_name name =
  Schema.qualified_name { Schema.module_name; message_name = name }

let analyze documents =
  let declared = Hashtbl.create 64 in
  let decl_spans = Hashtbl.create 64 in
  let diagnostics = ref [] in
  let module_files = Hashtbl.create 16 in

  (* Pass 1: module identity and declared message names. *)
  List.iter
    (fun (document : S.document) ->
      let context = { file = document.name; text = document.text } in
      let module_name = S.module_name_of_file document.name in
      if not (S.is_upper_ident module_name) then
        diagnostics :=
          diagnostic ~context ~path:[] ~code:Diag.Code.invalid_name
            (Printf.sprintf "invalid module name %S" module_name)
          :: !diagnostics;
      (match Hashtbl.find_opt module_files module_name with
       | Some first ->
         diagnostics :=
           diagnostic ~context ~path:[] ~code:Diag.Code.duplicate
             (Printf.sprintf "duplicate module %S" module_name)
           :: !diagnostics;
         ignore first
       | None -> Hashtbl.add module_files module_name document.name);
      List.iter
        (fun declaration ->
          match declaration with
          | S.Struct structure ->
            if S.is_upper_ident structure.name then begin
              let qualified = declared_name module_name structure.name in
              (match Hashtbl.find_opt declared qualified with
               | Some (first_file, first_span) ->
                 let related =
                   match first_span with
                   | Some span ->
                     [ (range_in first_file span,
                        Printf.sprintf "first declared in %s" first_file) ]
                   | None -> []
                 in
                 diagnostics :=
                   diagnostic ~context ~path:[ module_name ] ~span:structure.name_span
                     ~related ~code:Diag.Code.duplicate
                     (Printf.sprintf "duplicate message %S" structure.name)
                   :: !diagnostics
               | None ->
                 Hashtbl.add declared qualified (document.name, Some structure.name_span);
                 Hashtbl.add decl_spans qualified (document.name, structure.name_span))
            end
          | S.Variant variant ->
            if S.is_upper_ident variant.name then begin
              let qualified = declared_name module_name variant.name in
              (match Hashtbl.find_opt declared qualified with
               | Some (first_file, first_span) ->
                 let related =
                   match first_span with
                   | Some span ->
                     [ (range_in first_file span,
                        Printf.sprintf "first declared in %s" first_file) ]
                   | None -> []
                 in
                 diagnostics :=
                   diagnostic ~context ~path:[ module_name ] ~span:variant.name_span
                     ~related ~code:Diag.Code.duplicate
                     (Printf.sprintf "duplicate message %S" variant.name)
                   :: !diagnostics
               | None ->
                 Hashtbl.add declared qualified (document.name, Some variant.name_span);
                 Hashtbl.add decl_spans qualified (document.name, variant.name_span))
            end
          | S.Rpc _ -> ())
        document.S.declarations)
    documents;

  (* Pass 2: validate, resolve and index. *)
  let index = ref [] in
  let modules = ref [] in
  let add symbol = index := symbol :: !index in
  let emit diagnostic = diagnostics := diagnostic :: !diagnostics in

  List.iter
    (fun (document : S.document) ->
      let context = { file = document.name; text = document.text } in
      let module_name = S.module_name_of_file document.name in
      let messages = ref [] in
      let methods = ref [] in
      let seen_methods = Hashtbl.create 8 in

      let check_duplicate key store span ~what =
        match Hashtbl.find_opt store key with
        | Some first ->
          diagnostics :=
            diagnostic ~context ~path:[ module_name ] ~span
              ~related:[ (range_in context.file first, "first declaration") ]
              ~code:Diag.Code.duplicate
              (Printf.sprintf "duplicate %s %S" what key)
            :: !diagnostics
        | None -> Hashtbl.add store key span
      in

      List.iter
        (fun declaration ->
          match declaration with
          | S.Struct structure ->
            if not (S.is_upper_ident structure.name) then
              diagnostics :=
                diagnostic ~context ~path:[ module_name ] ~span:structure.name_span
                  ~code:Diag.Code.invalid_name
                  (Printf.sprintf "invalid message name %S" structure.name)
                :: !diagnostics;
            if S.is_reserved_type_name structure.name then
              diagnostics :=
                diagnostic ~context ~path:[ module_name ] ~span:structure.name_span
                  ~code:Diag.Code.invalid_name
                  (Printf.sprintf "%S is a reserved built-in type name" structure.name)
                :: !diagnostics;
            let self = { Schema.module_name; message_name = structure.name } in
            add { file = document.name; name = structure.name; kind = Struct;
                  name_span = structure.name_span; decl_span = structure.span;
                  target = None; self = Some self; detail = None };
            let seen_fields = Hashtbl.create 16 in
            let fields =
              List.filter_map
                (fun (field : S.field) ->
                  if not (S.is_snake_case field.name) then
                    diagnostics :=
                      diagnostic ~context ~path:[ module_name; structure.name ]
                        ~span:field.name_span ~code:Diag.Code.invalid_name
                        (Printf.sprintf "invalid field name %S" field.name)
                      :: !diagnostics;
                  check_duplicate field.name seen_fields field.name_span ~what:"field";
                  let resolved, references =
                    resolve_type ~emit ~context ~module_name ~declared
                      ~path:[ module_name; structure.name; field.name ]
                      field.S.type_
                  in
                  List.iter
                    (fun (name, span, target) ->
                      add { file = document.name; name; kind = Type_ref;
                            name_span = span; decl_span = span;
                            target; self = None; detail = Some name })
                    references;
                  add { file = document.name; name = field.name; kind = Field;
                        name_span = field.name_span; decl_span = field.span;
                        target = None; self = None;
                        detail =
                          (match resolved with
                           | Some type_ -> Some (string_of_type type_)
                           | None -> None) };
                  (match resolved with
                   | None -> None
                   | Some type_ ->
                     if field.optional then
                       (match type_ with
                        | Schema.Primitive Schema.Void ->
                          diagnostics :=
                            diagnostic ~context ~path:[ module_name; structure.name ]
                              ~span:field.name_span ~code:Diag.Code.invalid_optional
                              "an optional void field is not meaningful in Wire v1"
                            :: !diagnostics;
                          Some { Schema.name = field.name; type_ }
                        | Schema.Optional _ ->
                          diagnostics :=
                            diagnostic ~context ~path:[ module_name; structure.name ]
                              ~span:field.name_span ~code:Diag.Code.invalid_optional
                              "nested optional is not supported in Wire v1"
                            :: !diagnostics;
                          Some { Schema.name = field.name; type_ }
                        | _ -> Some { Schema.name = field.name; type_ = Schema.Optional type_ })
                     else Some { Schema.name = field.name; type_ }))
                structure.fields
            in
            messages := { Schema.name = structure.name; kind = Schema.Struct fields } :: !messages
          | S.Variant variant ->
            if not (S.is_upper_ident variant.name) then
              diagnostics :=
                diagnostic ~context ~path:[ module_name ] ~span:variant.name_span
                  ~code:Diag.Code.invalid_name
                  (Printf.sprintf "invalid message name %S" variant.name)
                :: !diagnostics;
            if S.is_reserved_type_name variant.name then
              diagnostics :=
                diagnostic ~context ~path:[ module_name ] ~span:variant.name_span
                  ~code:Diag.Code.invalid_name
                  (Printf.sprintf "%S is a reserved built-in type name" variant.name)
                :: !diagnostics;
            if variant.constructors = [] then
              diagnostics :=
                diagnostic ~context ~path:[ module_name; variant.name ]
                  ~span:variant.name_span ~code:Diag.Code.empty_variant
                  (Printf.sprintf "variant %S has no constructors" variant.name)
                :: !diagnostics;
            let self = { Schema.module_name; message_name = variant.name } in
            add { file = document.name; name = variant.name; kind = Variant;
                  name_span = variant.name_span; decl_span = variant.span;
                  target = None; self = Some self; detail = None };
            let seen_constructors = Hashtbl.create 16 in
            let constructors =
              List.filter_map
                (fun (constructor : S.constructor) ->
                  if not (S.is_upper_ident constructor.name) then
                    diagnostics :=
                      diagnostic ~context ~path:[ module_name; variant.name ]
                        ~span:constructor.name_span ~code:Diag.Code.invalid_name
                        (Printf.sprintf "invalid constructor name %S" constructor.name)
                      :: !diagnostics;
                  check_duplicate constructor.name seen_constructors constructor.name_span
                    ~what:"constructor";
                  let resolved, references =
                    match constructor.payload with
                    | None -> (Some (Schema.Primitive Schema.Void), [])
                    | Some payload ->
                      resolve_type ~emit ~context ~module_name ~declared
                        ~path:[ module_name; variant.name; constructor.name ]
                        payload
                  in
                  add { file = document.name; name = constructor.name; kind = Constructor;
                        name_span = constructor.name_span; decl_span = constructor.span;
                        target = None; self = None;
                        detail =
                          (match resolved with
                           | Some payload -> Some (string_of_type payload)
                           | None -> None) };
                  List.iter
                    (fun (name, span, target) ->
                      add { file = document.name; name; kind = Type_ref;
                            name_span = span; decl_span = span;
                            target; self = None; detail = Some name })
                    references;
                  (match resolved with
                   | None -> None
                   | Some payload -> Some { Schema.name = constructor.name; payload }))
                variant.constructors
            in
            messages := { Schema.name = variant.name; kind = Schema.Variant constructors } :: !messages
          | S.Rpc method_ ->
            if not (S.is_snake_case method_.name) then
              diagnostics :=
                diagnostic ~context ~path:[ module_name ] ~span:method_.name_span
                  ~code:Diag.Code.invalid_name
                  (Printf.sprintf "invalid method name %S" method_.name)
                :: !diagnostics;
            check_duplicate method_.name seen_methods method_.name_span ~what:"method";
            add { file = document.name; name = method_.name; kind = Method;
                  name_span = method_.name_span; decl_span = method_.span;
                  target = None; self = None;
                  detail =
                    Some
                      ("(" ^ type_of_expr method_.request ^ ") -> "
                       ^ type_of_expr method_.response) };
            let resolve_endpoint label expr =
              let resolved, references =
                resolve_type ~emit ~context ~module_name ~declared
                  ~path:[ module_name; "service"; method_.name; label ] expr
              in
              List.iter
                (fun (name, span, target) ->
                  add { file = document.name; name; kind = Rpc_ref;
                        name_span = span; decl_span = span;
                        target; self = None; detail = Some name })
                references;
              match resolved with
              | Some (Schema.Reference qualified) -> Some qualified
              | Some _ ->
                diagnostics :=
                  diagnostic ~context ~path:[ module_name; "service"; method_.name ]
                    ~span:expr.span ~code:Diag.Code.invalid_rpc
                    (Printf.sprintf "%S is not a named message" label)
                  :: !diagnostics;
                None
              | None -> None
            in
            (match (resolve_endpoint "request" method_.request,
                    resolve_endpoint "response" method_.response)
             with
             | Some request, Some response ->
               methods := { Schema.name = method_.name; request; response } :: !methods
             | _ -> ()))
        document.S.declarations;
      modules :=
        { Schema.name = module_name;
          messages = List.rev !messages;
          methods = List.rev !methods }
        :: !modules)
    documents;

  let modules = List.rev !modules in
  let cycle_diagnostics = detect_cycles ~decl_spans modules in
  let all_diagnostics = List.rev_append (List.rev !diagnostics) cycle_diagnostics in
  let modules =
    List.sort (fun (a : Schema.module_) b -> String.compare a.name b.name) modules
  in
  let declared_index = List.rev !index in
  let module_symbols =
    List.map
      (fun (document : S.document) ->
        { file = document.name; name = S.module_name_of_file document.name;
          kind = Module; name_span = S.Span.empty; decl_span = S.Span.empty;
          target = None; self = None; detail = None })
      documents
  in
  { schema = { Schema.modules };
    diagnostics = all_diagnostics;
    index = module_symbols @ declared_index }

let has_errors result = result.diagnostics <> []

let symbols_for (result : result) file =
  List.filter (fun (symbol : symbol) -> symbol.file = file) result.index

let reference_at (result : result) file offset =
  List.find_opt
    (fun (symbol : symbol) ->
      symbol.file = file
      && (symbol.kind = Type_ref || symbol.kind = Rpc_ref)
      && S.Span.contains symbol.name_span offset)
    result.index

let definition_of (result : result) (symbol : symbol) =
  match symbol.target with
  | None -> None
  | Some qualified ->
    List.find_opt
      (fun (candidate : symbol) ->
        candidate.self = Some qualified
        && (candidate.kind = Struct || candidate.kind = Variant))
      result.index

let definition (result : result) file offset =
  match reference_at result file offset with
  | None -> None
  | Some symbol -> (
    match definition_of result symbol with
    | None -> None
    | Some definition -> Some (definition.file, definition.name_span))

let symbol_at (result : result) file offset =
  List.fold_left
    (fun best (symbol : symbol) ->
      if symbol.file = file && S.Span.contains symbol.decl_span offset then
        match best with
        | None -> Some symbol
        | Some (current : symbol) ->
          if symbol.decl_span.S.Span.end_byte - symbol.decl_span.S.Span.start_byte
             < current.decl_span.S.Span.end_byte - current.decl_span.S.Span.start_byte
          then Some symbol
          else best
      else best)
    None result.index

let describe (result : result) file offset =
  match symbol_at result file offset with
  | None -> None
  | Some symbol ->
    Some
      (match symbol.kind with
       | Module -> "module " ^ symbol.name
       | Struct -> "struct " ^ symbol.name
       | Variant -> "variant " ^ symbol.name
       | Field ->
         (match symbol.detail with
          | Some detail -> "field " ^ symbol.name ^ ": " ^ detail
          | None -> "field " ^ symbol.name)
       | Constructor ->
         (match symbol.detail with
          | Some detail -> "constructor " ^ symbol.name ^ "(" ^ detail ^ ")"
          | None -> "constructor " ^ symbol.name)
       | Method ->
         (match symbol.detail with
          | Some detail -> "rpc " ^ symbol.name ^ detail
          | None -> "rpc " ^ symbol.name)
       | Type_ref ->
         (match symbol.target with
          | Some qualified -> "type " ^ Schema.qualified_name qualified
          | None -> "type " ^ symbol.name)
       | Rpc_ref ->
         (match symbol.target with
          | Some qualified -> "rpc endpoint " ^ Schema.qualified_name qualified
          | None -> "rpc endpoint " ^ symbol.name))