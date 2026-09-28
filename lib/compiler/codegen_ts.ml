(* TypeScript generator: disjoint unions, validation and explicit Wire errors. *)

module Schema = Cyrograf.Schema
module Naming = Naming

(* ── The shared runtime helper ────────────────────────────────────── *)

let wire_helper =
  {|export class WireError extends Error {
  readonly code: string;
  readonly path: string;
  constructor(code: string, path: string, message: string) {
    super(`${code} at ${path}: ${message}`);
    this.name = "WireError";
    this.code = code;
    this.path = path;
  }
}

export function fail(code: string, path: string, message: string): never {
  throw new WireError(code, path, message);
}

const MAX_SAFE_INT = 9007199254740991;

// A JSON number keeps both its binary64 value and the exact source spelling.
// The byte-level API uses the spelling to reject integers that only look
// integral after binary64 rounding; encoders serialise the value through
// toJSON so wrapper objects never leak into the Wire text.
export class JsonNumber {
  readonly lexeme: string;
  readonly value: number;
  constructor(lexeme: string, value: number) {
    this.lexeme = lexeme;
    this.value = value;
  }
  toJSON(): number {
    return this.value;
  }
}

function shown(value: unknown): string {
  if (value === null) return "null";
  if (Array.isArray(value)) return "array";
  if (value instanceof JsonNumber) return "number";
  return typeof value;
}

function exactInteger(value: string): number | "InvalidInt" | "IntOutOfRange" {
  const length = value.length;
  let index = 0;
  const negative = value[0] === "-";
  if (negative) index = 1;
  let integerEnd = index;
  while (integerEnd < length && value[integerEnd] >= "0" && value[integerEnd] <= "9") {
    integerEnd++;
  }
  const integerDigits = value.slice(index, integerEnd);
  let fractionDigits = "";
  let afterFraction = integerEnd;
  if (afterFraction < length && value[afterFraction] === ".") {
    let stop = afterFraction + 1;
    while (stop < length && value[stop] >= "0" && value[stop] <= "9") stop++;
    fractionDigits = value.slice(afterFraction + 1, stop);
    afterFraction = stop;
  }
  let exponent = 0;
  if (afterFraction < length && (value[afterFraction] === "e" || value[afterFraction] === "E")) {
    let position = afterFraction + 1;
    let sign = 1;
    if (position < length && (value[position] === "+" || value[position] === "-")) {
      if (value[position] === "-") sign = -1;
      position++;
    }
    const digitStart = position;
    while (position < length && value[position] >= "0" && value[position] <= "9") position++;
    if (position === digitStart) return "InvalidInt";
    exponent = sign * Number(value.slice(digitStart, position));
  }
  const mantissa = integerDigits + fractionDigits;
  let from = 0;
  while (from < mantissa.length && mantissa[from] === "0") from++;
  const cleaned = from >= mantissa.length ? "" : mantissa.slice(from);
  if (cleaned === "") return negative ? -0 : 0;
  const shift = exponent - fractionDigits.length;
  let magnitude: number | null = null;
  if (shift >= 0) {
    if (cleaned.length + shift > 16) magnitude = null;
    else magnitude = Number(cleaned + "0".repeat(shift));
  } else {
    const drop = -shift;
    if (drop >= cleaned.length) {
      magnitude = /^0*$/.test(cleaned) ? 0 : null;
    } else {
      const kept = cleaned.slice(0, cleaned.length - drop);
      magnitude = /^0*$/.test(cleaned.slice(cleaned.length - drop)) ? Number(kept) : null;
    }
  }
  if (magnitude === null) return "IntOutOfRange";
  const signed = negative ? -magnitude : magnitude;
  if (signed < -MAX_SAFE_INT || signed > MAX_SAFE_INT) return "IntOutOfRange";
  return signed;
}

function scanValidate(text: string): string[] {
  if (text.charCodeAt(0) === 0xfeff) {
    fail("InvalidJson", "wire", "a leading byte order mark is not valid Wire input");
  }
  const numbers: string[] = [];
  const length = text.length;
  const isNumberChar = (c: string) =>
    (c >= "0" && c <= "9") || c === "-" || c === "+" || c === "." || c === "e" || c === "E";
  const hex = (c: string): number | null => {
    if (c >= "0" && c <= "9") return c.charCodeAt(0) - 0x30;
    if (c >= "a" && c <= "f") return c.charCodeAt(0) - 0x61 + 10;
    if (c >= "A" && c <= "F") return c.charCodeAt(0) - 0x41 + 10;
    return null;
  };
  const scanString = (start: number): number => {
    let index = start;
    while (index < length) {
      const code = text.charCodeAt(index);
      if (code === 0x22) return index + 1;
      if (code < 0x20) fail("InvalidJson", "wire", "unescaped control character in string");
      if (code === 0x5c) {
        if (index + 1 >= length) fail("InvalidJson", "wire", "unterminated escape in string");
        const escape = text[index + 1];
        if (escape === "u") {
          if (index + 5 >= length) fail("InvalidJson", "wire", "truncated unicode escape");
          const a = hex(text[index + 2]);
          const b = hex(text[index + 3]);
          const c = hex(text[index + 4]);
          const d = hex(text[index + 5]);
          if (a === null || b === null || c === null || d === null) {
            fail("InvalidJson", "wire", "invalid unicode escape");
          }
          const point = (a << 12) | (b << 8) | (c << 4) | d;
          if (point >= 0xd800 && point <= 0xdbff) {
            if (
              index + 11 >= length || text[index + 6] !== "\\" || text[index + 7] !== "u"
            ) fail("InvalidJson", "wire", "unpaired surrogate");
            const e = hex(text[index + 8]);
            const f = hex(text[index + 9]);
            const g = hex(text[index + 10]);
            const h = hex(text[index + 11]);
            if (e === null || f === null || g === null || h === null) {
              fail("InvalidJson", "wire", "invalid unicode escape");
            }
            const low = (e << 12) | (f << 8) | (g << 4) | h;
            if (low < 0xdc00 || low > 0xdfff) fail("InvalidJson", "wire", "unpaired surrogate");
            index += 12;
            continue;
          }
          if (point >= 0xdc00 && point <= 0xdfff) {
            fail("InvalidJson", "wire", "unpaired surrogate");
          }
          index += 6;
          continue;
        }
        if (!'"\\/bfnrt'.includes(escape)) fail("InvalidJson", "wire", "invalid escape in string");
        index += 2;
        continue;
      }
      index++;
    }
    fail("InvalidJson", "wire", "unterminated string");
  };
  let index = 0;
  while (index < length) {
    const c = text[index];
    if (c === '"') {
      index = scanString(index + 1);
    } else if (c === "-" || (c >= "0" && c <= "9")) {
      let stop = index;
      while (stop < length && isNumberChar(text[stop])) stop++;
      numbers.push(text.slice(index, stop));
      index = stop;
    } else {
      index++;
    }
  }
  return numbers;
}

export function parseStrictText(text: string): unknown {
  const lexemes = scanValidate(text);
  let cursor = 0;
  let parsed: unknown;
  try {
    parsed = JSON.parse(text, (_key: string, value: unknown) => {
      if (typeof value === "number") {
        const lexeme = lexemes[cursor++];
        return new JsonNumber(lexeme ?? String(value), value);
      }
      return value;
    });
  } catch (error) {
    fail("InvalidJson", "wire", `invalid JSON: ${(error as Error).message}`);
  }
  scanDuplicateKeys(text);
  if (cursor !== lexemes.length) {
    fail("InvalidJson", "wire", "numeric literal count does not match");
  }
  checkFinite(parsed, "");
  return parsed;
}

export function asArray(value: unknown, path: string, length?: number): unknown[] {
  if (!Array.isArray(value)) {
    fail("TypeMismatch", path, `expected an array but found ${shown(value)}`);
  }
  if (length !== undefined && value.length !== length) {
    fail("UnexpectedLength", path, `expected ${length} element(s) but found ${value.length}`);
  }
  return value;
}

export function asString(value: unknown, path: string): string {
  if (typeof value !== "string") {
    fail("TypeMismatch", path, `expected a string but found ${shown(value)}`);
  }
  return value;
}

export function asInt(value: unknown, path: string): number {
  if (value instanceof JsonNumber) {
    const exact = exactInteger(value.lexeme);
    if (exact === "InvalidInt") fail("InvalidInt", path, "expected an exact integer");
    if (exact === "IntOutOfRange") fail("IntOutOfRange", path, "integer outside the Wire v1 range");
    return exact as number;
  }
  if (typeof value !== "number" || !Number.isInteger(value)) {
    fail("InvalidInt", path, "expected an exact integer");
  }
  if (!Number.isSafeInteger(value) || value < -MAX_SAFE_INT || value > MAX_SAFE_INT) {
    fail("IntOutOfRange", path, "integer outside the Wire v1 range");
  }
  return value;
}

export function asFloat(value: unknown, path: string): number {
  const number = value instanceof JsonNumber ? value.value : value;
  if (typeof number !== "number" || !Number.isFinite(number)) {
    fail("InvalidFloat", path, "expected a finite number");
  }
  return number;
}

export function asBool(value: unknown, path: string): boolean {
  if (typeof value !== "boolean") {
    fail("TypeMismatch", path, `expected a boolean but found ${shown(value)}`);
  }
  return value;
}

export function asNull(value: unknown, path: string): null {
  if (value !== null) {
    fail("TypeMismatch", path, `expected null but found ${shown(value)}`);
  }
  return null;
}

export function asRecord(value: unknown, path: string): Record<string, unknown> {
  if (
    value === null || value instanceof JsonNumber ||
    typeof value !== "object" || Array.isArray(value)
  ) {
    fail("TypeMismatch", path, `expected an object but found ${shown(value)}`);
  }
  return value as Record<string, unknown>;
}

export function encodeString(value: string, path: string): string {
  if (typeof value !== "string") {
    fail("TypeMismatch", path, `expected a string but found ${shown(value)}`);
  }
  return value;
}

export function encodeInt(value: number, path: string): number {
  if (typeof value !== "number" || !Number.isInteger(value)) {
    fail("InvalidInt", path, "expected an exact integer");
  }
  if (!Number.isSafeInteger(value) || value < -MAX_SAFE_INT || value > MAX_SAFE_INT) {
    fail("IntOutOfRange", path, "integer outside the Wire v1 range");
  }
  return value;
}

export function encodeFloat(value: number, path: string): number {
  if (typeof value !== "number" || !Number.isFinite(value)) {
    fail("InvalidFloat", path, "expected a finite number");
  }
  return value;
}

export function encodeBool(value: boolean, path: string): boolean {
  if (typeof value !== "boolean") {
    fail("TypeMismatch", path, `expected a boolean but found ${shown(value)}`);
  }
  return value;
}

export function encodeNull(value: null, path: string): null {
  if (value !== null) {
    fail("TypeMismatch", path, `expected null but found ${shown(value)}`);
  }
  return null;
}

export function checkFinite(value: unknown, path: string): void {
  if (value instanceof JsonNumber) {
    if (!Number.isFinite(value.value)) fail("NonFiniteNumber", path, "non-finite number");
    return;
  }
  if (typeof value === "number") {
    if (!Number.isFinite(value)) fail("NonFiniteNumber", path, "non-finite number");
    return;
  }
  if (Array.isArray(value)) {
    for (let i = 0; i < value.length; i++) checkFinite(value[i], `${path}[${i}]`);
    return;
  }
  if (value !== null && typeof value === "object") {
    for (const key of Object.keys(value as Record<string, unknown>)) {
      checkFinite((value as Record<string, unknown>)[key], `${path}.${key}`);
    }
  }
}

export function encodeRecord(value: Record<string, unknown>, path: string): Record<string, unknown> {
  checkFinite(value, path);
  return value;
}

export function stringifyWire(value: unknown): string {
  checkFinite(value, "");
  return JSON.stringify(value);
}

function scanDuplicateKeys(text: string): void {
  let position = 0;
  const isWs = (c: string) => c === " " || c === "\t" || c === "\n" || c === "\r";
  const skipWs = () => { while (position < text.length && isWs(text[position])) position++; };
  const parseString = (): string => {
    position++;
    let result = "";
    while (position < text.length) {
      const c = text[position];
      if (c === '"') { position++; return result; }
      if (c === "\\") {
        position++;
        const escape = text[position];
        if (escape === "u") {
          result += String.fromCharCode(parseInt(text.slice(position + 1, position + 5), 16));
          position += 5;
        } else {
          const decoded: Record<string, string> = {
            '"': '"', "\\": "\\", "/": "/", b: "\b", f: "\f", n: "\n", r: "\r", t: "\t",
          };
          result += decoded[escape] ?? escape;
          position++;
        }
      } else { result += c; position++; }
    }
    fail("InvalidJson", "wire", "unterminated string");
  };
  const parseValue = (): void => {
    skipWs();
    const c = text[position];
    if (c === "{") { position++; parseObject(); }
    else if (c === "[") { position++; parseArray(); }
    else if (c === '"') { parseString(); }
    else {
      while (position < text.length && !",]} \t\n\r".includes(text[position])) position++;
    }
  };
  const parseObject = (): void => {
    skipWs();
    if (text[position] === "}") { position++; return; }
    const keys = new Set<string>();
    for (;;) {
      skipWs();
      const key = parseString();
      if (keys.has(key)) fail("DuplicateKey", "wire", `duplicate object key ${key}`);
      keys.add(key);
      skipWs();
      if (text[position] !== ":") fail("InvalidJson", "wire", "expected a colon");
      position++;
      parseValue();
      skipWs();
      if (text[position] === ",") { position++; continue; }
      if (text[position] === "}") { position++; return; }
      fail("InvalidJson", "wire", "expected a comma or object end");
    }
  };
  const parseArray = (): void => {
    skipWs();
    if (text[position] === "]") { position++; return; }
    for (;;) {
      parseValue();
      skipWs();
      if (text[position] === ",") { position++; continue; }
      if (text[position] === "]") { position++; return; }
      fail("InvalidJson", "wire", "expected a comma or array end");
    }
  };
  parseValue();
  skipWs();
  if (position !== text.length) fail("InvalidJson", "wire", "trailing characters");
}

export function parseWireText(text: string): unknown {
  return parseStrictText(text);
}
|}

