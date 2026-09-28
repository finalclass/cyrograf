(* Java generator: JDK only, records and sealed variant interfaces.

   Each source module becomes a public outer class in [generated_contracts].
   Messages are nested records (structures) or a nested sealed interface with
   nested record cases (variants). The package-private [Wire] runtime carries
   the strict Drut text validation; message types expose exactly the two public
   conversions [toDrut]/[fromDrut]. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let wire_source =
  {j|package generated_contracts;

import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

final class Wire {

    interface Enc {
        Object apply(Object value, String path);
    }

    interface Dec {
        Object apply(Object data, String path);
    }

    static final class Num {
        final String lexeme;

        Num(String lexeme) {
            this.lexeme = lexeme;
        }
    }

    private static final long MAX_SAFE_INT = 9007199254740991L;
    private static final double MAX_SAFE_FLOAT = 9007199254740992.0;

    private Wire() {
    }

    static CyrografException fail(String code, String path, String message) {
        return new CyrografException(code, path, message);
    }

    static Object parseText(String text) {
        if (text.startsWith("\uFEFF")) {
            throw fail("InvalidJson", "", "a leading byte order mark is not valid Wire input");
        }
        Parser parser = new Parser(text);
        Object value = parser.parseValue();
        parser.skipWhitespace();
        if (parser.index != text.length()) {
            throw fail("InvalidJson", "", "trailing characters after the value");
        }
        return value;
    }

    static String stringify(Object value) {
        StringBuilder out = new StringBuilder();
        writeValue(value, out);
        return out.toString();
    }

    private static void writeValue(Object value, StringBuilder out) {
        if (value == null) {
            out.append("null");
            return;
        }
        if (value instanceof String string) {
            writeString(string, out);
            return;
        }
        if (value instanceof Boolean bool) {
            out.append(bool.booleanValue() ? "true" : "false");
            return;
        }
        if (value instanceof Num number) {
            out.append(number.lexeme);
            return;
        }
        if (value instanceof Long || value instanceof Integer || value instanceof Short
                || value instanceof Byte) {
            out.append(value.toString());
            return;
        }
        if (value instanceof Double || value instanceof Float) {
            double number = ((Number) value).doubleValue();
            if (!Double.isFinite(number)) {
                throw fail("NonFiniteNumber", "", "non-finite number");
            }
            out.append(Double.toString(number));
            return;
        }
        if (value instanceof List<?> list) {
            out.append('[');
            boolean first = true;
            for (Object item : list) {
                if (!first) {
                    out.append(',');
                }
                first = false;
                writeValue(item, out);
            }
            out.append(']');
            return;
        }
        if (value instanceof Map<?, ?> map) {
            out.append('{');
            boolean first = true;
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                if (!(entry.getKey() instanceof String key)) {
                    throw fail("InvalidJson", "", "object keys must be strings");
                }
                if (!first) {
                    out.append(',');
                }
                first = false;
                writeString(key, out);
                out.append(':');
                writeValue(entry.getValue(), out);
            }
            out.append('}');
            return;
        }
        throw fail("InvalidJson", "", "unsupported value");
    }

    private static void writeString(String value, StringBuilder out) {
        out.append('"');
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            switch (character) {
                case '"':
                    out.append("\\\"");
                    break;
                case '\\':
                    out.append("\\\\");
                    break;
                case '\b':
                    out.append("\\b");
                    break;
                case '\f':
                    out.append("\\f");
                    break;
                case '\n':
                    out.append("\\n");
                    break;
                case '\r':
                    out.append("\\r");
                    break;
                case '\t':
                    out.append("\\t");
                    break;
                default:
                    if (character < 0x20) {
                        out.append(String.format("\\u%04x", (int) character));
                    } else if (Character.isHighSurrogate(character)) {
                        if (index + 1 >= value.length()
                                || !Character.isLowSurrogate(value.charAt(index + 1))) {
                            throw fail("InvalidString", "", "string contains an unpaired surrogate");
                        }
                        out.append(character);
                        out.append(value.charAt(++index));
                    } else if (Character.isLowSurrogate(character)) {
                        throw fail("InvalidString", "", "string contains an unpaired surrogate");
                    } else {
                        out.append(character);
                    }
                    break;
            }
        }
        out.append('"');
    }

    private static final class Parser {
        private final String text;
        private int index;

        Parser(String text) {
            this.text = text;
        }

        void skipWhitespace() {
            while (index < text.length()) {
                char character = text.charAt(index);
                if (character == ' ' || character == '\t' || character == '\n'
                        || character == '\r') {
                    index++;
                } else {
                    break;
                }
            }
        }

        Object parseValue() {
            skipWhitespace();
            if (index >= text.length()) {
                throw fail("InvalidJson", "", "unexpected end of input");
            }
            char character = text.charAt(index);
            switch (character) {
                case '{':
                    return parseObject();
                case '[':
                    return parseArray();
                case '"':
                    return parseString();
                case 't':
                    expect("true");
                    return Boolean.TRUE;
                case 'f':
                    expect("false");
                    return Boolean.FALSE;
                case 'n':
                    expect("null");
                    return null;
                default:
                    if (character == '-' || isDigit(character)) {
                        return parseNumber();
                    }
                    throw fail("InvalidJson", "", "unexpected character");
            }
        }

        private void expect(String word) {
            if (!text.startsWith(word, index)) {
                throw fail("InvalidJson", "", "invalid literal");
            }
            index += word.length();
        }

        private Object parseObject() {
            index++;
            Map<String, Object> map = new LinkedHashMap<>();
            skipWhitespace();
            if (index < text.length() && text.charAt(index) == '}') {
                index++;
                return map;
            }
            while (true) {
                skipWhitespace();
                if (index >= text.length() || text.charAt(index) != '"') {
                    throw fail("InvalidJson", "", "expected an object key");
                }
                String key = parseString();
                if (map.containsKey(key)) {
                    throw fail("DuplicateKey", "", "duplicate object key " + key);
                }
                skipWhitespace();
                if (index >= text.length() || text.charAt(index) != ':') {
                    throw fail("InvalidJson", "", "expected a colon");
                }
                index++;
                Object value = parseValue();
                map.put(key, value);
                skipWhitespace();
                if (index >= text.length()) {
                    throw fail("InvalidJson", "", "unterminated object");
                }
                char character = text.charAt(index);
                if (character == ',') {
                    index++;
                    continue;
                }
                if (character == '}') {
                    index++;
                    return map;
                }
                throw fail("InvalidJson", "", "expected a comma or a closing brace");
            }
        }

        private Object parseArray() {
            index++;
            List<Object> list = new ArrayList<>();
            skipWhitespace();
            if (index < text.length() && text.charAt(index) == ']') {
                index++;
                return list;
            }
            while (true) {
                list.add(parseValue());
                skipWhitespace();
                if (index >= text.length()) {
                    throw fail("InvalidJson", "", "unterminated array");
                }
                char character = text.charAt(index);
                if (character == ',') {
                    index++;
                    continue;
                }
                if (character == ']') {
                    index++;
                    return list;
                }
                throw fail("InvalidJson", "", "expected a comma or a closing bracket");
            }
        }

        private String parseString() {
            index++;
            StringBuilder out = new StringBuilder();
            while (true) {
                if (index >= text.length()) {
                    throw fail("InvalidJson", "", "unterminated string");
                }
                char character = text.charAt(index++);
                if (character == '"') {
                    return out.toString();
                }
                if (character < 0x20) {
                    throw fail("InvalidJson", "", "unescaped control character in string");
                }
                if (character == '\\') {
                    if (index >= text.length()) {
                        throw fail("InvalidJson", "", "unterminated escape in string");
                    }
                    char escape = text.charAt(index++);
                    switch (escape) {
                        case '"':
                            out.append('"');
                            break;
                        case '\\':
                            out.append('\\');
                            break;
                        case '/':
                            out.append('/');
                            break;
                        case 'b':
                            out.append('\b');
                            break;
                        case 'f':
                            out.append('\f');
                            break;
                        case 'n':
                            out.append('\n');
                            break;
                        case 'r':
                            out.append('\r');
                            break;
                        case 't':
                            out.append('\t');
                            break;
                        case 'u':
                            int code = readHex4();
                            if (code >= 0xD800 && code <= 0xDBFF) {
                                if (index + 1 >= text.length() || text.charAt(index) != '\\'
                                        || text.charAt(index + 1) != 'u') {
                                    throw fail("InvalidJson", "", "unpaired surrogate");
                                }
                                index += 2;
                                int low = readHex4();
                                if (low < 0xDC00 || low > 0xDFFF) {
                                    throw fail("InvalidJson", "", "unpaired surrogate");
                                }
                                out.appendCodePoint(
                                        Character.toCodePoint((char) code, (char) low));
                            } else if (code >= 0xDC00 && code <= 0xDFFF) {
                                throw fail("InvalidJson", "", "unpaired surrogate");
                            } else {
                                out.append((char) code);
                            }
                            break;
                        default:
                            throw fail("InvalidJson", "", "invalid escape in string");
                    }
                    continue;
                }
                if (character >= 0xD800 && character <= 0xDBFF) {
                    if (index >= text.length()) {
                        throw fail("InvalidJson", "", "unpaired surrogate");
                    }
                    char low = text.charAt(index);
                    if (low < 0xDC00 || low > 0xDFFF) {
                        throw fail("InvalidJson", "", "unpaired surrogate");
                    }
                    out.append(character);
                    out.append(low);
                    index++;
                    continue;
                }
                if (character >= 0xDC00 && character <= 0xDFFF) {
                    throw fail("InvalidJson", "", "unpaired surrogate");
                }
                out.append(character);
            }
        }

        private int readHex4() {
            if (index + 4 > text.length()) {
                throw fail("InvalidJson", "", "truncated unicode escape");
            }
            int value = 0;
            for (int offset = 0; offset < 4; offset++) {
                int digit = hexValue(text.charAt(index++));
                if (digit < 0) {
                    throw fail("InvalidJson", "", "invalid unicode escape");
                }
                value = (value << 4) | digit;
            }
            return value;
        }

        private Object parseNumber() {
            int start = index;
            if (text.charAt(index) == '-') {
                index++;
            }
            if (index >= text.length() || !isDigit(text.charAt(index))) {
                throw fail("InvalidJson", "", "invalid number");
            }
            if (text.charAt(index) == '0') {
                index++;
            } else {
                while (index < text.length() && isDigit(text.charAt(index))) {
                    index++;
                }
            }
            if (index < text.length() && text.charAt(index) == '.') {
                index++;
                if (index >= text.length() || !isDigit(text.charAt(index))) {
                    throw fail("InvalidJson", "", "invalid number");
                }
                while (index < text.length() && isDigit(text.charAt(index))) {
                    index++;
                }
            }
            if (index < text.length()
                    && (text.charAt(index) == 'e' || text.charAt(index) == 'E')) {
                index++;
                if (index < text.length()
                        && (text.charAt(index) == '+' || text.charAt(index) == '-')) {
                    index++;
                }
                if (index >= text.length() || !isDigit(text.charAt(index))) {
                    throw fail("InvalidJson", "", "invalid number");
                }
                while (index < text.length() && isDigit(text.charAt(index))) {
                    index++;
                }
            }
            return new Num(text.substring(start, index));
        }

        private static boolean isDigit(char character) {
            return character >= '0' && character <= '9';
        }

        private static int hexValue(char character) {
            if (character >= '0' && character <= '9') {
                return character - '0';
            }
            if (character >= 'a' && character <= 'f') {
                return character - 'a' + 10;
            }
            if (character >= 'A' && character <= 'F') {
                return character - 'A' + 10;
            }
            return -1;
        }
    }

    private static Object recordNumber(Num number) {
        double value = Double.parseDouble(number.lexeme);
        if (Double.isFinite(value) && value == Math.rint(value)
                && Math.abs(value) <= MAX_SAFE_FLOAT) {
            return (long) value;
        }
        return value;
    }

    private static Object canonicalize(Object value) {
        if (value instanceof Num number) {
            return recordNumber(number);
        }
        if (value instanceof List<?> list) {
            List<Object> typed = castList(list);
            for (int index = 0; index < typed.size(); index++) {
                typed.set(index, canonicalize(typed.get(index)));
            }
            return typed;
        }
        if (value instanceof Map<?, ?> map) {
            Map<String, Object> typed = castMap(map);
            for (Map.Entry<String, Object> entry : typed.entrySet()) {
                entry.setValue(canonicalize(entry.getValue()));
            }
            return typed;
        }
        return value;
    }

    @SuppressWarnings("unchecked")
    private static List<Object> castList(List<?> list) {
        return (List<Object>) list;
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> castMap(Map<?, ?> map) {
        return (Map<String, Object>) map;
    }

    static List<Object> asArray(Object data, String path, int length) {
        if (!(data instanceof List<?> raw)) {
            throw fail("TypeMismatch", path, "expected an array");
        }
        List<Object> list = castList(raw);
        if (length >= 0 && list.size() != length) {
            throw fail("UnexpectedLength", path,
                    "expected " + length + " element(s) but found " + list.size());
        }
        return list;
    }

    static String asString(Object data, String path) {
        if (!(data instanceof String value)) {
            throw fail("TypeMismatch", path, "expected a string");
        }
        return value;
    }

    static long asInt(Object data, String path) {
        if (data instanceof Num number) {
            return exactInteger(number.lexeme, path);
        }
        if (data instanceof Long || data instanceof Integer) {
            return ((Number) data).longValue();
        }
        if (data instanceof Double value) {
            double number = value.doubleValue();
            if (number != Math.rint(number)) {
                throw fail("InvalidInt", path, "expected an exact integer");
            }
            if (number < -MAX_SAFE_INT || number > MAX_SAFE_INT) {
                throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
            }
            return (long) number;
        }
        throw fail("TypeMismatch", path, "expected an integer");
    }

    static double asFloat(Object data, String path) {
        if (data instanceof Boolean) {
            throw fail("TypeMismatch", path, "expected a number");
        }
        if (data instanceof Num number) {
            double value = Double.parseDouble(number.lexeme);
            if (!Double.isFinite(value)) {
                throw fail("InvalidFloat", path, "non-finite number");
            }
            return value;
        }
        if (data instanceof Long || data instanceof Integer) {
            return ((Number) data).doubleValue();
        }
        if (data instanceof Double value) {
            if (!Double.isFinite(value)) {
                throw fail("InvalidFloat", path, "non-finite number");
            }
            return value;
        }
        throw fail("TypeMismatch", path, "expected a number");
    }

    static boolean asBool(Object data, String path) {
        if (!(data instanceof Boolean value)) {
            throw fail("TypeMismatch", path, "expected a boolean");
        }
        return value;
    }

    static Void asNull(Object data, String path) {
        if (data != null) {
            throw fail("TypeMismatch", path, "expected null");
        }
        return null;
    }

    static Map<String, Object> asRecord(Object data, String path) {
        if (!(data instanceof Map<?, ?> raw)) {
            throw fail("TypeMismatch", path, "expected an object");
        }
        return castMap((Map<?, ?>) canonicalize(raw));
    }

    private static long exactInteger(String lexeme, String path) {
        int length = lexeme.length();
        if (length == 0) {
            throw fail("InvalidInt", path, "expected an exact integer");
        }
        boolean negative = lexeme.charAt(0) == '-';
        int start = negative ? 1 : 0;
        int integerEnd = start;
        while (integerEnd < length && isAsciiDigit(lexeme.charAt(integerEnd))) {
            integerEnd++;
        }
        String integerDigits = lexeme.substring(start, integerEnd);
        String fractionDigits = "";
        int afterFraction = integerEnd;
        if (afterFraction < length && lexeme.charAt(afterFraction) == '.') {
            int stop = afterFraction + 1;
            while (stop < length && isAsciiDigit(lexeme.charAt(stop))) {
                stop++;
            }
            fractionDigits = lexeme.substring(afterFraction + 1, stop);
            afterFraction = stop;
        }
        int exponent = 0;
        if (afterFraction < length
                && (lexeme.charAt(afterFraction) == 'e' || lexeme.charAt(afterFraction) == 'E')) {
            int position = afterFraction + 1;
            int sign = 1;
            if (position < length
                    && (lexeme.charAt(position) == '+' || lexeme.charAt(position) == '-')) {
                if (lexeme.charAt(position) == '-') {
                    sign = -1;
                }
                position++;
            }
            int digitStart = position;
            int value = 0;
            while (position < length && isAsciiDigit(lexeme.charAt(position))) {
                value = value * 10 + (lexeme.charAt(position) - '0');
                if (value > 1000000) {
                    throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
                }
                position++;
            }
            if (position == digitStart) {
                throw fail("InvalidInt", path, "expected an exact integer");
            }
            exponent = sign * value;
        }
        String mantissa = integerDigits + fractionDigits;
        int from = 0;
        while (from < mantissa.length() && mantissa.charAt(from) == '0') {
            from++;
        }
        String cleaned = mantissa.substring(from);
        if (cleaned.isEmpty()) {
            return 0;
        }
        int shift = exponent - fractionDigits.length();
        long magnitude;
        if (shift >= 0) {
            if (cleaned.length() + shift > 16) {
                throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
            }
            magnitude = parseMagnitude(cleaned + "0".repeat(shift), path);
        } else {
            int drop = -shift;
            if (drop >= cleaned.length()) {
                if (!cleaned.chars().allMatch(character -> character == '0')) {
                    throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
                }
                magnitude = 0;
            } else {
                String tail = cleaned.substring(cleaned.length() - drop);
                if (!tail.chars().allMatch(character -> character == '0')) {
                    throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
                }
                magnitude = parseMagnitude(cleaned.substring(0, cleaned.length() - drop), path);
            }
        }
        long signed = negative ? -magnitude : magnitude;
        if (signed < -MAX_SAFE_INT || signed > MAX_SAFE_INT) {
            throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
        }
        return signed;
    }

    private static long parseMagnitude(String digits, String path) {
        try {
            return Long.parseLong(digits);
        } catch (NumberFormatException error) {
            throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
        }
    }

    private static boolean isAsciiDigit(char character) {
        return character >= '0' && character <= '9';
    }

    private static void checkUnicode(String value, String path) {
        for (int index = 0; index < value.length(); index++) {
            char character = value.charAt(index);
            if (Character.isHighSurrogate(character)) {
                if (index + 1 >= value.length()
                        || !Character.isLowSurrogate(value.charAt(index + 1))) {
                    throw fail("InvalidString", path, "string contains an unpaired surrogate");
                }
                index++;
            } else if (Character.isLowSurrogate(character)) {
                throw fail("InvalidString", path, "string contains an unpaired surrogate");
            }
        }
    }

    static Object encodeString(String value, String path) {
        if (value == null) {
            throw fail("TypeMismatch", path, "expected a string");
        }
        checkUnicode(value, path);
        return value;
    }

    static Object encodeInt(long value, String path) {
        if (value < -MAX_SAFE_INT || value > MAX_SAFE_INT) {
            throw fail("IntOutOfRange", path, "integer outside the Wire v1 range");
        }
        return value;
    }

    static Object encodeFloat(double value, String path) {
        if (!Double.isFinite(value)) {
            throw fail("InvalidFloat", path, "non-finite number");
        }
        return value;
    }

    static Object encodeBool(boolean value, String path) {
        return value;
    }

    static Object encodeVoid(Void value, String path) {
        if (value != null) {
            throw fail("TypeMismatch", path, "expected null");
        }
        return null;
    }

    static Object encodeRecord(Object value, String path) {
        if (value == null) {
            throw fail("TypeMismatch", path, "expected an object");
        }
        checkFinite(value, path);
        return value;
    }

    static Object reference(Object value, String path, java.util.function.Supplier<String> text) {
        if (value == null) {
            throw fail("TypeMismatch", path, "expected a message");
        }
        return parseText(text.get());
    }

    private static void checkFinite(Object value, String path) {
        if (value instanceof Double number) {
            if (!Double.isFinite(number)) {
                throw fail("NonFiniteNumber", path, "non-finite number");
            }
        } else if (value instanceof List<?> list) {
            int index = 0;
            for (Object item : list) {
                checkFinite(item, path + "[" + index + "]");
                index++;
            }
        } else if (value instanceof Map<?, ?> map) {
            for (Map.Entry<?, ?> entry : map.entrySet()) {
                checkFinite(entry.getValue(), path + "." + entry.getKey());
            }
        }
    }

    static Object encodeList(List<?> items, String path, Enc encode) {
        if (items == null) {
            throw fail("TypeMismatch", path, "expected an array");
        }
        List<Object> out = new ArrayList<>();
        int index = 0;
        for (Object item : items) {
            out.add(encode.apply(item, path + "[" + index + "]"));
            index++;
        }
        return out;
    }

    @SuppressWarnings("unchecked")
    static <T> List<T> decodeList(Object data, String path, Dec decode) {
        List<Object> arr = asArray(data, path, -1);
        List<T> out = new ArrayList<>();
        for (int index = 0; index < arr.size(); index++) {
            out.add((T) decode.apply(arr.get(index), path + "[" + index + "]"));
        }
        return out;
    }

    static Object encodeOptional(Optional<?> value, String path, Enc encode) {
        if (value == null) {
            throw fail("TypeMismatch", path, "expected an Optional");
        }
        if (value.isEmpty()) {
            return null;
        }
        return encode.apply(value.get(), path);
    }

    @SuppressWarnings("unchecked")
    static <T> Optional<T> decodeOptional(Object data, String path, Dec decode) {
        if (data == null) {
            return Optional.empty();
        }
        return Optional.of((T) decode.apply(data, path));
    }
}
|j}

