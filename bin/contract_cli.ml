(* The single public program. It maps arguments to Tooling compositions and
   presents results; language rules and file access live in the libraries. *)

open Cyrograf

module CC = Cyrograf_compiler
module Tooling = Cyrograf_tooling.Tooling

let version = Version.value

let targets_help = "ocaml,typescript,go,dart,python,java,csharp,rust"

let general_help =
  Printf.sprintf
    "cyrograf %s\n\n\
     Cyrograf checks, builds, formats and migrates Drut contract projects.\n\n\
     Usage:\n\
     \  cyrograf check SOURCE_DIR [--targets %s]\n\
     \  cyrograf build SOURCE_DIR --output OUTPUT_DIR [--targets %s] \
     [--go-module MODULE_PATH]\n\
     \  cyrograf format [PATH ...] [--check]\n\
     \  cyrograf format --stdin --filename NAME.cyrograf\n\
     \  cyrograf migrate SOURCE_DIR --output OUTPUT_DIR\n\
     \  cyrograf lsp [--stdio]\n\
     \  cyrograf help [COMMAND]\n\
     \  cyrograf --version\n\n\
     Commands:\n\
     \  check    validate a contract project and target name collisions\n\
     \  build    check a project and publish generated types and codecs\n\
     \  format   give native .cyrograf files the canonical layout\n\
     \  migrate  convert a project to native .cyrograf sources\n\
     \  lsp      serve the language protocol on stdin/stdout\n\
     \  help     show this help or help for one command\n\n\
     Run 'cyrograf help COMMAND' for command details.\n"
    version targets_help targets_help

let check_help =
  "Usage: cyrograf check SOURCE_DIR [--targets " ^ targets_help ^ "]\n\n\
   Validate the contract project in SOURCE_DIR and the name collisions of the\n\
   selected targets. No artifact is written.\n"

let build_help =
  "Usage: cyrograf build SOURCE_DIR --output OUTPUT_DIR [--targets " ^ targets_help
  ^ "]\n\
  \       [--go-module MODULE_PATH] [--ocaml-profile native|js]\n\
  \       [--ocaml-library NAME]\n\n\
   Check the project, generate the selected targets and publish the result into\n\
   OUTPUT_DIR. --go-module selects the Go import path, default generated_contracts.\n\
   --ocaml-profile selects the OCaml Int representation, default native.\n\
   --ocaml-library selects the generated OCaml data library, default generated_contracts.\n"

let format_help =
  "Usage: cyrograf format [PATH ...] [--check]\n\
  \       cyrograf format --stdin --filename NAME.cyrograf\n\n\
   Give native .cyrograf files the canonical layout. Without PATH the current\n\
   directory is used; a directory contributes its .cyrograf files without\n\
   recursion. --check writes nothing and exits 1 when a file differs. --stdin\n\
   reads exactly one document and prints the formatted text to stdout.\n"

let migrate_help =
  "Usage: cyrograf migrate SOURCE_DIR --output OUTPUT_DIR\n\n\
   Convert .toml sources into native .cyrograf sources in a separate directory,\n\
   copy existing native sources unchanged and publish only after the result has\n\
   the same schema. SOURCE_DIR is never modified.\n"

let lsp_help =
  "Usage: cyrograf lsp [--stdio]\n\n\
   Serve the language protocol on stdin/stdout as JSON-RPC 2.0 with \
   Content-Length\n\
   framing. The server is a local adapter to the same analysis and formatter \
   as\n\
   the other commands; it opens no socket and writes nothing but protocol \
   frames\n\
   to stdout. It supports initialize/initialized/shutdown/exit, full text\n\
   document sync, diagnostics, formatting, hover, definition, document symbols\n\
   and completion.\n"

let print_string value =
  print_string value;
  flush stdout

let usage_error ~help message =
  prerr_endline ("cyrograf: " ^ message);
  prerr_string help;
  flush stderr;
  exit 2

let format_error (error : Error.t) =
  let location =
    match error.source with
    | Some { name; line; column } -> (
      match (line, column) with
      | Some line, Some column -> Printf.sprintf "%s:%d:%d: " name line column
      | Some line, None -> Printf.sprintf "%s:%d: " name line
      | None, _ -> (
        match error.path with
        | [] -> name ^ ": "
        | path -> name ^ ": " ^ String.concat "." path ^ ": "))
    | None -> (
      match error.path with
      | [] -> ""
      | path -> String.concat "." path ^ ": ")
  in
  Printf.sprintf "%s%s: %s" location error.code error.message

let fail errors =
  List.iter (fun error -> prerr_endline (format_error error)) errors;
  exit 1

let target_of_name = function
  | "ocaml" -> Some CC.Ocaml
  | "typescript" -> Some CC.Typescript
  | "go" -> Some CC.Go
  | "dart" -> Some CC.Dart
  | "python" -> Some CC.Python
  | "java" -> Some CC.Java
  | "csharp" -> Some CC.Csharp
  | "rust" -> Some CC.Rust
  | _ -> None

