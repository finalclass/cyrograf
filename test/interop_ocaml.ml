(* OCaml side of the cross-language Wire exchange test. *)

open Cyrograf

module G = Generated_fixtures
module Orders = G.Orders
module Common = G.Common
module Numbers = G.Numbers

module Runtime = G.Drut_runtime

let label =
  match Sys.getenv_opt "CYROGRAF_PEER" with
  | Some value -> value
  | None -> "ocaml"

let roundtrip decode encode text =
  match decode text with
  | Error error -> Error error
  | Ok value -> encode value

let registry =
  [ ("Orders.ReserveRequest",
     roundtrip Orders.ReserveRequest.from_drut Orders.ReserveRequest.to_drut);
    ("Orders.Reservation",
     roundtrip Orders.Reservation.from_drut Orders.Reservation.to_drut);
    ("Orders.Problem",
     roundtrip Orders.Problem.from_drut Orders.Problem.to_drut);
    ("Orders.ReserveResponse",
     roundtrip Orders.ReserveResponse.from_drut Orders.ReserveResponse.to_drut);
    ("Orders.ReservationBatch",
     roundtrip Orders.ReservationBatch.from_drut Orders.ReservationBatch.to_drut);
    ("Orders.Guard",
     roundtrip Orders.Guard.from_drut Orders.Guard.to_drut);
    ("Orders.ListBox",
     roundtrip Orders.ListBox.from_drut Orders.ListBox.to_drut);
    ("Orders.ResponseBox",
     roundtrip Orders.ResponseBox.from_drut Orders.ResponseBox.to_drut);
    ("Orders.Scalars",
     roundtrip Orders.Scalars.from_drut Orders.Scalars.to_drut);
    ("Common.UserCtx",
     roundtrip Common.UserCtx.from_drut Common.UserCtx.to_drut);
    ("Common.Wrapper",
     roundtrip Common.Wrapper.from_drut Common.Wrapper.to_drut);
    ("Common.Blob",
     roundtrip Common.Blob.from_drut Common.Blob.to_drut);
    ("Common.Empty",
     roundtrip Common.Empty.from_drut Common.Empty.to_drut);
    ("Common.VoidBox",
     roundtrip Common.VoidBox.from_drut Common.VoidBox.to_drut);
    ("Numbers.NumberBox",
     roundtrip Numbers.NumberBox.from_drut Numbers.NumberBox.to_drut);
    ("Numbers.NumberChoice",
     roundtrip Numbers.NumberChoice.from_drut Numbers.NumberChoice.to_drut);
    ("Numbers.NumberHolder",
     roundtrip Numbers.NumberHolder.from_drut Numbers.NumberHolder.to_drut);
    ("Numbers.NumberUser",
     roundtrip Numbers.NumberUser.from_drut Numbers.NumberUser.to_drut) ]

type entry = {
  id : string;
  type_name : string;
  wire : string;
  semantic : bool;
}

let entry_of_json json =
  let open Yojson.Safe.Util in
  { id = json |> member "id" |> to_string;
    type_name = json |> member "type" |> to_string;
    wire = json |> member "wire" |> to_string;
    semantic = json |> member "semantic" |> to_bool_option |> Option.value ~default:false }

let read_entries path =
  match Yojson.Safe.from_file path with
  | `List items -> List.map entry_of_json items
  | _ -> failwith "expected a JSON array"
  | exception Yojson.Json_error message -> failwith message

let same_value left right =
  Yojson.Safe.equal (Yojson.Safe.from_string left) (Yojson.Safe.from_string right)

let verify_entry (entry : entry) =
  match List.assoc_opt entry.type_name registry with
  | None -> failwith ("unknown type " ^ entry.type_name)
  | Some ops ->
    (match ops entry.wire with
     | Error error -> failwith (Error.to_string error)
     | Ok reencoded ->
       let matches =
         if entry.semantic then same_value reencoded entry.wire
         else reencoded = entry.wire
       in
       if not matches then
         failwith (Printf.sprintf "%s (%s): %s <> %s" entry.id entry.type_name
                     reencoded entry.wire);
       reencoded)

let emit (entry : entry) reencoded =
  `Assoc
    [ ("id", `String entry.id);
      ("type", `String entry.type_name);
      ("wire", `String reencoded) ]

(* ── Pinned Drut conformance corpus via root descriptors ───────────── *)

let primitives =
  [ ("void", `Null); ("int", `Null); ("float", `Null); ("bool", `Null);
    ("string", `Null); ("date", `Null); ("record", `Null) ]

let is_primitive name = List.mem_assoc name primitives

