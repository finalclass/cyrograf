(* Naming, ordering and collision helpers shared by the generators. *)

module Schema = Cyrograf.Schema

let snake_case name =
  let buffer = Buffer.create (String.length name) in
  String.iteri
    (fun index c ->
      if c >= 'A' && c <= 'Z' then begin
        if index > 0 then Buffer.add_char buffer '_';
        Buffer.add_char buffer (Char.lowercase_ascii c)
      end
      else Buffer.add_char buffer c)
    name;
  Buffer.contents buffer

let ocaml_module_ref name = String.capitalize_ascii (snake_case name)
let ocaml_file name = snake_case name ^ ".ml"
let ts_file name = String.lowercase_ascii name ^ ".ts"
let dart_file name = snake_case name ^ ".dart"
let go_file name = snake_case name ^ ".go"

let ocaml_keywords =
  [ "and"; "as"; "assert"; "asr"; "begin"; "class"; "constraint"; "do"; "done";
    "downto"; "else"; "end"; "exception"; "external"; "false"; "for"; "fun";
    "function"; "functor"; "if"; "in"; "include"; "inherit"; "initializer";
    "land"; "lazy"; "let"; "lor"; "lsl"; "lsr"; "lxor"; "match"; "method";
    "mod"; "module"; "mutable"; "new"; "nonrec"; "object"; "of"; "open"; "or";
    "private"; "rec"; "sig"; "struct"; "then"; "to"; "true"; "try"; "type";
    "val"; "virtual"; "when"; "while"; "with" ]

let ocaml_field name =
  if List.mem name ocaml_keywords then name ^ "'" else name

let go_word word =
  if word = "" then ""
  else if String.lowercase_ascii word = "id" then "ID"
  else String.capitalize_ascii word

let go_public_name name =
  if String.contains name '_' then
    String.split_on_char '_' name |> List.map go_word |> String.concat ""
  else go_word name

let go_package_name name = String.lowercase_ascii name

let dart_keywords =
  [ "abstract"; "as"; "assert"; "async"; "await"; "break"; "case"; "catch";
    "class"; "const"; "continue"; "covariant"; "default"; "deferred"; "do";
    "dynamic"; "else"; "enum"; "export"; "extends"; "extension"; "external";
    "factory"; "false"; "final"; "finally"; "for"; "get"; "hide"; "if";
    "implements"; "import"; "in"; "interface"; "is"; "late"; "library";
    "mixin"; "new"; "null"; "on"; "operator"; "part"; "required"; "rethrow";
    "return"; "sealed"; "set"; "show"; "static"; "super"; "switch"; "sync";
    "this"; "throw"; "true"; "try"; "typedef"; "var"; "void"; "while"; "with";
    "yield" ]

let camel_case name =
  if String.contains name '_' then
    match String.split_on_char '_' name with
    | [] -> ""
    | first :: rest ->
      first
      ^ String.concat ""
          (List.map
             (fun word -> if word = "" then "" else String.capitalize_ascii word)
             rest)
  else name

let ts_keywords =
  [ "any"; "as"; "boolean"; "break"; "case"; "catch"; "class"; "const";
    "constructor"; "continue"; "debugger"; "default"; "delete"; "do"; "else";
    "enum"; "export"; "extends"; "false"; "finally"; "for"; "from"; "function";
    "get"; "if"; "implements"; "import"; "in"; "instanceof"; "interface"; "let";
    "new"; "null"; "number"; "of"; "package"; "private"; "protected"; "public";
    "return"; "set"; "static"; "string"; "super"; "switch"; "this"; "throw";
    "true"; "try"; "typeof"; "undefined"; "var"; "void"; "while"; "with";
    "yield" ]

let ts_camel_case name =
  let value = camel_case name in
  if List.mem value ts_keywords then value ^ "_" else value

let dart_camel_case name =
  let value = camel_case name in
  if List.mem value dart_keywords then value ^ "_" else value

let python_keywords =
  [ "False"; "None"; "True"; "and"; "as"; "assert"; "async"; "await"; "break";
    "class"; "continue"; "def"; "del"; "elif"; "else"; "except"; "finally";
    "for"; "from"; "global"; "if"; "import"; "in"; "is"; "lambda"; "nonlocal";
    "not"; "or"; "pass"; "raise"; "return"; "try"; "while"; "with"; "yield" ]

let python_module_name name =
  let value = snake_case name in
  if List.mem value python_keywords then value ^ "_" else value

let python_file name = python_module_name name ^ ".py"

let python_field name =
  if List.mem name python_keywords then name ^ "_" else name

let java_keywords =
  [ "abstract"; "assert"; "boolean"; "break"; "byte"; "case"; "catch"; "char";
    "class"; "const"; "continue"; "default"; "do"; "double"; "else"; "enum";
    "extends"; "final"; "finally"; "float"; "for"; "goto"; "if"; "implements";
    "import"; "instanceof"; "int"; "interface"; "long"; "native"; "new";
    "package"; "private"; "protected"; "public"; "return"; "short"; "static";
    "strictfp"; "super"; "switch"; "synchronized"; "this"; "throw"; "throws";
    "transient"; "try"; "void"; "volatile"; "while"; "record"; "sealed";
    "permits"; "yield"; "var" ]

let java_class_name name =
  let value = String.capitalize_ascii name in
  if List.mem value java_keywords then value ^ "_" else value

let java_field name =
  let value = camel_case name in
  if List.mem value java_keywords then value ^ "_" else value

let java_file name = java_class_name name ^ ".java"