let exception_source =
  {j|package generated_contracts;

public class CyrografException extends RuntimeException {

    private static final long serialVersionUID = 1L;

    public final String code;
    public final String path;

    public CyrografException(String code, String path, String message) {
        super(message);
        this.code = code;
        this.path = path;
    }
}
|j}

let pom =
  {j|<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 http://maven.apache.org/xsd/maven-4.0.0.xsd">
  <modelVersion>4.0.0</modelVersion>
  <groupId>generated_contracts</groupId>
  <artifactId>generated-contracts</artifactId>
  <version>0.1.0</version>
  <packaging>jar</packaging>
  <name>generated contracts</name>
  <properties>
    <maven.compiler.release>21</maven.compiler.release>
    <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
  </properties>
</project>
|j}

let class_name = Naming.java_class_name
let field_name = Naming.java_field

let reserved_outer_names =
  [ "String"; "Object"; "Optional"; "List"; "Map"; "Void"; "Long"; "Double";
    "Boolean"; "Integer"; "Number"; "Wire"; "CyrografException" ]

let outer_names : (string, string) Hashtbl.t = Hashtbl.create 8

let outer_name module_name =
  match Hashtbl.find_opt outer_names module_name with
  | Some name -> name
  | None -> Naming.java_class_name module_name

let assign_outer_name (module_ : Schema.module_) =
  let taken =
    List.map (fun (message : Schema.message) -> class_name message.name) module_.messages
  in
  let rec pick name =
    if List.mem name taken || List.mem name reserved_outer_names then pick (name ^ "_")
    else name
  in
  let outer = pick (Naming.java_class_name module_.name) in
  Hashtbl.replace outer_names module_.name outer

