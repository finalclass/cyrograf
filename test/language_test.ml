(* Stage 01 language tests: native language, shared analysis and CLI-facing
   diagnostics. They exercise the checks listed under "Kontrakt języka" and
   "Natywny język i wspólna analiza" in docs/stp.md. *)

open Cyrograf
module CC = Cyrograf_compiler

let failures = ref 0

let check label condition =
  if not condition then begin
    incr failures;
    Printf.printf "FAIL: %s\n" label
  end

let check_equal label a b =
  if a <> b then begin
    incr failures;
    Printf.printf "FAIL: %s: %S <> %S\n" label a b
  end

let source name text = { CC.name; text }

let codes errors = List.map (fun (error : Error.t) -> error.code) errors

let has_code code errors = List.mem code (codes errors)

let expect_ok label = function
  | Ok value -> Some value
  | Error errors ->
    incr failures;
    Printf.printf "FAIL: %s returned errors:\n" label;
    List.iter (fun error -> Printf.printf "  %s\n" (Error.to_string error)) errors;
    None

let expect_errors label = function
  | Ok _ ->
    incr failures;
    Printf.printf "FAIL: %s unexpectedly succeeded\n" label;
    []
  | Error errors -> errors

let native_example =
  "// Reservation example\n\
   struct ReserveRequest {\n\
   \  owner_id: String\n\
   \  quantity: Int\n\
   \  note?: String\n\
   }\n\
   \n\
   struct Reservation {\n\
   \  id: String\n\
   }\n\
   \n\
   struct Problem {\n\
   \  code: String\n\
   \  message: String\n\
   }\n\
   \n\
   variant ReserveResponse {\n\
   \  Reserved(Reservation)\n\
   \  Rejected(Problem)\n\
   \  Unavailable\n\
   }\n\
   \n\
   struct ReservationBatch {\n\
   \  items: List<Reservation>\n\
   }\n\
   \n\
   rpc reserve(ReserveRequest) -> ReserveResponse\n"

let toml_equivalent =
  "[service.rpc]\n\
   reserve = \"ReserveRequest -> ReserveResponse\"\n\
   \n\
   [msg.ReserveRequest.struct]\n\
   owner_id = \"string\"\n\
   quantity = \"int\"\n\
   note = { type = \"string\", optional = true }\n\
   \n\
   [msg.Reservation.struct]\n\
   id = \"string\"\n\
   \n\
   [msg.Problem.struct]\n\
   code = \"string\"\n\
   message = \"string\"\n\
   \n\
   [msg.ReserveResponse.variant]\n\
   Reserved = \"Reservation\"\n\
   Rejected = \"Problem\"\n\
   Unavailable = \"void\"\n\
   \n\
   [msg.ReservationBatch.struct]\n\
   items = { type = \"list\", of = \"Reservation\" }\n"

let artifacts_of sources =
  match CC.compile ~sources with
  | Error errors ->
    incr failures;
    Printf.printf "FAIL: compile returned errors:\n";
    List.iter (fun error -> Printf.printf "  %s\n" (Error.to_string error)) errors;
    None
  | Ok schema ->
    let targets = [ CC.Ocaml; CC.Typescript; CC.Go; CC.Dart ] in
    (match CC.generate ~targets ~schema () with
     | Ok artifacts ->
       Some
         (CC.Descriptor.schema_json schema,
          List.map (fun (artifact : CC.artifact) -> artifact.path ^ "\000" ^ artifact.contents)
            artifacts)
     | Error errors ->
       incr failures;
       Printf.printf "FAIL: generate returned errors:\n";
       List.iter (fun error -> Printf.printf "  %s\n" (Error.to_string error)) errors;
       None)

let test_native_schema () =
  match CC.compile ~sources:[ source "Orders.cyrograf" native_example ] with
  | Error _ -> check "native example compiles" false
  | Ok schema ->
    let module_ =
      match Schema.find_module schema "Orders" with Some module_ -> module_ | None -> assert false
    in
    check_equal "native message order"
      "ReserveRequest,Reservation,Problem,ReserveResponse,ReservationBatch"
      (String.concat ","
         (List.map (fun (message : Schema.message) -> message.name) module_.messages));
    check_equal "native method count" "1" (string_of_int (List.length module_.methods));
    (match
       Schema.find_message schema
         { Schema.module_name = "Orders"; message_name = "ReserveRequest" }
     with
     | Some { Schema.kind = Schema.Struct fields; _ } ->
       check_equal "native optional"
         "owner_id=required,quantity=required,note=optional"
         (String.concat ","
            (List.map
               (fun (field : Schema.field) ->
                 field.name
                 ^ (match field.type_ with Schema.Optional _ -> "=optional" | _ -> "=required"))
               fields))
     | _ -> check "native ReserveRequest kind" false);
    (match
       Schema.find_message schema
         { Schema.module_name = "Orders"; message_name = "ReserveResponse" }
     with
     | Some { Schema.kind = Schema.Variant constructors; _ } ->
       check_equal "native void constructor"
         "Reserved,Rejected,Unavailable"
         (String.concat ","
            (List.map (fun (constructor : Schema.constructor) -> constructor.name) constructors))
     | _ -> check "native variant kind" false)

