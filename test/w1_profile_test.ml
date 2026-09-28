(* W1 acceptance on the native side: the OCaml js_of_ocaml profile ([Int] as
   [int64]) produces the same Drut text as the native profile and preserves the
   full Drut range, and the public compiler information projection matches the
   generated symbols. The real js_of_ocaml run is [make test-ocaml-js]. *)

module CN = Generated_fixtures
module CJ = Generated_fixtures_js
module CC = Cyrograf_compiler

let failures = ref 0

let check name condition =
  if not condition then begin
    incr failures;
    Printf.printf "FAIL: %s\n" name
  end

let native_guard text = CN.Orders.Guard.from_drut text
let js_guard text = CJ.Orders.Guard.from_drut text

let encoded_text name native_value js_value =
  match
    ( CN.Orders.Guard.to_drut native_value,
      CJ.Orders.Guard.to_drut js_value )
  with
  | Ok native_text, Ok js_text ->
    check (name ^ ": identical Drut text") (native_text = js_text);
    Some native_text
  | _ ->
    check (name ^ ": to_drut succeeded") false;
    None

let decode_guard name text expected_big expected_small expected_ratio =
  match (native_guard text, js_guard text) with
  | Ok native_value, Ok js_value ->
    check (name ^ ": native big") (native_value.CN.Orders.Guard.big = expected_big);
    check (name ^ ": native small") (native_value.CN.Orders.Guard.small = expected_small);
    check (name ^ ": native ratio") (native_value.CN.Orders.Guard.ratio = expected_ratio);
    check (name ^ ": js big") (js_value.CJ.Orders.Guard.big = Int64.of_int expected_big);
    check (name ^ ": js small")
      (js_value.CJ.Orders.Guard.small = Int64.of_int expected_small);
    check (name ^ ": js ratio") (js_value.CJ.Orders.Guard.ratio = expected_ratio);
    encoded_text name native_value js_value
  | Error (native : Cyrograf.Error.t), Error (js : Cyrograf.Error.t) ->
    check (name ^ ": native rejected") true;
    check (name ^ ": js rejected") true;
    check (name ^ ": same code") (native.code = js.code);
    None
  | Ok _, Error _ ->
    check (name ^ ": native accepted but js rejected") false;
    None
  | Error _, Ok _ ->
    check (name ^ ": js accepted but native rejected") false;
    None

let decode_rejected name text =
  let code_of result =
    match result with
    | Ok _ -> None
    | Error (error : Cyrograf.Error.t) -> Some error.code
  in
  let native = code_of (native_guard text) in
  let js = code_of (js_guard text) in
  check (name ^ ": native rejected") (native <> None);
  check (name ^ ": js rejected") (js <> None);
  check (name ^ ": same code") (native = js)

let int_range_and_boundaries () =
  ignore
    (decode_guard "drut max" {|["9007199254740991",-9007199254740991,0.5,"x"]|}
       9007199254740991 (-9007199254740991) 0.5);
  ignore
    (decode_guard "32-bit edges" {|["2147483648",-2147483649,1.5,"x"]|}
       2147483648 (-2147483649) 1.5);
  ignore
    (decode_guard "32-bit max" {|["2147483647",-2147483648,2.5,"x"]|}
       2147483647 (-2147483648) 2.5);
  ignore
    (decode_guard "exact exponent" {|["1e3",-2e3,1.5,"x"]|} 1000 (-2000) 1.5);
  ignore
    (decode_guard "exact fraction" {|["1.5e1",-3.0,1.5,"x"]|} 15 (-3) 1.5);
  decode_rejected "non-exact fraction" {|["1.0000000000000001",0,0.5,"x"]|};
  decode_rejected "non-exact fraction small" {|["1.5",0,0.5,"x"]|};
  decode_rejected "above range" {|["9007199254740992",0,0.5,"x"]|};
  decode_rejected "below range" {|["-9007199254740992",0,0.5,"x"]|}

let unicode_and_record () =
  let text = {|["1",-1,0.5,"zażółć gęślą jaźń 𝄞"]|} in
  match decode_guard "unicode" text 1 (-1) 0.5 with
  | None -> ()
  | Some _ ->
    let blob_text = {|["blob",{"a":1,"b":[true,"x"],"c":1.5,"d":9007199254740991}]|} in
    (match
       ( CN.Common.Blob.from_drut blob_text,
         CJ.Common.Blob.from_drut blob_text )
     with
     | Ok native, Ok js_value ->
       (match
          ( CN.Common.Blob.to_drut native,
            CJ.Common.Blob.to_drut js_value )
        with
        | Ok a, Ok b -> check "record: identical Drut text" (a = b)
        | _ -> check "record: to_drut succeeded" false)
     | _ -> check "record: decode succeeded" false)

