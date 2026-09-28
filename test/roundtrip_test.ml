(* Round-trips and error handling of the generated OCaml code through the two
   public conversions only. *)

open Cyrograf

module G = Generated_fixtures
module Orders = G.Orders
module Common = G.Common

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

let drut_text label to_drut value =
  match to_drut value with
  | Ok text -> Some text
  | Error error ->
    incr failures;
    Printf.printf "FAIL: %s encode error: %s\n" label (Error.to_string error);
    None

let test_reserve_request () =
  let value = Orders.ReserveRequest.make ~owner_id:"owner-7" ~quantity:2 () in
  check_equal "request wire" "[\"owner-7\",2,null]"
    (Option.value ~default:"?" (drut_text "request" Orders.ReserveRequest.to_drut value));
  (match Orders.ReserveRequest.from_drut "[\"owner-7\",2,null]" with
   | Ok decoded ->
     check "request round trip" (decoded = value)
   | Error error ->
     incr failures;
     Printf.printf "FAIL: request decode: %s\n" (Error.to_string error));
  (match Orders.ReserveRequest.from_drut "[\"owner-7\"]" with
   | Error { Error.code; _ } -> check_equal "request arity code" Error.Code.unexpected_length code
   | Ok _ ->
     incr failures;
     Printf.printf "FAIL: request arity accepted\n");
  (match Orders.ReserveRequest.from_drut "[\"owner-7\",null,null]" with
   | Error { Error.code; path; _ } ->
     check_equal "request null code" Error.Code.type_mismatch code;
     check "request null path" (List.mem "quantity" path)
   | Ok _ ->
     incr failures;
     Printf.printf "FAIL: request null accepted\n")

let test_variants () =
  let reserved =
    Orders.ReserveResponse.Reserved (Orders.Reservation.make ~id:"r-9" ())
  in
  check_equal "reserved wire" "[\"Reserved\",[\"r-9\"]]"
    (Option.value ~default:"?"
       (drut_text "reserved" Orders.ReserveResponse.to_drut reserved));
  let rejected =
    Orders.ReserveResponse.Rejected
      (Orders.Problem.make ~code:"quota" ~message:"Limit" ())
  in
  check_equal "rejected wire" "[\"Rejected\",[\"quota\",\"Limit\"]]"
    (Option.value ~default:"?"
       (drut_text "rejected" Orders.ReserveResponse.to_drut rejected));
  let unavailable = Orders.ReserveResponse.Unavailable in
  check_equal "unavailable wire" "[\"Unavailable\",null]"
    (Option.value ~default:"?"
       (drut_text "unavailable" Orders.ReserveResponse.to_drut unavailable));
  (match Orders.ReserveResponse.from_drut "[\"Reserved\",[\"r-9\"]]" with
   | Ok decoded -> check "reserved round trip" (decoded = reserved)
   | Error error ->
     incr failures;
     Printf.printf "FAIL: reserved decode: %s\n" (Error.to_string error));
  (match Orders.ReserveResponse.from_drut "[\"Nope\",null]" with
   | Error { Error.code; _ } -> check_equal "unknown tag" Error.Code.invalid_variant code
   | Ok _ ->
     incr failures;
     Printf.printf "FAIL: unknown tag accepted\n");
  (match Orders.ReserveResponse.from_drut "[\"Reserved\",1]" with
   | Error _ -> ()
   | Ok _ ->
     incr failures;
     Printf.printf "FAIL: bad payload accepted\n")

let test_batch () =
  let value =
    Orders.ReservationBatch.make
      ~items:
        [ Orders.Reservation.make ~id:"r-9" ();
          Orders.Reservation.make ~id:"r-10" () ]
      ()
  in
  check_equal "batch wire" "[[[\"r-9\"],[\"r-10\"]]]"
    (Option.value ~default:"?"
       (drut_text "batch" Orders.ReservationBatch.to_drut value));
  (match Orders.ReservationBatch.from_drut "[[[\"r-9\"]]]" with
   | Ok decoded ->
     check "batch round trip"
       (decoded = Orders.ReservationBatch.make
          ~items:[ Orders.Reservation.make ~id:"r-9" () ] ())
   | Error error ->
     incr failures;
     Printf.printf "FAIL: batch decode: %s\n" (Error.to_string error));
  let empty = Orders.ReservationBatch.make ~items:[] () in
  check_equal "empty batch wire" "[[]]"
    (Option.value ~default:"?"
       (drut_text "empty batch" Orders.ReservationBatch.to_drut empty))

let test_cross_module () =
  let value =
    Common.Wrapper.make ~ctx:(Common.UserCtx.make ~user_id:"u-1" ()) ~label:"L" ()
  in
  check_equal "wrapper wire" "[[\"u-1\"],\"L\"]"
    (Option.value ~default:"?"
       (drut_text "wrapper" Common.Wrapper.to_drut value));
  (match Common.Wrapper.from_drut "[[\"u-1\"],null]" with
   | Ok decoded -> check "wrapper none label" (decoded = Common.Wrapper.make ~ctx:(Common.UserCtx.make ~user_id:"u-1" ()) ())
   | Error error ->
     incr failures;
     Printf.printf "FAIL: wrapper decode: %s\n" (Error.to_string error))

let test_extra_shapes () =
  check_equal "empty struct wire" "[]"
    (Option.value ~default:"?"
       (drut_text "empty" Common.Empty.to_drut (Common.Empty.make ())));
  (match Common.Empty.from_drut "[]" with
   | Ok () -> ()
   | Error error ->
     incr failures;
     Printf.printf "FAIL: empty decode: %s\n" (Error.to_string error));
  check_equal "void field wire" "[null]"
    (Option.value ~default:"?"
       (drut_text "void" Common.VoidBox.to_drut (Common.VoidBox.make ~nothing:() ())));
  let none = Orders.ListBox.make () in
  check_equal "optional list none" "[null]"
    (Option.value ~default:"?"
       (drut_text "listbox none" Orders.ListBox.to_drut none));
  let some =
    Orders.ListBox.make
      ~items:[ Orders.Reservation.make ~id:"r-9" () ] ()
  in
  check_equal "optional list some" "[[[\"r-9\"]]]"
    (Option.value ~default:"?"
       (drut_text "listbox some" Orders.ListBox.to_drut some));
  (match Orders.ListBox.from_drut "[null]" with
   | Ok decoded -> check "optional list none round trip" (decoded = none)
   | Error error ->
     incr failures;
     Printf.printf "FAIL: listbox none decode: %s\n" (Error.to_string error))

let test_text_strictness () =
  let value = Orders.ReserveRequest.make ~owner_id:"o" ~quantity:1 () in
  (match Orders.ReserveRequest.to_drut value with
   | Ok text -> check_equal "text encode" "[\"o\",1,null]" text
   | Error error ->
     incr failures;
     Printf.printf "FAIL: text encode: %s\n" (Error.to_string error));
  (match Orders.ReserveRequest.from_drut "{\"a\":1,\"a\":2}" with
   | Error { Error.code; _ } -> check_equal "duplicate keys" Error.Code.duplicate_key code
   | Ok _ ->
     incr failures;
     Printf.printf "FAIL: duplicate keys accepted\n")

let () =
  test_reserve_request ();
  test_variants ();
  test_batch ();
  test_cross_module ();
  test_extra_shapes ();
  test_text_strictness ();
  if !failures = 0 then Printf.printf "all generated OCaml tests passed\n"
  else begin
    Printf.printf "%d generated test(s) failed\n" !failures;
    exit 1
  end