(* Native [.cyrograf] frontend.

   The parser turns UTF-8 source text into the shared [Syntax] model with byte
   ranges and comments. It validates notation only: names, primitive meaning,
   reference resolution and ordering belong to [Semantics]. On a notation error
   it recovers at the nearest declaration boundary so the editor still gets the
   declarations that were recognised. *)

module Diag = Cyrograf.Error
module S = Syntax

type token =
  | Ident of string
  | Lbrace
  | Rbrace
  | Lparen
  | Rparen
  | Lbracket
  | Rbracket
  | Lt
  | Gt
  | Colon
  | Question
  | Semi
  | Dot
  | Arrow
  | Newline
  | Eof

type lexeme = {
  token : token;
  start_byte : int;
  end_byte : int;
}

let valid_utf8 text =
  let length = String.length text in
  let continuation index =
    index < length
    && let code = Char.code text.[index] in
    code >= 0x80 && code < 0xC0
  in
  let rec scan index =
    if index >= length then true
    else
      let code = Char.code text.[index] in
      if code < 0x80 then scan (index + 1)
      else if code < 0xC2 then false
      else if code < 0xE0 then
        continuation (index + 1) && scan (index + 2)
      else if code < 0xF0 then
        continuation (index + 1) && continuation (index + 2)
        && (code <> 0xE0 || Char.code text.[index + 1] >= 0xA0)
        && (code <> 0xED || Char.code text.[index + 1] < 0xA0)
        && scan (index + 3)
      else if code < 0xF5 then
        continuation (index + 1) && continuation (index + 2)
        && continuation (index + 3)
        && (code <> 0xF0 || Char.code text.[index + 1] >= 0x90)
        && (code <> 0xF4 || Char.code text.[index + 1] < 0x90)
        && scan (index + 4)
      else false
  in
  scan 0

