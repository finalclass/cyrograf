let () =
  let request : Generated_fixtures.Orders.ReserveRequest.t =
    Generated_fixtures.Orders.ReserveRequest.make ~owner_id:"o1" ~quantity:2 ()
  in
  match Generated_fixtures.Orders.ReserveRequest.to_drut request with
  | Error error -> prerr_endline (Cyrograf.Error.to_string error); exit 1
  | Ok text -> (
    match Generated_fixtures.Orders.ReserveRequest.from_drut text with
    | Error error -> prerr_endline (Cyrograf.Error.to_string error); exit 1
    | Ok decoded -> Printf.printf "positive %s\n" decoded.owner_id)
