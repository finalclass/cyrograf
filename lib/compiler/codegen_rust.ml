(* Rust generator for edition 2024, rust-version 1.85.

   Each source module becomes a public module of the [generated_contracts]
   crate. Structures are structs with public typed fields; a variant is an enum
   with typed payload cases and unit cases for Void. The [wire] runtime is a
   private module; only [CyrografError] is re-exported. A message exposes
   exactly the two public conversions [to_drut]/[from_drut]; the internal value
   helpers are [pub(crate)]. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let wire_source =
  {j|#![allow(dead_code)]

use crate::CyrografError;

pub(crate) enum Val {
    Null,
    Bool(bool),
    Num(String),
    Str(String),
    List(Vec<Val>),
    Obj(Vec<(String, Val)>),
}

const MAX_SAFE_INT: i64 = 9007199254740991;

fn fail(code: &str, path: &str, message: &str) -> CyrografError {
    CyrografError::new(code, path, message)
}

pub(crate) fn parse_text(text: &str) -> Result<Val, CyrografError> {
    if text.starts_with('\u{feff}') {
        return Err(fail("InvalidJson", "", "a leading byte order mark is not valid Wire input"));
    }
    let mut parser = Parser { chars: text.chars().collect(), index: 0 };
    let value = parser.parse_value()?;
    parser.skip_whitespace();
    if parser.index != parser.chars.len() {
        return Err(fail("InvalidJson", "", "trailing characters after the value"));
    }
    Ok(value)
}

pub(crate) fn stringify(value: &Val) -> String {
    let mut output = String::new();
    write_value(value, &mut output);
    output
}

fn write_value(value: &Val, output: &mut String) {
    match value {
        Val::Null => output.push_str("null"),
        Val::Bool(flag) => output.push_str(if *flag { "true" } else { "false" }),
        Val::Num(lexeme) => output.push_str(lexeme),
        Val::Str(text) => write_string(text, output),
        Val::List(items) => {
            output.push('[');
            for (index, item) in items.iter().enumerate() {
                if index > 0 {
                    output.push(',');
                }
                write_value(item, output);
            }
            output.push(']');
        }
        Val::Obj(entries) => {
            output.push('{');
            for (index, (key, item)) in entries.iter().enumerate() {
                if index > 0 {
                    output.push(',');
                }
                write_string(key, output);
                output.push(':');
                write_value(item, output);
            }
            output.push('}');
        }
    }
}

fn write_string(value: &str, output: &mut String) {
    output.push('"');
    for character in value.chars() {
        match character {
            '"' => output.push_str("\\\""),
            '\\' => output.push_str("\\\\"),
            '\u{8}' => output.push_str("\\b"),
            '\u{c}' => output.push_str("\\f"),
            '\n' => output.push_str("\\n"),
            '\r' => output.push_str("\\r"),
            '\t' => output.push_str("\\t"),
            character if (character as u32) < 0x20 => {
                output.push_str(&format!("\\u{:04x}", character as u32));
            }
            character => output.push(character),
        }
    }
    output.push('"');
}

struct Parser {
    chars: Vec<char>,
    index: usize,
}

impl Parser {
    fn skip_whitespace(&mut self) {
        while self.index < self.chars.len() {
            match self.chars[self.index] {
                ' ' | '\t' | '\n' | '\r' => self.index += 1,
                _ => break,
            }
        }
    }

    fn parse_value(&mut self) -> Result<Val, CyrografError> {
        self.skip_whitespace();
        if self.index >= self.chars.len() {
            return Err(fail("InvalidJson", "", "unexpected end of input"));
        }
        let character = self.chars[self.index];
        match character {
            '{' => self.parse_object(),
            '[' => self.parse_array(),
            '"' => Ok(Val::Str(self.parse_string()?)),
            't' => {
                self.expect("true")?;
                Ok(Val::Bool(true))
            }
            'f' => {
                self.expect("false")?;
                Ok(Val::Bool(false))
            }
            'n' => {
                self.expect("null")?;
                Ok(Val::Null)
            }
            '-' | '0'..='9' => self.parse_number(),
            _ => Err(fail("InvalidJson", "", "unexpected character")),
        }
    }

    fn expect(&mut self, word: &str) -> Result<(), CyrografError> {
        for expected in word.chars() {
            if self.index >= self.chars.len() || self.chars[self.index] != expected {
                return Err(fail("InvalidJson", "", "invalid literal"));
            }
            self.index += 1;
        }
        Ok(())
    }

    fn parse_object(&mut self) -> Result<Val, CyrografError> {
        self.index += 1;
        let mut entries = Vec::new();
        let mut keys = std::collections::HashSet::new();
        self.skip_whitespace();
        if self.index < self.chars.len() && self.chars[self.index] == '}' {
            self.index += 1;
            return Ok(Val::Obj(entries));
        }
        loop {
            self.skip_whitespace();
            if self.index >= self.chars.len() || self.chars[self.index] != '"' {
                return Err(fail("InvalidJson", "", "expected an object key"));
            }
            let key = self.parse_string()?;
            if !keys.insert(key.clone()) {
                return Err(fail("DuplicateKey", "", "duplicate object key"));
            }
            self.skip_whitespace();
            if self.index >= self.chars.len() || self.chars[self.index] != ':' {
                return Err(fail("InvalidJson", "", "expected a colon"));
            }
            self.index += 1;
            let value = self.parse_value()?;
            entries.push((key, value));
            self.skip_whitespace();
            if self.index >= self.chars.len() {
                return Err(fail("InvalidJson", "", "unterminated object"));
            }
            let character = self.chars[self.index];
            if character == ',' {
                self.index += 1;
                continue;
            }
            if character == '}' {
                self.index += 1;
                return Ok(Val::Obj(entries));
            }
            return Err(fail("InvalidJson", "", "expected a comma or a closing brace"));
        }
    }

    fn parse_array(&mut self) -> Result<Val, CyrografError> {
        self.index += 1;
        let mut items = Vec::new();
        self.skip_whitespace();
        if self.index < self.chars.len() && self.chars[self.index] == ']' {
            self.index += 1;
            return Ok(Val::List(items));
        }
        loop {
            items.push(self.parse_value()?);
            self.skip_whitespace();
            if self.index >= self.chars.len() {
                return Err(fail("InvalidJson", "", "unterminated array"));
            }
            let character = self.chars[self.index];
            if character == ',' {
                self.index += 1;
                continue;
            }
            if character == ']' {
                self.index += 1;
                return Ok(Val::List(items));
            }
            return Err(fail("InvalidJson", "", "expected a comma or a closing bracket"));
        }
    }

    fn parse_string(&mut self) -> Result<String, CyrografError> {
        self.index += 1;
        let mut output = String::new();
        loop {
            if self.index >= self.chars.len() {
                return Err(fail("InvalidJson", "", "unterminated string"));
            }
            let character = self.chars[self.index];
            self.index += 1;
            if character == '"' {
                return Ok(output);
            }
            if (character as u32) < 0x20 {
                return Err(fail("InvalidJson", "", "unescaped control character in string"));
            }
            if character == '\\' {
                if self.index >= self.chars.len() {
                    return Err(fail("InvalidJson", "", "unterminated escape in string"));
                }
                let escape = self.chars[self.index];
                self.index += 1;
                match escape {
                    '"' => output.push('"'),
                    '\\' => output.push('\\'),
                    '/' => output.push('/'),
                    'b' => output.push('\u{8}'),
                    'f' => output.push('\u{c}'),
                    'n' => output.push('\n'),
                    'r' => output.push('\r'),
                    't' => output.push('\t'),
                    'u' => {
                        let code = self.read_hex4()?;
                        if (0xd800..=0xdbff).contains(&code) {
                            if self.index + 1 >= self.chars.len()
                                || self.chars[self.index] != '\\'
                                || self.chars[self.index + 1] != 'u'
                            {
                                return Err(fail("InvalidJson", "", "unpaired surrogate"));
                            }
                            self.index += 2;
                            let low = self.read_hex4()?;
                            if !(0xdc00..=0xdfff).contains(&low) {
                                return Err(fail("InvalidJson", "", "unpaired surrogate"));
                            }
                            let combined = 0x10000 + ((code - 0xd800) << 10) + (low - 0xdc00);
                            match char::from_u32(combined) {
                                Some(value) => output.push(value),
                                None => return Err(fail("InvalidJson", "", "unpaired surrogate")),
                            }
                        } else if (0xdc00..=0xdfff).contains(&code) {
                            return Err(fail("InvalidJson", "", "unpaired surrogate"));
                        } else {
                            match char::from_u32(code) {
                                Some(value) => output.push(value),
                                None => return Err(fail("InvalidJson", "", "invalid unicode escape")),
                            }
                        }
                    }
                    _ => return Err(fail("InvalidJson", "", "invalid escape in string")),
                }
                continue;
            }
            output.push(character);
        }
    }

    fn read_hex4(&mut self) -> Result<u32, CyrografError> {
        if self.index + 4 > self.chars.len() {
            return Err(fail("InvalidJson", "", "truncated unicode escape"));
        }
        let mut value = 0u32;
        for _ in 0..4 {
            let digit = match self.chars[self.index] {
                '0'..='9' => (self.chars[self.index] as u32) - ('0' as u32),
                'a'..='f' => (self.chars[self.index] as u32) - ('a' as u32) + 10,
                'A'..='F' => (self.chars[self.index] as u32) - ('A' as u32) + 10,
                _ => return Err(fail("InvalidJson", "", "invalid unicode escape")),
            };
            value = (value << 4) | digit;
            self.index += 1;
        }
        Ok(value)
    }

    fn parse_number(&mut self) -> Result<Val, CyrografError> {
        let start = self.index;
        if self.chars[self.index] == '-' {
            self.index += 1;
        }
        if self.index >= self.chars.len() || !self.chars[self.index].is_ascii_digit() {
            return Err(fail("InvalidJson", "", "invalid number"));
        }
        if self.chars[self.index] == '0' {
            self.index += 1;
        } else {
            while self.index < self.chars.len() && self.chars[self.index].is_ascii_digit() {
                self.index += 1;
            }
        }
        if self.index < self.chars.len() && self.chars[self.index] == '.' {
            self.index += 1;
            if self.index >= self.chars.len() || !self.chars[self.index].is_ascii_digit() {
                return Err(fail("InvalidJson", "", "invalid number"));
            }
            while self.index < self.chars.len() && self.chars[self.index].is_ascii_digit() {
                self.index += 1;
            }
        }
        if self.index < self.chars.len()
            && (self.chars[self.index] == 'e' || self.chars[self.index] == 'E')
        {
            self.index += 1;
            if self.index < self.chars.len()
                && (self.chars[self.index] == '+' || self.chars[self.index] == '-')
            {
                self.index += 1;
            }
            if self.index >= self.chars.len() || !self.chars[self.index].is_ascii_digit() {
                return Err(fail("InvalidJson", "", "invalid number"));
            }
            while self.index < self.chars.len() && self.chars[self.index].is_ascii_digit() {
                self.index += 1;
            }
        }
        Ok(Val::Num(self.chars[start..self.index].iter().collect()))
    }
}

pub(crate) fn as_array<'a>(
    value: &'a Val,
    path: &str,
    length: Option<usize>,
) -> Result<&'a [Val], CyrografError> {
    match value {
        Val::List(items) => {
            if let Some(expected) = length {
                if items.len() != expected {
                    return Err(fail("UnexpectedLength", path, "array length mismatch"));
                }
            }
            Ok(items)
        }
        _ => Err(fail("TypeMismatch", path, "expected an array")),
    }
}

