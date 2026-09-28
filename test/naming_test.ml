(* Target naming fixture: owner_id/ownerId/OwnerID, keyword suffixing and the
   canonical descriptor/Drut tags stay independent of the generated API names. *)

open Cyrograf
module CC = Cyrograf_compiler

let failures = ref 0

let check label condition =
  if condition then Printf.printf "PASS: %s\n" label
  else begin
    incr failures;
    Printf.printf "FAIL: %s\n" label
  end

let contains haystack needle =
  let n = String.length needle and h = String.length haystack in
  let rec loop index =
    if index + n > h then false
    else if String.sub haystack index n = needle then true
    else loop (index + 1)
  in
  loop 0

let source =
  { CC.name = "N.cyrograf";
    text = "struct Owner {\n  owner_id: String\n  class: String\n}\n" }

let artifact artifacts path =
  List.find_opt (fun (a : CC.artifact) -> a.path = path) artifacts

let () =
  let schema =
    match CC.compile ~sources:[ source ] with
    | Ok schema -> schema
    | Error errors ->
      List.iter (fun e -> prerr_endline (Error.to_string e)) errors;
      exit 1
  in
  let artifacts =
    match
      CC.generate
        ~targets:
          [ CC.Ocaml; CC.Typescript; CC.Go; CC.Dart; CC.Python; CC.Java; CC.Csharp;
            CC.Rust ]
        ~schema ()
    with
    | Ok artifacts -> artifacts
    | Error errors ->
      List.iter (fun e -> prerr_endline (Error.to_string e)) errors;
      exit 1
  in
  let ocaml = Option.value ~default:"" (Option.map (fun (a : CC.artifact) -> a.contents) (artifact artifacts "ocaml/n.ml")) in
  let ts = Option.value ~default:"" (Option.map (fun (a : CC.artifact) -> a.contents) (artifact artifacts "typescript/n.ts")) in
  let go = Option.value ~default:"" (Option.map (fun (a : CC.artifact) -> a.contents) (artifact artifacts "go/n/n.go")) in
  let dart = Option.value ~default:"" (Option.map (fun (a : CC.artifact) -> a.contents) (artifact artifacts "dart/n.dart")) in
  let python = Option.value ~default:"" (Option.map (fun (a : CC.artifact) -> a.contents) (artifact artifacts "python/generated_contracts/n.py")) in
  let java =
    Option.value ~default:""
      (Option.map (fun (a : CC.artifact) -> a.contents)
         (artifact artifacts "java/src/main/java/generated_contracts/N.java"))
  in
  let csharp =
    Option.value ~default:""
      (Option.map (fun (a : CC.artifact) -> a.contents)
         (artifact artifacts "csharp/GeneratedContracts.N.cs"))
  in
  let rust =
    Option.value ~default:""
      (Option.map (fun (a : CC.artifact) -> a.contents)
         (artifact artifacts "rust/src/n.rs"))
  in
  let json = CC.Descriptor.schema_json schema in

  check "ocaml keeps owner_id" (contains ocaml "owner_id : string");
  check "typescript uses ownerId" (contains ts "ownerId: string");
  check "go uses OwnerID" (contains go "OwnerID string");
  check "dart uses ownerId" (contains dart "ownerId;");
  check "python keeps owner_id" (contains python "owner_id: str");
  check "java uses ownerId" (contains java "ownerId");
  check "java keyword suffix" (contains java "class_");
  check "ocaml keyword suffix" (contains ocaml "class'");
  check "typescript keyword suffix" (contains ts "class_: string");
  check "dart keyword suffix" (contains dart "class_");
  check "python keyword suffix" (contains python "class_: str");
  check "csharp uses OwnerId" (contains csharp "OwnerId");
  check "rust keeps owner_id" (contains rust "pub owner_id: String");
  check "rust keeps non-keyword class" (contains rust "pub class: String");
  check "canonical descriptor keeps owner_id" (contains json "\"owner_id\"");
  check "drut tag keeps source name" (contains ocaml "\"owner_id\"");
  check "class tag keeps source name" (contains ocaml "\"class\"");

  (* A collision after target transformation is rejected for the target that
     collapses the names, while another target stays usable. *)
  let collision =
    { CC.name = "C.cyrograf";
      text = "struct M {\n  owner_id: String\n  owner_i_d: String\n}\n" }
  in
  (match CC.compile ~sources:[ collision ] with
   | Error _ -> check "collision fixture compiles" false
   | Ok schema ->
     let go_errors =
       match CC.validate ~targets:[ CC.Go ] ~schema with Ok () -> [] | Error e -> e
     in
     check "go collision detected by validate"
       (List.exists (fun e -> e.Error.code = Error.Code.name_collision) go_errors);
     let ocaml_ok =
       match CC.validate ~targets:[ CC.Ocaml ] ~schema with Ok () -> true | Error _ -> false
     in
     check "ocaml target of the collision fixture stays valid" ocaml_ok);

  (* A Python message member that shadows the generated conversion is rejected
     only for the Python target. *)
  let reserved =
    { CC.name = "R.cyrograf";
      text = "struct M {\n  to_drut: String\n}\n" }
  in
  (match CC.compile ~sources:[ reserved ] with
   | Error _ -> check "python reserved fixture compiles" false
   | Ok schema ->
     let python_errors =
       match CC.validate ~targets:[ CC.Python ] ~schema with
       | Ok () -> [] | Error e -> e
     in
     check "python reserved member detected by validate"
       (List.exists (fun e -> e.Error.code = Error.Code.name_collision) python_errors);
     let go_ok =
       match CC.validate ~targets:[ CC.Go ] ~schema with Ok () -> true | Error _ -> false
     in
     check "go target of the reserved fixture stays valid" go_ok);

  (* A Java message member that shadows a generated record member is rejected
     only for the Java target. *)
  let java_reserved =
    { CC.name = "J.cyrograf";
      text = "struct M {\n  hash_code: String\n}\n" }
  in
  (match CC.compile ~sources:[ java_reserved ] with
   | Error _ -> check "java reserved fixture compiles" false
   | Ok schema ->
     let java_errors =
       match CC.validate ~targets:[ CC.Java ] ~schema with
       | Ok () -> [] | Error e -> e
     in
     check "java reserved member detected by validate"
       (List.exists (fun e -> e.Error.code = Error.Code.name_collision) java_errors);
     let go_ok =
       match CC.validate ~targets:[ CC.Go ] ~schema with Ok () -> true | Error _ -> false
     in
     check "go target of the java reserved fixture stays valid" go_ok);

  (* A C# message member that shadows a generated record member is rejected
     only for the C# target. *)
  let csharp_reserved =
    { CC.name = "H.cyrograf";
      text = "struct M {\n  to_drut: String\n}\n" }
  in
  (match CC.compile ~sources:[ csharp_reserved ] with
   | Error _ -> check "csharp reserved fixture compiles" false
   | Ok schema ->
     let csharp_errors =
       match CC.validate ~targets:[ CC.Csharp ] ~schema with
       | Ok () -> [] | Error e -> e
     in
     check "csharp reserved member detected by validate"
       (List.exists (fun e -> e.Error.code = Error.Code.name_collision) csharp_errors);
     let go_ok =
       match CC.validate ~targets:[ CC.Go ] ~schema with Ok () -> true | Error _ -> false
     in
     check "go target of the csharp reserved fixture stays valid" go_ok);

  (* A Rust message member that shadows the generated conversion is rejected
     only for the Rust target. *)
  let rust_reserved =
    { CC.name = "K.cyrograf";
      text = "struct M {\n  to_drut: String\n}\n" }
  in
  (match CC.compile ~sources:[ rust_reserved ] with
   | Error _ -> check "rust reserved fixture compiles" false
   | Ok schema ->
     let rust_errors =
       match CC.validate ~targets:[ CC.Rust ] ~schema with
       | Ok () -> [] | Error e -> e
     in
     check "rust reserved member detected by validate"
       (List.exists (fun e -> e.Error.code = Error.Code.name_collision) rust_errors);
     let go_ok =
       match CC.validate ~targets:[ CC.Go ] ~schema with Ok () -> true | Error _ -> false
     in
     check "go target of the rust reserved fixture stays valid" go_ok);

  if !failures > 0 then exit 1