let reference_type ~local (qualified : Schema.qualified) =
  let message = class_name qualified.message_name in
  if qualified.module_name = local then message
  else outer_name qualified.module_name ^ "." ^ message

let rec java_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "String"
  | Schema.Primitive Schema.Int -> "long"
  | Schema.Primitive Schema.Float -> "double"
  | Schema.Primitive Schema.Bool -> "boolean"
  | Schema.Primitive Schema.Void -> "Void"
  | Schema.Primitive Schema.Record -> "java.util.Map<String, Object>"
  | Schema.Reference qualified -> reference_type ~local qualified
  | Schema.List inner -> "java.util.List<" ^ boxed_type ~local inner ^ ">"
  | Schema.Optional inner -> "java.util.Optional<" ^ boxed_type ~local inner ^ ">"

and boxed_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive Schema.Int -> "Long"
  | Schema.Primitive Schema.Float -> "Double"
  | Schema.Primitive Schema.Bool -> "Boolean"
  | Schema.Primitive Schema.Void -> "Void"
  | _ -> java_type ~local type_

let java_boxed_reference ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Reference qualified -> reference_type ~local qualified
  | _ -> boxed_type ~local type_

let lambda ~depth body =
  Printf.sprintf "(value%d, path%d) -> %s" depth depth body

