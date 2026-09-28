(* Optional-field semantics for all optional kinds (String/Int/Bool/List/variant).

   The fixture mirrors api.md: absence is distinct from an empty string, zero,
   false and an empty list, and decoding does not substitute defaults. *)

open Cyrograf

module Api = Generated_api.Api
module Box = Api.OptionalBox
module Choice = Api.Choice

let failures = ref 0

let check label condition =
  if condition then Printf.printf "PASS: %s\n" label
  else begin
    incr failures;
    Printf.printf "FAIL: %s\n" label
  end

let drut value =
  match Box.to_drut value with
  | Ok text -> text
  | Error error -> failwith (Error.to_string error)

let decode text =
  match Box.from_drut text with
  | Ok value -> value
  | Error error -> failwith (Error.to_string error)

let base = Box.make ~owner_id:"o1" ()

let () =
  check "all optional fields absent encode as null"
    (drut base = "[\"o1\",null,null,null,null,null]");

  check "present empty string differs from absence"
    (drut (Box.make ~owner_id:"o1" ~text:"" ()) = "[\"o1\",\"\",null,null,null,null]");

  check "present zero differs from absence"
    (drut (Box.make ~owner_id:"o1" ~count:0 ()) = "[\"o1\",null,0,null,null,null]");

  check "present false differs from absence"
    (drut (Box.make ~owner_id:"o1" ~flag:false ()) = "[\"o1\",null,null,false,null,null]");

  check "present empty list differs from absence"
    (drut (Box.make ~owner_id:"o1" ~items:[] ()) = "[\"o1\",null,null,null,[],null]");

  check "present variant with payload"
    (drut (Box.make ~owner_id:"o1" ~choice:(Choice.Text "x") ())
     = "[\"o1\",null,null,null,null,[\"Text\",\"x\"]]");

  check "present void variant"
    (drut (Box.make ~owner_id:"o1" ~choice:Choice.Empty ())
     = "[\"o1\",null,null,null,null,[\"Empty\",null]]");

  let absent = decode "[\"o1\",null,null,null,null,null]" in
  check "decoded absence is None"
    (absent.text = None && absent.count = None && absent.flag = None
     && absent.items = None && absent.choice = None);

  let present = decode "[\"o1\",\"\",0,false,[],[\"Empty\",null]]" in
  check "decoded empty values stay present"
    (present.text = Some "" && present.count = Some 0 && present.flag = Some false
     && present.items = Some [] && present.choice = Some Choice.Empty);

  check "roundtrip keeps absence"
    (drut (decode (drut base)) = drut base);

  check "roundtrip keeps present empty values"
    (drut (decode (drut present)) = drut present);

  check "required field cannot be absent"
    (match Box.from_drut "[null,null,null,null,null,null]" with
     | Error _ -> true
     | Ok _ -> false);

  check "wrong optional type is an error, not a default"
    (match Box.from_drut "[\"o1\",5,null,null,null,null]" with
     | Error _ -> true
     | Ok _ -> false);

  if !failures > 0 then exit 1