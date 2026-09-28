(* Python generator: standard library only, dataclasses and typed variants.

   The generated package ships its own private [_wire] runtime. Message modules
   expose exactly the two text conversions [to_drut]/[from_drut]; the private
   value helpers are not a public Drut/Codec surface. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let wire_source =
  {py|"""Private Drut runtime for the generated contracts. Not a public API."""

from __future__ import annotations

import json as _json
import math as _math
from typing import Any, Callable, Dict, List, NoReturn, Optional, Tuple, Union, cast

_MAX_SAFE_INT = 9007199254740991


class CyrografError(Exception):
    """Error raised by the generated Drut conversions."""

    def __init__(self, code: str, path: str, message: str) -> None:
        super().__init__(message)
        self.code = code
        self.path = path
        self.message = message


def fail(code: str, path: str, message: str) -> NoReturn:
    raise CyrografError(code, path, message)


class _Number:
    __slots__ = ("lexeme", "value")

    def __init__(self, lexeme: str, value: Union[int, float]) -> None:
        self.lexeme = lexeme
        self.value = value


def _is_digit(code: int) -> bool:
    return 0x30 <= code <= 0x39


def _hex_value(code: int) -> Optional[int]:
    if 0x30 <= code <= 0x39:
        return code - 0x30
    if 0x61 <= code <= 0x66:
        return code - 0x61 + 10
    if 0x41 <= code <= 0x46:
        return code - 0x41 + 10
    return None


def _exact_integer(lexeme: str) -> Union[int, str]:
    length = len(lexeme)
    if length == 0:
        return "InvalidInt"
    negative = lexeme[0] == "-"
    start = 1 if negative else 0
    integer_end = start
    while integer_end < length and _is_digit(ord(lexeme[integer_end])):
        integer_end += 1
    integer_digits = lexeme[start:integer_end]
    fraction_digits = ""
    after_fraction = integer_end
    if after_fraction < length and lexeme[after_fraction] == ".":
        stop = after_fraction + 1
        while stop < length and _is_digit(ord(lexeme[stop])):
            stop += 1
        fraction_digits = lexeme[after_fraction + 1:stop]
        after_fraction = stop
    exponent = 0
    if after_fraction < length and lexeme[after_fraction] in ("e", "E"):
        position = after_fraction + 1
        sign = 1
        if position < length and lexeme[position] in ("+", "-"):
            if lexeme[position] == "-":
                sign = -1
            position += 1
        digit_start = position
        value = 0
        while position < length and _is_digit(ord(lexeme[position])):
            value = value * 10 + (ord(lexeme[position]) - 0x30)
            if value > 1000000:
                return "IntOutOfRange"
            position += 1
        if position == digit_start:
            return "InvalidInt"
        exponent = sign * value
    mantissa = integer_digits + fraction_digits
    first = 0
    while first < len(mantissa) and mantissa[first] == "0":
        first += 1
    cleaned = mantissa[first:]
    if cleaned == "":
        return 0
    shift = exponent - len(fraction_digits)
    if shift >= 0:
        if len(cleaned) + shift > 16:
            return "IntOutOfRange"
        magnitude = int(cleaned + "0" * shift)
    else:
        drop = -shift
        if drop >= len(cleaned):
            if cleaned.strip("0") != "":
                return "IntOutOfRange"
            magnitude = 0
        else:
            tail = cleaned[len(cleaned) - drop:]
            if tail.strip("0") != "":
                return "IntOutOfRange"
            magnitude = int(cleaned[:len(cleaned) - drop])
    signed = -magnitude if negative else magnitude
    if signed < -_MAX_SAFE_INT or signed > _MAX_SAFE_INT:
        return "IntOutOfRange"
    return signed


def _scan_string_at(text: str, start: int) -> int:
    index = start
    length = len(text)
    while index < length:
        code = ord(text[index])
        if code == 0x22:
            return index + 1
        if code < 0x20:
            fail("InvalidJson", "", "unescaped control character in string")
        if code == 0x5C:
            if index + 1 >= length:
                fail("InvalidJson", "", "unterminated escape in string")
            escape = text[index + 1]
            if escape == "u":
                if index + 5 >= length:
                    fail("InvalidJson", "", "truncated unicode escape")
                a = _hex_value(ord(text[index + 2]))
                b = _hex_value(ord(text[index + 3]))
                c = _hex_value(ord(text[index + 4]))
                d = _hex_value(ord(text[index + 5]))
                if a is None or b is None or c is None or d is None:
                    fail("InvalidJson", "", "invalid unicode escape")
                point = (a << 12) | (b << 8) | (c << 4) | d
                if 0xD800 <= point <= 0xDBFF:
                    if (index + 11 >= length or text[index + 6] != "\\"
                            or text[index + 7] != "u"):
                        fail("InvalidJson", "", "unpaired surrogate")
                    e = _hex_value(ord(text[index + 8]))
                    f = _hex_value(ord(text[index + 9]))
                    g = _hex_value(ord(text[index + 10]))
                    h = _hex_value(ord(text[index + 11]))
                    if e is None or f is None or g is None or h is None:
                        fail("InvalidJson", "", "invalid unicode escape")
                    low = (e << 12) | (f << 8) | (g << 4) | h
                    if low < 0xDC00 or low > 0xDFFF:
                        fail("InvalidJson", "", "unpaired surrogate")
                    index += 12
                    continue
                if 0xDC00 <= point <= 0xDFFF:
                    fail("InvalidJson", "", "unpaired surrogate")
                index += 6
                continue
            if escape not in ('"', "\\", "/", "b", "f", "n", "r", "t"):
                fail("InvalidJson", "", "invalid escape in string")
            index += 2
            continue
        if 0xD800 <= code <= 0xDBFF:
            if index + 1 >= length:
                fail("InvalidJson", "", "unpaired surrogate")
            if not (0xDC00 <= ord(text[index + 1]) <= 0xDFFF):
                fail("InvalidJson", "", "unpaired surrogate")
            index += 2
            continue
        if 0xDC00 <= code <= 0xDFFF:
            fail("InvalidJson", "", "unpaired surrogate")
        index += 1
    fail("InvalidJson", "", "unterminated string")


def _scan_strings(text: str) -> None:
    index = 0
    length = len(text)
    while index < length:
        if text[index] == '"':
            index = _scan_string_at(text, index + 1)
        else:
            index += 1


def _reject_constant(_text: str) -> NoReturn:
    fail("InvalidJson", "", "unexpected numeric constant")


def _record_number(value: Union[int, float]) -> Union[int, float]:
    number = float(value)
    if _math.isfinite(number) and number == float(int(number)) and abs(number) <= 9007199254740992.0:
        return int(number)
    return number


def _canonical_numbers(value: Any) -> Any:
    if isinstance(value, _Number):
        return _record_number(value.value)
    if isinstance(value, list):
        for index in range(len(value)):
            value[index] = _canonical_numbers(value[index])
        return value
    if isinstance(value, dict):
        for key in list(value.keys()):
            value[key] = _canonical_numbers(value[key])
        return value
    return value


def parse_text(text: str) -> Any:
    if text.startswith("\ufeff"):
        fail("InvalidJson", "", "a leading byte order mark is not valid Wire input")
    _scan_strings(text)

    def pairs(items: List[Tuple[str, Any]]) -> Any:
        seen: set[str] = set()
        out: Dict[str, Any] = {}
        for key, item in items:
            if key in seen:
                fail("DuplicateKey", "", "duplicate object key " + key)
            seen.add(key)
            out[key] = item
        return out

    try:
        return _json.loads(
            text,
            object_pairs_hook=pairs,
            parse_int=lambda lexeme: _Number(lexeme, int(lexeme)),
            parse_float=lambda lexeme: _Number(lexeme, float(lexeme)),
            parse_constant=_reject_constant,
        )
    except CyrografError:
        raise
    except ValueError as error:
        fail("InvalidJson", "", "invalid JSON: " + str(error))


def as_array(data: Any, path: str, length: int = -1) -> List[Any]:
    if not isinstance(data, list):
        fail("TypeMismatch", path, "expected an array")
    if length >= 0 and len(data) != length:
        fail("UnexpectedLength", path,
             "expected %d element(s) but found %d" % (length, len(data)))
    return data


def as_string(data: Any, path: str) -> str:
    if not isinstance(data, str):
        fail("TypeMismatch", path, "expected a string")
    return data


def as_int(data: Any, path: str) -> int:
    if isinstance(data, _Number):
        exact = _exact_integer(data.lexeme)
        if isinstance(exact, str):
            if exact == "IntOutOfRange":
                fail("IntOutOfRange", path, "integer outside the Wire v1 range")
            fail("InvalidInt", path, "expected an exact integer")
        return exact
    if isinstance(data, bool):
        fail("TypeMismatch", path, "expected an integer")
    if isinstance(data, int):
        if data < -_MAX_SAFE_INT or data > _MAX_SAFE_INT:
            fail("IntOutOfRange", path, "integer outside the Wire v1 range")
        return data
    if isinstance(data, float):
        if data != _math.trunc(data):
            fail("InvalidInt", path, "expected an exact integer")
        if data < -_MAX_SAFE_INT or data > _MAX_SAFE_INT:
            fail("IntOutOfRange", path, "integer outside the Wire v1 range")
        return int(data)
    fail("TypeMismatch", path, "expected an integer")


def as_float(data: Any, path: str) -> float:
    if isinstance(data, bool):
        fail("TypeMismatch", path, "expected a number")
    if isinstance(data, _Number):
        number = float(data.value)
        if not _math.isfinite(number):
            fail("InvalidFloat", path, "non-finite number")
        return number
    if isinstance(data, int):
        return float(data)
    if isinstance(data, float):
        if not _math.isfinite(data):
            fail("InvalidFloat", path, "non-finite number")
        return data
    fail("TypeMismatch", path, "expected a number")


def as_bool(data: Any, path: str) -> bool:
    if not isinstance(data, bool):
        fail("TypeMismatch", path, "expected a boolean")
    return data


def as_null(data: Any, path: str) -> object:
    if data is not None:
        fail("TypeMismatch", path, "expected null")
    return None


def as_record(data: Any, path: str) -> Dict[str, object]:
    if not isinstance(data, dict):
        fail("TypeMismatch", path, "expected an object")
    return cast("Dict[str, object]", _canonical_numbers(data))


def _check_unicode(value: str, path: str) -> None:
    for code in (ord(character) for character in value):
        if 0xD800 <= code <= 0xDFFF:
            fail("InvalidString", path, "string contains an unpaired surrogate")


def encode_string(value: str, _path: str) -> str:
    _check_unicode(value, _path)
    return value


def encode_int(value: int, path: str) -> int:
    if isinstance(value, bool) or not isinstance(value, int):
        fail("TypeMismatch", path, "expected an integer")
    if value < -_MAX_SAFE_INT or value > _MAX_SAFE_INT:
        fail("IntOutOfRange", path, "integer outside the Wire v1 range")
    return value


def encode_float(value: float, path: str) -> float:
    if isinstance(value, bool) or not isinstance(value, float):
        fail("TypeMismatch", path, "expected a number")
    if not _math.isfinite(value):
        fail("InvalidFloat", path, "non-finite number")
    return value


def encode_bool(value: bool, path: str) -> bool:
    if not isinstance(value, bool):
        fail("TypeMismatch", path, "expected a boolean")
    return value


def encode_void(value: object, path: str) -> object:
    if value is not None:
        fail("TypeMismatch", path, "expected null")
    return None


def _check_finite(value: Any, path: str) -> None:
    if isinstance(value, bool):
        return
    if isinstance(value, float):
        if not _math.isfinite(value):
            fail("NonFiniteNumber", path, "non-finite number")
        return
    if isinstance(value, _Number):
        if isinstance(value.value, float) and not _math.isfinite(value.value):
            fail("NonFiniteNumber", path, "non-finite number")
        return
    if isinstance(value, list):
        for index, item in enumerate(value):
            _check_finite(item, "%s[%d]" % (path, index))
        return
    if isinstance(value, dict):
        for key, item in value.items():
            _check_finite(item, "%s.%s" % (path, key))
        return


def encode_record(value: Dict[str, object], path: str) -> object:
    _check_finite(value, path)
    return value


def encode_list(items: List[Any], path: str,
                encode: Callable[[Any, str], Any]) -> List[Any]:
    out: List[Any] = []
    for index, item in enumerate(items):
        out.append(encode(item, "%s[%d]" % (path, index)))
    return out


def decode_list(data: Any, path: str,
                decode: Callable[[Any, str], Any]) -> List[Any]:
    arr = as_array(data, path)
    return [decode(item, "%s[%d]" % (path, index)) for index, item in enumerate(arr)]


def encode_optional(value: Any, path: str,
                    encode: Callable[[Any, str], Any]) -> Any:
    if value is None:
        return None
    return encode(value, path)


def decode_optional(data: Any, path: str,
                    decode: Callable[[Any, str], Any]) -> Any:
    if data is None:
        return None
    return decode(data, path)


def stringify(value: Any) -> str:
    _check_finite(value, "")
    try:
        return _json.dumps(value, ensure_ascii=False, separators=(",", ":"),
                           allow_nan=False)
    except (TypeError, ValueError) as error:
        fail("InvalidJson", "", str(error))
|py}

let python_module_name = Naming.python_module_name

let reference_type ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name
  else python_module_name qualified.module_name ^ "." ^ qualified.message_name

let rec python_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "str"
  | Schema.Primitive Schema.Int -> "int"
  | Schema.Primitive Schema.Float -> "float"
  | Schema.Primitive Schema.Bool -> "bool"
  | Schema.Primitive Schema.Void -> "None"
  | Schema.Primitive Schema.Record -> "dict[str, object]"
  | Schema.Reference qualified -> reference_type ~local qualified
  | Schema.List inner -> "list[" ^ python_type ~local inner ^ "]"
  | Schema.Optional inner -> python_type ~local inner ^ " | None"

let rec encode_fn ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    "lambda x, p: _wire.encode_string(x, p)"
  | Schema.Primitive Schema.Int -> "lambda x, p: _wire.encode_int(x, p)"
  | Schema.Primitive Schema.Float -> "lambda x, p: _wire.encode_float(x, p)"
  | Schema.Primitive Schema.Bool -> "lambda x, p: _wire.encode_bool(x, p)"
  | Schema.Primitive Schema.Void -> "lambda x, p: _wire.encode_void(x, p)"
  | Schema.Primitive Schema.Record -> "lambda x, p: _wire.encode_record(x, p)"
  | Schema.Reference _ -> "lambda x, p: _wire.parse_text(x.to_drut())"
  | Schema.List inner ->
    Printf.sprintf "lambda x, p: _wire.encode_list(x, p, %s)" (encode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "lambda x, p: _wire.encode_optional(x, p, %s)"
      (encode_fn ~local inner)

let rec decode_fn ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    "lambda x, p: _wire.as_string(x, p)"
  | Schema.Primitive Schema.Int -> "lambda x, p: _wire.as_int(x, p)"
  | Schema.Primitive Schema.Float -> "lambda x, p: _wire.as_float(x, p)"
  | Schema.Primitive Schema.Bool -> "lambda x, p: _wire.as_bool(x, p)"
  | Schema.Primitive Schema.Void -> "lambda x, p: _wire.as_null(x, p)"
  | Schema.Primitive Schema.Record -> "lambda x, p: _wire.as_record(x, p)"
  | Schema.Reference qualified ->
    Printf.sprintf "lambda x, p: %s.from_drut(_wire.stringify(x))"
      (reference_type ~local qualified)
  | Schema.List inner ->
    Printf.sprintf "lambda x, p: _wire.decode_list(x, p, %s)" (decode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "lambda x, p: _wire.decode_optional(x, p, %s)"
      (decode_fn ~local inner)

let encode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "_wire.encode_string(%s, %S)" expr path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "_wire.encode_int(%s, %S)" expr path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "_wire.encode_float(%s, %S)" expr path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "_wire.encode_bool(%s, %S)" expr path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "_wire.encode_void(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "_wire.encode_record(%s, %S)" expr path
  | Schema.Reference _ -> Printf.sprintf "_wire.parse_text(%s.to_drut())" expr
  | Schema.List inner ->
    Printf.sprintf "_wire.encode_list(%s, %S, %s)" expr path (encode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "_wire.encode_optional(%s, %S, %s)" expr path
      (encode_fn ~local inner)

let decode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "_wire.as_string(%s, %S)" expr path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "_wire.as_int(%s, %S)" expr path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "_wire.as_float(%s, %S)" expr path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "_wire.as_bool(%s, %S)" expr path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "_wire.as_null(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "_wire.as_record(%s, %S)" expr path
  | Schema.Reference qualified ->
    Printf.sprintf "%s.from_drut(_wire.stringify(%s))"
      (reference_type ~local qualified) expr
  | Schema.List inner ->
    Printf.sprintf "_wire.decode_list(%s, %S, %s)" expr path (decode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "_wire.decode_optional(%s, %S, %s)" expr path
      (decode_fn ~local inner)

let field_name = Naming.python_field

let path_of ~module_name name = module_name ^ "." ^ name

let struct_code ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = path_of ~module_name name in
  p "@dataclass(kw_only=True)\n";
  p "class %s:\n" name;
  List.iter
    (fun (field : Schema.field) ->
      match field.type_ with
      | Schema.Optional _ ->
        p "    %s: %s = None\n" (field_name field.name)
          (python_type ~local field.type_)
      | _ ->
        p "    %s: %s\n" (field_name field.name) (python_type ~local field.type_))
    fields;
  p "\n";
  p "    def to_drut(self) -> str:\n";
  p "        return _wire.stringify(self._to_value())\n\n";
  p "    def _to_value(self) -> list[object]:\n";
  if fields = [] then p "        return []\n\n"
  else begin
    p "        return [\n";
    List.iter
      (fun (field : Schema.field) ->
        p "            %s,\n"
          (encode_expr ~local ("self." ^ field_name field.name)
             (path ^ "." ^ field.name) field.type_))
      fields;
    p "        ]\n\n"
  end;
  p "    @classmethod\n";
  p "    def from_drut(cls, text: str) -> %s:\n" name;
  p "        return cls._from_value(_wire.parse_text(text))\n\n";
  p "    @classmethod\n";
  p "    def _from_value(cls, data: object) -> %s:\n" name;
  if fields = [] then begin
    p "        _wire.as_array(data, %S, 0)\n" path;
    p "        return cls()\n"
  end
  else begin
    p "        arr = _wire.as_array(data, %S, %d)\n" path (List.length fields);
    List.iteri
      (fun index (field : Schema.field) ->
        match field.type_ with
        | Schema.Primitive Schema.Void ->
          p "        _wire.as_null(arr[%d], %S)\n" index
            (path ^ "." ^ field.name)
        | _ -> ())
      fields;
    p "        return cls(\n";
    List.iteri
      (fun index (field : Schema.field) ->
        let value =
          match field.type_ with
          | Schema.Primitive Schema.Void -> "None"
          | _ ->
            decode_expr ~local (Printf.sprintf "arr[%d]" index)
              (path ^ "." ^ field.name) field.type_
        in
        p "            %s=%s,\n" (field_name field.name) value)
      fields;
    p "        )\n"
  end;
  Buffer.contents buffer

let case_class_name name (constructor : Schema.constructor) =
  name ^ constructor.name

let variant_code ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = path_of ~module_name name in
  p "class %s:\n" name;
  p "    def to_drut(self) -> str:\n";
  p "        return _wire.stringify(self._to_value())\n\n";
  p "    def _to_value(self) -> list[object]:\n";
  p "        _wire.fail(\"InvalidVariant\", %S,\n" path;
  p "                   \"unsupported variant implementation\")\n\n";
  p "    @classmethod\n";
  p "    def from_drut(cls, text: str) -> %s:\n" name;
  p "        return cls._from_value(_wire.parse_text(text))\n\n";
  p "    @classmethod\n";
  p "    def _from_value(cls, data: object) -> %s:\n" name;
  p "        arr = _wire.as_array(data, %S, 2)\n" path;
  p "        tag = _wire.as_string(arr[0], %S)\n" (path ^ "[0]");
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "        if tag == %S:\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "            _wire.as_null(arr[1], %S)\n" (path ^ "[1]");
         p "            return %s()\n" (case_class_name name constructor)
       | type_ ->
         p "            return %s(\n" (case_class_name name constructor);
         p "                value=%s,\n"
           (decode_expr ~local "arr[1]" (path ^ "[1]") type_);
         p "            )\n"))
    constructors;
  p "        _wire.fail(\"UnknownVariantTag\", %S, \"unknown tag \" + tag)\n\n" path;
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "@dataclass\n";
      p "class %s(%s):\n" (case_class_name name constructor) name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void -> ()
       | type_ ->
         p "    value: %s\n" (python_type ~local type_));
      p "\n";
      p "    def _to_value(self) -> list[object]:\n";
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "        return [%S, None]\n\n" constructor.name
       | type_ ->
         p "        return [%S, %s]\n\n" constructor.name
           (encode_expr ~local "self.value" (path ^ ".value") type_)))
    constructors;
  Buffer.contents buffer

