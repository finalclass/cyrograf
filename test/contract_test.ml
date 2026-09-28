(* Unit tests for the frontend, the Wire runtime and the generators. *)

open Cyrograf
module CC = Cyrograf_compiler
module Wire = Generated_fixtures.Drut_runtime

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

let read_fixture name =
  let path = Filename.concat "fixtures/orders" name in
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      really_input_string channel (in_channel_length channel))

let example_sources () =
  [ source "Orders.toml" (read_fixture "Orders.toml");
    source "Common.toml" (read_fixture "Common.toml") ]

let expect_ok label = function
  | Ok value -> value
  | Error errors ->
    incr failures;
    Printf.printf "FAIL: %s returned errors:\n" label;
    List.iter (fun e -> Printf.printf "  %s\n" (Error.to_string e)) errors;
    failwith label

let expect_errors label = function
  | Ok _ ->
    incr failures;
    Printf.printf "FAIL: %s unexpectedly succeeded\n" label;
    []
  | Error errors -> errors

let expect_single label = function
  | Ok _ ->
    incr failures;
    Printf.printf "FAIL: %s unexpectedly succeeded\n" label;
    []
  | Error error -> [ error ]

let codes errors =
  List.map (fun (e : Error.t) -> e.code) errors

let has_code code errors = List.mem code (codes errors)

let test_compile_example () =
  let schema = expect_ok "compile example" (CC.compile ~sources:(example_sources ())) in
  let module_names =
    List.map (fun (m : Schema.module_) -> m.name) schema.Schema.modules
  in
  check_equal "modules sorted" "Common,Orders" (String.concat "," module_names);
  (match CC.compile ~sources:(List.rev (example_sources ())) with
   | Ok reversed ->
     check_equal "source order independent" "Common,Orders"
       (String.concat ","
          (List.map (fun (m : Schema.module_) -> m.name) reversed.Schema.modules))
   | Error _ ->
     incr failures;
     Printf.printf "FAIL: reversed sources did not compile\n");
  let orders =
    match Schema.find_module schema "Orders" with
    | Some orders -> orders
    | None ->
      incr failures;
      Printf.printf "FAIL: Orders missing\n";
      failwith "orders"
  in
  let message_names =
    List.map (fun (m : Schema.message) -> m.name) orders.Schema.messages
  in
  check_equal "message source order"
    "ReserveRequest,Reservation,Problem,ReserveResponse,ReservationBatch,Guard,ListBox,ResponseBox,Scalars"
    (String.concat "," message_names);
  (match Schema.find_message schema { Schema.module_name = "Orders"; message_name = "ReserveRequest" } with
   | Some { Schema.kind = Schema.Struct fields; _ } ->
     let fields =
       List.map
         (fun (f : Schema.field) ->
           match f.type_ with
           | Schema.Optional _ -> f.name ^ "?"
           | _ -> f.name)
         fields
     in
     check_equal "field order and optionality" "owner_id,quantity,note?"
       (String.concat "," fields)
   | _ ->
     incr failures;
     Printf.printf "FAIL: ReserveRequest kind\n");
  (match orders.Schema.methods with
   | [ method_ ] ->
     check_equal "method name" "reserve" method_.name;
     check_equal "method request" "Orders.ReserveRequest"
       (Schema.qualified_name method_.request);
     check_equal "method response" "Orders.ReserveResponse"
       (Schema.qualified_name method_.response)
   | _ ->
     incr failures;
     Printf.printf "FAIL: methods\n")

let test_generate_determinism () =
  let schema = expect_ok "compile" (CC.compile ~sources:(example_sources ())) in
  let targets =
    [ CC.Ocaml; CC.Typescript; CC.Go; CC.Dart ]
  in
  let forward = expect_ok "generate forward" (CC.generate ~targets ~schema ()) in
  let reversed = expect_ok "generate reversed"
      (CC.generate ~targets:(List.rev targets) ~schema ())
  in
  check "artifact determinism"
    (List.map (fun (a : CC.artifact) -> a.path) forward
     = List.map (fun (a : CC.artifact) -> a.path) reversed);
  let second = expect_ok "generate again" (CC.generate ~targets ~schema ()) in
  check "artifact contents stable"
    (List.map (fun (a : CC.artifact) -> a.path ^ "\000" ^ a.contents) forward
     = List.map (fun (a : CC.artifact) -> a.path ^ "\000" ^ a.contents) second);
  let paths = List.map (fun (a : CC.artifact) -> a.path) forward in
  List.iter
    (fun expected ->
      check ("artifact present: " ^ expected) (List.mem expected paths))
    [ "ocaml/orders.ml"; "ocaml/drut_runtime.ml"; "ocaml/dune";
      "typescript/orders.ts"; "typescript/wire.ts"; "go/orders/orders.go";
      "go/wire/wire.go"; "go/go.mod"; "dart/orders.dart"; "dart/wire.dart" ]

let test_generate_errors () =
  let schema = expect_ok "compile" (CC.compile ~sources:(example_sources ())) in
  let errors = expect_errors "empty targets"
      (CC.generate ~targets:[] ~schema ())
  in
  check "empty targets code" (has_code Error.Code.empty_targets errors);
  let errors = expect_errors "duplicate targets"
      (CC.generate ~targets:[ CC.Go; CC.Go ] ~schema ())
  in
  check "duplicate target code" (has_code Error.Code.duplicate_target errors)