let rec encode_fn ~depth ~local (type_ : Schema.type_) =
  let v = Printf.sprintf "value%d" depth in
  let p = Printf.sprintf "path%d" depth in
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    lambda ~depth (Printf.sprintf "Wire.encodeString((String) %s, %s)" v p)
  | Schema.Primitive Schema.Int ->
    lambda ~depth (Printf.sprintf "Wire.encodeInt((Long) %s, %s)" v p)
  | Schema.Primitive Schema.Float ->
    lambda ~depth (Printf.sprintf "Wire.encodeFloat((Double) %s, %s)" v p)
  | Schema.Primitive Schema.Bool ->
    lambda ~depth (Printf.sprintf "Wire.encodeBool((Boolean) %s, %s)" v p)
  | Schema.Primitive Schema.Void ->
    lambda ~depth (Printf.sprintf "Wire.encodeVoid((Void) %s, %s)" v p)
  | Schema.Primitive Schema.Record ->
    lambda ~depth (Printf.sprintf "Wire.encodeRecord(%s, %s)" v p)
  | Schema.Reference _ ->
    lambda ~depth
      (Printf.sprintf "Wire.reference(%s, %s, () -> ((%s) %s).toDrut())" v p
         (java_boxed_reference ~local type_) v)
  | Schema.List inner ->
    lambda ~depth
      (Printf.sprintf "Wire.encodeList((java.util.List<?>) %s, %s, %s)" v p
         (encode_fn ~depth:(depth + 1) ~local inner))
  | Schema.Optional inner ->
    lambda ~depth
      (Printf.sprintf "Wire.encodeOptional((java.util.Optional<?>) %s, %s, %s)" v p
         (encode_fn ~depth:(depth + 1) ~local inner))