(* ── Naming helpers ───────────────────────────────────────────────── *)

let ts_module_namespace = Fun.id

let reference_type ~local (qualified : Schema.qualified) =
  if qualified.module_name = local then qualified.message_name
  else ts_module_namespace qualified.module_name ^ "." ^ qualified.message_name

let rec ts_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "string"
  | Schema.Primitive (Schema.Int | Schema.Float) -> "number"
  | Schema.Primitive Schema.Bool -> "boolean"
  | Schema.Primitive Schema.Void -> "null"
  | Schema.Primitive Schema.Record -> "Record<string, unknown>"
  | Schema.Reference qualified -> reference_type ~local qualified
  | Schema.List inner -> "Array<" ^ ts_type ~local inner ^ ">"
  | Schema.Optional inner -> ts_type ~local inner

let rec ts_encode ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "encodeString(%s, %S)" expr path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "encodeInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "encodeFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "encodeBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "encodeNull(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "encodeRecord(%s, %S)" expr path
  | Schema.Reference qualified ->
    Printf.sprintf "parseWireText(%s.toDrut(%s))"
      (reference_type ~local qualified) expr
  | Schema.List inner ->
    Printf.sprintf "%s.map((x, i) => %s)" expr
      (ts_encode ~local "x" (path ^ "[${i}]") inner)
  | Schema.Optional inner ->
    Printf.sprintf "(%s === undefined ? null : %s)" expr
      (ts_encode ~local expr path inner)

let rec ts_decode ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "asString(%s, %S)" expr path
  | Schema.Primitive Schema.Int ->
    Printf.sprintf "asInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float ->
    Printf.sprintf "asFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool ->
    Printf.sprintf "asBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void ->
    Printf.sprintf "asNull(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "asRecord(%s, %S)" expr path
  | Schema.Reference qualified ->
    Printf.sprintf "%s.fromDrut(stringifyWire(%s))"
      (reference_type ~local qualified) expr
  | Schema.List inner ->
    Printf.sprintf "asArray(%s, %S).map((x, i) => %s)" expr path
      (ts_decode ~local "x" (path ^ "[${i}]") inner)
  | Schema.Optional inner ->
    Printf.sprintf "(%s === null ? undefined : %s)" expr
      (ts_decode ~local expr path inner)

(* ── Message generation ───────────────────────────────────────────── *)

let path_of ~module_name name = module_name ^ "." ^ name

let field_declaration ~local (field : Schema.field) =
  let name = Naming.ts_camel_case field.name in
  match field.type_ with
  | Schema.Optional inner ->
    Printf.sprintf "  %s?: %s;" name (ts_type ~local inner)
  | type_ -> Printf.sprintf "  %s: %s;" name (ts_type ~local type_)

let text_object buffer name =
  let p fmt = Printf.bprintf buffer fmt in
  p "export const %s = {\n" name;
  p "  toDrut(value: %s): string { return stringifyWire(wireEncode%s(value)); },\n"
    name name;
  p "  fromDrut(text: string): %s { return wireDecode%s(parseWireText(text)); },\n"
    name name;
  p "};\n"

let struct_code ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = path_of ~module_name name in
  p "export interface %s {\n" name;
  List.iter (fun field -> p "%s\n" (field_declaration ~local field)) fields;
  p "}\n\n";
  p "function wireEncode%s(v: %s, path: string = %S): unknown[] {\n"
    name name path;
  p "  return [";
  List.iteri
    (fun index (field : Schema.field) ->
      if index > 0 then p ", ";
      let access = "v." ^ Naming.ts_camel_case field.name in
      let field_path = path ^ "." ^ field.name in
      match field.type_ with
      | Schema.Optional inner ->
        p "(%s === undefined ? null : %s)" access
          (ts_encode ~local access field_path inner)
      | type_ -> p "%s" (ts_encode ~local access field_path type_))
    fields;
  p "];\n";
  p "}\n\n";
  p "function wireDecode%s(wire: unknown, path: string = %S): %s {\n"
    name path name;
  p "  const arr = asArray(wire, path, %d);\n" (List.length fields);
  let required_literal =
    List.filter_map
      (fun (index, (field : Schema.field)) ->
        match field.type_ with
        | Schema.Optional _ -> None
        | type_ ->
          Some
            (Printf.sprintf "%s: %s" (Naming.ts_camel_case field.name)
               (ts_decode ~local (Printf.sprintf "arr[%d]" index)
                  (path ^ "." ^ field.name) type_)))
      (List.mapi (fun index field -> (index, field)) fields)
  in
  p "  const out: %s = { %s };\n" name (String.concat ", " required_literal);
  List.iter
    (fun (index, (field : Schema.field)) ->
      match field.type_ with
      | Schema.Optional inner ->
        p "  if (arr[%d] !== null) { out.%s = %s; }\n" index
          (Naming.ts_camel_case field.name)
          (ts_decode ~local (Printf.sprintf "arr[%d]" index)
             (path ^ "." ^ field.name) inner)
      | _ -> ())
    (List.mapi (fun index field -> (index, field)) fields);
  p "  return out;\n";
  p "}\n\n";
  text_object buffer name;
  Buffer.contents buffer

let variant_code ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 512 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = message.Schema.name in
  let path = path_of ~module_name name in
  p "export type %s =\n" name;
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "  | { tag: %S }\n" constructor.name
      | type_ ->
        p "  | { tag: %S; value: %s }\n" constructor.name (ts_type ~local type_))
    constructors;
  p ";\n\n";
  p "function wireEncode%s(v: %s, path: string = %S): unknown[] {\n"
    name name path;
  p "  switch (v.tag) {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "    case %S: return [%S, null];\n" constructor.name constructor.name
      | type_ ->
        p "    case %S: return [%S, %s];\n" constructor.name constructor.name
          (ts_encode ~local
             (Printf.sprintf "(v as { value: %s }).value" (ts_type ~local type_))
             (path ^ ".value") type_))
    constructors;
  p "    default: return fail(\"InvalidVariant\", path, \"unknown tag\");\n";
  p "  }\n";
  p "}\n\n";
  p "function wireDecode%s(wire: unknown, path: string = %S): %s {\n"
    name path name;
  p "  const arr = asArray(wire, path, 2);\n";
  p "  const tag = asString(arr[0], `${path}[0]`);\n";
  p "  switch (tag) {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      match constructor.payload with
      | Schema.Primitive Schema.Void ->
        p "    case %S:\n" constructor.name;
        p "      asNull(arr[1], `${path}[1]`);\n";
        p "      return { tag: %S };\n" constructor.name
      | type_ ->
        p "    case %S: return { tag: %S, value: %s };\n" constructor.name
          constructor.name
          (ts_decode ~local "arr[1]" (path ^ "[1]") type_))
    constructors;
  p "    default: return fail(\"UnknownVariantTag\", path, `unknown tag ${tag}`);\n";
  p "  }\n";
  p "}\n\n";
  text_object buffer name;
  Buffer.contents buffer

let message_code ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_code ~module_name message fields
  | Schema.Variant constructors -> variant_code ~module_name message constructors

(* ── Cross-module imports ─────────────────────────────────────────── *)

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
  p "import { WireError, fail, asArray, asString, asInt, asFloat, asBool, asNull, asRecord, encodeString, encodeInt, encodeFloat, encodeBool, encodeNull, encodeRecord, stringifyWire, parseWireText } from \"./wire.ts\";\n";
  List.iter
    (fun name ->
      p "import * as %s from \"./%s\";\n" name (Naming.ts_file name))
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
        { Kernel.path = "typescript/" ^ Naming.ts_file module_.name;
          contents = module_code module_ })
      modules
  in
  { Kernel.path = "typescript/wire.ts"; contents = wire_helper } :: module_artifacts