let rec decode_desc desc value =
  let open Runtime.Syntax in
  match desc with
  | `String "void" ->
    let* _ = Runtime.dec_void value in
    Ok `Null
  | `String "int" ->
    let* number = Runtime.dec_int value in
    Ok (`Intlit (Runtime.int_to_string number))
  | `String "float" ->
    let* number = Runtime.dec_float value in
    Ok (`Float number)
  | `String "bool" ->
    let* flag = Runtime.dec_bool value in
    Ok (`Bool flag)
  | `String ("string" | "date") ->
    let* text = Runtime.dec_string value in
    Ok (`String text)
  | `String "record" -> Runtime.dec_record value
  | `Assoc [ ("list", inner) ] ->
    let* items = Runtime.dec_list (decode_desc inner) value in
    Ok (`List items)
  | _ ->
    Runtime.error ~code:Error.Code.invalid_type
      (Printf.sprintf "unsupported root descriptor %s"
         (Yojson.Safe.to_string desc))

let hex_to_string hex =
  let length = String.length hex in
  let buffer = Buffer.create (length / 2) in
  let digit character =
    match character with
    | '0' .. '9' -> Char.code character - Char.code '0'
    | 'a' .. 'f' -> Char.code character - Char.code 'a' + 10
    | 'A' .. 'F' -> Char.code character - Char.code 'A' + 10
    | _ -> failwith ("invalid hex digit " ^ String.make 1 character)
  in
  let rec loop index =
    if index + 1 < length then begin
      Buffer.add_char buffer
        (Char.chr ((digit hex.[index] lsl 4) lor digit hex.[index + 1]));
      loop (index + 2)
    end
  in
  loop 0;
  Buffer.contents buffer

type drut_case = {
  drut_id : string;
  drut_type : Yojson.Safe.t;
  drut_category : string;
  drut_wire : string option;
  drut_wire_hex : string option;
  drut_value : Yojson.Safe.t option;
}

let drut_of_json json =
  let open Yojson.Safe.Util in
  { drut_id = json |> member "id" |> to_string;
    drut_type = json |> member "type";
    drut_category =
      (match json |> member "category" with
       | `String value -> value
       | _ -> "runtime");
    drut_wire = json |> member "wire" |> to_string_option;
    drut_wire_hex = json |> member "wire_hex" |> to_string_option;
    drut_value = (match json |> member "value" with `Null -> None | value -> Some value) }

let read_drut path =
  match Yojson.Safe.from_file path with
  | `List items -> List.map drut_of_json items
  | _ -> failwith "expected a JSON array"
  | exception Yojson.Json_error message -> failwith message

let drut_bytes (case : drut_case) =
  match (case.drut_wire_hex, case.drut_wire) with
  | Some hex, _ -> hex_to_string hex
  | None, Some wire -> wire
  | None, None -> failwith (case.drut_id ^ ": case has neither wire nor wire_hex")

let run_drut_case (case : drut_case) =
  let bytes = drut_bytes case in
  match case.drut_type with
  | `String name when not (is_primitive name) ->
    (match List.assoc_opt name registry with
     | None -> Error (Error.make ~code:Error.Code.unknown_type ("unknown type " ^ name))
| Some ops ->
       (match ops bytes with
        | Error error -> Error error
        | Ok reencoded ->
          (match Yojson.Safe.from_string reencoded with
           | json -> Ok json
           | exception Yojson.Json_error message ->
             Error (Error.make ~code:Error.Code.invalid_json message))))
  | desc ->
    (match Runtime.of_string bytes with
     | Error error -> Error error
     | Ok value -> decode_desc desc value)

let is_named_descriptor = function
  | `String name -> not (is_primitive name)
  | _ -> false

let rec json_equal left right =
  match (left, right) with
  | `Assoc left_fields, `Assoc right_fields ->
    List.length left_fields = List.length right_fields
    && List.for_all
         (fun (name, value) ->
           match List.assoc_opt name right_fields with
           | Some other -> json_equal value other
           | None -> false)
         left_fields
  | `List left_items, `List right_items ->
    List.length left_items = List.length right_items
    && List.for_all2 json_equal left_items right_items
  | `Int a, `Int b -> a = b
  | `Float a, `Float b -> a = b
  | `Int a, `Float b | `Float b, `Int a -> float_of_int a = b
  | `Intlit a, other | other, `Intlit a ->
    json_equal (Yojson.Safe.from_string a) other
  | `String a, `String b -> a = b
  | `Bool a, `Bool b -> a = b
  | `Null, `Null -> true
  | _ -> false

let drut (valid_path : string) (invalid_path : string) (result_path : string) =
  let valid = read_drut valid_path in
  let invalid = read_drut invalid_path in
  let results = ref [] in
  List.iter
    (fun (case : drut_case) ->
      match run_drut_case case with
      | Error error -> failwith (case.drut_id ^ ": " ^ Error.to_string error)
      | Ok produced ->
        let expected =
          if is_named_descriptor case.drut_type then
            (match case.drut_wire with
             | Some wire -> Some (Yojson.Safe.from_string wire)
             | None -> case.drut_value)
          else case.drut_value
        in
(match expected with
         | Some expected ->
           if not (json_equal produced expected) then
             failwith (Printf.sprintf "%s: %s does not match the expected value"
                         case.drut_id (Yojson.Safe.to_string produced))
         | None -> ());
         let status =
           if case.drut_category = "public" then "executed" else "executed-runtime"
         in
         results := `Assoc [ ("id", `String case.drut_id); ("status", `String status) ]
                    :: !results)
    valid;
  List.iter
    (fun (case : drut_case) ->
      match run_drut_case case with
      | Ok _ -> failwith (case.drut_id ^ ": invalid wire accepted")
      | Error _ ->
        let status =
          if case.drut_category = "public" then "rejected" else "rejected-runtime"
        in
        results := `Assoc [ ("id", `String case.drut_id); ("status", `String status) ]
                   :: !results)
    invalid;
  let channel = open_out_bin result_path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      output_string channel (Yojson.Safe.to_string (`List (List.rev !results))));
  Printf.printf "%s drut: %d executed, %d rejected\n" label
    (List.length valid) (List.length invalid)

(* ── W1 profile cases: shared Drut text in both OCaml profiles ─────── *)

type profile_case = {
  pc_name : string;
  pc_type : string;
  pc_wire : string;
  pc_expect : string option;
}

let profile_cases =
  [ { pc_name = "int-max-range";
      pc_type = "Orders.Guard";
      pc_wire = {|[9007199254740991,-9007199254740991,0.5,"x"]|};
      pc_expect = Some {|[9007199254740991,-9007199254740991,0.5,"x"]|} };
    { pc_name = "int-32bit-edges";
      pc_type = "Orders.Guard";
      pc_wire = {|[2147483648,-2147483649,1.5,"x"]|};
      pc_expect = Some {|[2147483648,-2147483649,1.5,"x"]|} };
    { pc_name = "int-exact-exponent";
      pc_type = "Orders.Guard";
      pc_wire = {|[1e3,-2e3,0.5,"x"]|};
      pc_expect = Some {|[1000,-2000,0.5,"x"]|} };
    { pc_name = "int-non-exact-fraction";
      pc_type = "Orders.Guard";
      pc_wire = {|[1.0000000000000001,0,0.5,"x"]|};
      pc_expect = None };
    { pc_name = "int-above-range";
      pc_type = "Orders.Guard";
      pc_wire = {|[9007199254740992,0,0.5,"x"]|};
      pc_expect = None };
    { pc_name = "int-below-range";
      pc_type = "Orders.Guard";
      pc_wire = {|[-9007199254740992,0,0.5,"x"]|};
      pc_expect = None };
    { pc_name = "unicode";
      pc_type = "Orders.Guard";
      pc_wire = {|[1,-1,0.5,"zażółć gęślą jaźń 𝄞"]|};
      pc_expect = Some {|[1,-1,0.5,"zażółć gęślą jaźń 𝄞"]|} };
    { pc_name = "record";
      pc_type = "Common.Blob";
      pc_wire = {|["blob",{"a":1,"b":[true,"x"],"c":1.5,"d":9007199254740991}]|};
      pc_expect =
        Some {|["blob",{"a":1,"b":[true,"x"],"c":1.5,"d":9007199254740991}]|} };
    { pc_name = "optional-absent";
      pc_type = "Orders.ListBox";
      pc_wire = {|[null]|};
      pc_expect = Some {|[null]|} };
    { pc_name = "optional-present";
      pc_type = "Orders.ListBox";
      pc_wire = {|[[["r1"],["r2"]]]|};
      pc_expect = Some {|[[["r1"],["r2"]]]|} };
    { pc_name = "list";
      pc_type = "Orders.ReservationBatch";
      pc_wire = {|[[["r1"],["r2"]]]|};
      pc_expect = Some {|[[["r1"],["r2"]]]|} };
    { pc_name = "variant-payload";
      pc_type = "Orders.ReserveResponse";
      pc_wire = {|["Reserved",["r1"]]|};
      pc_expect = Some {|["Reserved",["r1"]]|} };
    { pc_name = "variant-void";
      pc_type = "Orders.ReserveResponse";
      pc_wire = {|["Unavailable",null]|};
      pc_expect = Some {|["Unavailable",null]|} };
    { pc_name = "cross-module-reference";
      pc_type = "Common.Wrapper";
      pc_wire = {|[["u1"],"l"]|};
      pc_expect = Some {|[["u1"],"l"]|} };
    { pc_name = "int-in-list";
      pc_type = "Numbers.NumberBox";
      pc_wire = {|[[9007199254740991,-9007199254740991,2147483648,-2147483649],[1,2]]|};
      pc_expect =
        Some {|[[9007199254740991,-9007199254740991,2147483648,-2147483649],[1,2]]|} };
    { pc_name = "int-in-list-optional-absent";
      pc_type = "Numbers.NumberBox";
      pc_wire = {|[[9007199254740991],null]|};
      pc_expect = Some {|[[9007199254740991],null]|} };
    { pc_name = "int-in-list-non-exact";
      pc_type = "Numbers.NumberBox";
      pc_wire = {|[[1.0000000000000001],null]|};
      pc_expect = None };
    { pc_name = "int-in-variant-payload";
      pc_type = "Numbers.NumberChoice";
      pc_wire = {|["Bare",9007199254740991]|};
      pc_expect = Some {|["Bare",9007199254740991]|} };
    { pc_name = "int-in-variant-void";
      pc_type = "Numbers.NumberChoice";
      pc_wire = {|["Nothing",null]|};
      pc_expect = Some {|["Nothing",null]|} };
    { pc_name = "int-in-variant-above-range";
      pc_type = "Numbers.NumberChoice";
      pc_wire = {|["Bare",9007199254740992]|};
      pc_expect = None };
    { pc_name = "int-in-reference";
      pc_type = "Numbers.NumberUser";
      pc_wire = {|[[9007199254740991,"x"],null]|};
      pc_expect = Some {|[[9007199254740991,"x"],null]|} };
    { pc_name = "int-in-reference-optional-present";
      pc_type = "Numbers.NumberUser";
      pc_wire = {|[[-9007199254740991,"x"],[-2147483649,"y"]]|};
      pc_expect = Some {|[[-9007199254740991,"x"],[-2147483649,"y"]]|} } ]

let profile () =
  let failures = ref 0 in
  List.iter
    (fun (case : profile_case) ->
      match List.assoc_opt case.pc_type registry with
      | None -> failwith ("unknown type " ^ case.pc_type)
      | Some ops ->
        (match (ops case.pc_wire, case.pc_expect) with
         | Error error, None ->
           Printf.printf "PASS: %s rejected (%s)\n" case.pc_name error.Error.code
         | Error error, Some _ ->
           incr failures;
           Printf.printf "FAIL: %s rejected: %s\n" case.pc_name
             (Error.to_string error)
         | Ok reencoded, None ->
           incr failures;
           Printf.printf "FAIL: %s accepted %s\n" case.pc_name reencoded
         | Ok reencoded, Some expected ->
           if reencoded = expected then
             Printf.printf "PASS: %s -> %s\n" case.pc_name reencoded
           else begin
             incr failures;
             Printf.printf "FAIL: %s: %s <> %s\n" case.pc_name reencoded expected
           end))
    profile_cases;
  if !failures > 0 then begin
    Printf.printf "%s profile: %d failure(s)\n" label !failures;
    exit 1
  end
  else Printf.printf "%s profile: %d case(s) ok\n" label (List.length profile_cases)

let () =
  let mode = Sys.argv.(1) in
  if mode = "drut" then begin
    drut Sys.argv.(2) Sys.argv.(3) Sys.argv.(4)
  end else if mode = "profile" then begin
    profile ()
  end else begin
  let input = Sys.argv.(2) in
  let entries = read_entries input in
  match mode with
  | "check" ->
    let output = Sys.argv.(3) in
    let results =
      List.map (fun entry -> emit entry (verify_entry entry)) entries
    in
    let channel = open_out_bin output in
    Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
        output_string channel (Yojson.Safe.to_string (`List results)));
    Printf.printf "%s verified %d fixture(s)\n" label (List.length entries)
  | "verify" ->
    List.iter (fun entry -> ignore (verify_entry entry)) entries;
    Printf.printf "%s decoded %d message(s) from peer\n" label
      (List.length entries)
  | "invalid" ->
    let rejected =
      List.fold_left
        (fun count entry ->
          match List.assoc_opt entry.type_name registry with
          | None -> failwith ("unknown type " ^ entry.type_name)
| Some ops ->
             (match ops entry.wire with
              | Error _ -> count + 1
              | Ok _ -> failwith (entry.id ^ ": invalid wire accepted")))
        0 entries
    in
    Printf.printf "%s rejected %d invalid message(s)\n" label rejected
  | other -> failwith ("unknown mode " ^ other)
  end