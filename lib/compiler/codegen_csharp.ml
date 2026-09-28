(* C# generator for net10.0.

   Each source module becomes a namespace [GeneratedContracts.<Module>].
   Structures are sealed positional records; a variant is an abstract record
   with nested sealed record cases. The [Wire] runtime is internal and uses
   only System.Text.Json for the native Record representation. Message types
   expose exactly the two public conversions [ToDrut]/[FromDrut]. *)

module Schema = Cyrograf.Schema
module Naming = Naming

let wire_source =
  {j|using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;

namespace GeneratedContracts;

internal static class Wire
{
    internal abstract record Val;

    internal sealed record VString(string Value) : Val;

    internal sealed record VBool(bool Value) : Val;

    internal sealed record VNum(string Lexeme) : Val;

    internal sealed record VList(List<object?> Items) : Val;

    internal sealed record VObj(List<KeyValuePair<string, object?>> Entries) : Val;

    internal sealed record RawJson(JsonElement Element);

    private const long MaxSafeInt = 9007199254740991L;

    internal static CyrografException Fail(string code, string path, string message)
    {
        return new CyrografException(code, path, message);
    }

    internal static object? ParseText(string text)
    {
        if (text is null)
        {
            throw Fail("InvalidJson", "", "expected Wire text");
        }
        if (text.Length > 0 && text[0] == '\uFEFF')
        {
            throw Fail("InvalidJson", "", "a leading byte order mark is not valid Wire input");
        }
        Parser parser = new Parser(text);
        Val? value = parser.ParseValue();
        parser.SkipWhitespace();
        if (parser.Index != text.Length)
        {
            throw Fail("InvalidJson", "", "trailing characters after the value");
        }
        return value;
    }

    internal static string Stringify(object? value)
    {
        StringBuilder output = new StringBuilder();
        WriteValue(value, output);
        return output.ToString();
    }

    private static void WriteValue(object? value, StringBuilder output)
    {
        switch (value)
        {
            case null:
                output.Append("null");
                return;
            case RawJson raw:
                WriteRaw(raw.Element, output);
                return;
            case Val val:
                WriteVal(val, output);
                return;
            case string text:
                WriteString(text, output);
                return;
            case bool flag:
                output.Append(flag ? "true" : "false");
                return;
            case long integer:
                output.Append(integer.ToString(CultureInfo.InvariantCulture));
                return;
            case int integer:
                output.Append(integer.ToString(CultureInfo.InvariantCulture));
                return;
            case short integer:
                output.Append(integer.ToString(CultureInfo.InvariantCulture));
                return;
            case byte integer:
                output.Append(integer.ToString(CultureInfo.InvariantCulture));
                return;
            case double number:
                WriteDouble(number, output);
                return;
            case float number:
                WriteDouble((double)number, output);
                return;
            case List<object?> list:
                output.Append('[');
                for (int index = 0; index < list.Count; index++)
                {
                    if (index > 0)
                    {
                        output.Append(',');
                    }
                    WriteValue(list[index], output);
                }
                output.Append(']');
                return;
            default:
                throw Fail("InvalidJson", "", "unsupported value");
        }
    }

    private static void WriteRaw(JsonElement element, StringBuilder output)
    {
        CheckElement(element, "");
        output.Append(element.GetRawText());
    }

    private static void CheckElement(JsonElement element, string path)
    {
        switch (element.ValueKind)
        {
            case JsonValueKind.Undefined:
                throw Fail("TypeMismatch", path, "undefined JsonElement is not valid Wire input");
            case JsonValueKind.Object:
                foreach (JsonProperty property in element.EnumerateObject())
                {
                    CheckElement(property.Value, path + "." + property.Name);
                }
                return;
            case JsonValueKind.Array:
                int index = 0;
                foreach (JsonElement item in element.EnumerateArray())
                {
                    CheckElement(item, path + "[" + index + "]");
                    index++;
                }
                return;
            default:
                return;
        }
    }

    private static void WriteDouble(double value, StringBuilder output)
    {
        if (!double.IsFinite(value))
        {
            throw Fail("NonFiniteNumber", "", "non-finite number");
        }
        output.Append(value.ToString("R", CultureInfo.InvariantCulture));
    }

    private static void WriteVal(Val value, StringBuilder output)
    {
        switch (value)
        {
            case VString text:
                WriteString(text.Value, output);
                return;
            case VBool flag:
                output.Append(flag.Value ? "true" : "false");
                return;
            case VNum number:
                output.Append(number.Lexeme);
                return;
            case VList list:
                output.Append('[');
                for (int index = 0; index < list.Items.Count; index++)
                {
                    if (index > 0)
                    {
                        output.Append(',');
                    }
                    WriteValue(list.Items[index], output);
                }
                output.Append(']');
                return;
            case VObj obj:
                output.Append('{');
                for (int index = 0; index < obj.Entries.Count; index++)
                {
                    if (index > 0)
                    {
                        output.Append(',');
                    }
                    WriteString(obj.Entries[index].Key, output);
                    output.Append(':');
                    WriteValue(obj.Entries[index].Value, output);
                }
                output.Append('}');
                return;
            default:
                throw Fail("InvalidJson", "", "unsupported value");
        }
    }

    private static void WriteString(string value, StringBuilder output)
    {
        output.Append('"');
        for (int index = 0; index < value.Length; index++)
        {
            char character = value[index];
            switch (character)
            {
                case '"':
                    output.Append("\\\"");
                    break;
                case '\\':
                    output.Append("\\\\");
                    break;
                case '\b':
                    output.Append("\\b");
                    break;
                case '\f':
                    output.Append("\\f");
                    break;
                case '\n':
                    output.Append("\\n");
                    break;
                case '\r':
                    output.Append("\\r");
                    break;
                case '\t':
                    output.Append("\\t");
                    break;
                default:
                    if (character < 0x20)
                    {
                        output.Append("\\u");
                        output.Append(((int)character).ToString("x4", CultureInfo.InvariantCulture));
                    }
                    else if (char.IsHighSurrogate(character))
                    {
                        if (index + 1 >= value.Length || !char.IsLowSurrogate(value[index + 1]))
                        {
                            throw Fail("InvalidString", "", "string contains an unpaired surrogate");
                        }
                        output.Append(character);
                        output.Append(value[++index]);
                    }
                    else if (char.IsLowSurrogate(character))
                    {
                        throw Fail("InvalidString", "", "string contains an unpaired surrogate");
                    }
                    else
                    {
                        output.Append(character);
                    }
                    break;
            }
        }
        output.Append('"');
    }

    private sealed class Parser
    {
        private readonly string text;

        internal Parser(string text)
        {
            this.text = text;
        }

        internal int Index { get; private set; }

        internal void SkipWhitespace()
        {
            while (Index < text.Length)
            {
                char character = text[Index];
                if (character == ' ' || character == '\t' || character == '\n' || character == '\r')
                {
                    Index++;
                }
                else
                {
                    break;
                }
            }
        }

        internal Val? ParseValue()
        {
            SkipWhitespace();
            if (Index >= text.Length)
            {
                throw Fail("InvalidJson", "", "unexpected end of input");
            }
            char character = text[Index];
            switch (character)
            {
                case '{':
                    return ParseObject();
                case '[':
                    return ParseArray();
                case '"':
                    return new VString(ParseString());
                case 't':
                    Expect("true");
                    return new VBool(true);
                case 'f':
                    Expect("false");
                    return new VBool(false);
                case 'n':
                    Expect("null");
                    return null;
                default:
                    if (character == '-' || IsDigit(character))
                    {
                        return ParseNumber();
                    }
                    throw Fail("InvalidJson", "", "unexpected character");
            }
        }

        private void Expect(string word)
        {
            if (Index + word.Length > text.Length || string.CompareOrdinal(text, Index, word, 0, word.Length) != 0)
            {
                throw Fail("InvalidJson", "", "invalid literal");
            }
            Index += word.Length;
        }

        private Val? ParseObject()
        {
            Index++;
            List<KeyValuePair<string, object?>> entries = new List<KeyValuePair<string, object?>>();
            HashSet<string> keys = new HashSet<string>(StringComparer.Ordinal);
            SkipWhitespace();
            if (Index < text.Length && text[Index] == '}')
            {
                Index++;
                return new VObj(entries);
            }
            while (true)
            {
                SkipWhitespace();
                if (Index >= text.Length || text[Index] != '"')
                {
                    throw Fail("InvalidJson", "", "expected an object key");
                }
                string key = ParseString();
                if (!keys.Add(key))
                {
                    throw Fail("DuplicateKey", "", "duplicate object key " + key);
                }
                SkipWhitespace();
                if (Index >= text.Length || text[Index] != ':')
                {
                    throw Fail("InvalidJson", "", "expected a colon");
                }
                Index++;
                object? value = ParseValue();
                entries.Add(new KeyValuePair<string, object?>(key, value));
                SkipWhitespace();
                if (Index >= text.Length)
                {
                    throw Fail("InvalidJson", "", "unterminated object");
                }
                char character = text[Index];
                if (character == ',')
                {
                    Index++;
                    continue;
                }
                if (character == '}')
                {
                    Index++;
                    return new VObj(entries);
                }
                throw Fail("InvalidJson", "", "expected a comma or a closing brace");
            }
        }

        private VList ParseArray()
        {
            Index++;
            List<object?> items = new List<object?>();
            SkipWhitespace();
            if (Index < text.Length && text[Index] == ']')
            {
                Index++;
                return new VList(items);
            }
            while (true)
            {
                items.Add(ParseValue());
                SkipWhitespace();
                if (Index >= text.Length)
                {
                    throw Fail("InvalidJson", "", "unterminated array");
                }
                char character = text[Index];
                if (character == ',')
                {
                    Index++;
                    continue;
                }
                if (character == ']')
                {
                    Index++;
                    return new VList(items);
                }
                throw Fail("InvalidJson", "", "expected a comma or a closing bracket");
            }
        }

        private string ParseString()
        {
            Index++;
            StringBuilder output = new StringBuilder();
            while (true)
            {
                if (Index >= text.Length)
                {
                    throw Fail("InvalidJson", "", "unterminated string");
                }
                char character = text[Index++];
                if (character == '"')
                {
                    return output.ToString();
                }
                if (character < 0x20)
                {
                    throw Fail("InvalidJson", "", "unescaped control character in string");
                }
                if (character == '\\')
                {
                    if (Index >= text.Length)
                    {
                        throw Fail("InvalidJson", "", "unterminated escape in string");
                    }
                    char escape = text[Index++];
                    switch (escape)
                    {
                        case '"':
                            output.Append('"');
                            break;
                        case '\\':
                            output.Append('\\');
                            break;
                        case '/':
                            output.Append('/');
                            break;
                        case 'b':
                            output.Append('\b');
                            break;
                        case 'f':
                            output.Append('\f');
                            break;
                        case 'n':
                            output.Append('\n');
                            break;
                        case 'r':
                            output.Append('\r');
                            break;
                        case 't':
                            output.Append('\t');
                            break;
                        case 'u':
                            int code = ReadHex4();
                            if (code >= 0xD800 && code <= 0xDBFF)
                            {
                                if (Index + 1 >= text.Length || text[Index] != '\\' || text[Index + 1] != 'u')
                                {
                                    throw Fail("InvalidJson", "", "unpaired surrogate");
                                }
                                Index += 2;
                                int low = ReadHex4();
                                if (low < 0xDC00 || low > 0xDFFF)
                                {
                                    throw Fail("InvalidJson", "", "unpaired surrogate");
                                }
                                output.Append(char.ConvertFromUtf32(char.ConvertToUtf32((char)code, (char)low)));
                            }
                            else if (code >= 0xDC00 && code <= 0xDFFF)
                            {
                                throw Fail("InvalidJson", "", "unpaired surrogate");
                            }
                            else
                            {
                                output.Append((char)code);
                            }
                            break;
                        default:
                            throw Fail("InvalidJson", "", "invalid escape in string");
                    }
                    continue;
                }
                if (char.IsHighSurrogate(character))
                {
                    if (Index >= text.Length)
                    {
                        throw Fail("InvalidJson", "", "unpaired surrogate");
                    }
                    char low = text[Index];
                    if (!char.IsLowSurrogate(low))
                    {
                        throw Fail("InvalidJson", "", "unpaired surrogate");
                    }
                    output.Append(character);
                    output.Append(low);
                    Index++;
                    continue;
                }
                if (char.IsLowSurrogate(character))
                {
                    throw Fail("InvalidJson", "", "unpaired surrogate");
                }
                output.Append(character);
            }
        }

        private int ReadHex4()
        {
            if (Index + 4 > text.Length)
            {
                throw Fail("InvalidJson", "", "truncated unicode escape");
            }
            int value = 0;
            for (int offset = 0; offset < 4; offset++)
            {
                int digit = HexValue(text[Index++]);
                if (digit < 0)
                {
                    throw Fail("InvalidJson", "", "invalid unicode escape");
                }
                value = (value << 4) | digit;
            }
            return value;
        }

        private VNum ParseNumber()
        {
            int start = Index;
            if (text[Index] == '-')
            {
                Index++;
            }
            if (Index >= text.Length || !IsDigit(text[Index]))
            {
                throw Fail("InvalidJson", "", "invalid number");
            }
            if (text[Index] == '0')
            {
                Index++;
            }
            else
            {
                while (Index < text.Length && IsDigit(text[Index]))
                {
                    Index++;
                }
            }
            if (Index < text.Length && text[Index] == '.')
            {
                Index++;
                if (Index >= text.Length || !IsDigit(text[Index]))
                {
                    throw Fail("InvalidJson", "", "invalid number");
                }
                while (Index < text.Length && IsDigit(text[Index]))
                {
                    Index++;
                }
            }
            if (Index < text.Length && (text[Index] == 'e' || text[Index] == 'E'))
            {
                Index++;
                if (Index < text.Length && (text[Index] == '+' || text[Index] == '-'))
                {
                    Index++;
                }
                if (Index >= text.Length || !IsDigit(text[Index]))
                {
                    throw Fail("InvalidJson", "", "invalid number");
                }
                while (Index < text.Length && IsDigit(text[Index]))
                {
                    Index++;
                }
            }
            return new VNum(text.Substring(start, Index - start));
        }

        private static bool IsDigit(char character)
        {
            return character >= '0' && character <= '9';
        }

        private static int HexValue(char character)
        {
            if (character >= '0' && character <= '9')
            {
                return character - '0';
            }
            if (character >= 'a' && character <= 'f')
            {
                return character - 'a' + 10;
            }
            if (character >= 'A' && character <= 'F')
            {
                return character - 'A' + 10;
            }
            return -1;
        }
    }

    internal static List<object?> AsArray(object? data, string path, int length)
    {
        if (data is not VList list)
        {
            throw Fail("TypeMismatch", path, "expected an array");
        }
        if (length >= 0 && list.Items.Count != length)
        {
            throw Fail("UnexpectedLength", path,
                "expected " + length + " element(s) but found " + list.Items.Count);
        }
        return list.Items;
    }

    internal static string AsString(object? data, string path)
    {
        if (data is VString text)
        {
            return text.Value;
        }
        throw Fail("TypeMismatch", path, "expected a string");
    }

    internal static long AsInt(object? data, string path)
    {
        if (data is VNum number)
        {
            return ExactInteger(number.Lexeme, path);
        }
        throw Fail("TypeMismatch", path, "expected an integer");
    }

    internal static double AsFloat(object? data, string path)
    {
        if (data is VNum number)
        {
            double value = double.Parse(number.Lexeme, NumberStyles.Float, CultureInfo.InvariantCulture);
            if (!double.IsFinite(value))
            {
                throw Fail("InvalidFloat", path, "non-finite number");
            }
            return value;
        }
        throw Fail("TypeMismatch", path, "expected a number");
    }

    internal static bool AsBool(object? data, string path)
    {
        if (data is VBool flag)
        {
            return flag.Value;
        }
        throw Fail("TypeMismatch", path, "expected a boolean");
    }

    internal static CyrografUnit DecodeVoid(object? data, string path)
    {
        if (data is not null)
        {
            throw Fail("TypeMismatch", path, "expected null");
        }
        return CyrografUnit.Value;
    }

    internal static Dictionary<string, JsonElement> AsRecord(object? data, string path)
    {
        if (data is not VObj obj)
        {
            throw Fail("TypeMismatch", path, "expected an object");
        }
        CheckRecordNumbers(obj, path);
        string text = Stringify(obj);
        using JsonDocument document = JsonDocument.Parse(text);
        JsonElement root = document.RootElement.Clone();
        Dictionary<string, JsonElement> result = new Dictionary<string, JsonElement>();
        foreach (JsonProperty property in root.EnumerateObject())
        {
            result[property.Name] = property.Value;
        }
        return result;
    }

    private static void CheckRecordNumbers(object? value, string path)
    {
        switch (value)
        {
            case VNum number:
                if (!double.TryParse(number.Lexeme, NumberStyles.Float, CultureInfo.InvariantCulture, out double parsed)
                    || !double.IsFinite(parsed))
                {
                    throw Fail("NonFiniteNumber", path, "non-finite number");
                }
                return;
            case VList list:
                for (int index = 0; index < list.Items.Count; index++)
                {
                    CheckRecordNumbers(list.Items[index], path + "[" + index + "]");
                }
                return;
            case VObj obj:
                foreach (KeyValuePair<string, object?> entry in obj.Entries)
                {
                    CheckRecordNumbers(entry.Value, path + "." + entry.Key);
                }
                return;
            default:
                return;
        }
    }

    private static long ExactInteger(string lexeme, string path)
    {
        int length = lexeme.Length;
        if (length == 0)
        {
            throw Fail("InvalidInt", path, "expected an exact integer");
        }
        bool negative = lexeme[0] == '-';
        int start = negative ? 1 : 0;
        int integerEnd = start;
        while (integerEnd < length && IsAsciiDigit(lexeme[integerEnd]))
        {
            integerEnd++;
        }
        string integerDigits = lexeme.Substring(start, integerEnd - start);
        string fractionDigits = "";
        int afterFraction = integerEnd;
        if (afterFraction < length && lexeme[afterFraction] == '.')
        {
            int stop = afterFraction + 1;
            while (stop < length && IsAsciiDigit(lexeme[stop]))
            {
                stop++;
            }
            fractionDigits = lexeme.Substring(afterFraction + 1, stop - (afterFraction + 1));
            afterFraction = stop;
        }
        int exponent = 0;
        if (afterFraction < length && (lexeme[afterFraction] == 'e' || lexeme[afterFraction] == 'E'))
        {
            int position = afterFraction + 1;
            int sign = 1;
            if (position < length && (lexeme[position] == '+' || lexeme[position] == '-'))
            {
                if (lexeme[position] == '-')
                {
                    sign = -1;
                }
                position++;
            }
            int digitStart = position;
            int value = 0;
            while (position < length && IsAsciiDigit(lexeme[position]))
            {
                value = value * 10 + (lexeme[position] - '0');
                if (value > 1000000)
                {
                    throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
                }
                position++;
            }
            if (position == digitStart)
            {
                throw Fail("InvalidInt", path, "expected an exact integer");
            }
            exponent = sign * value;
        }
        string mantissa = integerDigits + fractionDigits;
        int from = 0;
        while (from < mantissa.Length && mantissa[from] == '0')
        {
            from++;
        }
        string cleaned = mantissa.Substring(from);
        if (cleaned.Length == 0)
        {
            return 0;
        }
        int shift = exponent - fractionDigits.Length;
        long magnitude;
        if (shift >= 0)
        {
            if (cleaned.Length + shift > 16)
            {
                throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
            }
            magnitude = ParseMagnitude(cleaned + new string('0', shift), path);
        }
        else
        {
            int drop = -shift;
            if (drop >= cleaned.Length)
            {
                if (!AllZeros(cleaned))
                {
                    throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
                }
                magnitude = 0;
            }
            else
            {
                string tail = cleaned.Substring(cleaned.Length - drop);
                if (!AllZeros(tail))
                {
                    throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
                }
                magnitude = ParseMagnitude(cleaned.Substring(0, cleaned.Length - drop), path);
            }
        }
        long signed = negative ? -magnitude : magnitude;
        if (signed < -MaxSafeInt || signed > MaxSafeInt)
        {
            throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
        }
        return signed;
    }

    private static bool AllZeros(string value)
    {
        for (int index = 0; index < value.Length; index++)
        {
            if (value[index] != '0')
            {
                return false;
            }
        }
        return true;
    }

    private static long ParseMagnitude(string digits, string path)
    {
        if (!long.TryParse(digits, NumberStyles.None, CultureInfo.InvariantCulture, out long value))
        {
            throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
        }
        return value;
    }

    private static bool IsAsciiDigit(char character)
    {
        return character >= '0' && character <= '9';
    }

    private static void CheckUnicode(string value, string path)
    {
        for (int index = 0; index < value.Length; index++)
        {
            char character = value[index];
            if (char.IsHighSurrogate(character))
            {
                if (index + 1 >= value.Length || !char.IsLowSurrogate(value[index + 1]))
                {
                    throw Fail("InvalidString", path, "string contains an unpaired surrogate");
                }
                index++;
            }
            else if (char.IsLowSurrogate(character))
            {
                throw Fail("InvalidString", path, "string contains an unpaired surrogate");
            }
        }
    }

    internal static object? EncodeString(string value, string path)
    {
        if (value is null)
        {
            throw Fail("TypeMismatch", path, "expected a string");
        }
        CheckUnicode(value, path);
        return value;
    }

    internal static object? EncodeInt(long value, string path)
    {
        if (value < -MaxSafeInt || value > MaxSafeInt)
        {
            throw Fail("IntOutOfRange", path, "integer outside the Wire v1 range");
        }
        return value;
    }

    internal static object? EncodeFloat(double value, string path)
    {
        if (!double.IsFinite(value))
        {
            throw Fail("InvalidFloat", path, "non-finite number");
        }
        return value;
    }

    internal static object? EncodeBool(bool value, string path)
    {
        return value;
    }

    internal static object? EncodeVoid(CyrografUnit value, string path)
    {
        return null;
    }

    internal static object? EncodeRecord(Dictionary<string, JsonElement> value, string path)
    {
        if (value is null)
        {
            throw Fail("TypeMismatch", path, "expected an object");
        }
        using MemoryStream stream = new MemoryStream();
        using (Utf8JsonWriter writer = new Utf8JsonWriter(stream))
        {
            writer.WriteStartObject();
            foreach (KeyValuePair<string, JsonElement> pair in value)
            {
                if (pair.Key is null)
                {
                    throw Fail("TypeMismatch", path, "object keys must be strings");
                }
                writer.WritePropertyName(pair.Key);
                CheckElement(pair.Value, path + "." + pair.Key);
                pair.Value.WriteTo(writer);
            }
            writer.WriteEndObject();
        }
        using JsonDocument document = JsonDocument.Parse(stream.ToArray());
        return new RawJson(document.RootElement.Clone());
    }

    internal static object? Reference(object? value, string path, Func<string> text)
    {
        if (value is null)
        {
            throw Fail("TypeMismatch", path, "expected a message");
        }
        return ParseText(text());
    }

    internal static object? EncodeList<T>(IReadOnlyList<T> items, string path, Func<T, string, object?> encode)
    {
        if (items is null)
        {
            throw Fail("TypeMismatch", path, "expected an array");
        }
        List<object?> output = new List<object?>(items.Count);
        for (int index = 0; index < items.Count; index++)
        {
            output.Add(encode(items[index], path + "[" + index + "]"));
        }
        return output;
    }

    internal static List<T> DecodeList<T>(object? data, string path, Func<object?, string, T> decode)
    {
        List<object?> array = AsArray(data, path, -1);
        List<T> output = new List<T>(array.Count);
        for (int index = 0; index < array.Count; index++)
        {
            output.Add(decode(array[index], path + "[" + index + "]"));
        }
        return output;
    }
}
|j}