let is_ident_start c =
  (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') || c = '_'

let is_ident_char c = is_ident_start c || (c >= '0' && c <= '9')

type frontend = {
  name : string;
  text : string;
  mutable lexemes : lexeme array;
  mutable comments : S.comment list;
  mutable diagnostics : Diagnostic.t list;
  mutable index : int;
  mutable last_end : int;
}

let diagnostic frontend ?(range = None) ~code message =
  frontend.diagnostics <- Diagnostic.make ?range ~code message :: frontend.diagnostics

let token_diagnostic frontend ~code message lexeme =
  diagnostic frontend
    ~range:(Some { Diagnostic.source = frontend.name;
                   start_byte = lexeme.start_byte;
                   end_byte = lexeme.end_byte })
    ~code message

let lex frontend =
  let text = frontend.text in
  let length = String.length text in
  let tokens = ref [] in
  let comments = ref [] in
  let index = ref 0 in
  if length >= 3 && String.sub text 0 3 = "\xEF\xBB\xBF" then index := 3;
  let push token start_byte end_byte =
    tokens := { token; start_byte; end_byte } :: !tokens
  in
  let own_line start =
    let rec back position =
      if position <= 0 then true
      else
        match text.[position - 1] with
        | '\n' -> true
        | ' ' | '\t' -> back (position - 1)
        | _ -> false
    in
    back start
  in
  while !index < length do
    let start = !index in
    match text.[start] with
    | ' ' | '\t' -> incr index
    | '\r' ->
      index := if start + 1 < length && text.[start + 1] = '\n' then start + 2 else start + 1;
      push Newline start !index
    | '\n' ->
      incr index;
      push Newline start !index
    | '/' when start + 1 < length && text.[start + 1] = '/' ->
      index := start + 2;
      while !index < length && text.[!index] <> '\n' && text.[!index] <> '\r' do
        incr index
      done;
      let content = String.sub text (start + 2) (!index - start - 2) in
      comments :=
        { S.text = content;
          span = S.Span.make start !index;
          own_line = own_line start }
        :: !comments
    | '{' -> incr index; push Lbrace start !index
    | '}' -> incr index; push Rbrace start !index
    | '(' -> incr index; push Lparen start !index
    | ')' -> incr index; push Rparen start !index
    | '[' -> incr index; push Lbracket start !index
    | ']' -> incr index; push Rbracket start !index
    | '<' -> incr index; push Lt start !index
    | '>' -> incr index; push Gt start !index
    | ':' -> incr index; push Colon start !index
    | '?' -> incr index; push Question start !index
    | ';' -> incr index; push Semi start !index
    | '.' -> incr index; push Dot start !index
    | '-' when start + 1 < length && text.[start + 1] = '>' ->
      index := start + 2;
      push Arrow start !index
    | c when is_ident_start c ->
      incr index;
      while !index < length && is_ident_char text.[!index] do
        incr index
      done;
      push (Ident (String.sub text start (!index - start))) start !index
    | _ ->
      let lexeme = { token = Eof; start_byte = start; end_byte = start + 1 } in
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax
        "unexpected character outside a comment" lexeme;
      incr index
  done;
  push Eof length length;
  frontend.lexemes <- Array.of_list (List.rev !tokens);
  frontend.comments <- List.rev !comments

let peek frontend =
  if frontend.index >= Array.length frontend.lexemes then
    { token = Eof; start_byte = String.length frontend.text; end_byte = String.length frontend.text }
  else frontend.lexemes.(frontend.index)

let peek_token frontend = (peek frontend).token

let advance frontend =
  let lexeme = peek frontend in
  frontend.last_end <- lexeme.end_byte;
  if frontend.index < Array.length frontend.lexemes then frontend.index <- frontend.index + 1;
  lexeme

let at_eof frontend = peek_token frontend = Eof

let span_of _frontend lexeme =
  S.Span.make lexeme.start_byte lexeme.end_byte

let skip_separators frontend =
  let rec loop () =
    match peek_token frontend with
    | Newline | Semi ->
      ignore (advance frontend);
      loop ()
    | _ -> ()
  in
  loop ()

let skip_newlines frontend =
  let rec loop () =
    match peek_token frontend with
    | Newline ->
      ignore (advance frontend);
      loop ()
    | _ -> ()
  in
  loop ()

let expect frontend token message =
  if peek_token frontend = token then ignore (advance frontend)
  else begin
    let lexeme = peek frontend in
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax
      (Printf.sprintf "expected %s" message) lexeme
  end

let empty_type = { S.desc = S.Named ""; span = S.Span.empty }

let rec parse_type frontend ~allow_newlines =
  if allow_newlines then skip_newlines frontend;
  let lexeme = peek frontend in
  match lexeme.token with
  | Ident "List" ->
    ignore (advance frontend);
    skip_newlines frontend;
    ignore (expect frontend Lt "'<'");
    let inner = parse_type frontend ~allow_newlines:true in
    skip_newlines frontend;
    ignore (expect frontend Gt "'>'");
    { S.desc = S.List inner; span = S.Span.make lexeme.start_byte frontend.last_end }
  | Ident name ->
    ignore (advance frontend);
    if allow_newlines then skip_newlines frontend;
    if peek_token frontend = Lt then begin
      let angle = peek frontend in
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax
        "generic type parameters are not supported" angle;
      let depth = ref 1 in
      while !depth > 0 && not (at_eof frontend) do
        (match peek_token frontend with
         | Lt -> incr depth
         | Gt -> decr depth
         | _ -> ());
        ignore (advance frontend)
      done;
      { S.desc = S.Named name; span = S.Span.make lexeme.start_byte frontend.last_end }
    end
    else if peek_token frontend = Dot then begin
      ignore (advance frontend);
      if allow_newlines then skip_newlines frontend;
      (match peek frontend with
       | { token = Ident message; _ } as message_lexeme ->
         ignore (advance frontend);
         { S.desc = S.Qualified (name, message);
           span = S.Span.make lexeme.start_byte message_lexeme.end_byte }
       | other ->
         token_diagnostic frontend ~code:Diag.Code.invalid_syntax
           "expected a message name after '.'" other;
         { S.desc = S.Qualified (name, ""); span = S.Span.make lexeme.start_byte frontend.last_end })
    end
    else { S.desc = S.Named name; span = span_of frontend lexeme }
  | _ ->
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax "expected a type" lexeme;
    ignore (advance frontend);
    { S.desc = S.Named ""; span = span_of frontend lexeme }

let recover_to_separator frontend =
  let rec loop () =
    match peek_token frontend with
    | Newline | Semi | Rbrace | Eof -> ()
    | _ ->
      ignore (advance frontend);
      loop ()
  in
  loop ()

let end_member frontend =
  match peek_token frontend with
  | Newline | Semi -> skip_separators frontend
  | Rbrace | Eof -> ()
  | _ ->
    let lexeme = peek frontend in
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax
      "expected a separator or the closing '}'" lexeme

let parse_field frontend =
  let lexeme = peek frontend in
  match lexeme.token with
  | Ident name ->
    ignore (advance frontend);
    let name_span = span_of frontend lexeme in
    let optional =
      if peek_token frontend = Question then begin
        ignore (advance frontend);
        true
      end
      else false
    in
    ignore (expect frontend Colon "':'");
    let type_ = parse_type frontend ~allow_newlines:false in
    Some
      { S.name;
        name_span;
        type_;
        optional;
        span = S.Span.make lexeme.start_byte frontend.last_end }
  | _ ->
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax "expected a field" lexeme;
    recover_to_separator frontend;
    None

let parse_constructor frontend =
  let lexeme = peek frontend in
  match lexeme.token with
  | Ident name ->
    ignore (advance frontend);
    let name_span = span_of frontend lexeme in
    let payload =
      match peek_token frontend with
      | Lparen ->
        ignore (advance frontend);
        let inner = parse_type frontend ~allow_newlines:true in
        skip_newlines frontend;
        ignore (expect frontend Rparen "')'");
        Some inner
      | _ -> None
    in
    Some
      { S.name;
        name_span;
        payload;
        span = S.Span.make lexeme.start_byte frontend.last_end }
  | _ ->
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax "expected a constructor" lexeme;
    recover_to_separator frontend;
    None

let parse_structure frontend keyword =
  let name_lexeme = peek frontend in
  let name, name_span =
    match name_lexeme.token with
    | Ident name ->
      ignore (advance frontend);
      (name, span_of frontend name_lexeme)
    | _ ->
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax "expected a message name" name_lexeme;
      ("", span_of frontend name_lexeme)
  in
  ignore (expect frontend Lbrace "'{'");
  let fields = ref [] in
  let rec loop () =
    skip_separators frontend;
    match peek_token frontend with
    | Rbrace ->
      ignore (advance frontend);
      ()
    | Eof ->
      let lexeme = peek frontend in
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax
        "unclosed struct body" lexeme
    | _ ->
      (match parse_field frontend with
       | Some field -> fields := field :: !fields
       | None -> ());
      end_member frontend;
      loop ()
  in
  loop ();
  S.Struct
    { name;
      name_span;
      span = S.Span.make keyword.start_byte frontend.last_end;
      fields = List.rev !fields }

let parse_variant frontend keyword =
  let name_lexeme = peek frontend in
  let name, name_span =
    match name_lexeme.token with
    | Ident name ->
      ignore (advance frontend);
      (name, span_of frontend name_lexeme)
    | _ ->
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax "expected a message name" name_lexeme;
      ("", span_of frontend name_lexeme)
  in
  ignore (expect frontend Lbrace "'{'");
  let constructors = ref [] in
  let rec loop () =
    skip_separators frontend;
    match peek_token frontend with
    | Rbrace ->
      ignore (advance frontend);
      ()
    | Eof ->
      let lexeme = peek frontend in
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax
        "unclosed variant body" lexeme
    | _ ->
      (match parse_constructor frontend with
       | Some constructor -> constructors := constructor :: !constructors
       | None -> ());
      end_member frontend;
      loop ()
  in
  loop ();
  S.Variant
    { name;
      name_span;
      span = S.Span.make keyword.start_byte frontend.last_end;
      constructors = List.rev !constructors }

let parse_method frontend keyword =
  let name_lexeme = peek frontend in
  let name, name_span =
    match name_lexeme.token with
    | Ident name ->
      ignore (advance frontend);
      (name, span_of frontend name_lexeme)
    | _ ->
      token_diagnostic frontend ~code:Diag.Code.invalid_syntax "expected a method name" name_lexeme;
      ("", span_of frontend name_lexeme)
  in
  ignore (expect frontend Lparen "'('");
  let request = parse_type frontend ~allow_newlines:true in
  skip_newlines frontend;
  ignore (expect frontend Rparen "')'");
  ignore (expect frontend Arrow "'->'");
  let response = parse_type frontend ~allow_newlines:false in
  (match peek_token frontend with
   | Newline | Semi -> skip_separators frontend
   | Eof -> ()
   | _ ->
     let lexeme = peek frontend in
     token_diagnostic frontend ~code:Diag.Code.invalid_syntax
       "expected the end of the method declaration" lexeme);
  S.Rpc
    { name;
      name_span;
      span = S.Span.make keyword.start_byte frontend.last_end;
      request;
      response }

let parse_declaration frontend =
  let lexeme = peek frontend in
  match lexeme.token with
  | Ident "struct" ->
    ignore (advance frontend);
    parse_structure frontend lexeme
  | Ident "variant" ->
    ignore (advance frontend);
    parse_variant frontend lexeme
  | Ident "rpc" ->
    ignore (advance frontend);
    parse_method frontend lexeme
  | Ident _ | Lbrace | Lparen | Lbracket ->
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax
      "expected a struct, variant or rpc declaration" lexeme;
    recover_to_separator frontend;
    ignore (advance frontend);
    let dummy = peek frontend in
    S.Struct { name = ""; name_span = span_of frontend dummy
             ; span = span_of frontend lexeme; fields = [] }
  | _ ->
    token_diagnostic frontend ~code:Diag.Code.invalid_syntax
      "expected a struct, variant or rpc declaration" lexeme;
    recover_to_separator frontend;
    ignore (advance frontend);
    S.Struct { name = ""; name_span = span_of frontend lexeme
             ; span = span_of frontend lexeme; fields = [] }

let parse_document frontend =
  let declarations = ref [] in
  skip_separators frontend;
  while not (at_eof frontend) do
    let before = frontend.index in
    declarations := parse_declaration frontend :: !declarations;
    if frontend.index = before then ignore (advance frontend);
    skip_separators frontend
  done;
  List.rev !declarations

let parse ~name ~text =
  if not (valid_utf8 text) then
    ({ S.name; text; declarations = []; comments = [] },
     [ Diagnostic.make ~code:Diag.Code.invalid_source_encoding
         "the source is not valid UTF-8" ])
  else begin
    let frontend =
      { name; text; lexemes = [||]; comments = []; diagnostics = []
      ; index = 0; last_end = 0 }
    in
    lex frontend;
    let declarations = parse_document frontend in
    ({ S.name; text; declarations; comments = frontend.comments },
     List.rev frontend.diagnostics)
  end