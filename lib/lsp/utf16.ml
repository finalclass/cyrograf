(* Conversion between byte offsets in UTF-8 source text and LSP positions.

   LSP lines and columns are counted from 0 and the column counts UTF-16 code
   units, so a code point outside the BMP contributes two units. Line breaks
   are LF, CRLF and a lone CR. The parser offsets remain bytes; this module is
   the only place that maps them to protocol positions. *)

let decode text index =
  let length = String.length text in
  let byte at = if at < length then Char.code text.[at] else 0 in
  let continuation at = at < length && byte at land 0xC0 = 0x80 in
  let b0 = byte index in
  if b0 < 0x80 then (b0, index + 1)
  else if b0 < 0xC0 then (b0, index + 1)
  else if b0 < 0xE0 && continuation (index + 1) then
    ((((b0 land 0x1F) lsl 6) lor (byte (index + 1) land 0x3F)), index + 2)
  else if b0 < 0xF0 && continuation (index + 1) && continuation (index + 2) then
    ( ((b0 land 0x0F) lsl 12)
      lor ((byte (index + 1) land 0x3F) lsl 6)
      lor (byte (index + 2) land 0x3F),
      index + 3 )
  else if b0 < 0xF5 && continuation (index + 1) && continuation (index + 2)
          && continuation (index + 3) then
    ( ((b0 land 0x07) lsl 18)
      lor ((byte (index + 1) land 0x3F) lsl 12)
      lor ((byte (index + 2) land 0x3F) lsl 6)
      lor (byte (index + 3) land 0x3F),
      index + 4 )
  else (b0, index + 1)

let width code_point = if code_point > 0xFFFF then 2 else 1

let position_of_offset text offset =
  let length = String.length text in
  let limit = if offset < 0 then 0 else if offset > length then length else offset in
  let line = ref 0 and character = ref 0 and index = ref 0 in
  while !index < limit do
    match text.[!index] with
    | '\r' ->
      if !index + 1 < length && text.[!index + 1] = '\n' && !index + 2 <= limit then begin
        incr line;
        character := 0;
        index := !index + 2
      end
      else begin
        incr line;
        character := 0;
        incr index
      end
    | '\n' ->
      incr line;
      character := 0;
      incr index
    | c when Char.code c < 0x80 ->
      incr character;
      incr index
    | _ ->
      let code_point, next = decode text !index in
      character := !character + width code_point;
      index := next
  done;
  (!line, !character)

let offset_of_position text ~line ~character =
  let length = String.length text in
  let current_line = ref 0 and index = ref 0 in
  while !current_line < line && !index < length do
    (match text.[!index] with
     | '\r' when !index + 1 < length && text.[!index + 1] = '\n' ->
       index := !index + 2;
       incr current_line
     | '\n' | '\r' ->
       incr index;
       incr current_line
     | _ -> incr index)
  done;
  let column = ref 0 in
  while !column < character && !index < length do
    match text.[!index] with
    | '\n' | '\r' -> column := character
    | c when Char.code c < 0x80 ->
      incr column;
      incr index
    | _ ->
      let code_point, next = decode text !index in
      let step = width code_point in
      if !column + step > character then column := character
      else begin
        column := !column + step;
        index := next
      end
  done;
  !index