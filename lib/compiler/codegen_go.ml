(* Go generator: standard library only, explicit errors, no transport. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let wire_source =
  {|package wire

import (
	"encoding/json"
	"fmt"
	"io"
	"math"
	"strconv"
	"strings"
	"unicode/utf8"
)

type WireError struct {
	Code    string
	Path    string
	Message string
}

func (e *WireError) Error() string {
	return e.Code + " at " + e.Path + ": " + e.Message
}

func Fail(code, path, message string) error {
	return &WireError{Code: code, Path: path, Message: message}
}

const maxSafeInt = 9007199254740991

// exactInteger returns the exact integer a JSON number lexeme denotes, or a
// diagnostic code when the spelling is fractional, unparseable or outside the
// inclusive Wire v1 range. It reasons about the digits instead of binary64, so
// 1.0000000000000001 and 1e-400 are rejected although float64 would round them.
func exactInteger(lexeme string) (int64, string) {
	length := len(lexeme)
	if length == 0 {
		return 0, "InvalidInt"
	}
	negative := lexeme[0] == '-'
	start := 0
	if negative {
		start = 1
	}
	integerEnd := start
	for integerEnd < length && lexeme[integerEnd] >= '0' && lexeme[integerEnd] <= '9' {
		integerEnd++
	}
	integerDigits := lexeme[start:integerEnd]
	fractionDigits := ""
	afterFraction := integerEnd
	if afterFraction < length && lexeme[afterFraction] == '.' {
		stop := afterFraction + 1
		for stop < length && lexeme[stop] >= '0' && lexeme[stop] <= '9' {
			stop++
		}
		fractionDigits = lexeme[afterFraction+1 : stop]
		afterFraction = stop
	}
	exponent := 0
	if afterFraction < length && (lexeme[afterFraction] == 'e' || lexeme[afterFraction] == 'E') {
		position := afterFraction + 1
		sign := 1
		if position < length && (lexeme[position] == '+' || lexeme[position] == '-') {
			if lexeme[position] == '-' {
				sign = -1
			}
			position++
		}
		digitStart := position
		value := 0
		for position < length && lexeme[position] >= '0' && lexeme[position] <= '9' {
			value = value*10 + int(lexeme[position]-'0')
			if value > 1000000 {
				return 0, "IntOutOfRange"
			}
			position++
		}
		if position == digitStart {
			return 0, "InvalidInt"
		}
		exponent = sign * value
	}
	mantissa := integerDigits + fractionDigits
	from := 0
	for from < len(mantissa) && mantissa[from] == '0' {
		from++
	}
	cleaned := mantissa[from:]
	if cleaned == "" {
		return 0, ""
	}
	shift := exponent - len(fractionDigits)
	var magnitude int64
	if shift >= 0 {
		if len(cleaned)+shift > 16 {
			return 0, "IntOutOfRange"
		}
		parsed, err := strconv.ParseInt(cleaned+strings.Repeat("0", shift), 10, 64)
		if err != nil {
			return 0, "IntOutOfRange"
		}
		magnitude = parsed
	} else {
		drop := -shift
		if drop >= len(cleaned) {
			if strings.Trim(cleaned, "0") != "" {
				return 0, "IntOutOfRange"
			}
			magnitude = 0
		} else {
			tail := cleaned[len(cleaned)-drop:]
			if strings.Trim(tail, "0") != "" {
				return 0, "IntOutOfRange"
			}
			parsed, err := strconv.ParseInt(cleaned[:len(cleaned)-drop], 10, 64)
			if err != nil {
				return 0, "IntOutOfRange"
			}
			magnitude = parsed
		}
	}
	if negative {
		magnitude = -magnitude
	}
	if magnitude < -maxSafeInt || magnitude > maxSafeInt {
		return 0, "IntOutOfRange"
	}
	return magnitude, ""
}

func hexValue(character byte) (int, bool) {
	switch {
	case character >= '0' && character <= '9':
		return int(character - '0'), true
	case character >= 'a' && character <= 'f':
		return int(character-'a') + 10, true
	case character >= 'A' && character <= 'F':
		return int(character-'A') + 10, true
	}
	return 0, false
}

func scanStringAt(text string, start int) (int, error) {
	index := start
	for index < len(text) {
		character := text[index]
		if character == '"' {
			return index + 1, nil
		}
		if character < 0x20 {
			return 0, Fail("InvalidJson", "", "unescaped control character in string")
		}
		if character == '\\' {
			if index+1 >= len(text) {
				return 0, Fail("InvalidJson", "", "unterminated escape in string")
			}
			escape := text[index+1]
			if escape == 'u' {
				if index+5 >= len(text) {
					return 0, Fail("InvalidJson", "", "truncated unicode escape")
				}
				a, ok1 := hexValue(text[index+2])
				b, ok2 := hexValue(text[index+3])
				c, ok3 := hexValue(text[index+4])
				d, ok4 := hexValue(text[index+5])
				if !ok1 || !ok2 || !ok3 || !ok4 {
					return 0, Fail("InvalidJson", "", "invalid unicode escape")
				}
				point := a<<12 | b<<8 | c<<4 | d
				if point >= 0xD800 && point <= 0xDBFF {
					if index+11 >= len(text) || text[index+6] != '\\' || text[index+7] != 'u' {
						return 0, Fail("InvalidJson", "", "unpaired surrogate")
					}
					e, o1 := hexValue(text[index+8])
					f, o2 := hexValue(text[index+9])
					g, o3 := hexValue(text[index+10])
					h, o4 := hexValue(text[index+11])
					if !o1 || !o2 || !o3 || !o4 {
						return 0, Fail("InvalidJson", "", "invalid unicode escape")
					}
					low := e<<12 | f<<8 | g<<4 | h
					if low < 0xDC00 || low > 0xDFFF {
						return 0, Fail("InvalidJson", "", "unpaired surrogate")
					}
					index += 12
					continue
				}
				if point >= 0xDC00 && point <= 0xDFFF {
					return 0, Fail("InvalidJson", "", "unpaired surrogate")
				}
				index += 6
				continue
			}
			switch escape {
			case '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
			default:
				return 0, Fail("InvalidJson", "", "invalid escape in string")
			}
			index += 2
			continue
		}
		index++
	}
	return 0, Fail("InvalidJson", "", "unterminated string")
}

func scanStrings(text string) error {
	for index := 0; index < len(text); {
		if text[index] == '"' {
			next, err := scanStringAt(text, index+1)
			if err != nil {
				return err
			}
			index = next
		} else {
			index++
		}
	}
	return nil
}

func canonicalNumbers(value any) any {
	switch typed := value.(type) {
	case json.Number:
		if number, err := typed.Float64(); err == nil && !math.IsNaN(number) && !math.IsInf(number, 0) {
			return number
		}
		return typed
	case []any:
		for index := range typed {
			typed[index] = canonicalNumbers(typed[index])
		}
		return typed
	case map[string]any:
		for key, item := range typed {
			typed[key] = canonicalNumbers(item)
		}
		return typed
	default:
		return value
	}
}

func AsArray(data any, path string, length int) ([]any, error) {
	arr, ok := data.([]any)
	if !ok {
		return nil, Fail("TypeMismatch", path, "expected an array")
	}
	if length >= 0 && len(arr) != length {
		return nil, Fail("UnexpectedLength", path, fmt.Sprintf("expected %d element(s) but found %d", length, len(arr)))
	}
	return arr, nil
}

func AsString(data any, path string) (string, error) {
	value, ok := data.(string)
	if !ok {
		return "", Fail("TypeMismatch", path, "expected a string")
	}
	return value, nil
}

func AsInt(data any, path string) (int, error) {
	switch value := data.(type) {
	case int:
		return value, nil
	case float64:
		if value != math.Trunc(value) {
			return 0, Fail("InvalidInt", path, "expected an exact integer")
		}
		if value < -maxSafeInt || value > maxSafeInt {
			return 0, Fail("IntOutOfRange", path, "integer outside the Wire v1 range")
		}
		return int(value), nil
	case json.Number:
		parsed, code := exactInteger(value.String())
		if code == "InvalidInt" {
			return 0, Fail("InvalidInt", path, "expected an exact integer")
		}
		if code != "" {
			return 0, Fail("IntOutOfRange", path, "integer outside the Wire v1 range")
		}
		return int(parsed), nil
	default:
		return 0, Fail("TypeMismatch", path, "expected an integer")
	}
}

func AsFloat(data any, path string) (float64, error) {
	switch value := data.(type) {
	case float64:
		if math.IsNaN(value) || math.IsInf(value, 0) {
			return 0, Fail("InvalidFloat", path, "non-finite number")
		}
		return value, nil
	case int:
		return float64(value), nil
	case json.Number:
		parsed, err := value.Float64()
		if err != nil || math.IsNaN(parsed) || math.IsInf(parsed, 0) {
			return 0, Fail("InvalidFloat", path, "non-finite number")
		}
		return parsed, nil
	default:
		return 0, Fail("TypeMismatch", path, "expected a number")
	}
}

func AsBool(data any, path string) (bool, error) {
	value, ok := data.(bool)
	if !ok {
		return false, Fail("TypeMismatch", path, "expected a boolean")
	}
	return value, nil
}

func AsNull(data any, path string) error {
	if data != nil {
		return Fail("TypeMismatch", path, "expected null")
	}
	return nil
}

func AsRecord(data any, path string) (map[string]any, error) {
	value, ok := data.(map[string]any)
	if !ok {
		return nil, Fail("TypeMismatch", path, "expected an object")
	}
	return canonicalNumbers(value).(map[string]any), nil
}

func EncodeString(value string, _ string) (any, error) { return value, nil }

func EncodeInt(value int, path string) (any, error) {
	if value < -maxSafeInt || value > maxSafeInt {
		return nil, Fail("IntOutOfRange", path, "integer outside the Wire v1 range")
	}
	return value, nil
}

func EncodeFloat(value float64, path string) (any, error) {
	if math.IsNaN(value) || math.IsInf(value, 0) {
		return nil, Fail("InvalidFloat", path, "non-finite number")
	}
	return value, nil
}

func EncodeBool(value bool, _ string) (any, error) { return value, nil }

func EncodeVoid(_ string) (any, error) { return nil, nil }

func EncodeRecord(value map[string]any, path string) (any, error) {
	if err := checkFinite(value, path); err != nil {
		return nil, err
	}
	return value, nil
}

func checkFinite(value any, path string) error {
	switch typed := value.(type) {
	case float64:
		if math.IsNaN(typed) || math.IsInf(typed, 0) {
			return Fail("NonFiniteNumber", path, "non-finite number")
		}
	case json.Number:
		number, err := typed.Float64()
		if err != nil || math.IsNaN(number) || math.IsInf(number, 0) {
			return Fail("NonFiniteNumber", path, "non-finite number")
		}
	case []any:
		for index, item := range typed {
			if err := checkFinite(item, fmt.Sprintf("%s[%d]", path, index)); err != nil {
				return err
			}
		}
	case map[string]any:
		for key, item := range typed {
			if err := checkFinite(item, path+"."+key); err != nil {
				return err
			}
		}
	}
	return nil
}

func EncodeList[T any](items []T, path string, encode func(T, string) (any, error)) (any, error) {
	out := make([]any, len(items))
	for index, item := range items {
		encoded, err := encode(item, fmt.Sprintf("%s[%d]", path, index))
		if err != nil {
			return nil, err
		}
		out[index] = encoded
	}
	return out, nil
}

func DecodeList[T any](data any, path string, decode func(any, string) (T, error)) ([]T, error) {
	arr, err := AsArray(data, path, -1)
	if err != nil {
		var zero []T
		return zero, err
	}
	out := make([]T, len(arr))
	for index, item := range arr {
		decoded, err := decode(item, fmt.Sprintf("%s[%d]", path, index))
		if err != nil {
			var zero []T
			return zero, err
		}
		out[index] = decoded
	}
	return out, nil
}

func EncodeOptional[T any](value *T, path string, encode func(T, string) (any, error)) (any, error) {
	if value == nil {
		return nil, nil
	}
	return encode(*value, path)
}

func DecodeOptional[T any](data any, path string, decode func(any, string) (T, error)) (*T, error) {
	if data == nil {
		return nil, nil
	}
	value, err := decode(data, path)
	if err != nil {
		var zero *T
		return zero, err
	}
	return &value, nil
}

func Stringify(value any) (string, error) {
	if err := checkFinite(value, ""); err != nil {
		return "", err
	}
	data, err := json.Marshal(value)
	if err != nil {
		return "", Fail("InvalidJson", "", err.Error())
	}
	return string(data), nil
}

func checkDuplicateKeys(text string) error {
	decoder := json.NewDecoder(strings.NewReader(text))
	var walk func() error
	walk = func() error {
		token, err := decoder.Token()
		if err != nil {
			return Fail("InvalidJson", "", err.Error())
		}
		delim, ok := token.(json.Delim)
		if !ok {
			return nil
		}
		switch delim {
		case '{':
			seen := map[string]bool{}
			for decoder.More() {
				keyToken, err := decoder.Token()
				if err != nil {
					return Fail("InvalidJson", "", err.Error())
				}
				key, _ := keyToken.(string)
				if seen[key] {
					return Fail("DuplicateKey", "", "duplicate object key "+key)
				}
				seen[key] = true
				if err := walk(); err != nil {
					return err
				}
			}
			_, err := decoder.Token()
			return err
		case '[':
			for decoder.More() {
				if err := walk(); err != nil {
					return err
				}
			}
			_, err := decoder.Token()
			return err
		}
		return nil
	}
	if err := walk(); err != nil {
		return err
	}
	if _, err := decoder.Token(); err != io.EOF {
		return Fail("InvalidJson", "", "trailing characters after the value")
	}
	return nil
}

func ParseText(text string) (any, error) {
	if strings.HasPrefix(text, "\xef\xbb\xbf") {
		return nil, Fail("InvalidJson", "", "a leading byte order mark is not valid Wire input")
	}
	if !utf8.ValidString(text) {
		return nil, Fail("InvalidJson", "", "input is not well-formed UTF-8")
	}
	if err := scanStrings(text); err != nil {
		return nil, err
	}
	if err := checkDuplicateKeys(text); err != nil {
		return nil, err
	}
	decoder := json.NewDecoder(strings.NewReader(text))
	decoder.UseNumber()
	var value any
	if err := decoder.Decode(&value); err != nil {
		return nil, Fail("InvalidJson", "", err.Error())
	}
	if _, err := decoder.Token(); err != io.EOF {
		return nil, Fail("InvalidJson", "", "trailing characters after the value")
	}
	return value, nil
}
|}

let rec go_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "string"
  | Schema.Primitive Schema.Int -> "int"
  | Schema.Primitive Schema.Float -> "float64"
  | Schema.Primitive Schema.Bool -> "bool"
  | Schema.Primitive Schema.Void -> "struct{}"
  | Schema.Primitive Schema.Record -> "map[string]any"
  | Schema.Reference qualified ->
    if qualified.module_name = local then qualified.message_name
    else Naming.go_package_name qualified.module_name ^ "." ^ qualified.message_name
  | Schema.List inner -> "[]" ^ go_type ~local inner
  | Schema.Optional inner -> "*" ^ go_type ~local inner

let go_pkg_of name = Naming.go_package_name name

let to_drut_name ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name ^ "ToDrut"
  else go_pkg_of qualified.module_name ^ "." ^ qualified.message_name ^ "ToDrut"

let from_drut_name ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name ^ "FromDrut"
  else go_pkg_of qualified.module_name ^ "." ^ qualified.message_name ^ "FromDrut"

let rec encode_fn_expr ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "wire.EncodeString"
  | Schema.Primitive Schema.Int -> "wire.EncodeInt"
  | Schema.Primitive Schema.Float -> "wire.EncodeFloat"
  | Schema.Primitive Schema.Bool -> "wire.EncodeBool"
  | Schema.Primitive Schema.Void ->
    "func(_ struct{}, _ string) (any, error) { return nil, nil }"
  | Schema.Primitive Schema.Record -> "wire.EncodeRecord"
  | Schema.Reference qualified ->
    Printf.sprintf
      "func(x %s, _ string) (any, error) { text, err := %s(x); if err != nil { return nil, err }; return wire.ParseText(text) }"
      (go_type ~local type_) (to_drut_name ~local qualified)
  | Schema.List inner ->
    Printf.sprintf "func(x %s, p string) (any, error) { return wire.EncodeList(x, p, %s) }"
      (go_type ~local type_) (encode_fn_expr ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "func(x %s, p string) (any, error) { return wire.EncodeOptional(x, p, %s) }"
      (go_type ~local type_) (encode_fn_expr ~local inner)

let rec decode_fn_expr ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "wire.AsString"
  | Schema.Primitive Schema.Int -> "wire.AsInt"
  | Schema.Primitive Schema.Float -> "wire.AsFloat"
  | Schema.Primitive Schema.Bool -> "wire.AsBool"
  | Schema.Primitive Schema.Void ->
    "func(x any, p string) (struct{}, error) { return struct{}{}, wire.AsNull(x, p) }"
  | Schema.Primitive Schema.Record -> "wire.AsRecord"
  | Schema.Reference qualified ->
    Printf.sprintf
      "func(x any, _ string) (%s, error) { var zero %s; text, err := wire.Stringify(x); if err != nil { return zero, err }; return %s(text) }"
      (go_type ~local type_) (go_type ~local type_)
      (from_drut_name ~local qualified)
  | Schema.List inner ->
    Printf.sprintf "func(x any, p string) (%s, error) { return wire.DecodeList(x, p, %s) }"
      (go_type ~local type_) (decode_fn_expr ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "func(x any, p string) (%s, error) { return wire.DecodeOptional(x, p, %s) }"
      (go_type ~local type_) (decode_fn_expr ~local inner)

let path_of ~module_name name = module_name ^ "." ^ name

let generate_struct ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = path_of ~module_name name in
  p "type %s struct {\n" name;
  List.iter
    (fun (field : Schema.field) ->
      p "\t%s %s\n" (Naming.go_public_name field.name)
        (go_type ~local field.type_))
    fields;
  p "}\n\n";
  p "func encode%sValue(v %s) (any, error) {\n" name name;
  List.iteri
    (fun index (field : Schema.field) ->
      p "\tf%d, err := %s(v.%s, %S)\n" index
        (encode_fn_expr ~local field.type_)
        (Naming.go_public_name field.name)
        (path ^ "." ^ field.name);
      p "\tif err != nil {\n\t\treturn nil, err\n\t}\n")
    fields;
  p "\tout := []any{";
  List.iteri (fun index _ -> if index > 0 then p ", "; p "f%d" index) fields;
  p "}\n";
  p "\treturn out, nil\n";
  p "}\n\n";
  p "func decode%sValue(data any) (%s, error) {\n" name name;
  p "\tarr, err := wire.AsArray(data, %S, %d)\n" path (List.length fields);
  p "\tif err != nil {\n\t\tvar zero %s\n\t\treturn zero, err\n\t}\n" name;
  if fields = [] then p "\t_ = arr\n";
  List.iteri
    (fun index (field : Schema.field) ->
      p "\tf%d, err := %s(arr[%d], %S)\n" index
        (decode_fn_expr ~local field.type_) index
        (path ^ "." ^ field.name);
      p "\tif err != nil {\n\t\tvar zero %s\n\t\treturn zero, err\n\t}\n" name)
    fields;
  p "\treturn %s{" name;
  List.iteri
    (fun index (field : Schema.field) ->
      if index > 0 then p ", ";
      p "%s: f%d" (Naming.go_public_name field.name) index)
    fields;
  p "}, nil\n";
  p "}\n\n";
  p "func %sToDrut(value %s) (string, error) {\n" name name;
  p "\twireValue, err := encode%sValue(value)\n" name;
  p "\tif err != nil {\n\t\treturn \"\", err\n\t}\n";
  p "\treturn wire.Stringify(wireValue)\n";
  p "}\n\n";
  p "func %sFromDrut(text string) (%s, error) {\n" name name;
  p "\twireValue, err := wire.ParseText(text)\n";
  p "\tif err != nil {\n\t\tvar zero %s\n\t\treturn zero, err\n\t}\n" name;
  p "\treturn decode%sValue(wireValue)\n" name;
  p "}\n";
  Buffer.contents buffer

let generate_variant ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = path_of ~module_name name in
  let case_name (constructor : Schema.constructor) =
    name ^ Naming.go_public_name constructor.name
  in
  p "type %s interface {\n" name;
  p "\tis%s()\n" name;
  p "}\n\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      let case = case_name constructor in
      p "type %s struct {\n" case;
      (match constructor.payload with
       | Schema.Primitive Schema.Void -> ()
       | type_ -> p "\tValue %s\n" (go_type ~local type_));
      p "}\n\n";
      p "func (%s) is%s() {}\n\n" case name)
    constructors;
  p "func encode%sValue(v %s) (any, error) {\n" name name;
  p "\tif v == nil {\n";
  p "\t\treturn nil, wire.Fail(\"InvalidVariant\", %S, \"nil variant\")\n" path;
  p "\t}\n";
  p "\tswitch typed := v.(type) {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      let case = case_name constructor in
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "\tcase %s:\n\t\treturn []any{%S, nil}, nil\n" case constructor.name
       | type_ ->
         p "\tcase %s:\n" case;
         p "\t\tf0, err := %s(typed.Value, %S)\n"
           (encode_fn_expr ~local type_) (path ^ ".value");
         p "\t\tif err != nil {\n\t\t\treturn nil, err\n\t\t}\n";
         p "\t\treturn []any{%S, f0}, nil\n" constructor.name))
    constructors;
  p "\tdefault:\n";
  p "\t\treturn nil, wire.Fail(\"InvalidVariant\", %S, \"unsupported variant implementation\")\n" path;
  p "\t}\n";
  p "}\n\n";
  p "func decode%sValue(data any) (%s, error) {\n" name name;
  p "\tarr, err := wire.AsArray(data, %S, 2)\n" path;
  p "\tif err != nil {\n\t\treturn nil, err\n\t}\n";
  p "\ttag, err := wire.AsString(arr[0], %S)\n" (path ^ "[0]");
  p "\tif err != nil {\n\t\treturn nil, err\n\t}\n";
  p "\tswitch tag {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "\tcase %S:\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "\t\tif err := wire.AsNull(arr[1], %S); err != nil {\n\t\t\treturn nil, err\n\t\t}\n"
           (path ^ "[1]");
         p "\t\treturn %s{}, nil\n" (case_name constructor)
       | type_ ->
         p "\t\tpayload, err := %s(arr[1], %S)\n"
           (decode_fn_expr ~local type_) (path ^ "[1]");
         p "\t\tif err != nil {\n\t\t\treturn nil, err\n\t\t}\n";
         p "\t\treturn %s{Value: payload}, nil\n" (case_name constructor)))
    constructors;
  p "\tdefault:\n";
  p "\t\treturn nil, wire.Fail(\"UnknownVariantTag\", %S, \"unknown tag \"+tag)\n" path;
  p "\t}\n";
  p "}\n\n";
  p "func %sToDrut(value %s) (string, error) {\n" name name;
  p "\twireValue, err := encode%sValue(value)\n" name;
  p "\tif err != nil {\n\t\treturn \"\", err\n\t}\n";
  p "\treturn wire.Stringify(wireValue)\n";
  p "}\n\n";
  p "func %sFromDrut(text string) (%s, error) {\n" name name;
  p "\twireValue, err := wire.ParseText(text)\n";
  p "\tif err != nil {\n\t\treturn nil, err\n\t}\n";
  p "\treturn decode%sValue(wireValue)\n" name;
  p "}\n";
  Buffer.contents buffer

