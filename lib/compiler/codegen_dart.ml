(* Dart generator: sealed variants, explicit Wire errors, dart:convert only. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let wire_helper =
  {|import 'dart:convert';

class WireError implements Exception {
  final String code;
  final String path;
  final String message;
  const WireError(this.code, this.path, this.message);
  @override
  String toString() => '$code at $path: $message';
}

Never wireFail(String code, String path, String message) {
  throw WireError(code, path, message);
}

/// A JSON number that keeps the exact source spelling next to its binary64
/// value. The byte API uses the spelling to reject an integer that only looks
/// integral after binary64 rounding; serialisation drops the wrapper.
class _WireNumber {
  final String lexeme;
  final num value;
  const _WireNumber(this.lexeme, this.value);
}

int? _hexValue(int code) {
  if (code >= 0x30 && code <= 0x39) return code - 0x30;
  if (code >= 0x61 && code <= 0x66) return code - 0x61 + 10;
  if (code >= 0x41 && code <= 0x46) return code - 0x41 + 10;
  return null;
}

bool _isDigit(int code) => code >= 0x30 && code <= 0x39;

/// Returns the exact integer a JSON number lexeme denotes, the string
/// 'InvalidInt' when the spelling is not a number, or 'IntOutOfRange' when it
/// is not an exact integer inside the inclusive Wire range.
dynamic _exactInteger(String lexeme) {
  final length = lexeme.length;
  if (length == 0) return 'InvalidInt';
  final negative = lexeme.codeUnitAt(0) == 0x2d;
  var index = negative ? 1 : 0;
  var integerEnd = index;
  while (integerEnd < length && _isDigit(lexeme.codeUnitAt(integerEnd))) {
    integerEnd++;
  }
  final integerDigits = lexeme.substring(index, integerEnd);
  var fractionDigits = '';
  var afterFraction = integerEnd;
  if (afterFraction < length && lexeme.codeUnitAt(afterFraction) == 0x2e) {
    var stop = afterFraction + 1;
    while (stop < length && _isDigit(lexeme.codeUnitAt(stop))) {
      stop++;
    }
    fractionDigits = lexeme.substring(afterFraction + 1, stop);
    afterFraction = stop;
  }
  var exponent = 0;
  if (afterFraction < length &&
      (lexeme.codeUnitAt(afterFraction) == 0x65 ||
          lexeme.codeUnitAt(afterFraction) == 0x45)) {
    var position = afterFraction + 1;
    var sign = 1;
    if (position < length &&
        (lexeme.codeUnitAt(position) == 0x2b ||
            lexeme.codeUnitAt(position) == 0x2d)) {
      if (lexeme.codeUnitAt(position) == 0x2d) sign = -1;
      position++;
    }
    final digitStart = position;
    var value = 0;
    while (position < length && _isDigit(lexeme.codeUnitAt(position))) {
      value = value * 10 + (lexeme.codeUnitAt(position) - 0x30);
      if (value > 1000000) return 'IntOutOfRange';
      position++;
    }
    if (position == digitStart) return 'InvalidInt';
    exponent = sign * value;
  }
  final mantissa = integerDigits + fractionDigits;
  var from = 0;
  while (from < mantissa.length && mantissa.codeUnitAt(from) == 0x30) {
    from++;
  }
  final cleaned = mantissa.substring(from);
  if (cleaned.isEmpty) return negative ? -0 : 0;
  final shift = exponent - fractionDigits.length;
  int? magnitude;
  if (shift >= 0) {
    if (cleaned.length + shift > 16) return 'IntOutOfRange';
    final padded =
        shift == 0 ? cleaned : cleaned + '0'.padRight(shift, '0');
    magnitude = int.tryParse(padded);
  } else {
    final drop = -shift;
    if (drop >= cleaned.length) {
      magnitude = cleaned.replaceAll('0', '').isEmpty ? 0 : null;
    } else {
      final kept = cleaned.substring(0, cleaned.length - drop);
      final tail = cleaned.substring(cleaned.length - drop);
      magnitude = tail.replaceAll('0', '').isEmpty ? int.tryParse(kept) : null;
    }
  }
  if (magnitude == null) return 'IntOutOfRange';
  final signed = negative ? -magnitude : magnitude;
  if (signed < -9007199254740991 || signed > 9007199254740991) {
    return 'IntOutOfRange';
  }
  return signed;
}

class Wire {
  static const int maxSafeInt = 9007199254740991;

  static List<dynamic> asArray(dynamic value, String path, [int? length]) {
    if (value is! List) {
      wireFail('TypeMismatch', path, 'expected an array');
    }
    final List<dynamic> arr = value;
    if (length != null && arr.length != length) {
      wireFail('UnexpectedLength', path,
          'expected $length element(s) but found ${arr.length}');
    }
    return arr;
  }

  static String asString(dynamic value, String path) {
    if (value is! String) {
      wireFail('TypeMismatch', path, 'expected a string');
    }
    return value;
  }

  static int asInt(dynamic value, String path) {
    if (value is _WireNumber) {
      final exact = _exactInteger(value.lexeme);
      if (exact == 'InvalidInt') {
        wireFail('InvalidInt', path, 'expected an exact integer');
      }
      if (exact == 'IntOutOfRange') {
        wireFail('IntOutOfRange', path, 'integer outside the Wire v1 range');
      }
      return exact as int;
    }
    if (value is int) {
      if (value < -maxSafeInt || value > maxSafeInt) {
        wireFail('IntOutOfRange', path, 'integer outside the Wire v1 range');
      }
      return value;
    }
    if (value is double && value == value.truncateToDouble()) {
      if (value < -maxSafeInt || value > maxSafeInt) {
        wireFail('IntOutOfRange', path, 'integer outside the Wire v1 range');
      }
      return value.toInt();
    }
    wireFail('InvalidInt', path, 'expected an exact integer');
  }

  static double asFloat(dynamic value, String path) {
    final number = value is _WireNumber ? value.value : value;
    if (number is double) {
      if (number.isNaN || number.isInfinite) {
        wireFail('InvalidFloat', path, 'non-finite number');
      }
      return number;
    }
    if (number is int) {
      return number.toDouble();
    }
    wireFail('TypeMismatch', path, 'expected a number');
  }

  static bool asBool(dynamic value, String path) {
    if (value is! bool) {
      wireFail('TypeMismatch', path, 'expected a boolean');
    }
    return value;
  }

  static dynamic asNull(dynamic value, String path) {
    if (value != null) {
      wireFail('TypeMismatch', path, 'expected null');
    }
    return null;
  }

  static Map<String, dynamic> asRecord(dynamic value, String path) {
    if (value is! Map) {
      wireFail('TypeMismatch', path, 'expected an object');
    }
    return canonicalNumbers(value) as Map<String, dynamic>;
  }

  static num _recordNumber(num value) {
    final number = value.toDouble();
    if (number.isFinite &&
        number == number.truncateToDouble() &&
        number.abs() <= 9007199254740992.0) {
      return number.toInt();
    }
    return number;
  }

  static dynamic canonicalNumbers(dynamic value) {
    if (value is _WireNumber) {
      return _recordNumber(value.value);
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        value[i] = canonicalNumbers(value[i]);
      }
      return value;
    }
    if (value is Map) {
      for (final key in value.keys.toList()) {
        value[key] = canonicalNumbers(value[key]);
      }
      return value;
    }
    return value;
  }

  static String encodeString(String value, String path) => value;

  static int encodeInt(int value, String path) {
    if (value < -maxSafeInt || value > maxSafeInt) {
      wireFail('IntOutOfRange', path, 'integer outside the Wire v1 range');
    }
    return value;
  }

  static double encodeFloat(double value, String path) {
    if (value.isNaN || value.isInfinite) {
      wireFail('InvalidFloat', path, 'non-finite number');
    }
    return value;
  }

  static bool encodeBool(bool value, String path) => value;

  static dynamic encodeNull(Null value, String path) => null;

  static Map<String, dynamic> encodeRecord(
      Map<String, dynamic> value, String path) {
    checkFinite(value, path);
    return value;
  }

  static void checkFinite(dynamic value, String path) {
    if (value is _WireNumber) {
      if (value.value is double &&
          ((value.value as double).isNaN || (value.value as double).isInfinite)) {
        wireFail('NonFiniteNumber', path, 'non-finite number');
      }
      return;
    }
    if (value is double) {
      if (value.isNaN || value.isInfinite) {
        wireFail('NonFiniteNumber', path, 'non-finite number');
      }
      return;
    }
    if (value is List) {
      for (var i = 0; i < value.length; i++) {
        checkFinite(value[i], '$path[$i]');
      }
      return;
    }
    if (value is Map) {
      value.forEach((key, item) => checkFinite(item, '$path.$key'));
    }
  }

  static List<dynamic> encodeList<T>(
      List<T> items, String path, dynamic Function(T, String) encode) {
    final out = <dynamic>[];
    for (var i = 0; i < items.length; i++) {
      out.add(encode(items[i], '$path[$i]'));
    }
    return out;
  }

  static List<T> decodeList<T>(
      dynamic data, String path, T Function(dynamic, String) decode) {
    final arr = asArray(data, path);
    return arr
        .asMap()
        .entries
        .map((entry) => decode(entry.value, '$path[${entry.key}]'))
        .toList();
  }

  static dynamic encodeOptional<T>(
      T? value, String path, dynamic Function(T, String) encode) {
    if (value == null) {
      return null;
    }
    return encode(value, path);
  }

  static T? decodeOptional<T>(
      dynamic data, String path, T Function(dynamic, String) decode) {
    if (data == null) {
      return null;
    }
    return decode(data, path);
  }

  static String stringify(dynamic value) {
    checkFinite(value, '');
    return jsonEncode(canonicalNumbers(value));
  }

  static void _scanDuplicateKeys(String text) {
    var position = 0;
    bool isWs(int code) =>
        code == 0x20 || code == 0x09 || code == 0x0a || code == 0x0d;
    void skipWs() {
      while (position < text.length &&
          isWs(text.codeUnitAt(position))) {
        position++;
      }
    }

    String parseString() {
      position++;
      final buffer = StringBuffer();
      while (position < text.length) {
        final code = text.codeUnitAt(position);
        if (code == 0x22) {
          position++;
          return buffer.toString();
        }
        if (code == 0x5c) {
          position++;
          if (position < text.length) {
            buffer.writeCharCode(text.codeUnitAt(position));
            position++;
          }
        } else {
          buffer.writeCharCode(code);
          position++;
        }
      }
      wireFail('InvalidJson', 'wire', 'unterminated string');
    }

    late void Function() parseValue;
    late void Function() parseObject;
    late void Function() parseArray;

    parseValue = () {
      skipWs();
      final code = position < text.length ? text.codeUnitAt(position) : -1;
      if (code == 0x7b) {
        position++;
        parseObject();
      } else if (code == 0x5b) {
        position++;
        parseArray();
      } else if (code == 0x22) {
        parseString();
      } else {
        while (position < text.length &&
            !',]} \t\n\r'.contains(text[position])) {
          position++;
        }
      }
    };

    parseObject = () {
      skipWs();
      if (position < text.length && text.codeUnitAt(position) == 0x7d) {
        position++;
        return;
      }
      final keys = <String>{};
      for (;;) {
        skipWs();
        final key = parseString();
        if (!keys.add(key)) {
          wireFail('DuplicateKey', 'wire', 'duplicate object key $key');
        }
        skipWs();
        if (position >= text.length || text.codeUnitAt(position) != 0x3a) {
          wireFail('InvalidJson', 'wire', 'expected a colon');
        }
        position++;
        parseValue();
        skipWs();
        if (position < text.length && text.codeUnitAt(position) == 0x2c) {
          position++;
          continue;
        }
        if (position < text.length && text.codeUnitAt(position) == 0x7d) {
          position++;
          return;
        }
        wireFail('InvalidJson', 'wire', 'expected a comma or object end');
      }
    };

    parseArray = () {
      skipWs();
      if (position < text.length && text.codeUnitAt(position) == 0x5d) {
        position++;
        return;
      }
      for (;;) {
        parseValue();
        skipWs();
        if (position < text.length && text.codeUnitAt(position) == 0x2c) {
          position++;
          continue;
        }
        if (position < text.length && text.codeUnitAt(position) == 0x5d) {
          position++;
          return;
        }
        wireFail('InvalidJson', 'wire', 'expected a comma or array end');
      }
    };

    parseValue();
    skipWs();
    if (position != text.length) {
      wireFail('InvalidJson', 'wire', 'trailing characters');
    }
  }

  static List<String> _scanValidate(String text) {
    final numbers = <String>[];
    final length = text.length;
    bool isNumberChar(int code) =>
        _isDigit(code) ||
        code == 0x2d ||
        code == 0x2b ||
        code == 0x2e ||
        code == 0x65 ||
        code == 0x45;
    int scanString(int start) {
      var index = start;
      while (index < length) {
        final code = text.codeUnitAt(index);
        if (code == 0x22) return index + 1;
        if (code < 0x20) {
          wireFail('InvalidJson', 'wire', 'unescaped control character in string');
        }
        if (code == 0x5c) {
          if (index + 1 >= length) {
            wireFail('InvalidJson', 'wire', 'unterminated escape in string');
          }
          final escape = text.codeUnitAt(index + 1);
          if (escape == 0x75) {
            if (index + 5 >= length) {
              wireFail('InvalidJson', 'wire', 'truncated unicode escape');
            }
            final a = _hexValue(text.codeUnitAt(index + 2));
            final b = _hexValue(text.codeUnitAt(index + 3));
            final c = _hexValue(text.codeUnitAt(index + 4));
            final d = _hexValue(text.codeUnitAt(index + 5));
            if (a == null || b == null || c == null || d == null) {
              wireFail('InvalidJson', 'wire', 'invalid unicode escape');
            }
            final point = (a << 12) | (b << 8) | (c << 4) | d;
            if (point >= 0xd800 && point <= 0xdbff) {
              if (index + 11 >= length ||
                  text.codeUnitAt(index + 6) != 0x5c ||
                  text.codeUnitAt(index + 7) != 0x75) {
                wireFail('InvalidJson', 'wire', 'unpaired surrogate');
              }
              final e = _hexValue(text.codeUnitAt(index + 8));
              final f = _hexValue(text.codeUnitAt(index + 9));
              final g = _hexValue(text.codeUnitAt(index + 10));
              final h = _hexValue(text.codeUnitAt(index + 11));
              if (e == null || f == null || g == null || h == null) {
                wireFail('InvalidJson', 'wire', 'invalid unicode escape');
              }
              final low = (e << 12) | (f << 8) | (g << 4) | h;
              if (low < 0xdc00 || low > 0xdfff) {
                wireFail('InvalidJson', 'wire', 'unpaired surrogate');
              }
              index += 12;
              continue;
            }
            if (point >= 0xdc00 && point <= 0xdfff) {
              wireFail('InvalidJson', 'wire', 'unpaired surrogate');
            }
            index += 6;
            continue;
          }
          if (!const [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74]
              .contains(escape)) {
            wireFail('InvalidJson', 'wire', 'invalid escape in string');
          }
          index += 2;
          continue;
        }
        if (code >= 0xd800 && code <= 0xdbff) {
          if (index + 1 >= length ||
              text.codeUnitAt(index + 1) < 0xdc00 ||
              text.codeUnitAt(index + 1) > 0xdfff) {
            wireFail('InvalidJson', 'wire', 'unpaired surrogate');
          }
          index += 2;
          continue;
        }
        if (code >= 0xdc00 && code <= 0xdfff) {
          wireFail('InvalidJson', 'wire', 'unpaired surrogate');
        }
        index++;
      }
      wireFail('InvalidJson', 'wire', 'unterminated string');
    }

    var index = 0;
    while (index < length) {
      final code = text.codeUnitAt(index);
      if (code == 0x22) {
        index = scanString(index + 1);
      } else if (code == 0x2d || _isDigit(code)) {
        var stop = index;
        while (stop < length && isNumberChar(text.codeUnitAt(stop))) {
          stop++;
        }
        numbers.add(text.substring(index, stop));
        index = stop;
      } else {
        index++;
      }
    }
    return numbers;
  }

  static dynamic parseText(String text) {
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) {
      wireFail('InvalidJson', 'wire',
          'a leading byte order mark is not valid Wire input');
    }
    final lexemes = _scanValidate(text);
    dynamic value;
    try {
      value = jsonDecode(text);
    } on FormatException catch (error) {
      wireFail('InvalidJson', 'wire', 'invalid JSON: ${error.message}');
    }
    _scanDuplicateKeys(text);
    var cursor = 0;
    dynamic wrap(dynamic item) {
      if (item is num) {
        return _WireNumber(lexemes[cursor++], item);
      }
      if (item is List) {
        for (var i = 0; i < item.length; i++) {
          item[i] = wrap(item[i]);
        }
        return item;
      }
      if (item is Map) {
        for (final key in item.keys.toList()) {
          item[key] = wrap(item[key]);
        }
        return item;
      }
      return item;
    }

    value = wrap(value);
    if (cursor != lexemes.length) {
      wireFail('InvalidJson', 'wire', 'numeric literal count does not match');
    }
    checkFinite(value, '');
    return value;
  }

  static dynamic parseBytes(List<int> bytes) {
    if (bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf) {
      wireFail('InvalidJson', 'wire',
          'a leading byte order mark is not valid Wire input');
    }
    String text;
    try {
      text = utf8.decode(bytes);
    } on FormatException {
      wireFail('InvalidJson', 'wire', 'input is not well-formed UTF-8');
    }
    return parseText(text);
  }
}
|}

