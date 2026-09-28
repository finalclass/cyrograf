(* ArtifactAccess: publish a complete result owned by one command.

   Paths are relative, unique and free of [..], absolute components and symlink
   traversal. A foreign file or a malformed manifest blocks publication. The
   whole result is prepared in a temporary directory on the same filesystem
   before the previous result is touched; a failure during preparation or
   commit leaves the previous result in place, and only previous files that are
   no longer in the new manifest are removed. *)

module Error = Cyrograf.Error
module CC = Cyrograf_compiler

let error code message = Error.make ~code message

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () -> really_input_string channel (in_channel_length channel))

let rec mkdir_p directory =
  if directory = "" || directory = "/" || directory = "." then ()
  else if Sys.file_exists directory then ()
  else begin
    mkdir_p (Filename.dirname directory);
    Unix.mkdir directory 0o755
  end

let write_file path contents =
  mkdir_p (Filename.dirname path);
  let channel = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out channel)
    (fun () -> output_string channel contents)

let rec list_files ~prefix directory =
  Sys.readdir directory |> Array.to_list
  |> List.concat_map (fun name ->
      let path = Filename.concat directory name in
      let relative = if prefix = "" then name else prefix ^ "/" ^ name in
      if Sys.is_directory path then list_files ~prefix:relative path else [ relative ])

let rec canonical path =
  if Sys.file_exists path then (try Unix.realpath path with Unix.Unix_error _ -> path)
  else
    let parent = Filename.dirname path in
    if parent = path then path
    else Filename.concat (canonical parent) (Filename.basename path)

let same_or_nested a b =
  let a = canonical a in
  let b = canonical b in
  String.length a <= String.length b
  && String.sub b 0 (String.length a) = a
  && (String.length a = String.length b || b.[String.length a] = '/')

let is_safe_relative path =
  path <> ""
  && Filename.is_relative path
  && not (String.length path > 0 && path.[0] = '/')
  && not (List.exists (fun segment -> segment = "..") (String.split_on_char '/' path))

let rec symlink_component base = function
  | [] -> false
  | part :: rest ->
    let path = Filename.concat base part in
    if Sys.file_exists path || (try ignore (Unix.lstat path); true with Unix.Unix_error _ -> false)
    then
      (match (Unix.lstat path).Unix.st_kind with
       | Unix.S_LNK -> true
       | _ -> symlink_component path rest)
    else false

