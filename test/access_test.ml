(* Stage 02 tests for [WorkspaceAccess] and [ArtifactAccess], covering the
   checks under "Publikacja artefaktów i instalacja" and the format write
   boundary in docs/stp.md. *)

open Cyrograf
module CC = Cyrograf_compiler
module AA = Cyrograf_tooling.Artifact_access
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
    Printf.printf "FAIL: %s: %S <> %S\n" label a b
  end

let rec remove_tree path =
  match (try Some ((Unix.lstat path).Unix.st_kind) with Unix.Unix_error _ -> None) with
  | None -> ()
  | Some Unix.S_DIR ->
    Sys.readdir path |> Array.iter (fun name -> remove_tree (Filename.concat path name));
    Unix.rmdir path
  | Some _ -> Sys.remove path

let temp_dir () =
  let path = Filename.temp_file "cyrograf-access" "" in
  Sys.remove path;
  Unix.mkdir path 0o755;
  path

let rec mkdir_parents directory =
  if directory = "" || directory = "/" || directory = "." then ()
  else if Sys.file_exists directory then ()
  else begin
    mkdir_parents (Filename.dirname directory);
    Unix.mkdir directory 0o755
  end

let write path text =
  mkdir_parents (Filename.dirname path);
  let channel = open_out_bin path in
  output_string channel text;
  close_out channel

let read path =
  let channel = open_in_bin path in
  let text = really_input_string channel (in_channel_length channel) in
  close_in channel;
  text

let artifact path contents = { CC.path; contents }

let has_code code errors = List.exists (fun (error : Error.t) -> error.code = code) errors

let test_publish_success_and_stale () =
  let directory = temp_dir () and output = temp_dir () in
  remove_tree output;
  (match
     AA.publish ~directory ~output
       ~artifacts:[ artifact "a.txt" "one"; artifact "sub/b.txt" "two" ]
   with
   | Error _ -> check "publish first" false
   | Ok paths ->
     check_equal "publish paths" "a.txt,sub/b.txt" (String.concat "," (List.sort String.compare paths));
     check_equal "artifact a" "one" (read (Filename.concat output "a.txt"));
     check_equal "artifact b" "two" (read (Filename.concat output "sub/b.txt")));
  (match AA.publish ~directory ~output ~artifacts:[ artifact "sub/b.txt" "three" ] with
   | Error _ -> check "publish second" false
   | Ok _ -> ());
  check "stale own file removed" (not (Sys.file_exists (Filename.concat output "a.txt")));
  check_equal "artifact b updated" "three" (read (Filename.concat output "sub/b.txt"));
  remove_tree directory;
  remove_tree output

let test_foreign_and_manifest () =
  let directory = temp_dir () and output = temp_dir () in
  write (Filename.concat output "keep.txt") "foreign\n";
  (match AA.publish ~directory ~output ~artifacts:[ artifact "a.txt" "one" ] with
   | Ok _ -> check "foreign file blocks" false
   | Error errors -> check "foreign file code" (has_code Error.Code.foreign_file errors));
  check_equal "foreign file preserved" "foreign\n" (read (Filename.concat output "keep.txt"));
  remove_tree output;
  Unix.mkdir output 0o755;
  write (Filename.concat output "manifest.json") "\"not a list\"";
  (match AA.publish ~directory ~output ~artifacts:[ artifact "a.txt" "one" ] with
   | Ok _ -> check "invalid manifest blocks" false
   | Error _ -> ());
  check "invalid manifest publishes nothing" (not (Sys.file_exists (Filename.concat output "a.txt")));
  remove_tree directory;
  remove_tree output

let test_unsafe_paths () =
  let directory = temp_dir () and output = temp_dir () in
  remove_tree output;
  (match AA.publish ~directory ~output ~artifacts:[ artifact "../escape" "x" ] with
   | Ok _ -> check "parent path rejected" false
   | Error _ -> ());
  (match AA.publish ~directory ~output ~artifacts:[ artifact "/abs" "x" ] with
   | Ok _ -> check "absolute path rejected" false
   | Error _ -> ());
  (match
     AA.publish ~directory ~output
       ~artifacts:[ artifact "dup" "1"; artifact "dup" "2" ]
   with
   | Ok _ -> check "duplicate path rejected" false
   | Error _ -> ());
  check "unsafe paths publish nothing" (not (Sys.file_exists output));
  remove_tree directory;
  remove_tree output