let generate_message ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> generate_struct ~module_name message fields
  | Schema.Variant constructors -> generate_variant ~module_name message constructors

let resolve_ref ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name
  else
    go_pkg_of qualified.module_name ^ "." ^ qualified.message_name

let generate_interface ~local methods =
  let buffer = Buffer.create 256 in
  let p fmt = Printf.bprintf buffer fmt in
  p "type Handler interface {\n";
  List.iter
    (fun (method_ : Schema.method_) ->
      p "\t%s(req %s) (%s, error)\n" (Naming.go_public_name method_.name)
        (resolve_ref ~local method_.request)
        (resolve_ref ~local method_.response))
    methods;
  p "}\n";
  Buffer.contents buffer

let referenced_packages (module_ : Schema.module_) =
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

let module_code ~go_module (module_ : Schema.module_) =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let package = go_pkg_of module_.name in
  p "package %s\n\n" package;
  p "import (\n";
  if module_.messages <> [] then
    p "\t%S\n" (go_module ^ "/wire");
  List.iter
    (fun name -> p "\t%S\n" (go_module ^ "/" ^ go_pkg_of name))
    (referenced_packages module_);
  p ")\n\n";
  Naming.topo_sort module_
  |> List.iter (fun message ->
      p "%s\n" (generate_message ~module_name:module_.name message));
  (match module_.methods with
   | [] -> ()
   | methods -> p "%s\n" (generate_interface ~local:module_.name methods));
  Buffer.contents buffer

let go_mod ~go_module = Printf.sprintf "module %s\n\ngo 1.21\n" go_module

let generate ~go_module ~modules : Kernel.artifact list =
  let module_artifacts =
    List.map
      (fun (module_ : Schema.module_) ->
        let package = go_pkg_of module_.name in
        { Kernel.path = "go/" ^ package ^ "/" ^ package ^ ".go";
          contents = module_code ~go_module module_ })
      modules
  in
  [ { Kernel.path = "go/go.mod"; contents = go_mod ~go_module };
    { Kernel.path = "go/wire/wire.go"; contents = wire_source } ]
  @ module_artifacts