pub(crate) fn as_string<'a>(value: &'a Val, path: &str) -> Result<&'a str, CyrografError> {
    match value {
        Val::Str(text) => Ok(text),
        _ => Err(fail("TypeMismatch", path, "expected a string")),
    }
}

pub(crate) fn as_int(value: &Val, path: &str) -> Result<i64, CyrografError> {
    match value {
        Val::Num(lexeme) => exact_integer(lexeme, path),
        _ => Err(fail("TypeMismatch", path, "expected an integer")),
    }
}

pub(crate) fn as_float(value: &Val, path: &str) -> Result<f64, CyrografError> {
    match value {
        Val::Num(lexeme) => {
            let parsed: f64 = lexeme
                .parse()
                .map_err(|_| fail("InvalidFloat", path, "invalid number"))?;
            if !parsed.is_finite() {
                return Err(fail("InvalidFloat", path, "non-finite number"));
            }
            Ok(parsed)
        }
        _ => Err(fail("TypeMismatch", path, "expected a number")),
    }
}

pub(crate) fn as_bool(value: &Val, path: &str) -> Result<bool, CyrografError> {
    match value {
        Val::Bool(flag) => Ok(*flag),
        _ => Err(fail("TypeMismatch", path, "expected a boolean")),
    }
}

pub(crate) fn decode_void(value: &Val, path: &str) -> Result<(), CyrografError> {
    match value {
        Val::Null => Ok(()),
        _ => Err(fail("TypeMismatch", path, "expected null")),
    }
}