let test_symlink_and_overlap () =
  let directory = temp_dir () and output = temp_dir () in
  remove_tree output;
  Unix.mkdir output 0o755;
  Unix.mkdir (Filename.concat output "real") 0o755;
  Unix.symlink (Filename.concat output "real") (Filename.concat output "link");
  (match AA.publish ~directory ~output ~artifacts:[ artifact "link/x" "x" ] with
   | Ok _ -> check "symlink traversal rejected" false
   | Error _ -> ());
  (match
     AA.publish ~directory ~output
       ~artifacts:[ artifact "a" "x"; artifact "a/legal" "x" ]
   with
   | Ok _ -> check "file/dir overlap rejected" false
   | Error _ -> ());
  let nested = Filename.concat directory "out" in
  (match AA.publish ~directory ~output:nested ~artifacts:[ artifact "a.txt" "x" ] with
   | Ok _ -> check "source/output overlap rejected" false
   | Error _ -> ());
  check "overlap publishes nothing" (not (Sys.file_exists nested));
  remove_tree directory;
  remove_tree output

let test_commit_failure_preserves () =
  let directory = temp_dir () and output = temp_dir () in
  remove_tree output;
  (match
     AA.publish ~directory ~output
       ~artifacts:[ artifact "keep" "old"; artifact "a.txt" "alpha" ]
   with
   | Error _ -> check "publish baseline" false
   | Ok _ -> ());
  (match AA.publish ~directory ~output ~artifacts:[ artifact "keep/b.txt" "new" ] with
   | Ok _ -> check "commit failure expected" false
   | Error errors -> check "commit failure reported" (has_code Error.Code.io_error errors));
  check_equal "previous file kept" "old" (read (Filename.concat output "keep"));
  check_equal "previous sibling kept" "alpha" (read (Filename.concat output "a.txt"));
  remove_tree directory;
  remove_tree output

let test_native_capture () =
  let directory = temp_dir () in
  write (Filename.concat directory "A.cyrograf") "struct A { x: string }\n";
  write (Filename.concat directory "Data.toml") "[msg.M.struct]\ny = \"string\"\n";
  write (Filename.concat directory "notes.txt") "ignore\n";
  (match WA.capture_native ~paths:[ directory ] with
   | Error _ -> check "native capture" false
   | Ok snapshot ->
     check_equal "native selection" "A.cyrograf"
       (String.concat "," (List.map (fun (s : WA.native_source) -> s.name) snapshot.WA.native_sources)));
  (match WA.capture_native ~paths:[ Filename.concat directory "Data.toml" ] with
   | Ok _ -> check "explicit TOML rejected" false
   | Error errors ->
     check "explicit TOML code" (has_code Error.Code.unsupported_source_format errors));
  let target = Filename.concat directory "A.cyrograf" in
  Unix.symlink target (Filename.concat directory "Link.cyrograf");
  (match WA.capture_native ~paths:[ Filename.concat directory "Link.cyrograf" ] with
   | Ok _ -> check "symlink rejected" false
   | Error _ -> ());
  remove_tree directory

let test_replace_native () =
  let directory = temp_dir () in
  let path = Filename.concat directory "A.cyrograf" in
  write path "struct A { x: string }\n";
  Unix.chmod path 0o640;
  (match WA.capture_native ~paths:[ directory ] with
   | Error _ -> check "capture for replace" false
   | Ok snapshot ->
     (match
        WA.replace_native snapshot
          [ (path, "struct A {\n  x: string\n}\n") ]
      with
      | Error _ -> check "replace writes" false
      | Ok () -> ());
     let perm = (Unix.stat path).Unix.st_perm in
     check "replace preserves permissions" (perm = 0o640);
     check_equal "replace content" "struct A {\n  x: string\n}\n" (read path);
     (match WA.replace_native snapshot [ (path, "struct A {}\n") ] with
      | Ok _ -> check "stale revision rejected" false
      | Error errors -> check "stale revision code" (has_code Error.Code.source_changed errors)));
  remove_tree directory

let () =
  test_publish_success_and_stale ();
  test_foreign_and_manifest ();
  test_unsafe_paths ();
  test_symlink_and_overlap ();
  test_commit_failure_preserves ();
  test_native_capture ();
  test_replace_native ();
  if !failures = 0 then Printf.printf "all access tests passed\n"
  else begin
    Printf.printf "%d access test(s) failed\n" !failures;
    exit 1
  end