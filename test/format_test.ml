(* Stage 02 tests for [Layout] and the [format] composition. They cover the
   checks listed under "Formatowanie" in docs/stp.md. The boundary tests replace
   [WorkspaceAccess] with a controlled resource to trigger a revision conflict
   and a preparation failure deterministically. *)

open Cyrograf
module CC = Cyrograf_compiler
module Tooling = Cyrograf_tooling.Tooling
module WA = Cyrograf_tooling.Workspace_access

let failures = ref 0

let check label condition =
  if not condition then begin
    incr failures;
    Printf.printf "FAIL: %s\n" label
  end

let check_equal label a b =
  if a <> b then begin
    incr failures;
    Printf.printf "FAIL: %s:\n--- expected ---\n%s\n--- actual ---\n%s\n" label a b
  end

let format name text = CC.format ~name ~text

let expect_format label input expected =
  match format "Test.cyrograf" input with
  | Ok output -> check_equal label expected output
  | Error errors ->
    incr failures;
    Printf.printf "FAIL: %s returned errors:\n" label;
    List.iter (fun error -> Printf.printf "  %s\n" (Error.to_string error)) errors

let canonical_example =
  "// Reservation example\n\
   struct ReserveRequest {\n\
   \  owner_id: String\n\
   \  quantity: Int\n\
   \  note?: String // trailing comment\n\
   }\n\
   \n\
   struct Empty {}\n\
   \n\
   variant ReserveResponse {\n\
   \  Reserved(Reservation)\n\
   \  Rejected(Problem)\n\
   \  Unavailable(Void)\n\
   }\n\
   \n\
   struct Problem {\n\
   \  code: String\n\
   \  message: String\n\
   }\n\
   \n\
   struct Reservation {\n\
   \  id: String\n\
   }\n\
   \n\
   struct ReservationBatch {\n\
   \  items: List<\n\
   \    // the payload may stay multiline when a comment lives inside it\n\
   \    Reservation\n\
   \  >\n\
   }\n\
   \n\
   rpc reserve(ReserveRequest) -> ReserveResponse\n"

let test_canonical () =
  expect_format "canonical example" canonical_example canonical_example

let test_idempotent () =
  match format "Test.cyrograf" canonical_example with
  | Error _ -> check "idempotent format" false
  | Ok once -> (
    match format "Test.cyrograf" once with
    | Ok twice -> check_equal "idempotent format" once twice
    | Error _ -> check "idempotent reparse" false)

let test_comments () =
  let input =
    "struct A { // header\nx:String // field\n// own\ny:Int\n}\n"
  in
  let expected =
    "struct A { // header\n  x: String // field\n  // own\n  y: Int\n}\n"
  in
  expect_format "comments" input expected

let test_empty_and_nested () =
  let input =
    "struct Empty {}\nstruct Nested { xs: List< List< String > > }\nstruct S { v: Void }\n"
  in
  let expected =
    "struct Empty {}\n\n\
     struct Nested {\n\
     \  xs: List<List<String>>\n\
     }\n\n\
     struct S {\n\
     \  v: Void\n\
     }\n"
  in
  expect_format "empty, nested list and explicit void" input expected

let test_nested_optional_with_comments () =
  let input =
    "struct Holder {\n  name?: List< List<\n    // inner\n    String\n  > >\n}\n"
  in
  let expected =
    "struct Holder {\n\
     \  name?: List<\n\
     \    List<\n\
     \      // inner\n\
     \      String\n\
     \    >\n\
     \  >\n\
     }\n"
  in
  expect_format "nested optional list with comments" input expected;
  (match format "Test.cyrograf" expected with
   | Ok again -> check_equal "nested list idempotent" expected again
   | Error _ -> check "nested list idempotent" false)

let test_crlf_bom () =
  let input =
    "\xEF\xBB\xBFstruct A { x: String; y: Int }\r\nstruct Name { very_long_field_name?: List< List< String > > }\r\n"
  in
  let expected =
    "struct A {\n\
     \  x: String\n\
     \  y: Int\n\
     }\n\n\
     struct Name {\n\
     \  very_long_field_name?: List<List<String>>\n\
     }\n"
  in
  expect_format "CRLF and BOM" input expected