let lists_variants_and_optional () =
  let reservation text =
    (CN.Orders.Reservation.from_drut text, CJ.Orders.Reservation.from_drut text)
  in
  (match reservation {|["r1"]|} with
   | Ok a, Ok b ->
     (match
        (CN.Orders.Reservation.to_drut a, CJ.Orders.Reservation.to_drut b)
      with
      | Ok x, Ok y -> check "reference: identical Drut text" (x = y)
      | _ -> check "reference: to_drut succeeded" false)
   | _ -> check "reference: decode succeeded" false);
  let list_text = {|[[["r1"],["r2"]]]|} in
  (match (CN.Orders.ListBox.from_drut list_text, CJ.Orders.ListBox.from_drut list_text) with
   | Ok a, Ok b ->
     (match (CN.Orders.ListBox.to_drut a, CJ.Orders.ListBox.to_drut b) with
      | Ok x, Ok y -> check "optional list present: identical Drut text" (x = y)
      | _ -> check "optional list present: to_drut succeeded" false)
   | _ -> check "optional list present: decode succeeded" false);
  let absent_text = {|[null]|} in
  (match (CN.Orders.ListBox.from_drut absent_text, CJ.Orders.ListBox.from_drut absent_text) with
   | Ok a, Ok b ->
     (match (CN.Orders.ListBox.to_drut a, CJ.Orders.ListBox.to_drut b) with
      | Ok x, Ok y -> check "optional list absent: identical Drut text" (x = y)
      | _ -> check "optional list absent: to_drut succeeded" false)
   | _ -> check "optional list absent: decode succeeded" false);
  let variant_payload = {|["Reserved",["r1"]]|} in
  (match
     ( CN.Orders.ReserveResponse.from_drut variant_payload,
       CJ.Orders.ReserveResponse.from_drut variant_payload )
   with
   | Ok a, Ok b ->
     (match
        (CN.Orders.ReserveResponse.to_drut a, CJ.Orders.ReserveResponse.to_drut b)
      with
      | Ok x, Ok y -> check "variant payload: identical Drut text" (x = y)
      | _ -> check "variant payload: to_drut succeeded" false)
   | _ -> check "variant payload: decode succeeded" false);
  let variant_void = {|["Unavailable",null]|} in
  (match
     ( CN.Orders.ReserveResponse.from_drut variant_void,
       CJ.Orders.ReserveResponse.from_drut variant_void )
   with
   | Ok a, Ok b ->
     (match
        (CN.Orders.ReserveResponse.to_drut a, CJ.Orders.ReserveResponse.to_drut b)
      with
      | Ok x, Ok y -> check "variant void: identical Drut text" (x = y)
      | _ -> check "variant void: to_drut succeeded" false)
   | _ -> check "variant void: decode succeeded" false);
  (match (CN.Common.Empty.from_drut "[]", CJ.Common.Empty.from_drut "[]") with
   | Ok a, Ok b ->
     (match (CN.Common.Empty.to_drut a, CJ.Common.Empty.to_drut b) with
      | Ok x, Ok y -> check "empty struct: identical Drut text" (x = y)
      | _ -> check "empty struct: to_drut succeeded" false)
   | _ -> check "empty struct: decode succeeded" false);
  (match (CN.Common.VoidBox.from_drut "[null]", CJ.Common.VoidBox.from_drut "[null]") with
   | Ok a, Ok b ->
     (match (CN.Common.VoidBox.to_drut a, CJ.Common.VoidBox.to_drut b) with
      | Ok x, Ok y -> check "void: identical Drut text" (x = y)
      | _ -> check "void: to_drut succeeded" false)
   | _ -> check "void: decode succeeded" false)

let reconstructed_values () =
  let native =
    CN.Orders.Guard.make ~big:9007199254740991 ~small:(-2147483649) ~ratio:0.5
      ~label:"x" ()
  in
  let js_value =
    CJ.Orders.Guard.make ~big:9007199254740991L ~small:(-2147483649L) ~ratio:0.5
      ~label:"x" ()
  in
  ignore (encoded_text "constructed" native js_value)

let info_projection () =
  check "target name"
    (CC.Info.target_name CC.Ocaml = "ocaml");
  check "ocaml module symbol"
    (CC.Info.module_symbol CC.Ocaml ~module_name:"Orders" = "Orders");
  check "ocaml message symbol"
    (CC.Info.message_symbol CC.Ocaml ~message_name:"Guard" = "Guard");
  check "ocaml qualified message"
    (CC.Info.qualified_message CC.Ocaml ~module_name:"Orders" ~message_name:"Guard"
     = "Orders.Guard");
  check "ocaml data artifact"
    (CC.Info.data_artifact CC.Ocaml ~module_name:"OrderItems"
     = "ocaml/order_items.ml");
  check "ocaml field normalization"
    (CC.Info.normalize_field CC.Ocaml "owner_id" = "owner_id");
  check "typescript module symbol"
    (CC.Info.module_symbol CC.Typescript ~module_name:"Orders" = "Orders");
  check "typescript data artifact"
    (CC.Info.data_artifact CC.Typescript ~module_name:"Orders" = "typescript/orders.ts");
  check "typescript field normalization"
    (CC.Info.normalize_field CC.Typescript "owner_id" = "ownerId");
  check "go field normalization"
    (CC.Info.normalize_field CC.Go "owner_id" = "OwnerID");
  check "go data artifact"
    (CC.Info.data_artifact CC.Go ~module_name:"OrderItems"
     = "go/orderitems/orderitems.go");
  check "rust qualified message"
    (CC.Info.qualified_message CC.Rust ~module_name:"Orders" ~message_name:"ReserveRequest"
     = "orders::ReserveRequest")

let () =
  int_range_and_boundaries ();
  unicode_and_record ();
  lists_variants_and_optional ();
  reconstructed_values ();
  info_projection ();
  if !failures > 0 then begin
    Printf.printf "w1 profile test: %d failure(s)\n" !failures;
    exit 1
  end
  else print_endline "w1 profile test: ok"