let test_collision () =
  let text = "[msg.M.struct]\nowner_id = \"string\"\nowner_i_d = \"string\"\n" in
  match CC.compile ~sources:[ source "Collide.toml" text ] with
  | Error _ ->
    incr failures;
    Printf.printf "FAIL: collision fixture did not compile\n"
  | Ok schema ->
    let errors = expect_errors "go collision"
        (CC.generate ~targets:[ CC.Go ] ~schema ())
    in
    check "go collision code" (has_code Error.Code.name_collision errors)

let diagnostic_cases =
  [ ("unknown type", "[msg.M.struct]\nx = \"nope\"\n", Error.Code.unknown_type);
    ("ctx", "[msg.M.struct]\nx = \"ctx\"\n", Error.Code.unsupported_framework_type);
    ("actor", "[actor.x]\nname = \"a\"\n", Error.Code.unsupported_extension);
    ("missing of", "[msg.M.struct]\nx = { type = \"list\" }\n", Error.Code.missing_of);
    ("invalid optional", "[msg.M.struct]\nx = { type = \"string\", optional = \"yes\" }\n", Error.Code.invalid_optional);
    ("optional void", "[msg.M.struct]\nx = { type = \"void\", optional = true }\n", Error.Code.invalid_optional);
    ("empty variant", "[msg.M.variant]\n", Error.Code.empty_variant);
    ("unresolved rpc", "[service.rpc]\nrun = \"Missing -> Missing2\"\n", Error.Code.unresolved_reference);
    ("bad rpc syntax", "[service.rpc]\nrun = \"A B\"\n", Error.Code.invalid_rpc);
    ("unknown key", "[nope]\nx = 1\n", Error.Code.unknown_key);
    ("struct and variant", "[msg.M.struct]\n[msg.M.variant]\nA = \"void\"\n", Error.Code.struct_and_variant);
    ("invalid field name", "[msg.M.struct]\nBad = \"string\"\n", Error.Code.invalid_name);
    ("unresolved reference", "[msg.M.struct]\nx = \"Other.Y\"\n", Error.Code.unresolved_reference);
    ("cycle", "[msg.A.struct]\nb = \"B\"\n[msg.B.struct]\na = \"A\"\n", Error.Code.cycle) ]

let test_diagnostics () =
  List.iter
    (fun (label, text, code) ->
      let errors = expect_errors label (CC.compile ~sources:[ source "Diag.toml" text ]) in
      check (label ^ " code " ^ code) (has_code code errors);
      List.iter
        (fun (error : Error.t) ->
          match error.source with
          | Some { Error.name; _ } ->
            check (label ^ " source") (name = "Diag.toml")
          | None ->
            incr failures;
            Printf.printf "FAIL: %s error without source\n" label)
        errors)
    diagnostic_cases

let test_wire () =
  (match Wire.of_string "[\"a\",2,null]" with
   | Ok (`List [ `String "a"; `Int 2; `Null ]) -> ()
   | _ ->
     incr failures;
     Printf.printf "FAIL: wire parse\n");
  let errors = expect_single "wire duplicate" (Wire.of_string "{\"a\":1,\"a\":2}") in
  check "wire duplicate code" (has_code Error.Code.duplicate_key errors);
  check "wire invalid json"
    (has_code Error.Code.invalid_json (expect_single "wire json" (Wire.of_string "{oops")));
  check "wire comment"
    (has_code Error.Code.invalid_json
       (expect_single "wire comment" (Wire.of_string "/* hi */[]")));
  check "wire int range"
    (has_code Error.Code.int_out_of_range (expect_single "wire range" (Wire.enc_int 9007199254740992)));
  check "wire int non-integer"
    (has_code Error.Code.invalid_int
       (expect_single "wire non-integer" (Wire.dec_int (`Float 1.5))));
  check "wire float nan"
    (has_code Error.Code.invalid_float
       (expect_single "wire nan" (Wire.enc_float Float.nan)));
  check "wire required null"
    (has_code Error.Code.type_mismatch
       (expect_single "wire null" (Wire.dec_string `Null)));
  let list_result =
    Wire.dec_list Wire.dec_int (`List [ `Int 1; `String "x" ])
  in
  (match list_result with
   | Error { Error.path = [ "1" ]; _ } -> ()
   | _ ->
     incr failures;
     Printf.printf "FAIL: nested list error path\n");
  check_equal "wire compact" "[\"x,y\",3,null]"
    (Wire.to_string (`List [ `String "x,y"; `Int 3; `Null ]));
  check_equal "wire float accepts int" "1.5" "1.5";
  (match Wire.dec_int (`Float 2.0) with
   | Ok 2 -> ()
   | _ ->
     incr failures;
     Printf.printf "FAIL: float integral int\n")

let test_descriptor () =
  let schema = expect_ok "compile" (CC.compile ~sources:(example_sources ())) in
  let json = CC.Descriptor.schema_json schema in
  match Yojson.Safe.from_string json with
  | `Assoc fields ->
    check "descriptor format"
      (List.assoc_opt "format" fields = Some (`Int 1));
    (match List.assoc_opt "modules" fields with
     | Some (`List [ `Assoc common; `Assoc orders ]) ->
       check "descriptor module order"
         (List.assoc_opt "name" common = Some (`String "Common")
          && List.assoc_opt "name" orders = Some (`String "Orders"))
     | _ ->
       incr failures;
       Printf.printf "FAIL: descriptor modules\n")
  | _ ->
    incr failures;
    Printf.printf "FAIL: descriptor root\n"

let () =
  test_compile_example ();
  test_generate_determinism ();
  test_generate_errors ();
  test_collision ();
  test_diagnostics ();
  test_wire ();
  test_descriptor ();
  if !failures = 0 then Printf.printf "all contract tests passed\n"
  else begin
    Printf.printf "%d contract test(s) failed\n" !failures;
    exit 1
  end