let rec decode_fn ~depth ~local (type_ : Schema.type_) =
  let v = Printf.sprintf "value%d" depth in
  let p = Printf.sprintf "path%d" depth in
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    lambda ~depth (Printf.sprintf "Wire.asString(%s, %s)" v p)
  | Schema.Primitive Schema.Int -> lambda ~depth (Printf.sprintf "Wire.asInt(%s, %s)" v p)
  | Schema.Primitive Schema.Float -> lambda ~depth (Printf.sprintf "Wire.asFloat(%s, %s)" v p)
  | Schema.Primitive Schema.Bool -> lambda ~depth (Printf.sprintf "Wire.asBool(%s, %s)" v p)
  | Schema.Primitive Schema.Void -> lambda ~depth (Printf.sprintf "Wire.asNull(%s, %s)" v p)
  | Schema.Primitive Schema.Record -> lambda ~depth (Printf.sprintf "Wire.asRecord(%s, %s)" v p)
  | Schema.Reference qualified ->
    lambda ~depth
      (Printf.sprintf "%s.fromDrut(Wire.stringify(%s))" (reference_type ~local qualified) v)
  | Schema.List inner ->
    lambda ~depth
      (Printf.sprintf "Wire.decodeList(%s, %s, %s)" v p
         (decode_fn ~depth:(depth + 1) ~local inner))
  | Schema.Optional inner ->
    lambda ~depth
      (Printf.sprintf "Wire.decodeOptional(%s, %s, %s)" v p
         (decode_fn ~depth:(depth + 1) ~local inner))