let exception_source =
  {j|using System;

namespace GeneratedContracts;

public class CyrografException : Exception
{
    public string Code { get; }

    public string Path { get; }

    public CyrografException(string code, string path, string message)
        : base(message)
    {
        Code = code;
        Path = path;
    }
}
|j}

let unit_source =
  {j|namespace GeneratedContracts;

public readonly struct CyrografUnit
{
    public static CyrografUnit Value
    {
        get
        {
            return default;
        }
    }
}
|j}

let project =
  {j|<Project Sdk="Microsoft.NET.Sdk">
  <PropertyGroup>
    <TargetFramework>net10.0</TargetFramework>
    <Nullable>enable</Nullable>
    <ImplicitUsings>disable</ImplicitUsings>
    <LangVersion>latest</LangVersion>
    <AssemblyName>GeneratedContracts</AssemblyName>
    <RootNamespace>GeneratedContracts</RootNamespace>
    <GenerateDocumentationFile>false</GenerateDocumentationFile>
  </PropertyGroup>
</Project>
|j}

let type_name = Naming.csharp_type_name
let field_name = Naming.csharp_field

let reference_type ~local (qualified : Schema.qualified) =
  let message = type_name qualified.message_name in
  if qualified.module_name = local then message
  else "GeneratedContracts." ^ type_name qualified.module_name ^ "." ^ message