pub(crate) fn as_record(
    value: &Val,
    path: &str,
) -> Result<serde_json::Map<String, serde_json::Value>, CyrografError> {
    match value {
        Val::Obj(entries) => {
            let mut map = serde_json::Map::new();
            for (key, item) in entries {
                map.insert(key.clone(), json_from_val(item, path)?);
            }
            Ok(map)
        }
        _ => Err(fail("TypeMismatch", path, "expected an object")),
    }
}

pub(crate) fn encode_string(value: &str, _path: &str) -> Result<Val, CyrografError> {
    Ok(Val::Str(value.to_string()))
}

pub(crate) fn encode_int(value: &i64, path: &str) -> Result<Val, CyrografError> {
    if *value < -MAX_SAFE_INT || *value > MAX_SAFE_INT {
        return Err(fail("IntOutOfRange", path, "integer outside the Wire v1 range"));
    }
    Ok(Val::Num(value.to_string()))
}

pub(crate) fn encode_float(value: &f64, path: &str) -> Result<Val, CyrografError> {
    if !value.is_finite() {
        return Err(fail("InvalidFloat", path, "non-finite number"));
    }
    Ok(Val::Num(format_float(*value)))
}

pub(crate) fn encode_record(
    value: &serde_json::Map<String, serde_json::Value>,
    path: &str,
) -> Result<Val, CyrografError> {
    let mut entries = Vec::with_capacity(value.len());
    for (key, item) in value {
        entries.push((key.clone(), val_from_json(item, path)?));
    }
    Ok(Val::Obj(entries))
}