let test_syntax_blocks () =
  (match format "Test.cyrograf" "struct A { x: String\n" with
   | Ok _ -> check "syntax error blocks" false
   | Error errors ->
     check "syntax error code"
       (List.exists (fun (error : Error.t) -> error.code = Error.Code.invalid_syntax) errors));
  match format "Test.cyrograf" "struct A { x: nope }\n" with
  | Ok _ -> ()
  | Error _ -> check "semantic error does not block" false

let test_schema_preserved () =
  let source = "Orders.cyrograf" in
  let messy =
    "struct ReserveRequest { owner_id:String\n quantity:Int\n note?:String }\n\
     struct Reservation { id:String }\n\
     struct Problem { code:String; message:String }\n\
     variant ReserveResponse { Reserved(Reservation); Rejected(Problem); Unavailable }\n\
     rpc reserve(ReserveRequest) -> ReserveResponse\n"
  in
  let careful =
    "struct ReserveRequest {\n  owner_id: String\n  quantity: Int\n  note?: String\n}\n\
     struct Reservation {\n  id: String\n}\n\
     struct Problem {\n  code: String\n  message: String\n}\n\
     variant ReserveResponse {\n  Reserved(Reservation)\n  Rejected(Problem)\n  Unavailable\n}\n\
     rpc reserve(ReserveRequest) -> ReserveResponse\n"
  in
  match (CC.compile ~sources:[ { CC.name = source; text = messy } ],
         CC.compile ~sources:[ { CC.name = source; text = careful } ])
  with
  | Error _, _ -> check "messy project compiles" false
  | _, Error _ -> check "careful project compiles" false
  | Ok schema_messy, Ok schema_careful -> (
    match format source messy with
    | Error _ -> check "formats valid project" false
    | Ok formatted ->
      check_equal "format preserves schema" (CC.Descriptor.schema_json schema_careful)
        (CC.Descriptor.schema_json schema_messy);
      check_equal "format output matches compiled schema"
        (CC.Descriptor.schema_json schema_careful)
        (CC.Descriptor.schema_json
           (match CC.compile ~sources:[ { CC.name = source; text = formatted } ] with
            | Ok schema -> schema
            | Error _ ->
              check "formatted project compiles" false;
              schema_messy)))

(* ── Controlled access boundary ───────────────────────────────────── *)

let controlled_source =
  { WA.path = "/controlled/A.cyrograf";
    name = "A.cyrograf";
    text = "struct A { x:String }\n";
    digest = "controlled" }

module Conflict_access = struct
  let capture_native ~paths:_ = Ok { WA.native_sources = [ controlled_source ] }
  let replace_native _ _ = Error [ Error.make ~code:Error.Code.source_changed "conflict" ]
end

module Failure_access = struct
  let capture_native ~paths:_ = Ok { WA.native_sources = [ controlled_source ] }
  let replace_native _ _ = Error [ Error.make ~code:Error.Code.io_error "prepare failed" ]
end

let test_controlled_access () =
  (match
     Tooling.format
       ~access:(module Conflict_access : WA.FORMAT_ACCESS)
       ~paths:[ "/controlled" ] ~check:false ()
   with
   | Ok _ -> check "revision conflict reported" false
   | Error errors ->
     check "revision conflict code"
       (List.exists (fun (error : Error.t) -> error.code = Error.Code.source_changed) errors));
  match
    Tooling.format
      ~access:(module Failure_access : WA.FORMAT_ACCESS)
      ~paths:[ "/controlled" ] ~check:false ()
  with
  | Ok _ -> check "preparation failure reported" false
  | Error errors ->
    check "preparation failure code"
      (List.exists (fun (error : Error.t) -> error.code = Error.Code.io_error) errors)

(* ── CLI process boundary ─────────────────────────────────────────── *)

let binary = Sys.getenv_opt "CYROGRAF_BIN"