let test_frontend_equivalence () =
  match (artifacts_of [ source "Orders.cyrograf" native_example ],
         artifacts_of [ source "Orders.toml" toml_equivalent ])
  with
  | Some (native_schema, native_artifacts), Some (toml_schema, toml_artifacts) ->
    check_equal "native and TOML descriptor" native_schema toml_schema;
    check_equal "native and TOML artifacts"
      (String.concat "\n" native_artifacts) (String.concat "\n" toml_artifacts)
  | _ -> ()

let test_mixed_project () =
  let sources =
    [ source "Common.cyrograf" "struct UserCtx { user_id: String }\n";
      source "Orders.cyrograf"
        "struct Request {\n  ctx: Common.UserCtx\n  user_id: String\n}\n" ]
  in
  match artifacts_of sources with
  | Some _ -> ()
  | None -> check "mixed project compiles" false

let test_forward_reference () =
  expect_ok "forward reference"
    (CC.compile
       ~sources:[ source "Chain.cyrograf" "struct First { second: Second }\nstruct Second { value: String }\n" ])
  |> ignore

let test_nested_list () =
  match CC.compile ~sources:[ source "Nested.cyrograf" "struct Box { items: List<List<String>> }\n" ] with
  | Error _ -> check "nested list compiles" false
  | Ok schema -> (
    match
      Schema.find_message schema { Schema.module_name = "Nested"; message_name = "Box" }
    with
    | Some { Schema.kind = Schema.Struct [ field ]; _ } ->
      (match field.type_ with
       | Schema.List (Schema.List (Schema.Primitive Schema.String)) -> ()
       | _ -> check "nested list shape" false)
    | _ -> check "nested list message" false)

let test_contextual_keywords () =
  expect_ok "contextual keywords as field names"
    (CC.compile
       ~sources:
         [ source "Words.cyrograf"
             "struct Words {\n  struct: String\n  variant: Int\n  rpc: Bool\n}\n" ])
  |> ignore

let test_variant_void () =
  expect_ok "variant void forms"
    (CC.compile
       ~sources:
         [ source "Maybe.cyrograf"
             "variant Maybe {\n  None\n  Some(String)\n  Nothing(Void)\n}\n" ])
  |> ignore

let test_separators_unicode () =
  expect_ok "semicolons and CRLF"
    (CC.compile
       ~sources:
         [ source "Sep.cyrograf"
             "struct A { x: String; y: Int }\r\nstruct B { z: Bool }\r\n" ])
  |> ignore;
  expect_ok "BOM and semicolons"
    (CC.compile
       ~sources:[ source "Bom.cyrograf" "\xEF\xBB\xBFstruct A { x: String; }\n" ])
  |> ignore;
  expect_ok "Unicode comment"
    (CC.compile
       ~sources:[ source "Comment.cyrograf" "// zażółć gęślą jaźń 😀\nstruct A { x: String }\n" ])
  |> ignore

let test_source_order () =
  let sources =
    [ source "Alpha.cyrograf" "struct A { b: Beta.B }\n";
      source "Beta.cyrograf" "struct B { value: String }\n" ]
  in
  match (artifacts_of sources, artifacts_of (List.rev sources)) with
  | Some (schema_a, artifacts_a), Some (schema_b, artifacts_b) ->
    check_equal "file order descriptor" schema_a schema_b;
    check_equal "file order artifacts"
      (String.concat "\n" artifacts_a) (String.concat "\n" artifacts_b)
  | _ -> ()

let test_field_order_matters () =
  let forward =
    CC.compile
      ~sources:[ source "Order.cyrograf" "struct Pair {\n  first: String\n  second: Int\n}\n" ]
  in
  let backward =
    CC.compile
      ~sources:[ source "Order.cyrograf" "struct Pair {\n  second: Int\n  first: String\n}\n" ]
  in
  match (forward, backward) with
  | Ok a, Ok b ->
    check "field order changes descriptor"
      (CC.Descriptor.schema_json a <> CC.Descriptor.schema_json b)
  | _ -> check "field order schemas compile" false