let read_previous_manifest path =
  if not (Sys.file_exists path) then Ok []
  else
    match Yojson.Safe.from_string (read_file path) with
    | `List items ->
      if List.for_all (function `String _ -> true | _ -> false) items then
        Ok (List.map (function `String item -> item | _ -> assert false) items)
      else Error [ error Error.Code.io_error "manifest.json must be a list of strings" ]
    | _ -> Error [ error Error.Code.io_error "manifest.json is not a JSON array" ]
    | exception Yojson.Json_error message ->
      Error [ error Error.Code.io_error message ]

let make_temp_dir parent =
  let file = Filename.temp_file ~temp_dir:parent "cyrograf" ".prepare" in
  Sys.remove file;
  Unix.mkdir file 0o755;
  file

let rec remove_tree path =
  if Sys.file_exists path then
    if Sys.is_directory path then begin
      Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
      (try Unix.rmdir path with Unix.Unix_error _ -> ())
    end
    else (try Sys.remove path with Sys_error _ -> ())

let publish ~directory ~output ~artifacts =
  if Sys.file_exists output && not (Sys.is_directory output) then
    Error [ error Error.Code.io_error (Printf.sprintf "%s is not a directory" output) ]
  else if
    same_or_nested output directory || same_or_nested directory output
  then Error [ error Error.Code.io_error "OUTPUT_DIR and SOURCE_DIR overlap" ]
  else
    let paths = List.map (fun (artifact : CC.artifact) -> artifact.CC.path) artifacts in
    let unsafe =
      List.filter_map
        (fun path ->
          if not (is_safe_relative path) then
            Some
              (error Error.Code.foreign_file
                 (Printf.sprintf "unsafe artifact path %S" path))
          else if symlink_component output (String.split_on_char '/' path) then
            Some
              (error Error.Code.foreign_file
                 (Printf.sprintf "artifact path %S traverses a symlink" path))
          else None)
        paths
    in
    let duplicates =
      let seen = Hashtbl.create 16 in
      List.filter
        (fun path ->
          if Hashtbl.mem seen path then true
          else begin
            Hashtbl.add seen path ();
            false
          end)
        paths
    in
    if unsafe <> [] then Error unsafe
    else if duplicates <> [] then
      Error
        (List.map
           (fun path ->
             error Error.Code.foreign_file
               (Printf.sprintf "duplicate artifact path %S" path))
           duplicates)
    else
      match read_previous_manifest (Filename.concat output "manifest.json") with
      | Error errors -> Error errors
      | Ok previous ->
        let existing = if Sys.file_exists output then list_files ~prefix:"" output else [] in
        let allowed = "manifest.json" :: previous in
        let foreign = List.filter (fun path -> not (List.mem path allowed)) existing in
        if foreign <> [] then
          Error
            (List.map
               (fun path ->
                 error Error.Code.foreign_file
                   (Printf.sprintf "refusing to overwrite foreign file %s" path))
               foreign)
        else begin
          let parent = canonical (Filename.dirname output) in
          mkdir_p parent;
          let temp_dir =
            try Ok (make_temp_dir parent)
            with Sys_error message | Unix.Unix_error (_, _, message) ->
              Error [ error Error.Code.io_error message ]
          in
          match temp_dir with
          | Error errors -> Error errors
          | Ok temp_dir ->
            let prepare_errors = ref [] in
            List.iter
              (fun (artifact : CC.artifact) ->
                try
                  write_file (Filename.concat temp_dir artifact.CC.path) artifact.CC.contents
                with
                | Sys_error message ->
                  prepare_errors :=
                    error Error.Code.io_error
                      (Printf.sprintf "cannot prepare %s: %s" artifact.CC.path message)
                    :: !prepare_errors
                | Unix.Unix_error (code, _, _) ->
                  prepare_errors :=
                    error Error.Code.io_error
                      (Printf.sprintf "cannot prepare %s: %s" artifact.CC.path
                         (Unix.error_message code))
                    :: !prepare_errors)
              artifacts;
            if !prepare_errors <> [] then begin
              remove_tree temp_dir;
              Error (List.rev !prepare_errors)
            end
            else begin
              mkdir_p output;
              let backup_dir = Filename.concat temp_dir "_backup" in
              mkdir_p backup_dir;
              let placed = ref [] in
              let backups = ref [] in
              let failure = ref None in
              List.iter
                (fun (artifact : CC.artifact) ->
                  if !failure = None then begin
                    let destination = Filename.concat output artifact.CC.path in
                    mkdir_p (Filename.dirname destination);
                    if Sys.file_exists destination then begin
                      let backup = Filename.concat backup_dir artifact.CC.path in
                      mkdir_p (Filename.dirname backup);
                      Unix.rename destination backup;
                      backups := (destination, backup) :: !backups
                    end;
                    let prepared = Filename.concat temp_dir artifact.CC.path in
                    try
                      Unix.rename prepared destination;
                      placed := destination :: !placed
                    with Unix.Unix_error (code, _, _) ->
                      failure :=
                        Some
                          (error Error.Code.io_error
                             (Printf.sprintf "cannot publish %s: %s"
                                artifact.CC.path (Unix.error_message code)))
                  end)
                artifacts;
              match !failure with
              | Some failure_error ->
                List.iter (fun path -> try Sys.remove path with Sys_error _ -> ()) !placed;
                let restore_errors = ref [] in
                List.iter
                  (fun (destination, backup) ->
                    try Unix.rename backup destination
                    with Unix.Unix_error (code, _, _) ->
                      restore_errors :=
                        error Error.Code.io_error
                          (Printf.sprintf "previous file kept at %s: %s"
                             backup (Unix.error_message code))
                        :: !restore_errors)
                  !backups;
                remove_tree temp_dir;
                Error (failure_error :: List.rev !restore_errors)
              | None ->
                let new_paths = List.map (fun (artifact : CC.artifact) -> artifact.CC.path) artifacts in
                List.iter
                  (fun path ->
                    if not (List.mem path new_paths) then
                      try Sys.remove (Filename.concat output path)
                      with Sys_error _ -> ())
                  previous;
                write_file (Filename.concat output "manifest.json")
                  (CC.Descriptor.manifest_json (List.sort String.compare new_paths));
                remove_tree temp_dir;
                Ok new_paths
            end
        end