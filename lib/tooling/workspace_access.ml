(* WorkspaceAccess: the only place that reads contract sources from disk and
   writes source changes back.

   It captures one immutable snapshot following the source discovery rules of
   docs/cli.md: a single directory, no recursion, regular [.cyrograf] and
   [.toml] files, symlinks rejected, an empty selection reported as
   [EmptySources]. The formatter path additionally captures explicit native
   files or directories and replaces them only after checking that the files
   did not change since the read. Later analysis never touches the filesystem. *)

module Error = Cyrograf.Error
module CC = Cyrograf_compiler

type source = CC.source = {
  name : string;
  text : string;
}

type revision = {
  name : string;
  digest : string;
}

type snapshot = {
  directory : string;
  sources : source list;
  revisions : revision list;
}

type native_source = {
  path : string;
  name : string;
  text : string;
  digest : string;
}

type native_snapshot = {
  native_sources : native_source list;
}

type overlay = {
  path : string;
  text : string;
  version : int;
}

type overlay_store = {
  mutable overlays : (string * overlay) list;
}

let create_overlay_store () = { overlays = [] }

let overlay_list store = List.map snd store.overlays

module type FORMAT_ACCESS = sig
  val capture_native : paths:string list -> (native_snapshot, Error.t list) result
  val replace_native :
    native_snapshot -> (string * string) list -> (unit, Error.t list) result
end

let error code message = Error.make ~code message

let read_file path =
  let channel = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in channel)
    (fun () ->
      let length = in_channel_length channel in
      really_input_string channel length)

let digest_of_text text = Digest.to_hex (Digest.string text)

let is_toml name = Filename.check_suffix name ".toml"
let is_native name = Filename.check_suffix name ".cyrograf"

let is_editor_lock_file name =
  String.length name >= 2 && String.sub name 0 2 = ".#"

let is_contract name = is_native name || is_toml name
let is_source_entry name = is_contract name && not (is_editor_lock_file name)

let symlink_error path =
  error Error.Code.io_error
    (Printf.sprintf "%s is a symlink; contract sources must be regular files" path)

let capture ~directory =
  if not (Sys.file_exists directory && Sys.is_directory directory) then
    Error
      [ error Error.Code.io_error (Printf.sprintf "%s is not a directory" directory) ]
  else
    let entries =
      Sys.readdir directory |> Array.to_list |> List.sort String.compare
      |> List.filter is_source_entry
    in
    let errors = ref [] in
    let sources = ref [] in
    let revisions = ref [] in
    List.iter
      (fun name ->
        let path = Filename.concat directory name in
        match (Unix.lstat path).Unix.st_kind with
        | Unix.S_LNK -> errors := symlink_error path :: !errors
        | Unix.S_REG ->
          (match
             (try Ok (read_file path) with Sys_error message -> Error message)
           with
           | Ok text ->
             sources := { name; text } :: !sources;
             revisions := { name; digest = digest_of_text text } :: !revisions
           | Error message -> errors := error Error.Code.io_error message :: !errors)
        | _ -> ())
      entries;
    if !errors <> [] then Error (List.rev !errors)
    else if !sources = [] then
      Error
        [ error Error.Code.empty_sources
            (Printf.sprintf "%s contains no .cyrograf or .toml files" directory) ]
    else
      Ok
        { directory;
          sources = List.rev !sources;
          revisions = List.rev !revisions }

(* ── Native selection and safe replacement ─────────────────────────── *)

let normalize path =
  try Unix.realpath path with Unix.Unix_error _ -> path

let apply_overlay store ~path ~version ~text =
  let path = normalize path in
  match List.assoc_opt path store.overlays with
  | Some current when current.version >= version -> false
  | _ ->
    store.overlays <-
      (path, { path; text; version }) :: List.remove_assoc path store.overlays;
    true

let close_overlay store ~path =
  store.overlays <- List.remove_assoc (normalize path) store.overlays

let overlay_version store ~path =
  match List.assoc_opt (normalize path) store.overlays with
  | Some overlay -> Some overlay.version
  | None -> None

let native_source path =
  let text = read_file path in
  { path = normalize path;
    name = Filename.basename path;
    text;
    digest = digest_of_text text }

let add_native_directory path errors collected =
  let entries = Sys.readdir path |> Array.to_list |> List.sort String.compare in
  List.iter
    (fun name ->
      if is_native name && not (is_editor_lock_file name) then begin
        let child = Filename.concat path name in
        match (Unix.lstat child).Unix.st_kind with
        | Unix.S_LNK -> errors := symlink_error child :: !errors
        | Unix.S_REG -> collected := child :: !collected
        | _ -> ()
      end)
    entries