let encode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "Wire.encodeString(%s, %S)" expr path
  | Schema.Primitive Schema.Int -> Printf.sprintf "Wire.encodeInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float -> Printf.sprintf "Wire.encodeFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool -> Printf.sprintf "Wire.encodeBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void -> Printf.sprintf "Wire.encodeVoid(%s, %S)" expr path
  | Schema.Primitive Schema.Record -> Printf.sprintf "Wire.encodeRecord(%s, %S)" expr path
  | Schema.Reference _ ->
    Printf.sprintf "Wire.reference(%s, %S, () -> %s.toDrut())" expr path expr
  | Schema.List inner ->
    Printf.sprintf "Wire.encodeList(%s, %S, %s)" expr path
      (encode_fn ~depth:0 ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "Wire.encodeOptional(%s, %S, %s)" expr path
      (encode_fn ~depth:0 ~local inner)

let decode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "Wire.asString(%s, %S)" expr path
  | Schema.Primitive Schema.Int -> Printf.sprintf "Wire.asInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float -> Printf.sprintf "Wire.asFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool -> Printf.sprintf "Wire.asBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void -> Printf.sprintf "Wire.asNull(%s, %S)" expr path
  | Schema.Primitive Schema.Record -> Printf.sprintf "Wire.asRecord(%s, %S)" expr path
  | Schema.Reference qualified ->
    Printf.sprintf "%s.fromDrut(Wire.stringify(%s))" (reference_type ~local qualified) expr
  | Schema.List inner ->
    Printf.sprintf "Wire.decodeList(%s, %S, %s)" expr path
      (decode_fn ~depth:0 ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "Wire.decodeOptional(%s, %S, %s)" expr path
      (decode_fn ~depth:0 ~local inner)

let path_of ~module_name name = module_name ^ "." ^ name

let case_type_name (constructor : Schema.constructor) = class_name constructor.name

let struct_code ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = class_name message.Schema.name in
  let path = path_of ~module_name message.name in
  p "public record %s(\n" name;
  let count = List.length fields in
  List.iteri
    (fun index (field : Schema.field) ->
      p "        %s %s%s\n" (java_type ~local field.type_)
        (field_name field.name)
        (if index + 1 = count then "" else ","))
    fields;
  p ") {\n\n";
  p "    public String toDrut() {\n";
  p "        return Wire.stringify(encodeValue());\n";
  p "    }\n\n";
  p "    private Object encodeValue() {\n";
  if fields = [] then p "        return new java.util.ArrayList<>();\n"
  else begin
    p "        java.util.List<Object> out = new java.util.ArrayList<>();\n";
    List.iter
      (fun (field : Schema.field) ->
        p "        out.add(%s);\n"
          (encode_expr ~local (field_name field.name)
             (path ^ "." ^ field.name) field.type_))
      fields;
    p "        return out;\n"
  end;
  p "    }\n\n";
  p "    public static %s fromDrut(String text) {\n" name;
  p "        return decodeValue(Wire.parseText(text));\n";
  p "    }\n\n";
  p "    private static %s decodeValue(Object data) {\n" name;
  if fields = [] then begin
    p "        Wire.asArray(data, %S, 0);\n" path;
    p "        return new %s();\n" name
  end
  else begin
    p "        java.util.List<Object> arr = Wire.asArray(data, %S, %d);\n" path
      (List.length fields);
    p "        return new %s(\n" name;
    List.iteri
      (fun index (field : Schema.field) ->
        p "            %s%s\n"
          (decode_expr ~local (Printf.sprintf "arr.get(%d)" index)
             (path ^ "." ^ field.name) field.type_)
          (if index + 1 = count then "" else ","))
      fields;
    p "        );\n"
  end;
  p "    }\n";
  p "}\n";
  Buffer.contents buffer

let variant_code ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = class_name message.Schema.name in
  let path = path_of ~module_name message.name in
  p "public sealed interface %s {\n\n" name;
  p "    String toDrut();\n\n";
  p "    static %s fromDrut(String text) {\n" name;
  p "        return decodeValue(Wire.parseText(text));\n";
  p "    }\n\n";
  p "    private static %s decodeValue(Object data) {\n" name;
  p "        java.util.List<Object> arr = Wire.asArray(data, %S, 2);\n" path;
  p "        String tag = Wire.asString(arr.get(0), %S);\n" (path ^ "[0]");
  p "        switch (tag) {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "            case %S:\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "                Wire.asNull(arr.get(1), %S);\n" (path ^ "[1]");
         p "                return new %s();\n" (case_type_name constructor)
       | type_ ->
         p "                return new %s(%s);\n" (case_type_name constructor)
           (decode_expr ~local "arr.get(1)" (path ^ "[1]") type_)))
    constructors;
  p "            default:\n";
  p "                throw Wire.fail(\"UnknownVariantTag\", %S, \"unknown tag \" + tag);\n" path;
  p "        }\n";
  p "    }\n\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "    record %s(" (case_type_name constructor);
      (match constructor.payload with
       | Schema.Primitive Schema.Void -> ()
       | type_ -> p "%s value" (java_type ~local type_));
      p ") implements %s {\n\n" name;
      p "        public String toDrut() {\n";
      p "            return Wire.stringify(encodeValue());\n";
      p "        }\n\n";
      p "        private Object encodeValue() {\n";
      p "            java.util.List<Object> out = new java.util.ArrayList<>();\n";
      p "            out.add(%S);\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void -> p "            out.add(null);\n"
       | type_ ->
         p "            out.add(%s);\n"
           (encode_expr ~local "value" (path ^ ".value") type_));
      p "            return out;\n";
      p "        }\n";
      p "    }\n\n")
    constructors;
  p "}\n";
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
  Hashtbl.fold (fun name () acc -> name :: acc) modules [] |> List.sort String.compare