let parse_targets ~help value =
  let parts = String.split_on_char ',' value in
  if parts = [] || List.exists (fun part -> part = "") parts then
    usage_error ~help "the target list must not be empty";
  let targets =
    List.map
      (fun part ->
        match target_of_name part with
        | Some target -> target
        | None -> usage_error ~help (Printf.sprintf "unknown target %S" part))
      parts
  in
  let seen = Hashtbl.create 4 in
  List.iter
    (fun part ->
      if Hashtbl.mem seen part then
        usage_error ~help (Printf.sprintf "duplicate target %S" part)
      else Hashtbl.add seen part ())
    parts;
  targets

let all_targets =
  [ CC.Ocaml; CC.Typescript; CC.Go; CC.Dart; CC.Python; CC.Java; CC.Csharp;
    CC.Rust ]

type parsed = {
  positional : string list;
  targets : CC.target list option;
  output : string option;
  go_module : string option;
  ocaml_profile : CC.ocaml_profile option;
  ocaml_library : string option;
}

let profile_of_name = function
  | "native" -> Some CC.Native
  | "js" -> Some CC.Js
  | _ -> None

let parse_arguments ~help arguments =
  let rec loop parsed = function
    | [] -> parsed
    | "--" :: rest ->
      { parsed with positional = parsed.positional @ rest }
    | ("--targets" | "--output" | "--go-module" | "--ocaml-profile"
      | "--ocaml-library") :: [] ->
      usage_error ~help "missing value for an option"
    | "--targets" :: value :: rest ->
      loop { parsed with targets = Some (parse_targets ~help value) } rest
    | "--output" :: value :: rest -> loop { parsed with output = Some value } rest
    | "--go-module" :: value :: rest -> loop { parsed with go_module = Some value } rest
    | "--ocaml-profile" :: value :: rest ->
      loop
        { parsed with
          ocaml_profile =
            (match profile_of_name value with
             | Some profile -> Some profile
             | None ->
               usage_error ~help
                 (Printf.sprintf "unknown ocaml profile %S" value)) }
        rest
    | "--ocaml-library" :: value :: rest ->
      loop { parsed with ocaml_library = Some value } rest
    | flag :: _ when String.length flag > 0 && flag.[0] = '-' ->
      usage_error ~help (Printf.sprintf "unknown option %S" flag)
    | value :: rest -> loop { parsed with positional = parsed.positional @ [ value ] } rest
  in
  loop
    { positional = []; targets = None; output = None; go_module = None;
      ocaml_profile = None; ocaml_library = None }
    arguments

let has_help arguments =
  let rec loop = function
    | [] -> false
    | "--" :: _ -> false
    | ("--help" | "-h") :: _ -> true
    | _ :: rest -> loop rest
  in
  loop arguments

let command_check arguments =
  if has_help arguments then begin
    print_string check_help;
    exit 0
  end;
  let parsed = parse_arguments ~help:check_help arguments in
  if parsed.output <> None || parsed.go_module <> None
     || parsed.ocaml_profile <> None || parsed.ocaml_library <> None
  then
    usage_error ~help:check_help
      "check does not accept --output, --go-module, --ocaml-profile or --ocaml-library";
  let directory =
    match parsed.positional with
    | [ directory ] -> directory
    | [] -> usage_error ~help:check_help "check needs exactly one SOURCE_DIR"
    | _ -> usage_error ~help:check_help "check needs exactly one SOURCE_DIR"
  in
  let targets = Option.value ~default:all_targets parsed.targets in
  match Tooling.check ~directory ~targets with
  | Ok modules ->
    Printf.printf "ok: %d module(s)\n" modules;
    exit 0
  | Error errors -> fail errors

let command_build arguments =
  if has_help arguments then begin
    print_string build_help;
    exit 0
  end;
  let parsed = parse_arguments ~help:build_help arguments in
  let directory =
    match parsed.positional with
    | [ directory ] -> directory
    | _ -> usage_error ~help:build_help "build needs exactly one SOURCE_DIR"
  in
  let output =
    match parsed.output with
    | Some output -> output
    | None -> usage_error ~help:build_help "build needs --output OUTPUT_DIR"
  in
  let targets = Option.value ~default:all_targets parsed.targets in
  let go_module = Option.value ~default:"generated_contracts" parsed.go_module in
  match
    Tooling.build ~directory ~output ~targets ~go_module
      ?ocaml_profile:parsed.ocaml_profile ?ocaml_library:parsed.ocaml_library ()
  with
  | Ok paths ->
    Printf.printf "built %d file(s) into %s\n" (List.length paths) output;
    exit 0
  | Error errors -> fail errors