let dart_prefix name = Naming.snake_case name

let reference_type ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name
  else dart_prefix qualified.module_name ^ "." ^ qualified.message_name

let rec dart_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "String"
  | Schema.Primitive Schema.Int -> "int"
  | Schema.Primitive Schema.Float -> "double"
  | Schema.Primitive Schema.Bool -> "bool"
  | Schema.Primitive Schema.Void -> "Null"
  | Schema.Primitive Schema.Record -> "Map<String, dynamic>"
  | Schema.Reference qualified -> reference_type ~local qualified
  | Schema.List inner -> "List<" ^ dart_type ~local inner ^ ">"
  | Schema.Optional inner -> dart_type ~local inner ^ "?"

let rec encode_fn ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    "(x, p) => Wire.encodeString(x, p)"
  | Schema.Primitive Schema.Int -> "(x, p) => Wire.encodeInt(x, p)"
  | Schema.Primitive Schema.Float -> "(x, p) => Wire.encodeFloat(x, p)"
  | Schema.Primitive Schema.Bool -> "(x, p) => Wire.encodeBool(x, p)"
  | Schema.Primitive Schema.Void -> "(x, p) => Wire.encodeNull(x, p)"
  | Schema.Primitive Schema.Record -> "(x, p) => Wire.encodeRecord(x, p)"
  | Schema.Reference _ -> "(x, p) => Wire.parseText(x.toDrut())"
  | Schema.List inner ->
    Printf.sprintf "(x, p) => Wire.encodeList(x, p, %s)" (encode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "(x, p) => Wire.encodeOptional(x, p, %s)"
      (encode_fn ~local inner)

let rec decode_fn ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    "(x, p) => Wire.asString(x, p)"
  | Schema.Primitive Schema.Int -> "(x, p) => Wire.asInt(x, p)"
  | Schema.Primitive Schema.Float -> "(x, p) => Wire.asFloat(x, p)"
  | Schema.Primitive Schema.Bool -> "(x, p) => Wire.asBool(x, p)"
  | Schema.Primitive Schema.Void -> "(x, p) => Wire.asNull(x, p)"
  | Schema.Primitive Schema.Record -> "(x, p) => Wire.asRecord(x, p)"
  | Schema.Reference qualified ->
    Printf.sprintf "(x, p) => %s.fromDrut(Wire.stringify(x))"
      (reference_type ~local qualified)
  | Schema.List inner ->
    Printf.sprintf "(x, p) => Wire.decodeList(x, p, %s)" (decode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "(x, p) => Wire.decodeOptional(x, p, %s)"
      (decode_fn ~local inner)

let encode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "Wire.encodeString(%s, %S)" expr path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "Wire.encodeInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "Wire.encodeFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "Wire.encodeBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "Wire.encodeNull(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "Wire.encodeRecord(%s, %S)" expr path
  | Schema.Reference _ -> Printf.sprintf "Wire.parseText(%s.toDrut())" expr
  | Schema.List inner ->
    Printf.sprintf "Wire.encodeList(%s, %S, %s)" expr path (encode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "Wire.encodeOptional(%s, %S, %s)" expr path
      (encode_fn ~local inner)

let decode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "Wire.asString(%s, %S)" expr path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "Wire.asInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "Wire.asFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "Wire.asBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "Wire.asNull(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "Wire.asRecord(%s, %S)" expr path
  | Schema.Reference qualified ->
    Printf.sprintf "%s.fromDrut(Wire.stringify(%s))"
      (reference_type ~local qualified) expr
  | Schema.List inner ->
    Printf.sprintf "Wire.decodeList(%s, %S, %s)" expr path (decode_fn ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "Wire.decodeOptional(%s, %S, %s)" expr path
      (decode_fn ~local inner)

let dart_field name = Naming.dart_camel_case name

let struct_code ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = module_name ^ "." ^ name in
  p "class %s {\n" name;
  List.iter
    (fun (field : Schema.field) ->
      p "  final %s %s;\n" (dart_type ~local field.type_) (dart_field field.name))
    fields;
  p "\n";
  (match fields with
   | [] -> p "  const %s();\n\n" name
   | _ ->
     p "  const %s({\n" name;
     List.iter
       (fun (field : Schema.field) ->
         match field.type_ with
         | Schema.Optional _ -> p "    this.%s,\n" (dart_field field.name)
         | _ -> p "    required this.%s,\n" (dart_field field.name))
       fields;
     p "  });\n\n");
  p "  factory %s._fromValue(dynamic data) {\n" name;
  if fields = [] then
    p "    Wire.asArray(data, %S, 0);\n    return const %s();\n" path name
  else begin
    p "    final arr = Wire.asArray(data, %S, %d);\n" path (List.length fields);
    p "    return %s(\n" name;
    List.iteri
      (fun index (field : Schema.field) ->
        p "      %s: %s,\n" (dart_field field.name)
          (decode_expr ~local (Printf.sprintf "arr[%d]" index)
             (path ^ "." ^ field.name) field.type_))
      fields;
    p "    );\n"
  end;
  p "  }\n\n";
  p "  List<dynamic> _toValue() {\n";
  p "    return [\n";
  List.iter
    (fun (field : Schema.field) ->
      p "      %s,\n"
        (encode_expr ~local (dart_field field.name)
           (path ^ "." ^ field.name) field.type_))
    fields;
  p "    ];\n";
  p "  }\n\n";
  p "  String toDrut() => Wire.stringify(_toValue());\n";
  p "  static %s fromDrut(String text) => %s._fromValue(Wire.parseText(text));\n"
    name name;
  p "}\n";
  Buffer.contents buffer

let variant_code ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = module_name ^ "." ^ name in
  let subclass (constructor : Schema.constructor) =
    name ^ Naming.dart_camel_case constructor.name
  in
  p "sealed class %s {\n" name;
  p "  const %s();\n\n" name;
  p "  factory %s._fromValue(dynamic data) {\n" name;
  p "    final arr = Wire.asArray(data, %S, 2);\n" path;
  p "    final tag = Wire.asString(arr[0], %S);\n" (path ^ "[0]");
  p "    switch (tag) {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "      case %S:\n" constructor.name;
        p "        Wire.asNull(arr[1], %S);\n" (path ^ "[1]");
        p "        return const %s();\n" (subclass constructor)
      | type_ ->
        p "      case %S:\n" constructor.name;
        p "        return %s(%s);\n" (subclass constructor)
          (decode_expr ~local "arr[1]" (path ^ "[1]") type_))
    constructors;
  p "      default:\n";
  p "        wireFail('UnknownVariantTag', %S, 'unknown tag $tag');\n" path;
  p "    }\n";
  p "  }\n\n";
  p "  List<dynamic> _toValue();\n";
  p "  String toDrut() => Wire.stringify(_toValue());\n";
  p "  static %s fromDrut(String text) => %s._fromValue(Wire.parseText(text));\n"
    name name;
  p "}\n\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "class %s extends %s {\n" (subclass constructor) name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void -> p "  const %s();\n\n" (subclass constructor)
       | type_ ->
         p "  final %s value;\n" (dart_type ~local type_);
         p "  const %s(this.value);\n\n" (subclass constructor));
      p "  @override\n";
      p "  List<dynamic> _toValue() {\n";
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "    return [%S, null];\n" constructor.name
       | type_ ->
         p "    return [%S, %s];\n" constructor.name
           (encode_expr ~local "value" (path ^ ".value") type_));
      p "  }\n";
      p "}\n\n")
    constructors;
  Buffer.contents buffer

let message_code ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_code ~module_name message fields
  | Schema.Variant constructors -> variant_code ~module_name message constructors

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
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  p "import 'wire.dart';\n";
  List.iter
    (fun name ->
      p "import '%s' as %s;\n" (Naming.dart_file name)
        (dart_prefix name))
    (referenced_modules module_);
  p "\n";
  Naming.topo_sort module_
  |> List.iter (fun message ->
      p "%s\n" (message_code ~module_name:module_.name message));
  Buffer.contents buffer

let generate ~modules : Kernel.artifact list =
  let module_artifacts =
    List.map
      (fun (module_ : Schema.module_) ->
        { Kernel.path = "dart/" ^ Naming.dart_file module_.name;
          contents = module_code module_ })
      modules
  in
  [ { Kernel.path = "dart/pubspec.yaml";
      contents =
        "name: generated_contracts\nenvironment:\n  sdk: \">=3.0.0 <4.0.0\"\n" };
    { Kernel.path = "dart/wire.dart"; contents = wire_helper } ]
  @ module_artifacts