let indent text =
  String.split_on_char '\n' text
  |> List.map (fun line -> if line = "" then "" else "    " ^ line)
  |> String.concat "\n"

let module_code (module_ : Schema.module_) =
  let buffer = Buffer.create 2048 in
  let p fmt = Printf.bprintf buffer fmt in
  let name = outer_name module_.name in
  p "package generated_contracts;\n\n";
  p "public final class %s {\n\n" name;
  p "    private %s() {\n    }\n\n" name;
  Naming.topo_sort module_
  |> List.iter (fun message ->
      p "%s\n" (indent (message_code ~module_name:module_.name message)));
  p "}\n";
  Buffer.contents buffer

let generate ~modules : Kernel.artifact list =
  Hashtbl.clear outer_names;
  List.iter assign_outer_name modules;
  let module_artifacts =
    List.map
      (fun (module_ : Schema.module_) ->
        { Kernel.path =
            "java/src/main/java/generated_contracts/" ^ outer_name module_.name ^ ".java";
          contents = module_code module_ })
      modules
  in
  [ { Kernel.path = "java/pom.xml"; contents = pom };
    { Kernel.path = "java/src/main/java/generated_contracts/CyrografException.java";
      contents = exception_source };
    { Kernel.path = "java/src/main/java/generated_contracts/Wire.java";
      contents = wire_source } ]
  @ module_artifacts