let command_format arguments =
  if has_help arguments then begin
    print_string format_help;
    exit 0
  end;
  let stdin_mode = ref false in
  let filename = ref None in
  let check = ref false in
  let paths = ref [] in
  let rec loop = function
    | [] -> ()
    | "--" :: rest -> paths := !paths @ rest
    | "--stdin" :: rest ->
      stdin_mode := true;
      loop rest
    | "--check" :: rest ->
      check := true;
      loop rest
    | "--filename" :: [] ->
      usage_error ~help:format_help "missing value for --filename"
    | "--filename" :: value :: rest ->
      filename := Some value;
      loop rest
    | flag :: _ when String.length flag > 0 && flag.[0] = '-' ->
      usage_error ~help:format_help (Printf.sprintf "unknown option %S" flag)
    | value :: rest ->
      paths := !paths @ [ value ];
      loop rest
  in
  loop arguments;
  if !stdin_mode then begin
    if !paths <> [] || !check then
      usage_error ~help:format_help "--stdin cannot be combined with PATH or --check";
    let name =
      match !filename with
      | Some name -> name
      | None -> usage_error ~help:format_help "--stdin requires --filename"
    in
    if not (Filename.check_suffix name ".cyrograf") then
      usage_error ~help:format_help "--filename must end with .cyrograf";
    let text = In_channel.input_all stdin in
    match CC.format ~name ~text with
    | Ok formatted ->
      print_string formatted;
      exit 0
    | Error errors -> fail errors
  end
  else begin
    if !filename <> None then
      usage_error ~help:format_help "--filename requires --stdin";
    let paths = if !paths = [] then [ "." ] else !paths in
    match Tooling.format ~paths ~check:!check () with
    | Error errors -> fail errors
    | Ok changed ->
      if !check then begin
        List.iter print_endline changed;
        exit (if changed = [] then 0 else 1)
      end
      else begin
        Printf.printf "formatted %d file(s)\n" (List.length changed);
        exit 0
      end
  end

let command_lsp arguments =
  if has_help arguments then begin
    print_string lsp_help;
    exit 0
  end;
  let rec loop = function
    | [] -> ()
    | "--stdio" :: rest -> loop rest
    | "--" :: [] -> ()
    | ("--" :: _ | _ :: _) as rest ->
      let value = match rest with value :: _ -> value | [] -> "" in
      usage_error ~help:lsp_help (Printf.sprintf "unexpected argument %S" value)
  in
  loop arguments;
  exit (Cyrograf_lsp.Server.run ~version ~ic:stdin ~oc:stdout ())

let command_migrate arguments =
  if has_help arguments then begin
    print_string migrate_help;
    exit 0
  end;
  let parsed = parse_arguments ~help:migrate_help arguments in
  if parsed.targets <> None then
    usage_error ~help:migrate_help "migrate does not accept --targets";
  if parsed.go_module <> None || parsed.ocaml_profile <> None
     || parsed.ocaml_library <> None
  then
    usage_error ~help:migrate_help
      "migrate does not accept --go-module, --ocaml-profile or --ocaml-library";
  let directory =
    match parsed.positional with
    | [ directory ] -> directory
    | _ -> usage_error ~help:migrate_help "migrate needs exactly one SOURCE_DIR"
  in
  let output =
    match parsed.output with
    | Some output -> output
    | None -> usage_error ~help:migrate_help "migrate needs --output OUTPUT_DIR"
  in
  match Tooling.migrate ~directory ~output with
  | Error errors -> fail errors
  | Ok (paths, comments_moved) ->
    Printf.printf "migrated %d file(s) into %s\n" (List.length paths) output;
    if comments_moved then
      Printf.printf "TOML comments were moved to the start of their files\n";
    Printf.printf "run 'cyrograf check %s' to verify the result\n" output;
    exit 0

let command_help = function
  | [] ->
    print_string general_help;
    exit 0
  | [ "check" ] -> print_string check_help; exit 0
  | [ "build" ] -> print_string build_help; exit 0
  | [ "format" ] -> print_string format_help; exit 0
  | [ "migrate" ] -> print_string migrate_help; exit 0
  | [ "lsp" ] -> print_string lsp_help; exit 0
  | [ "help" ] -> print_string general_help; exit 0
  | [ name ] ->
    prerr_endline (Printf.sprintf "cyrograf: unknown command %S" name);
    prerr_string general_help;
    flush stderr;
    exit 2
  | _ ->
    prerr_endline "cyrograf: help accepts at most one COMMAND";
    prerr_string general_help;
    flush stderr;
    exit 2

let () =
  let arguments = Array.to_list Sys.argv |> List.tl in
  match arguments with
  | [] ->
    print_string general_help;
    exit 0
  | [ ("--help" | "-h") ] ->
    print_string general_help;
    exit 0
  | [ "--version" ] ->
    Printf.printf "cyrograf %s\n" version;
    exit 0
  | "help" :: rest -> command_help rest
  | "check" :: rest -> command_check rest
  | "build" :: rest -> command_build rest
  | "format" :: rest -> command_format rest
  | "migrate" :: rest -> command_migrate rest
  | "lsp" :: rest -> command_lsp rest
  | command :: _ ->
    prerr_endline (Printf.sprintf "cyrograf: unknown command %S" command);
    prerr_string general_help;
    flush stderr;
    exit 2