let rec csharp_type ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) -> "string"
  | Schema.Primitive Schema.Int -> "long"
  | Schema.Primitive Schema.Float -> "double"
  | Schema.Primitive Schema.Bool -> "bool"
  | Schema.Primitive Schema.Void -> "CyrografUnit"
  | Schema.Primitive Schema.Record -> "Dictionary<string, JsonElement>"
  | Schema.Reference qualified -> reference_type ~local qualified
  | Schema.List inner -> "List<" ^ csharp_type ~local inner ^ ">"
  | Schema.Optional inner -> csharp_nullable ~local inner

and csharp_nullable ~local (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive Schema.Int -> "long?"
  | Schema.Primitive Schema.Float -> "double?"
  | Schema.Primitive Schema.Bool -> "bool?"
  | Schema.Primitive Schema.Void -> "CyrografUnit?"
  | _ -> csharp_type ~local type_ ^ "?"

let value_type (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.Int | Schema.Float | Schema.Bool | Schema.Void) -> true
  | _ -> false

let inline ~depth body = Printf.sprintf "(v%d, p%d) => %s" depth depth body

let indent_block depth body =
  let pad = String.make depth ' ' in
  String.split_on_char '\n' body
  |> List.map (fun line -> if line = "" then "" else pad ^ line)
  |> String.concat "\n"

let rec encode_fn ~depth ~local (type_ : Schema.type_) =
  let v = Printf.sprintf "v%d" depth in
  let p = Printf.sprintf "p%d" depth in
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    inline ~depth (Printf.sprintf "Wire.EncodeString((string)%s, %s)" v p)
  | Schema.Primitive Schema.Int ->
    inline ~depth (Printf.sprintf "Wire.EncodeInt((long)%s, %s)" v p)
  | Schema.Primitive Schema.Float ->
    inline ~depth (Printf.sprintf "Wire.EncodeFloat((double)%s, %s)" v p)
  | Schema.Primitive Schema.Bool ->
    inline ~depth (Printf.sprintf "Wire.EncodeBool((bool)%s, %s)" v p)
  | Schema.Primitive Schema.Void ->
    inline ~depth (Printf.sprintf "Wire.EncodeVoid((CyrografUnit)%s, %s)" v p)
  | Schema.Primitive Schema.Record ->
    inline ~depth (Printf.sprintf "Wire.EncodeRecord((Dictionary<string, JsonElement>)%s, %s)" v p)
  | Schema.Reference _ ->
    inline ~depth
      (Printf.sprintf "Wire.Reference(%s, %s, () => ((%s)%s).ToDrut())" v p
         (csharp_type ~local type_) v)
  | Schema.List inner ->
    inline ~depth
      (Printf.sprintf "Wire.EncodeList((List<%s>)%s, %s, %s)"
         (csharp_type ~local inner) v p (encode_fn ~depth:(depth + 1) ~local inner))
  | Schema.Optional inner ->
    if value_type inner then
      inline ~depth
        (Printf.sprintf "%s is null ? null : %s" v
           (encode_expr ~local
              (Printf.sprintf "((%s)%s).Value" (csharp_nullable ~local inner) v)
              p inner))
    else
      inline ~depth
        (Printf.sprintf "%s is null ? null : %s" v
           (encode_expr ~local (Printf.sprintf "((%s)%s)" (csharp_type ~local inner) v) p inner))

and encode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "Wire.EncodeString(%s, %S)" expr path
  | Schema.Primitive Schema.Int -> Printf.sprintf "Wire.EncodeInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float -> Printf.sprintf "Wire.EncodeFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool -> Printf.sprintf "Wire.EncodeBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void -> Printf.sprintf "Wire.EncodeVoid(%s, %S)" expr path
  | Schema.Primitive Schema.Record ->
    Printf.sprintf "Wire.EncodeRecord(%s, %S)" expr path
  | Schema.Reference _ ->
    Printf.sprintf "Wire.Reference(%s, %S, () => %s.ToDrut())" expr path expr
  | Schema.List inner ->
    Printf.sprintf "Wire.EncodeList(%s, %S, %s)" expr path
      (encode_fn ~depth:0 ~local inner)
  | Schema.Optional inner ->
    if value_type inner then
      Printf.sprintf "%s is null ? null : %s" expr
        (encode_expr ~local (expr ^ ".Value") path inner)
    else Printf.sprintf "%s is null ? null : %s" expr (encode_expr ~local expr path inner)

let rec decode_fn ~depth ~local (type_ : Schema.type_) =
  let v = Printf.sprintf "v%d" depth in
  let p = Printf.sprintf "p%d" depth in
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    inline ~depth (Printf.sprintf "Wire.AsString(%s, %s)" v p)
  | Schema.Primitive Schema.Int -> inline ~depth (Printf.sprintf "Wire.AsInt(%s, %s)" v p)
  | Schema.Primitive Schema.Float -> inline ~depth (Printf.sprintf "Wire.AsFloat(%s, %s)" v p)
  | Schema.Primitive Schema.Bool -> inline ~depth (Printf.sprintf "Wire.AsBool(%s, %s)" v p)
  | Schema.Primitive Schema.Void -> inline ~depth (Printf.sprintf "Wire.DecodeVoid(%s, %s)" v p)
  | Schema.Primitive Schema.Record -> inline ~depth (Printf.sprintf "Wire.AsRecord(%s, %s)" v p)
  | Schema.Reference qualified ->
    inline ~depth
      (Printf.sprintf "%s.FromDrut(Wire.Stringify(%s))" (reference_type ~local qualified) v)
  | Schema.List inner ->
    inline ~depth
      (Printf.sprintf "Wire.DecodeList(%s, %s, %s)" v p
         (decode_fn ~depth:(depth + 1) ~local inner))
  | Schema.Optional inner ->
    inline ~depth
      (Printf.sprintf "%s is null ? default(%s) : %s" v (csharp_nullable ~local inner)
         (decode_expr ~local v p inner))

and decode_expr ~local expr path (type_ : Schema.type_) =
  match type_ with
  | Schema.Primitive (Schema.String | Schema.Date) ->
    Printf.sprintf "Wire.AsString(%s, %S)" expr path
  | Schema.Primitive Schema.Int -> Printf.sprintf "Wire.AsInt(%s, %S)" expr path
  | Schema.Primitive Schema.Float -> Printf.sprintf "Wire.AsFloat(%s, %S)" expr path
  | Schema.Primitive Schema.Bool -> Printf.sprintf "Wire.AsBool(%s, %S)" expr path
  | Schema.Primitive Schema.Void -> Printf.sprintf "Wire.DecodeVoid(%s, %S)" expr path
  | Schema.Primitive Schema.Record -> Printf.sprintf "Wire.AsRecord(%s, %S)" expr path
  | Schema.Reference qualified ->
    Printf.sprintf "%s.FromDrut(Wire.Stringify(%s))" (reference_type ~local qualified) expr
  | Schema.List inner ->
    Printf.sprintf "Wire.DecodeList(%s, %S, %s)" expr path
      (decode_fn ~depth:0 ~local inner)
  | Schema.Optional inner ->
    Printf.sprintf "%s is null ? default(%s) : %s" expr (csharp_nullable ~local inner)
      (decode_expr ~local expr path inner)

let path_of ~module_name name = module_name ^ "." ^ name

let struct_code ~module_name (message : Schema.message) fields =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = type_name message.Schema.name in
  let path = path_of ~module_name message.name in
  let count = List.length fields in
  if fields = [] then p "public sealed record %s\n{\n" name
  else begin
    p "public sealed record %s(\n" name;
    List.iteri
      (fun index (field : Schema.field) ->
        p "    %s %s%s\n" (csharp_type ~local field.type_) (field_name field.name)
          (if index + 1 = count then "" else ","))
      fields;
    p ")\n{\n"
  end;
  p "    public string ToDrut()\n    {\n";
  p "        return Wire.Stringify(EncodeValue());\n";
  p "    }\n\n";
  p "    private List<object?> EncodeValue()\n    {\n";
  p "        List<object?> out_ = new List<object?>();\n";
  List.iter
    (fun (field : Schema.field) ->
      p "        out_.Add(%s);\n"
        (encode_expr ~local (field_name field.name) (path ^ "." ^ field.name) field.type_))
    fields;
  p "        return out_;\n";
  p "    }\n\n";
  p "    public static %s FromDrut(string text)\n    {\n" name;
  p "        return DecodeValue(Wire.ParseText(text));\n";
  p "    }\n\n";
  p "    private static %s DecodeValue(object? data)\n    {\n" name;
  if fields = [] then begin
    p "        Wire.AsArray(data, %S, 0);\n" path;
    p "        return new %s();\n" name
  end
  else begin
    p "        List<object?> arr = Wire.AsArray(data, %S, %d);\n" path count;
    p "        return new %s(\n" name;
    List.iteri
      (fun index (field : Schema.field) ->
        p "            %s%s\n"
          (decode_expr ~local (Printf.sprintf "arr[%d]" index) (path ^ "." ^ field.name)
             field.type_)
          (if index + 1 = count then "" else ","))
      fields;
    p "        );\n"
  end;
  p "    }\n";
  p "}\n";
  Buffer.contents buffer

let case_name (constructor : Schema.constructor) = type_name constructor.name

let variant_payload_type ~local (constructor : Schema.constructor) =
  match constructor.payload with
  | Schema.Primitive Schema.Void -> None
  | type_ -> Some (csharp_type ~local type_)

let variant_code ~module_name (message : Schema.message) constructors =
  let buffer = Buffer.create 1024 in
  let p fmt = Printf.bprintf buffer fmt in
  let local = module_name in
  let name = type_name message.Schema.name in
  let path = path_of ~module_name message.name in
  p "public abstract record %s\n{\n" name;
  p "    public abstract string ToDrut();\n\n";
  p "    public static %s FromDrut(string text)\n    {\n" name;
  p "        return DecodeValue(Wire.ParseText(text));\n";
  p "    }\n\n";
  p "    private static %s DecodeValue(object? data)\n    {\n" name;
  p "        List<object?> arr = Wire.AsArray(data, %S, 2);\n" path;
  p "        string tag = Wire.AsString(arr[0], %S);\n" (path ^ "[0]");
  p "        switch (tag)\n        {\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      p "            case %S:\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void ->
         p "                Wire.DecodeVoid(arr[1], %S);\n" (path ^ "[1]");
         p "                return new %s();\n" (case_name constructor)
       | type_ ->
         p "                return new %s(%s);\n" (case_name constructor)
           (decode_expr ~local "arr[1]" (path ^ "[1]") type_)))
    constructors;
  p "            default:\n";
  p "                throw Wire.Fail(\"UnknownVariantTag\", %S, \"unknown tag \" + tag);\n" path;
  p "        }\n";
  p "    }\n\n";
  List.iter
    (fun (constructor : Schema.constructor) ->
      let case = case_name constructor in
      (match variant_payload_type ~local constructor with
       | Some payload -> p "    public sealed record %s(%s Value) : %s\n" case payload name
       | None -> p "    public sealed record %s : %s\n" case name);
      p "    {\n";
      p "        public override string ToDrut()\n        {\n";
      p "            return Wire.Stringify(EncodeValue());\n";
      p "        }\n\n";
      p "        private List<object?> EncodeValue()\n        {\n";
      p "            List<object?> out_ = new List<object?>();\n";
      p "            out_.Add(%S);\n" constructor.name;
      (match constructor.payload with
       | Schema.Primitive Schema.Void -> p "            out_.Add(null);\n"
       | type_ ->
         p "            out_.Add(%s);\n"
           (encode_expr ~local "Value" (path ^ ".Value") type_));
      p "            return out_;\n";
      p "        }\n";
      p "    }\n\n")
    constructors;
  p "}\n";
  Buffer.contents buffer