let capture_native ~paths =
  let errors = ref [] in
  let collected = ref [] in
  List.iter
    (fun path ->
      if not (Sys.file_exists path) then
        errors :=
          error Error.Code.io_error (Printf.sprintf "%s does not exist" path)
          :: !errors
      else
        match (Unix.lstat path).Unix.st_kind with
        | Unix.S_LNK -> errors := symlink_error path :: !errors
        | Unix.S_DIR -> add_native_directory path errors collected
        | Unix.S_REG ->
          if is_native path then collected := path :: !collected
          else if is_toml path then
            errors :=
              error Error.Code.unsupported_source_format
                (Printf.sprintf "%s is TOML; the formatter accepts native sources only" path)
              :: !errors
          else
            errors :=
              error Error.Code.unsupported_source_format
                (Printf.sprintf "%s is not a native contract source" path)
              :: !errors
        | _ -> ())
    paths;
  if !errors <> [] then Error (List.rev !errors)
  else
    let paths = List.sort_uniq String.compare (List.map normalize !collected) in
    if paths = [] then
      Error [ error Error.Code.empty_sources "no native .cyrograf source was selected" ]
    else
      let sources =
        List.filter_map
          (fun path ->
            try Some (native_source path)
            with Sys_error message ->
              errors := error Error.Code.io_error message :: !errors;
              None)
          paths
      in
      if !errors <> [] then Error (List.rev !errors)
      else Ok { native_sources = sources }

(* ── Editor snapshot with overlays ────────────────────────────────── *)

let capture_editor ~directory ~store =
  let normalized = normalize directory in
  if not (Sys.file_exists normalized && Sys.is_directory normalized) then
    Error
      [ error Error.Code.io_error
          (Printf.sprintf "%s is not a directory" directory) ]
  else begin
    let entries =
      Sys.readdir normalized |> Array.to_list |> List.sort String.compare
      |> List.filter is_source_entry
    in
    let errors = ref [] in
    let disk = ref [] in
    List.iter
      (fun name ->
        let path = Filename.concat normalized name in
        match (Unix.lstat path).Unix.st_kind with
        | Unix.S_LNK -> errors := symlink_error path :: !errors
        | Unix.S_REG ->
          (match (try Ok (read_file path) with Sys_error message -> Error message) with
           | Ok text -> disk := (name, text) :: !disk
           | Error message -> errors := error Error.Code.io_error message :: !errors)
        | _ -> ())
      entries;
    if !errors <> [] then Error (List.rev !errors)
    else begin
      let overlays =
        List.filter
          (fun (overlay : overlay) -> Filename.dirname overlay.path = normalized)
          (overlay_list store)
      in
      let table = Hashtbl.create 16 in
      List.iter (fun (name, text) -> Hashtbl.replace table name text) !disk;
      List.iter
        (fun (overlay : overlay) ->
          Hashtbl.replace table (Filename.basename overlay.path) overlay.text)
        overlays;
      let names = Hashtbl.fold (fun name _ acc -> name :: acc) table [] in
      let names = List.sort String.compare names in
      if names = [] then
        Error
          [ error Error.Code.empty_sources
              (Printf.sprintf "%s contains no .cyrograf or .toml files" directory) ]
      else
        let sources =
          List.map (fun name -> { name; text = Hashtbl.find table name }) names
        in
        Ok sources
    end
  end

let replace_native snapshot edits =
  let table = Hashtbl.create 16 in
  List.iter
    (fun (source : native_source) -> Hashtbl.replace table source.path source)
    snapshot.native_sources;
  let conflicts = ref [] in
  let plans =
    List.map
      (fun (path, text) ->
        let normalized = normalize path in
        match Hashtbl.find_opt table normalized with
        | None ->
          conflicts :=
            error Error.Code.source_changed
              (Printf.sprintf "%s is not part of the captured snapshot" path)
            :: !conflicts;
          None
        | Some source ->
          (match (try Ok (read_file normalized) with Sys_error message -> Error message) with
           | Error message ->
             conflicts := error Error.Code.io_error message :: !conflicts;
             None
           | Ok current ->
             if digest_of_text current <> source.digest then begin
               conflicts :=
                 error Error.Code.source_changed
                   (Printf.sprintf "%s changed since it was read" path)
                 :: !conflicts;
               None
             end
             else Some (normalized, text)))
      edits
  in
  if !conflicts <> [] then Error (List.rev !conflicts)
  else begin
    let pending = List.filter_map (fun plan -> plan) plans in
    let prepared = ref [] in
    let prepare_error = ref None in
    List.iter
      (fun (path, text) ->
        match !prepare_error with
        | Some _ -> ()
        | None ->
          let directory = Filename.dirname path in
          let temp, channel =
            Filename.open_temp_file ~temp_dir:directory "cyrograf" ".tmp"
          in
          (try
             output_string channel text;
             close_out channel;
             let perm = (Unix.stat path).Unix.st_perm in
             Unix.chmod temp perm;
             prepared := (temp, path) :: !prepared
           with Sys_error message ->
             (try close_out channel with Sys_error _ -> ());
             prepare_error :=
               Some
                 (error Error.Code.io_error
                    (Printf.sprintf "cannot prepare %s: %s" path message))))
      pending;
    match !prepare_error with
    | Some failure ->
      List.iter (fun (temp, _) -> try Sys.remove temp with Sys_error _ -> ()) !prepared;
      Error [ failure ]
    | None ->
      let rename_errors = ref [] in
      List.iter
        (fun (temp, path) ->
          try Unix.rename temp path
          with Unix.Unix_error (code, _, _) ->
            rename_errors :=
              error Error.Code.io_error
                (Printf.sprintf "cannot replace %s: %s" path
                   (Unix.error_message code))
              :: !rename_errors)
        (List.rev !prepared);
      if !rename_errors <> [] then Error (List.rev !rename_errors) else Ok ()
  end