fn format_float(value: f64) -> String {
    let mut text = format!("{}", value);
    if !text.contains('.') && !text.contains('e') && !text.contains('E') {
        text.push_str(".0");
    }
    text
}

fn exact_integer(lexeme: &str, path: &str) -> Result<i64, CyrografError> {
    let bytes = lexeme.as_bytes();
    let length = bytes.len();
    if length == 0 {
        return Err(fail("InvalidInt", path, "expected an exact integer"));
    }
    let negative = bytes[0] == b'-';
    let start = if negative { 1 } else { 0 };
    let mut integer_end = start;
    while integer_end < length && bytes[integer_end].is_ascii_digit() {
        integer_end += 1;
    }
    let integer_digits = &lexeme[start..integer_end];
    let mut fraction_digits = "";
    let mut after_fraction = integer_end;
    if after_fraction < length && bytes[after_fraction] == b'.' {
        let mut stop = after_fraction + 1;
        while stop < length && bytes[stop].is_ascii_digit() {
            stop += 1;
        }
        fraction_digits = &lexeme[after_fraction + 1..stop];
        after_fraction = stop;
    }
    let mut exponent: i64 = 0;
    if after_fraction < length
        && (bytes[after_fraction] == b'e' || bytes[after_fraction] == b'E')
    {
        let mut position = after_fraction + 1;
        let mut sign: i64 = 1;
        if position < length && (bytes[position] == b'+' || bytes[position] == b'-') {
            if bytes[position] == b'-' {
                sign = -1;
            }
            position += 1;
        }
        let digit_start = position;
        let mut value: i64 = 0;
        while position < length && bytes[position].is_ascii_digit() {
            value = value * 10 + i64::from(bytes[position] - b'0');
            if value > 1_000_000 {
                return Err(fail("IntOutOfRange", path, "integer outside the Wire v1 range"));
            }
            position += 1;
        }
        if position == digit_start {
            return Err(fail("InvalidInt", path, "expected an exact integer"));
        }
        exponent = sign * value;
    }
    let mut mantissa = String::from(integer_digits);
    mantissa.push_str(fraction_digits);
    let trimmed = mantissa.trim_start_matches('0');
    if trimmed.is_empty() {
        return Ok(0);
    }
    let shift = exponent - (fraction_digits.len() as i64);
    let magnitude: u64;
    if shift >= 0 {
        if trimmed.len() as i64 + shift > 16 {
            return Err(fail("IntOutOfRange", path, "integer outside the Wire v1 range"));
        }
        let mut digits = String::from(trimmed);
        for _ in 0..shift {
            digits.push('0');
        }
        magnitude = digits
            .parse::<u64>()
            .map_err(|_| fail("IntOutOfRange", path, "integer outside the Wire v1 range"))?;
    } else {
        let drop = (-shift) as usize;
        if drop >= trimmed.len() {
            return Err(fail("IntOutOfRange", path, "integer outside the Wire v1 range"));
        }
        let (head, tail) = trimmed.split_at(trimmed.len() - drop);
        if !tail.bytes().all(|digit| digit == b'0') {
            return Err(fail("IntOutOfRange", path, "integer outside the Wire v1 range"));
        }
        magnitude = head
            .parse::<u64>()
            .map_err(|_| fail("IntOutOfRange", path, "integer outside the Wire v1 range"))?;
    }
    let signed = if negative { -(magnitude as i64) } else { magnitude as i64 };
    if signed < -MAX_SAFE_INT || signed > MAX_SAFE_INT {
        return Err(fail("IntOutOfRange", path, "integer outside the Wire v1 range"));
    }
    Ok(signed)
}