let message_code ~module_name (message : Schema.message) =
  match message.kind with
  | Schema.Struct fields -> struct_code ~module_name message fields
  | Schema.Variant constructors -> variant_code ~module_name message constructors

let module_code (module_ : Schema.module_) =
  let buffer = Buffer.create 2048 in
  let p fmt = Printf.bprintf buffer fmt in
  p "using System.Collections.Generic;\n";
  p "using System.Text.Json;\n\n";
  p "namespace GeneratedContracts.%s;\n\n" (type_name module_.name);
  let messages = Naming.topo_sort module_ in
  List.iteri
    (fun index message ->
      if index > 0 then p "\n";
      p "%s" (message_code ~module_name:module_.name message))
    messages;
  Buffer.contents buffer

let generate ~modules : Kernel.artifact list =
  let module_artifacts =
    List.map
      (fun (module_ : Schema.module_) ->
        { Kernel.path =
            "csharp/GeneratedContracts." ^ type_name module_.name ^ ".cs";
          contents = module_code module_ })
      modules
  in
  [ { Kernel.path = "csharp/GeneratedContracts.csproj"; contents = project };
    { Kernel.path = "csharp/GeneratedContracts.CyrografException.cs";
      contents = exception_source };
    { Kernel.path = "csharp/GeneratedContracts.CyrografUnit.cs"; contents = unit_source };
    { Kernel.path = "csharp/GeneratedContracts.Wire.cs"; contents = wire_source } ]
  @ module_artifacts