let read_all channel =
  let buffer = Buffer.create 256 in
  (try
     while true do
       Buffer.add_channel buffer channel 1
     done
   with End_of_file -> ());
  Buffer.contents buffer

let run_cli args input =
  match binary with
  | None -> None
  | Some binary ->
    let argv = Array.of_list (binary :: args) in
    let stdout_channel, stdin_channel, stderr_channel =
      Unix.open_process_args_full binary argv (Unix.environment ())
    in
    (match input with Some text -> output_string stdin_channel text | None -> ());
    close_out stdin_channel;
    let stdout = read_all stdout_channel in
    let stderr = read_all stderr_channel in
    let status = Unix.close_process_full (stdout_channel, stdin_channel, stderr_channel) in
    Some (status, stdout, stderr)

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      Unix.rmdir path
    end
    else Sys.remove path

let temp_dir () =
  let path = Filename.temp_file "cyrograf-format" "" in
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

let exit_code = function
  | Unix.WEXITED code -> code
  | _ -> -1

let test_cli_process () =
  match binary with
  | None -> Printf.printf "note: CYROGRAF_BIN not set; skipping CLI process tests\n"
  | Some _ ->
    let directory = temp_dir () in
    let messy = Filename.concat directory "Messy.cyrograf" in
    let messy_text = "struct   A{x:String;y:Int}\n" in
    write messy messy_text;
    (match run_cli [ "format"; messy ] None with
     | Some (status, _, _) ->
       check "format writes exit 0" (exit_code status = 0);
       check_equal "format writes canonical" "struct A {\n  x: String\n  y: Int\n}\n"
         (read messy)
     | None -> ());
    (match run_cli [ "format"; "--check"; messy ] None with
     | Some (status, stdout, _) ->
       check "format --check clean exit 0" (exit_code status = 0);
       check_equal "format --check clean output" "" stdout
     | None -> ());
    write messy messy_text;
    (match run_cli [ "format"; "--check"; messy ] None with
     | Some (status, stdout, _) ->
       check "format --check dirty exit 1" (exit_code status = 1);
       check "format --check prints path" (String.length stdout > 0)
     | None -> ());
    (match run_cli [ "format"; "--stdin"; "--filename"; "Q.cyrograf" ]
             (Some "struct   Q{ a:List< String > }\n")
     with
     | Some (status, stdout, _) ->
       check "stdin exit 0" (exit_code status = 0);
       check_equal "stdin output" "struct Q {\n  a: List<String>\n}\n" stdout
     | None -> ());
    (match run_cli [ "format"; "--stdin"; "--filename"; "Q.toml" ] (Some "x=1\n") with
     | Some (status, _, stderr) ->
       check "stdin rejects TOML filename" (exit_code status = 2);
       check "stdin TOML error on stderr" (String.length stderr > 0)
     | None -> ());
    let spaced = Filename.concat directory "with space" in
    Unix.mkdir spaced 0o755;
    let spaced_file = Filename.concat spaced "Space.cyrograf" in
    write spaced_file messy_text;
    (match run_cli [ "format"; spaced ] None with
     | Some (status, _, _) ->
       check "format path with spaces" (exit_code status = 0);
       check_equal "format spaced file" "struct A {\n  x: String\n  y: Int\n}\n"
         (read spaced_file)
     | None -> ());
    let dash = Filename.concat directory "-leading.cyrograf" in
    write dash messy_text;
    (match run_cli [ "format"; "--"; dash ] None with
     | Some (status, _, _) -> check "format -- path" (exit_code status = 0)
     | None -> ());
    remove_tree directory

let () =
  test_canonical ();
  test_idempotent ();
  test_comments ();
  test_empty_and_nested ();
  test_nested_optional_with_comments ();
  test_crlf_bom ();
  test_syntax_blocks ();
  test_schema_preserved ();
  test_controlled_access ();
  test_cli_process ();
  if !failures = 0 then Printf.printf "all format tests passed\n"
  else begin
    Printf.printf "%d format test(s) failed\n" !failures;
    exit 1
  end