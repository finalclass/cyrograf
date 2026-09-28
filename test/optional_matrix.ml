(* One endpoint of the cross-language optional-field exchange.

   produce OUT : build each canonical optional case through the public
                 `to_drut` of the generated message and write its encodings.
   consume IN  : decode a peer's encodings through the public `from_drut`,
                 check the typed field states and re-encode the same Drut. *)

open Cyrograf

module Api = Generated_api.Api
module Box = Api.OptionalBox
module Choice = Api.Choice

let cases =
  [ ("absent", Box.make ~owner_id:"o1" ());
    ("empty_string", Box.make ~owner_id:"o1" ~text:"" ());
    ("zero", Box.make ~owner_id:"o1" ~count:0 ());
    ("false", Box.make ~owner_id:"o1" ~flag:false ());
    ("empty_list", Box.make ~owner_id:"o1" ~items:[] ());
    ("variant_text", Box.make ~owner_id:"o1" ~choice:(Choice.Text "x") ());
    ("variant_void", Box.make ~owner_id:"o1" ~choice:Choice.Empty ());
    ("all_present",
     Box.make ~owner_id:"o1" ~text:"" ~count:0 ~flag:false ~items:[]
       ~choice:Choice.Empty ()) ]

let fail message =
  prerr_endline ("FAIL: " ^ message);
  exit 1

let drut value =
  match Box.to_drut value with
  | Ok text -> text
  | Error error -> fail (Error.to_string error)

let decode text =
  match Box.from_drut text with
  | Ok value -> value
  | Error error -> fail (Error.to_string error)

let expected_wires () =
  match Yojson.Safe.from_file Sys.argv.(2) with
  | `List items ->
    List.map
      (fun json ->
        let open Yojson.Safe.Util in
        (json |> member "id" |> to_string, json |> member "wire" |> to_string))
      items
  | _ -> fail "the cases file is not a JSON array"
  | exception Yojson.Json_error message -> fail message

let check_semantics id (value : Box.t) =
  let none = function None -> true | Some _ -> false in
  let expected =
    match id with
    | "absent" ->
      none value.text && none value.count && none value.flag && none value.items
      && none value.choice
    | "empty_string" ->
      value.text = Some "" && none value.count && none value.flag
      && none value.items && none value.choice
    | "zero" ->
      none value.text && value.count = Some 0 && none value.flag
      && none value.items && none value.choice
    | "false" ->
      none value.text && none value.count && value.flag = Some false
      && none value.items && none value.choice
    | "empty_list" ->
      none value.text && none value.count && none value.flag
      && value.items = Some [] && none value.choice
    | "variant_text" ->
      none value.text && none value.count && none value.flag && none value.items
      && value.choice = Some (Choice.Text "x")
    | "variant_void" ->
      none value.text && none value.count && none value.flag && none value.items
      && value.choice = Some Choice.Empty
    | "all_present" ->
      value.text = Some "" && value.count = Some 0 && value.flag = Some false
      && value.items = Some [] && value.choice = Some Choice.Empty
    | other -> fail ("unknown case " ^ other)
  in
  if not expected then fail ("case " ^ id ^ " decoded to the wrong typed value")

let produce () =
  let wires = expected_wires () in
  let entries =
    List.map
      (fun (id, value) ->
        let wire = drut value in
        (match List.assoc_opt id wires with
         | Some expected when expected = wire -> ()
         | Some expected ->
           fail (Printf.sprintf "case %s encoded %s, expected %s" id wire expected)
         | None -> fail ("no canonical wire for case " ^ id));
        `Assoc [ ("id", `String id); ("wire", `String wire) ])
      cases
  in
  let channel = open_out_bin Sys.argv.(3) in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      output_string channel (Yojson.Safe.to_string (`List entries)));
  Printf.printf "ocaml produced %d optional case(s)\n" (List.length cases)

let consume () =
  match Yojson.Safe.from_file Sys.argv.(2) with
  | `List items ->
    List.iter
      (fun json ->
        let open Yojson.Safe.Util in
        let id = json |> member "id" |> to_string in
        let wire = json |> member "wire" |> to_string in
        let value = decode wire in
        check_semantics id value;
        let reencoded = drut value in
        if reencoded <> wire then
          fail (Printf.sprintf "case %s re-encoded %s, received %s" id reencoded wire))
      items;
    Printf.printf "ocaml consumed %d optional case(s)\n" (List.length items)
  | _ -> fail "the peer file is not a JSON array"
  | exception Yojson.Json_error message -> fail message

let () =
  match Sys.argv.(1) with
  | "produce" -> produce ()
  | "consume" -> consume ()
  | other -> fail ("unknown mode " ^ other)