let test_duplicate_module () =
  let errors =
    expect_errors "duplicate module"
      (CC.compile
         ~sources:
           [ source "Orders.cyrograf" "struct A { x: String }\n";
             source "Orders.toml" "[msg.B.struct]\ny = \"string\"\n" ])
  in
  check "duplicate module code" (has_code Error.Code.duplicate errors)

let diagnostic_case label text expected_code =
  match CC.compile ~sources:[ source "Diag.cyrograf" text ] with
  | Ok _ ->
    incr failures;
    Printf.printf "FAIL: %s unexpectedly succeeded\n" label
  | Error errors ->
    check (label ^ " code " ^ expected_code) (has_code expected_code errors);
    List.iter
      (fun (error : Error.t) ->
        match error.source with
        | Some { Error.name; _ } -> check (label ^ " source") (name = "Diag.cyrograf")
        | None ->
          incr failures;
          Printf.printf "FAIL: %s error without source\n" label)
      errors

let test_diagnostics () =
  diagnostic_case "invalid utf8" "struct A {\n  x: \xFF\n}\n"
    Error.Code.invalid_source_encoding;
  diagnostic_case "unclosed brace" "struct A {\n  x: String\n"
    Error.Code.invalid_syntax;
  diagnostic_case "missing type" "struct A {\n  x:\n}\n" Error.Code.invalid_syntax;
  diagnostic_case "unknown type" "struct A {\n  x: nope\n}\n" Error.Code.unknown_type;
  diagnostic_case "optional void" "struct A {\n  x?: Void\n}\n" Error.Code.invalid_optional;
  diagnostic_case "duplicate message" "struct A { x: String }\nstruct A { y: String }\n"
    Error.Code.duplicate;
  diagnostic_case "cycle" "struct A { b: B }\nstruct B { a: A }\n" Error.Code.cycle;
  diagnostic_case "bad reference" "struct A { b: Missing }\n" Error.Code.unresolved_reference;
  diagnostic_case "ctx type" "struct A { x: ctx }\n" Error.Code.unsupported_framework_type

let analysis_of text =
  CC.Analysis.analyze ~sources:[ source "Recover.cyrograf" text ]

let test_eof_range () =
  let text = "struct A {" in
  let result = analysis_of text in
  match CC.Analysis.diagnostics result with
  | diagnostic :: _ ->
    check "EOF diagnostic is syntax" (diagnostic.CC.Analysis.code = Error.Code.invalid_syntax);
    (match (diagnostic.start_byte, diagnostic.end_byte) with
     | Some start, Some stop ->
       check "EOF range at end" (start = String.length text && stop = String.length text)
     | _ -> check "EOF range present" false)
  | [] -> check "EOF diagnostic present" false

let test_astral_range () =
  let text = "// 😀\nstruct A { x: nope }\n" in
  let result = analysis_of text in
  match CC.Analysis.diagnostics result with
  | diagnostic :: _ -> (
    match diagnostic.start_byte with
    | Some start ->
      check "astral error on second line"
        (start > String.length "// ")
    | None -> check "astral error range" false)
  | [] -> check "astral diagnostic present" false

let test_multiple_errors () =
  let result = analysis_of "struct A { x: nope }\nstruct B { y: alsoNope }\n" in
  let unknown =
    List.filter
      (fun (diagnostic : CC.Analysis.diagnostic) -> diagnostic.code = Error.Code.unknown_type)
      (CC.Analysis.diagnostics result)
  in
  check_equal "independent errors" "2" (string_of_int (List.length unknown))

let test_index_recovery () =
  let result = analysis_of "struct Bad { x: nope }\nstruct Good { y: String }\n" in
  check "no schema with errors"
    (match CC.Analysis.schema result with Error _ -> true | Ok _ -> false);
  let symbols = CC.Analysis.symbols result "Recover.cyrograf" in
  let names = List.map (fun (symbol : CC.Analysis.symbol) -> symbol.name) symbols in
  check "recovered declaration in index" (List.mem "Good" names);
  let good =
    List.find (fun (symbol : CC.Analysis.symbol) -> symbol.name = "Good") symbols
  in
  check "symbol has declaration range"
    (good.decl_start_byte <= good.start_byte && good.start_byte < good.decl_end_byte)

let test_cli_analysis_parity () =
  let text = "struct A { x: nope }\n" in
  let result = analysis_of text in
  let analysis_diagnostics = CC.Analysis.diagnostics result in
  let errors = expect_errors "parity compile" (CC.compile ~sources:[ source "Recover.cyrograf" text ]) in
  check_equal "parity code count"
    (string_of_int (List.length analysis_diagnostics)) (string_of_int (List.length errors));
  match (analysis_diagnostics, errors) with
  | analysis_diagnostic :: _, error :: _ ->
    check_equal "parity code" error.code analysis_diagnostic.code;
    check_equal "parity path"
      (String.concat "." error.path)
      (String.concat "." analysis_diagnostic.path)
  | _ -> ()

