(* A tooling diagnostic: a stable [Cyrograf.Error.t] plus an optional byte
   range in a named source and optional related locations. *)

module Diag = Cyrograf.Error

type range = {
  source : string;
  start_byte : int;
  end_byte : int;
}

type t = {
  error : Diag.t;
  range : range option;
  related : (range * string) list;
}

let make ?range ?(related = []) ?(path = []) ?source ~code message =
  let error = Diag.make ?source ~path ~code message in
  { error; range; related }

let range_of error source start_byte end_byte =
  ignore error;
  { source; start_byte; end_byte }

let with_range_opt range diagnostic =
  match (diagnostic.range, range) with
  | Some _, _ -> diagnostic
  | None, Some _ -> { diagnostic with range }
  | None, None -> diagnostic

let source_name diagnostic =
  match diagnostic.range with
  | Some range -> Some range.source
  | None -> (
    match diagnostic.error.source with
    | Some source -> Some source.name
    | None -> None)

let code diagnostic = diagnostic.error.code
let message diagnostic = diagnostic.error.message
let path diagnostic = diagnostic.error.path

let to_error ?text diagnostic =
  let error = diagnostic.error in
  match diagnostic.range with
  | None -> error
  | Some range ->
    let source =
      match text with
      | Some text ->
        { Diag.name = range.source;
          line = Some (Syntax.line_of_offset text range.start_byte);
          column = Some (Syntax.column_of_offset text range.start_byte) }
      | None -> { Diag.name = range.source; line = None; column = None }
    in
    Diag.with_source source error

let to_string ?text diagnostic =
  Diag.to_string (to_error ?text diagnostic)