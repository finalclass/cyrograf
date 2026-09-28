(* Stage 02 tests for the [migrate] composition. They cover the checks listed
   under "Migracja" in docs/stp.md. *)

open Cyrograf
module CC = Cyrograf_compiler
module Tooling = Cyrograf_tooling.Tooling

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

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    end
    else Sys.remove path

let temp_dir () =
  let path = Filename.temp_file "cyrograf-migrate" "" in
  Sys.remove path;
  Unix.mkdir path 0o755;
  path

let write path text =
  let channel = open_out_bin path in
  output_string channel text;
  close_out channel

let read path =
  let channel = open_in_bin path in
  let text = really_input_string channel (in_channel_length channel) in
  close_in channel;
  text

let has_code code errors = List.exists (fun (error : Error.t) -> error.code = code) errors

let orders_toml =
  "# Service contract\n\
   [service.rpc]\n\
   reserve = \"ReserveRequest -> ReserveResponse\"\n\
   \n\
   [msg.ReserveRequest.struct]\n\
   owner_id = \"string\"\n\
   quantity = \"int\"\n\
   note = { type = \"string\", optional = true } # a trailing TOML comment\n\
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

let common_native = "struct UserCtx { user_id: String }\n"

let make_project directory =
  write (Filename.concat directory "Orders.toml") orders_toml;
  write (Filename.concat directory "Common.cyrograf") common_native

let is_contract name =
  Filename.check_suffix name ".cyrograf" || Filename.check_suffix name ".toml"

let sources_of directory =
  Sys.readdir directory |> Array.to_list |> List.sort String.compare
  |> List.filter is_contract
  |> List.map (fun name ->
      { CC.name; text = read (Filename.concat directory name) })

let test_migration () =
  let source = temp_dir () and output = temp_dir () in
  remove_tree output;
  make_project source;
  let before = sources_of source in
  (match Tooling.migrate ~directory:source ~output with
   | Error errors ->
     incr failures;
     Printf.printf "FAIL: migrate returned errors:\n";
     List.iter (fun error -> Printf.printf "  %s\n" (Error.to_string error)) errors
   | Ok (paths, comments_moved) ->
     check "migration publishes paths" (List.length paths >= 2);
     check "migration reports moved comments" comments_moved;
     check "native file copied" (Sys.file_exists (Filename.concat output "Common.cyrograf"));
     check "toml file converted" (Sys.file_exists (Filename.concat output "Orders.cyrograf"));
     let native_text = read (Filename.concat output "Orders.cyrograf") in
     check "comments moved to the top"
       (String.length native_text >= 19
        && String.sub native_text 0 19 = "// Service contract");
     check_equal "native copy unchanged" common_native
       (read (Filename.concat output "Common.cyrograf")));
  check_equal "sources unchanged" (String.concat "\000" (List.map (fun s -> s.CC.text) before))
    (String.concat "\000" (List.map (fun s -> s.CC.text) (sources_of source)));
  (match CC.compile ~sources:(sources_of source) with
   | Error _ -> check "input compiles" false
   | Ok input_schema -> (
     match CC.compile ~sources:(sources_of output) with
     | Error _ -> check "output compiles" false
     | Ok output_schema ->
       check_equal "migration preserves schema"
         (CC.Descriptor.schema_json input_schema)
         (CC.Descriptor.schema_json output_schema)));
  let first = sources_of output in
  (match Tooling.migrate ~directory:source ~output with
   | Error _ -> check "second migration succeeds" false
   | Ok _ ->
     check_equal "second migration deterministic"
       (String.concat "\000" (List.map (fun s -> s.CC.text) first))
       (String.concat "\000" (List.map (fun s -> s.CC.text) (sources_of output))));
  remove_tree source;
  remove_tree output

let test_native_only () =
  let source = temp_dir () and output = temp_dir () in
  remove_tree output;
  write (Filename.concat source "Common.cyrograf") common_native;
  (match Tooling.migrate ~directory:source ~output with
   | Error _ -> check "native-only migration" false
   | Ok (_, comments_moved) ->
     check "native-only has no moved comments" (not comments_moved);
     check_equal "native-only copies bytes" common_native
       (read (Filename.concat output "Common.cyrograf")));
  remove_tree source;
  remove_tree output

let test_invalid_no_partial () =
  let source = temp_dir () and output = temp_dir () in
  remove_tree output;
  write (Filename.concat source "Bad.toml") "[msg.M.struct]\nx = \"nope\"\n";
  (match Tooling.migrate ~directory:source ~output with
   | Ok _ -> check "invalid migration rejected" false
   | Error errors -> check "invalid migration code" (has_code Error.Code.unknown_type errors));
  check "invalid migration publishes nothing" (not (Sys.file_exists output));
  remove_tree source;
  remove_tree output

let test_duplicate_module () =
  let source = temp_dir () and output = temp_dir () in
  remove_tree output;
  write (Filename.concat source "Orders.toml") orders_toml;
  write (Filename.concat source "Orders.cyrograf") "struct A { x: String }\n";
  (match Tooling.migrate ~directory:source ~output with
   | Ok _ -> check "duplicate module rejected" false
   | Error errors -> check "duplicate module code" (has_code Error.Code.duplicate errors));
  check "duplicate module publishes nothing" (not (Sys.file_exists output));
  remove_tree source;
  remove_tree output

let test_foreign_output () =
  let source = temp_dir () and output = temp_dir () in
  write (Filename.concat source "Orders.toml") orders_toml;
  write (Filename.concat output "keep.txt") "foreign\n";
  (match Tooling.migrate ~directory:source ~output with
   | Ok _ -> check "foreign file rejected" false
   | Error errors -> check "foreign file code" (has_code Error.Code.foreign_file errors));
  check "foreign file preserved" (Sys.file_exists (Filename.concat output "keep.txt"));
  remove_tree source;
  remove_tree output

let test_overlap () =
  let source = temp_dir () in
  write (Filename.concat source "Orders.toml") orders_toml;
  let output = Filename.concat source "out" in
  (match Tooling.migrate ~directory:source ~output with
   | Ok _ -> check "overlapping output rejected" false
   | Error _ -> ());
  check "overlapping output publishes nothing" (not (Sys.file_exists output));
  remove_tree source

let () =
  test_migration ();
  test_native_only ();
  test_invalid_no_partial ();
  test_duplicate_module ();
  test_foreign_output ();
  test_overlap ();
  if !failures = 0 then Printf.printf "all migrate tests passed\n"
  else begin
    Printf.printf "%d migrate test(s) failed\n" !failures;
    exit 1
  end