fn json_from_val(value: &Val, path: &str) -> Result<serde_json::Value, CyrografError> {
    match value {
        Val::Null => Ok(serde_json::Value::Null),
        Val::Bool(flag) => Ok(serde_json::Value::Bool(*flag)),
        Val::Str(text) => Ok(serde_json::Value::String(text.clone())),
        Val::Num(lexeme) => number_from_lexeme(lexeme, path),
        Val::List(items) => {
            let mut array = Vec::with_capacity(items.len());
            for item in items {
                array.push(json_from_val(item, path)?);
            }
            Ok(serde_json::Value::Array(array))
        }
        Val::Obj(entries) => {
            let mut map = serde_json::Map::new();
            for (key, item) in entries {
                map.insert(key.clone(), json_from_val(item, path)?);
            }
            Ok(serde_json::Value::Object(map))
        }
    }
}

fn number_from_lexeme(lexeme: &str, path: &str) -> Result<serde_json::Value, CyrografError> {
    let is_integer = !lexeme.contains('.') && !lexeme.contains('e') && !lexeme.contains('E');
    if is_integer {
        if let Ok(value) = lexeme.parse::<i64>() {
            return Ok(serde_json::Value::Number(value.into()));
        }
        if let Ok(value) = lexeme.parse::<u64>() {
            return Ok(serde_json::Value::Number(value.into()));
        }
    }
    let parsed: f64 = lexeme
        .parse()
        .map_err(|_| fail("InvalidJson", path, "invalid number"))?;
    match serde_json::Number::from_f64(parsed) {
        Some(number) => Ok(serde_json::Value::Number(number)),
        None => Err(fail("NonFiniteNumber", path, "non-finite number")),
    }
}

