(* Test helper: compile fixtures and write generated target files. *)

open Cyrograf
module CC = Cyrograf_compiler

let read_file path =
  let channel = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in channel) (fun () ->
      really_input_string channel (in_channel_length channel))

let write_file path contents =
  let channel = open_out_bin path in
  Fun.protect ~finally:(fun () -> close_out channel) (fun () ->
      output_string channel contents)

let () =
  let source_dir = Sys.argv.(1) in
  let output_dir = Sys.argv.(2) in
  let target =
    match Sys.argv.(3) with
    | "ocaml" -> CC.Ocaml
    | "typescript" -> CC.Typescript
    | "go" -> CC.Go
    | "dart" -> CC.Dart
    | other ->
      prerr_endline ("unknown target " ^ other);
      exit 2
  in
  let profile =
    if Array.length Sys.argv <= 4 then CC.Native
    else
      match Sys.argv.(4) with
      | "native" -> CC.Native
      | "js" -> CC.Js
      | other ->
        prerr_endline ("unknown ocaml profile " ^ other);
        exit 2
  in
  let files =
    Sys.readdir source_dir |> Array.to_list
    |> List.filter (fun name -> Filename.check_suffix name ".toml")
    |> List.sort String.compare
  in
  let sources =
    List.map
      (fun name ->
        { CC.name; text = read_file (Filename.concat source_dir name) })
      files
  in
  let schema =
    match CC.compile ~sources with
    | Ok schema -> schema
    | Error errors ->
      List.iter (fun e -> prerr_endline (Error.to_string e)) errors;
      exit 1
  in
  let artifacts =
    match CC.generate ~ocaml_profile:profile ~targets:[ target ] ~schema () with
    | Ok artifacts -> artifacts
    | Error errors ->
      List.iter (fun e -> prerr_endline (Error.to_string e)) errors;
      exit 1
  in
  List.iter
    (fun (artifact : CC.artifact) ->
      let base = Filename.basename artifact.path in
      if Filename.check_suffix base ".ml"
         || Filename.check_suffix base ".mli"
         || Filename.check_suffix base ".ts"
         || Filename.check_suffix base ".go"
         || Filename.check_suffix base ".dart"
         || base = "wire.ts"
         || base = "wire.go"
         || base = "wire.dart"
      then write_file (Filename.concat output_dir base) artifact.contents)
    artifacts