let message_code ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_code ~module_name message fields
  | Schema.Variant constructors -> variant_code ~module_name message constructors

let module_exports (module_ : Schema.module_) =
  List.concat_map
    (fun (message : Schema.message) ->
      match message.kind with
      | Schema.Struct _ -> [ message.name ]
      | Schema.Variant constructors ->
        message.name :: List.map (case_class_name message.name) constructors)
    module_.messages

let referenced_modules (module_ : Schema.module_) =
  let modules = Hashtbl.create 8 in
  let rec scan (type_ : Schema.type_) =
    match type_ with
    | Schema.Primitive _ -> ()
    | Schema.Reference qualified ->
      if qualified.module_name <> module_.name then
        Hashtbl.replace modules qualified.module_name ()
    | Schema.List inner -> scan inner
    | Schema.Optional inner -> scan inner
  in
  List.iter
    (fun (message : Schema.message) ->
      match message.kind with
      | Schema.Struct fields ->
        List.iter (fun (field : Schema.field) -> scan field.type_) fields
      | Schema.Variant constructors ->
        List.iter (fun (constructor : Schema.constructor) -> scan constructor.payload)
          constructors)
    module_.messages;
  List.iter
    (fun (method_ : Schema.method_) ->
      let check (qualified : Schema.qualified) =
        if qualified.module_name <> module_.name then
          Hashtbl.replace modules qualified.module_name ()
      in
      check method_.request;
      check method_.response)
    module_.methods;
  Hashtbl.fold (fun name () acc -> name :: acc) modules []
  |> List.sort String.compare