fn val_from_json(value: &serde_json::Value, path: &str) -> Result<Val, CyrografError> {
    match value {
        serde_json::Value::Null => Ok(Val::Null),
        serde_json::Value::Bool(flag) => Ok(Val::Bool(*flag)),
        serde_json::Value::String(text) => Ok(Val::Str(text.clone())),
        serde_json::Value::Number(number) => {
            if let Some(value) = number.as_i64() {
                Ok(Val::Num(value.to_string()))
            } else if let Some(value) = number.as_u64() {
                Ok(Val::Num(value.to_string()))
            } else if let Some(value) = number.as_f64() {
                if !value.is_finite() {
                    return Err(fail("NonFiniteNumber", path, "non-finite number"));
                }
                Ok(Val::Num(format_float(value)))
            } else {
                Err(fail("InvalidJson", path, "unsupported number"))
            }
        }
        serde_json::Value::Array(items) => {
            let mut values = Vec::with_capacity(items.len());
            for item in items {
                values.push(val_from_json(item, path)?);
            }
            Ok(Val::List(values))
        }
        serde_json::Value::Object(entries) => {
            let mut values = Vec::with_capacity(entries.len());
            for (key, item) in entries {
                values.push((key.clone(), val_from_json(item, path)?));
            }
            Ok(Val::Obj(values))
        }
    }
}
|j}

let error_source =
  {j|use std::fmt;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct CyrografError {
    code: String,
    message: String,
    path: String,
}

impl CyrografError {
    pub(crate) fn new(code: &str, path: &str, message: &str) -> Self {
        CyrografError {
            code: code.to_string(),
            message: message.to_string(),
            path: path.to_string(),
        }
    }

    pub fn code(&self) -> &str {
        &self.code
    }

    pub fn message(&self) -> &str {
        &self.message
    }

    pub fn path(&self) -> &str {
        &self.path
    }
}

impl fmt::Display for CyrografError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(formatter, "{}: {} ({})", self.code, self.message, self.path)
    }
}

impl std::error::Error for CyrografError {}
|j}

let manifest =
  {j|[package]
name = "generated_contracts"
version = "0.1.0"
edition = "2024"
rust-version = "1.85"

[lib]
path = "src/lib.rs"

[dependencies]
serde = "=1.0.219"
serde_json = "=1.0.140"
|j}

let module_name = Naming.rust_module_name
let type_name = Naming.rust_type_name
let field_name = Naming.rust_field

let reference_type (qualified : Schema.qualified) =
  "crate::" ^ module_name qualified.module_name ^ "::"
  ^ type_name qualified.message_name