let test_definition_query () =
  let text = "struct Request { user: User }\nstruct User { id: String }\n" in
  let result = analysis_of text in
  let field_offset = String.length "struct Request { user: U" in
  match CC.Analysis.definition result ~file:"Recover.cyrograf" ~offset:field_offset with
  | Some location -> check "definition points to User" (location.start_byte > field_offset)
  | None -> check "definition found" false

let test_target_collision () =
  match
    CC.compile ~sources:[ source "Collide.cyrograf" "struct M { owner_id: String\n owner_i_d: String }\n" ]
  with
  | Error errors ->
    check "collision fixture does not fail the language" (not (has_code Error.Code.name_collision errors))
  | Ok schema -> (
    let errors = expect_errors "go collision" (CC.validate ~targets:[ CC.Go ] ~schema) in
    check "go collision code" (has_code Error.Code.name_collision errors))

let test_empty_sources () =
  let errors = expect_errors "empty sources" (CC.compile ~sources:[]) in
  check "empty sources code" (has_code Error.Code.empty_sources errors)

let test_new_notation () =
  let text =
    "struct Common {\n  nothing: Void\n  activity_24h: Int\n}\n\
     struct Box {\n  name?: List<List<Common>>\n  items?: List<String>\n  note?: String\n}\n\
     rpc activity_24h(Box) -> Box\n"
  in
  (match CC.compile ~sources:[ source "New.cyrograf" text ] with
   | Ok _ -> ()
   | Error errors ->
     incr failures;
     Printf.printf "FAIL: new notation returned errors:\n";
     List.iter (fun error -> Printf.printf "  %s\n" (Error.to_string error)) errors);
  let schema =
    match CC.compile ~sources:[ source "New.cyrograf" text ] with
    | Ok schema -> schema
    | Error _ -> assert false
  in
  match Schema.find_message schema { Schema.module_name = "New"; message_name = "Box" } with
  | Some { Schema.kind = Schema.Struct fields; _ } ->
    check "optional list of list shape"
      (match List.nth_opt fields 0 with
       | Some { Schema.type_ = Schema.Optional (Schema.List (Schema.List _)); _ } -> true
       | _ -> false)
  | _ -> check "new notation shape" false

let test_old_notation_rejected () =
  let cases =
    [ ("lowercase primitive", "struct A { x: string }\n", Error.Code.unknown_type);
      ("bracket list", "struct A { x: [Reservation] }\nstruct Reservation { id: String }\n",
       Error.Code.invalid_syntax);
      ("postfix optional", "struct A { x: String? }\n", Error.Code.invalid_syntax);
      ("empty generic", "struct A { x: List<> }\n", Error.Code.invalid_syntax);
      ("two generic arguments", "struct A { x: List<String, Int> }\n", Error.Code.invalid_syntax);
      ("unknown generic", "struct A { x: Box<String> }\n", Error.Code.invalid_syntax);
      ("optional void", "struct A { x?: Void }\n", Error.Code.invalid_optional);
      ("reserved type name", "struct String { x: Int }\n", Error.Code.invalid_name);
      ("bad snake case", "struct A { someField: Int }\n", Error.Code.invalid_name);
      ("empty snake case segment", "struct A { some__field: Int }\n", Error.Code.invalid_name);
      ("trailing snake case separator", "struct A { some_: Int }\n", Error.Code.invalid_name) ]
  in
  List.iter
    (fun (label, text, code) ->
      match CC.compile ~sources:[ source "Old.cyrograf" text ] with
      | Ok _ ->
        incr failures;
        Printf.printf "FAIL: old notation accepted: %s\n" label
      | Error errors ->
        check ("old notation " ^ label) (has_code code errors))
    cases



let () =
  test_native_schema ();
  test_frontend_equivalence ();
  test_mixed_project ();
  test_forward_reference ();
  test_nested_list ();
  test_contextual_keywords ();
  test_variant_void ();
  test_separators_unicode ();
  test_source_order ();
  test_field_order_matters ();
  test_duplicate_module ();
  test_diagnostics ();
  test_eof_range ();
  test_astral_range ();
  test_multiple_errors ();
  test_index_recovery ();
  test_cli_analysis_parity ();
  test_definition_query ();
  test_target_collision ();
  test_empty_sources ();
  test_new_notation ();
  test_old_notation_rejected ();
  if !failures = 0 then Printf.printf "all language tests passed\n"
  else begin
    Printf.printf "%d language test(s) failed\n" !failures;
    exit 1
  end