let csharp_keywords =
  [ "abstract"; "as"; "base"; "bool"; "break"; "byte"; "case"; "catch";
    "char"; "checked"; "class"; "const"; "continue"; "decimal"; "default";
    "delegate"; "do"; "double"; "else"; "enum"; "event"; "explicit"; "extern";
    "false"; "finally"; "fixed"; "float"; "for"; "foreach"; "goto"; "if";
    "implicit"; "in"; "int"; "interface"; "internal"; "is"; "lock"; "long";
    "namespace"; "new"; "null"; "object"; "operator"; "out"; "override";
    "params"; "private"; "protected"; "public"; "readonly"; "ref"; "return";
    "sbyte"; "sealed"; "short"; "sizeof"; "stackalloc"; "static"; "string";
    "struct"; "switch"; "this"; "throw"; "true"; "try"; "typeof"; "uint";
    "ulong"; "unchecked"; "unsafe"; "ushort"; "using"; "virtual"; "void";
    "volatile"; "while" ]

let csharp_pascal_case name =
  if String.contains name '_' then
    match String.split_on_char '_' name with
    | [] -> ""
    | parts ->
      String.concat ""
        (List.map
           (fun word -> if word = "" then "" else String.capitalize_ascii word)
           parts)
  else String.capitalize_ascii name

let csharp_type_name name = csharp_pascal_case name

let csharp_field name =
  let value = csharp_pascal_case name in
  if List.mem value csharp_keywords then value ^ "_" else value

let csharp_file name = csharp_type_name name ^ ".cs"

let rust_keywords =
  [ "abstract"; "as"; "async"; "await"; "become"; "box"; "break"; "const";
    "continue"; "crate"; "do"; "dyn"; "else"; "enum"; "extern"; "false";
    "final"; "fn"; "for"; "if"; "impl"; "in"; "let"; "loop"; "macro"; "match";
    "mod"; "move"; "mut"; "override"; "priv"; "pub"; "ref"; "return"; "self";
    "Self"; "static"; "struct"; "super"; "trait"; "true"; "try"; "type";
    "typeof"; "unsafe"; "unsized"; "use"; "virtual"; "where"; "while"; "yield" ]

let rust_module_name name =
  let value = snake_case name in
  if List.mem value rust_keywords then value ^ "_" else value

let rust_file name = rust_module_name name ^ ".rs"

let rust_type_name name =
  if List.mem name rust_keywords then name ^ "_" else name

let rust_field name =
  if List.mem name rust_keywords then name ^ "_" else name

(* ── Deterministic message order ──────────────────────────────────── *)

let message_references (message : Schema.message) =
  let rec collect acc = function
    | Schema.Primitive _ -> acc
    | Schema.Reference qualified -> Schema.qualified_name qualified :: acc
    | Schema.List inner -> collect acc inner
    | Schema.Optional inner -> collect acc inner
  in
  match message.kind with
  | Schema.Struct fields ->
    List.fold_left
      (fun acc (field : Schema.field) -> collect acc field.type_)
      [] fields
  | Schema.Variant constructors ->
    List.fold_left
      (fun acc (constructor : Schema.constructor) -> collect acc constructor.payload)
      [] constructors

let topo_sort (module_ : Schema.module_) =
  let local_name (message : Schema.message) =
    Schema.qualified_name
      { Schema.module_name = module_.name; message_name = message.name }
  in
  let names = List.map local_name module_.messages in
  let remaining = Hashtbl.create 16 in
  List.iter
    (fun (message : Schema.message) ->
      let dependencies =
        message_references message
        |> List.filter (fun name -> List.mem name names)
        |> List.sort_uniq String.compare
      in
      Hashtbl.replace remaining (local_name message) dependencies)
    module_.messages;
  let ordered = ref [] in
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun (message : Schema.message) ->
        let name = local_name message in
        match Hashtbl.find_opt remaining name with
        | None -> ()
        | Some dependencies ->
          let unresolved =
            List.filter (Hashtbl.mem remaining) dependencies
          in
          if unresolved = [] then begin
            ordered := message :: !ordered;
            Hashtbl.remove remaining name;
            changed := true
          end)
      module_.messages
  done;
  (* A cycle is reported by the parser; keep the rest in source order. *)
  List.iter
    (fun (message : Schema.message) ->
      if Hashtbl.mem remaining (local_name message) then
        ordered := message :: !ordered)
    module_.messages;
  List.rev !ordered

(* ── Collision detection ──────────────────────────────────────────── *)

let collisions ~normalize names =
  let seen = Hashtbl.create 32 in
  let found = ref [] in
  List.iter
    (fun name ->
      let key = normalize name in
      match Hashtbl.find_opt seen key with
      | Some original -> found := (key, original, name) :: !found
      | None -> Hashtbl.add seen key name)
    names;
  List.rev !found

let message_names (module_ : Schema.module_) =
  List.map (fun (message : Schema.message) -> message.name) module_.messages

let name_collision_errors ~target ~normalize module_ =
  let error scope key first second =
    Cyrograf.Error.make ~path:[ module_.Schema.name; scope ]
      ~code:Cyrograf.Error.Code.name_collision
      (Printf.sprintf "%s target normalizes %S and %S to %S" target first second
         key)
  in
  let message_collisions =
    collisions ~normalize (message_names module_)
    |> List.map (fun (key, first, second) ->
        error "message" key first second)
  in
  let member_collisions =
    List.concat_map
      (fun (message : Schema.message) ->
        match message.kind with
        | Schema.Struct fields ->
          let names = List.map (fun (field : Schema.field) -> field.name) fields in
          collisions ~normalize names
          |> List.map (fun (key, first, second) ->
              error message.name key first second)
        | Schema.Variant constructors ->
          let names =
            List.map (fun (constructor : Schema.constructor) -> constructor.name)
              constructors
          in
          collisions ~normalize names
          |> List.map (fun (key, first, second) ->
              error message.name key first second))
      module_.messages
  in
  message_collisions @ member_collisions