let rec rust_type (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "String"
  | Schema.Primitive Schema.Int -> "i64"
  | Schema.Primitive Schema.Float -> "f64"
  | Schema.Primitive Schema.Bool -> "bool"
  | Schema.Primitive Schema.Void -> "()"
  | Schema.Primitive Schema.Record -> "serde_json::Map<String, serde_json::Value>"
  | Schema.Reference qualified -> reference_type qualified
  | Schema.List inner -> "Vec<" ^ rust_type inner ^ ">"
  | Schema.Optional inner -> "Option<" ^ rust_type inner ^ ">"

let path_of ~module_name name = module_name ^ "." ^ name

let dynamic_path parent = Printf.sprintf "&format!(\"{}[{}]\", %s, _index)" parent

(* [value] must be an expression of a reference to the encoded type. *)
let rec encode ~value ~path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "crate::wire::encode_string(%s, %s)?" value path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "crate::wire::encode_int(%s, %s)?" value path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "crate::wire::encode_float(%s, %s)?" value path
  | Schema.Primitive Schema.Bool -> Printf.sprintf "crate::wire::Val::Bool(*%s)" value
  | Schema.Primitive Schema.Void -> "crate::wire::Val::Null"
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "crate::wire::encode_record(%s, %s)?" value path
  | Schema.Reference _ -> Printf.sprintf "(%s).encode_value()?" value
  | Schema.List inner ->
    Printf.sprintf
      "{\n\
      \        let list = %s;\n\
      \        let mut items = Vec::with_capacity(list.len());\n\
      \        for (_index, _element) in list.iter().enumerate() {\n\
      \            items.push(%s);\n\
      \        }\n\
      \        crate::wire::Val::List(items)\n\
      \    }"
      value
      (encode ~value:"_element" ~path:(dynamic_path path) inner)
  | Schema.Optional inner ->
    Printf.sprintf
      "match %s {\n\
      \        Some(value) => %s,\n\
      \        None => crate::wire::Val::Null,\n\
      \    }"
      value
      (encode ~value:"value" ~path inner)

(* [value] must be an expression of type [&Val]. *)
let rec decode ~value ~path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "crate::wire::as_string(%s, %s)?.to_string()" value path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "crate::wire::as_int(%s, %s)?" value path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "crate::wire::as_float(%s, %s)?" value path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "crate::wire::as_bool(%s, %s)?" value path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "crate::wire::decode_void(%s, %s)?" value path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "crate::wire::as_record(%s, %s)?" value path
  | Schema.Reference qualified ->
    Printf.sprintf "%s::decode_value(%s)?" (reference_type qualified) value
  | Schema.List inner ->
    Printf.sprintf
      "{\n\
      \        let array = crate::wire::as_array(%s, %s, None)?;\n\
      \        let mut items = Vec::with_capacity(array.len());\n\
      \        for (_index, _element) in array.iter().enumerate() {\n\
      \            items.push(%s);\n\
      \        }\n\
      \        items\n\
      \    }"
      value path
      (decode ~value:"_element" ~path:(dynamic_path path) inner)
  | Schema.Optional inner ->
    Printf.sprintf
      "match %s {\n\
      \        crate::wire::Val::Null => None,\n\
      \        other => Some(%s),\n\
      \    }"
      value
      (decode ~value:"other" ~path inner)

let struct_code ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let name = type_name message.Schema.name in
  let path = path_of ~module_name message.name in
  let count = List.length fields in
  p "pub struct %s {\n" name;
  List.iter
    (fun (field : Schema.field) ->
      p "    pub %s: %s,\n" (field_name field.name) (rust_type field.type_))
    fields;
  p "}\n\n";
  p "impl %s {\n" name;
  p "    pub fn to_drut(&self) -> Result<String, crate::CyrografError> {\n";
  p "        Ok(crate::wire::stringify(&self.encode_value()?))\n";
  p "    }\n\n";
  p "    pub fn from_drut(text: &str) -> Result<Self, crate::CyrografError> {\n";
  p "        let value = crate::wire::parse_text(text)?;\n";
  p "        Self::decode_value(&value)\n";
  p "    }\n\n";
  p "    pub(crate) fn encode_value(&self) -> Result<crate::wire::Val, crate::CyrografError> {\n";
  if fields = [] then p "        Ok(crate::wire::Val::List(Vec::new()))\n"
  else begin
    p "        Ok(crate::wire::Val::List(vec![\n";
    List.iter
      (fun (field : Schema.field) ->
        p "            %s,\n"
          (encode ~value:("&self." ^ field_name field.name)
             ~path:(Printf.sprintf "%S" (path ^ "." ^ field.name))
             field.type_))
      fields;
    p "        ]))\n"
  end;
  p "    }\n\n";
  p
    "    pub(crate) fn decode_value(value: &crate::wire::Val) -> \
     Result<Self, crate::CyrografError> {\n";
  if fields = [] then begin
    p "        crate::wire::as_array(value, %S, Some(0))?;\n" path;
    p "        Ok(%s {})\n" name
  end
  else begin
    p "        let fields = crate::wire::as_array(value, %S, Some(%d))?;\n" path count;
    p "        Ok(%s {\n" name;
    List.iteri
      (fun index (field : Schema.field) ->
        p "            %s: %s,\n" (field_name field.name)
          (decode ~value:(Printf.sprintf "&fields[%d]" index)
             ~path:(Printf.sprintf "%S" (Printf.sprintf "%s[%d]" path index))
             field.type_))
      fields;
    p "        })\n"
  end;
  p "    }\n";
  p "}\n";
  Buffer.contents buffer

let case_name (constructor : Schema.constructor) = type_name constructor.name

let variant_code ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let name = type_name message.Schema.name in
  let path = path_of ~module_name message.name in
  p "pub enum %s {\n" name;
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void -> p "    %s,\n" (case_name constructor)
      | type_ -> p "    %s(%s),\n" (case_name constructor) (rust_type type_))
    constructors;
  p "}\n\n";
  p "impl %s {\n" name;
  p "    pub fn to_drut(&self) -> Result<String, crate::CyrografError> {\n";
  p "        Ok(crate::wire::stringify(&self.encode_value()?))\n";
  p "    }\n\n";
  p "    pub fn from_drut(text: &str) -> Result<Self, crate::CyrografError> {\n";
  p "        let value = crate::wire::parse_text(text)?;\n";
  p "        Self::decode_value(&value)\n";
  p "    }\n\n";
  p "    pub(crate) fn encode_value(&self) -> Result<crate::wire::Val, crate::CyrografError> {\n";
  p "        Ok(match self {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "            %s::%s => crate::wire::Val::List(vec![\n" name
          (case_name constructor);
        p "                crate::wire::Val::Str(%S.to_string()),\n" constructor.name;
        p "                crate::wire::Val::Null,\n";
        p "            ]),\n"
      | type_ ->
        p "            %s::%s(value) => crate::wire::Val::List(vec![\n" name
          (case_name constructor);
        p "                crate::wire::Val::Str(%S.to_string()),\n" constructor.name;
        p "                %s,\n"
          (encode ~value:"value"
             ~path:(Printf.sprintf "%S" (path ^ "[1]"))
             type_);
        p "            ]),\n")
    constructors;
  p "        })\n";
  p "    }\n\n";
  p
    "    pub(crate) fn decode_value(value: &crate::wire::Val) -> \
     Result<Self, crate::CyrografError> {\n";
  p "        let fields = crate::wire::as_array(value, %S, Some(2))?;\n" path;
  p "        let tag = crate::wire::as_string(&fields[0], %S)?;\n"
    (Printf.sprintf "%s[0]" path);
  p "        match tag {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "            %S => {\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "                crate::wire::decode_void(&fields[1], %S)?;\n"
           (Printf.sprintf "%s[1]" path);
         p "                Ok(%s::%s)\n" name (case_name constructor)
       | type_ ->
         p "                let payload = %s;\n"
           (decode ~value:"&fields[1]"
              ~path:(Printf.sprintf "%S" (Printf.sprintf "%s[1]" path))
              type_);
         p "                Ok(%s::%s(payload))\n" name (case_name constructor));
      p "            }\n")
    constructors;
  p "            _ => Err(crate::CyrografError::new(\n";
  p "                \"UnknownVariantTag\",\n";
  p "                %S,\n" path;
  p "                \"unknown tag\",\n";
  p "            )),\n";
  p "        }\n";
  p "    }\n";
  p "}\n";
  Buffer.contents buffer