let module_code (module_ : Schema.module_) =
  let buffer = Buffer.create 2048 in
  let p fmt = Printf.bprintf buffer fmt in
  p "# Generated by Cyrograf. Do not edit.\n\n";
  p "from __future__ import annotations\n\n";
  p "from dataclasses import dataclass\n\n";
  p "from . import _wire\n";
  List.iter
    (fun name ->
      p "from . import %s\n" (python_module_name name))
    (referenced_modules module_);
  p "\n";
  (match module_exports module_ with
   | [] -> p "__all__: list[str] = []\n\n"
   | exports ->
     p "__all__ = [\n";
     List.iter (fun name -> p "    %S,\n" name) exports;
     p "]\n\n");
  Naming.topo_sort module_
  |> List.iter (fun message ->
      p "%s\n" (message_code ~module_name:module_.name message));
  Buffer.contents buffer

let init_source =
  {py|"""Generated Cyrograf contracts."""

from ._wire import CyrografError

__all__ = ["CyrografError"]
|py}

let pyproject =
  {py|[build-system]
requires = ["setuptools>=68"]
build-backend = "setuptools.build_meta"

[project]
name = "generated-contracts"
version = "0.1.0"
description = "Generated Cyrograf contracts"
requires-python = ">=3.11"

[tool.setuptools]
packages = ["generated_contracts"]

[tool.setuptools.package-data]
generated_contracts = ["py.typed"]
|py}

let generate ~modules : Kernel.artifact list =
  let module_artifacts =
    List.map
      (fun (module_ : Schema.module_) ->
        { Kernel.path =
            "python/generated_contracts/" ^ Naming.python_file module_.name;
          contents = module_code module_ })
      modules
  in
  [ { Kernel.path = "python/pyproject.toml"; contents = pyproject };
    { Kernel.path = "python/generated_contracts/__init__.py"; contents = init_source };
    { Kernel.path = "python/generated_contracts/_wire.py"; contents = wire_source };
    { Kernel.path = "python/generated_contracts/py.typed"; contents = "" } ]
  @ module_artifacts