let message_code ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_code ~module_name message fields
  | Schema.Variant constructors -> variant_code ~module_name message constructors

let module_code (module_ : Schema.module_) =
  let buffer = Buffer.create 2048 in
  let p fmt = Printf.bprintf buffer fmt in
  List.iteri
    (fun index message ->
      if index > 0 then p "\n";
      p "%s" (message_code ~module_name:module_.name message))
    module_.messages;
  Buffer.contents buffer

let lib_source modules =
  let buffer = Buffer.create 256 in
  let p fmt = Printf.bprintf buffer fmt in
  p "mod error;\n";
  p "mod wire;\n\n";
  p "pub use error::CyrografError;\n\n";
  List.iter
    (fun (module_ : Schema.module_) ->
      p "pub mod %s;\n" (module_name module_.name))
    modules;
  Buffer.contents buffer

let generate ~modules : Kernel.artifact list =
  let module_artifacts =
    List.map
      (fun (module_ : Schema.module_) ->
        { Kernel.path = "rust/src/" ^ module_name module_.name ^ ".rs";
          contents = module_code module_ })
      modules
  in
  [ { Kernel.path = "rust/Cargo.toml"; contents = manifest };
    { Kernel.path = "rust/src/lib.rs"; contents = lib_source modules };
    { Kernel.path = "rust/src/error.rs"; contents = error_source };
    { Kernel.path = "rust/src/wire.rs"; contents = wire_source } ]
  @ module_artifacts