using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using GeneratedContracts;

internal static class Interop
{
    private static readonly Dictionary<string, Func<string, string>> Roundtrip = new()
    {
        ["Orders.ReserveRequest"] = text => GeneratedContracts.Orders.ReserveRequest.FromDrut(text).ToDrut(),
        ["Orders.Reservation"] = text => GeneratedContracts.Orders.Reservation.FromDrut(text).ToDrut(),
        ["Orders.Problem"] = text => GeneratedContracts.Orders.Problem.FromDrut(text).ToDrut(),
        ["Orders.ReserveResponse"] = text => GeneratedContracts.Orders.ReserveResponse.FromDrut(text).ToDrut(),
        ["Orders.ReservationBatch"] = text => GeneratedContracts.Orders.ReservationBatch.FromDrut(text).ToDrut(),
        ["Orders.Guard"] = text => GeneratedContracts.Orders.Guard.FromDrut(text).ToDrut(),
        ["Orders.ListBox"] = text => GeneratedContracts.Orders.ListBox.FromDrut(text).ToDrut(),
        ["Orders.ResponseBox"] = text => GeneratedContracts.Orders.ResponseBox.FromDrut(text).ToDrut(),
        ["Orders.Scalars"] = text => GeneratedContracts.Orders.Scalars.FromDrut(text).ToDrut(),
        ["Common.UserCtx"] = text => GeneratedContracts.Common.UserCtx.FromDrut(text).ToDrut(),
        ["Common.Wrapper"] = text => GeneratedContracts.Common.Wrapper.FromDrut(text).ToDrut(),
        ["Common.Blob"] = text => GeneratedContracts.Common.Blob.FromDrut(text).ToDrut(),
        ["Common.Empty"] = text => GeneratedContracts.Common.Empty.FromDrut(text).ToDrut(),
        ["Common.VoidBox"] = text => GeneratedContracts.Common.VoidBox.FromDrut(text).ToDrut(),
    };

    private static readonly HashSet<string> Primitives = new(StringComparer.Ordinal)
    {
        "void", "int", "float", "bool", "string", "date", "record",
    };

    internal static void Run(string[] arguments)
    {
        switch (arguments[0])
        {
            case "check":
                Check(arguments[1], arguments[2]);
                break;
            case "verify":
                Verify(arguments[1]);
                break;
            case "invalid":
                Invalid(arguments[1]);
                break;
            case "drut":
                Drut(arguments[1], arguments[2], arguments[3]);
                break;
            case "optional":
                Optional();
                break;
            default:
                Fail("unknown interop mode " + arguments[0]);
                break;
        }
    }

    [DoesNotReturn]
    internal static void Fail(string message)
    {
        Console.Error.WriteLine("FAIL: " + message);
        Environment.Exit(1);
    }

    private static JsonNode Load(string path)
    {
        return JsonNode.Parse(File.ReadAllText(path, Encoding.UTF8))!;
    }

    private static string RoundtripEntry(JsonObject entry)
    {
        string type = entry["type"]!.GetValue<string>();
        if (!Roundtrip.TryGetValue(type, out Func<string, string>? ops))
        {
            Fail("unknown type " + type);
        }
        return ops(entry["wire"]!.GetValue<string>());
    }

    private static void Check(string inputPath, string outputPath)
    {
        JsonArray entries = Load(inputPath)!.AsArray();
        JsonArray results = new();
        foreach (JsonNode? raw in entries)
        {
            JsonObject entry = raw!.AsObject();
            string id = entry["id"]!.GetValue<string>();
            string type = entry["type"]!.GetValue<string>();
            string reencoded = RoundtripEntry(entry);
            bool semantic = entry["semantic"]?.GetValue<bool>() ?? false;
            bool matches = semantic
                ? NodeEquals(JsonNode.Parse(reencoded), JsonNode.Parse(entry["wire"]!.GetValue<string>()))
                : reencoded == entry["wire"]!.GetValue<string>();
            if (!matches)
            {
                Fail(id + " (" + type + "): " + reencoded + " != " + entry["wire"]!.GetValue<string>());
            }
            JsonObject result = new() { ["id"] = id, ["type"] = type, ["wire"] = reencoded };
            if (semantic)
            {
                result["semantic"] = true;
            }
            results.Add(result);
        }
        File.WriteAllText(outputPath, results.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine("csharp verified " + entries.Count + " fixture(s)");
    }

    private static void Verify(string inputPath)
    {
        JsonArray entries = Load(inputPath)!.AsArray();
        foreach (JsonNode? raw in entries)
        {
            JsonObject entry = raw!.AsObject();
            string reencoded = RoundtripEntry(entry);
            if (!NodeEquals(JsonNode.Parse(reencoded), JsonNode.Parse(entry["wire"]!.GetValue<string>())))
            {
                Fail(entry["id"] + " (" + entry["type"] + "): " + reencoded
                    + " != " + entry["wire"]!.GetValue<string>());
            }
        }
        Console.WriteLine("csharp decoded " + entries.Count + " message(s) from peer");
    }

    private static void Invalid(string inputPath)
    {
        JsonArray entries = Load(inputPath)!.AsArray();
        foreach (JsonNode? raw in entries)
        {
            JsonObject entry = raw!.AsObject();
            try
            {
                RoundtripEntry(entry);
            }
            catch (CyrografException)
            {
                continue;
            }
            Fail(entry["id"] + " (" + entry["type"] + "): invalid wire accepted");
        }
        Console.WriteLine("csharp rejected " + entries.Count + " invalid message(s)");
    }

    private static void Optional()
    {
        Expect("absent string",
            new GeneratedContracts.Orders.ReserveRequest("o1", 2, null).ToDrut(),
            "[\"o1\",2,null]");
        Expect("present empty string",
            new GeneratedContracts.Orders.ReserveRequest("o1", 2, "").ToDrut(),
            "[\"o1\",2,\"\"]");
        if (GeneratedContracts.Orders.ReserveRequest.FromDrut("[\"o1\",2,null]").Note is not null)
        {
            Fail("decoded absent string is present");
        }
        if (!(GeneratedContracts.Orders.ReserveRequest.FromDrut("[\"o1\",2,\"\"]").Note == ""))
        {
            Fail("decoded empty string is not present empty");
        }

        string absentList = new GeneratedContracts.Orders.ListBox(null).ToDrut();
        Expect("absent list", absentList, "[null]");
        string emptyList = new GeneratedContracts.Orders.ListBox(new List<GeneratedContracts.Orders.Reservation>()).ToDrut();
        Expect("empty list", emptyList, "[[]]");
        if (absentList == emptyList)
        {
            Fail("empty optional and present empty list encode identically");
        }
        if (GeneratedContracts.Orders.ListBox.FromDrut(emptyList).Items is not { Count: 0 })
        {
            Fail("decoded empty list is not a present empty list");
        }

        string absentVariant = new GeneratedContracts.Orders.ResponseBox(null).ToDrut();
        Expect("absent variant", absentVariant, "[null]");
        string presentVariant = new GeneratedContracts.Orders.ResponseBox(
            new GeneratedContracts.Orders.ReserveResponse.Unavailable()).ToDrut();
        Expect("present void variant", presentVariant, "[[\"Unavailable\",null]]");

        ExpectError("wrong required type",
            () => GeneratedContracts.Orders.ReserveRequest.FromDrut("[\"o1\",\"x\",null]"));
        ExpectError("null required reference",
            () => new GeneratedContracts.Common.Wrapper(null!, null).ToDrut());
        ExpectError("null required string",
            () => new GeneratedContracts.Orders.ReserveRequest(null!, 2, null).ToDrut());
        Console.WriteLine("csharp optional checks passed");
    }

    private static void Expect(string label, string got, string want)
    {
        if (got != want)
        {
            Fail(label + ": " + got + " != " + want);
        }
    }

    private static void ExpectError(string label, Action call)
    {
        try
        {
            call();
        }
        catch (CyrografException)
        {
            return;
        }
        Fail(label + " accepted by the runtime");
    }

    private static void Drut(string validPath, string invalidPath, string resultPath)
    {
        JsonArray valid = Load(validPath)!.AsArray();
        JsonArray invalid = Load(invalidPath)!.AsArray();
        JsonArray results = new();
        foreach (JsonNode? raw in valid)
        {
            JsonObject item = raw!.AsObject();
            string id = item["id"]!.GetValue<string>();
            if (item["utf8_invalid"]?.GetValue<bool>() ?? false)
            {
                results.Add(Entry(id, "inexpressible"));
                continue;
            }
            JsonNode? produced = RunCase(item);
            JsonNode? expected = Named(item["type"]) ? JsonNode.Parse(item["wire"]!.GetValue<string>())
                : item["value"];
            if (!NodeEquals(produced, expected))
            {
                Fail(id + ": produced value does not match the expected value");
            }
            string status = Category(item) == "public" ? "executed" : "executed-runtime";
            results.Add(Entry(id, status));
        }
        foreach (JsonNode? raw in invalid)
        {
            JsonObject item = raw!.AsObject();
            string id = item["id"]!.GetValue<string>();
            if (item["utf8_invalid"]?.GetValue<bool>() ?? false)
            {
                results.Add(Entry(id, "inexpressible"));
                continue;
            }
            try
            {
                RunCase(item);
            }
            catch (CyrografException)
            {
                string status = Category(item) == "public" ? "rejected" : "rejected-runtime";
                results.Add(Entry(id, status));
                continue;
            }
            Fail(id + ": invalid wire accepted");
        }
        File.WriteAllText(resultPath, results.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine("csharp drut: " + valid.Count + " executed, " + invalid.Count + " rejected");
    }

    private static string Category(JsonObject item)
    {
        if (Named(item["type"]))
        {
            return item["category"]?.GetValue<string>() ?? "public";
        }
        return item["category"]?.GetValue<string>() ?? "runtime";
    }

    private static JsonObject Entry(string id, string status)
    {
        return new JsonObject { ["id"] = id, ["status"] = status };
    }

    private static bool Named(JsonNode? descriptor)
    {
        return descriptor is JsonValue value
            && value.TryGetValue(out string? name)
            && !Primitives.Contains(name!);
    }

    private static string CaseText(JsonObject item)
    {
        if (item["wire"] is JsonNode wire)
        {
            return wire.GetValue<string>();
        }
        if (item["wire_hex"] is JsonNode hex)
        {
            byte[] bytes = HexToBytes(hex.GetValue<string>());
            return new UTF8Encoding(false, true).GetString(bytes);
        }
        Fail(item["id"]!.GetValue<string>() + ": case has neither wire nor wire_hex");
        return "";
    }

    private static byte[] HexToBytes(string hex)
    {
        byte[] bytes = new byte[hex.Length / 2];
        for (int index = 0; index < bytes.Length; index++)
        {
            bytes[index] = byte.Parse(hex.Substring(index * 2, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }
        return bytes;
    }

    private static JsonNode? RunCase(JsonObject item)
    {
        string raw = CaseText(item);
        JsonNode? descriptor = item["type"];
        if (Named(descriptor))
        {
            string name = descriptor!.GetValue<string>();
            if (!Roundtrip.TryGetValue(name, out Func<string, string>? ops))
            {
                Fail("unknown type " + name);
            }
            return JsonNode.Parse(ops(raw));
        }
        object? value = Wire.ParseText(raw);
        return DecodeDesc(descriptor!, value);
    }

    private static JsonNode? DecodeDesc(JsonNode descriptor, object? value)
    {
        if (descriptor is JsonValue node && node.TryGetValue(out string? name))
        {
            switch (name)
            {
                case "void":
                    Wire.DecodeVoid(value, "");
                    return null;
                case "int":
                    return JsonValue.Create(Wire.AsInt(value, ""));
                case "float":
                    return JsonValue.Create(Wire.AsFloat(value, ""));
                case "bool":
                    return JsonValue.Create(Wire.AsBool(value, ""));
                case "string":
                case "date":
                    return JsonValue.Create(Wire.AsString(value, ""));
                case "record":
                    return JsonSerializer.SerializeToNode(Wire.AsRecord(value, ""));
                default:
                    Fail("unknown primitive " + name);
                    return null;
            }
        }
        if (descriptor is JsonObject obj && obj["list"] is JsonNode inner)
        {
            JsonArray array = new();
            foreach (object? item in Wire.AsArray(value, "", -1))
            {
                array.Add(DecodeDesc(inner, item));
            }
            return array;
        }
        Fail("unsupported root descriptor " + descriptor.ToJsonString());
        return null;
    }

    internal static bool NodeEquals(JsonNode? left, JsonNode? right)
    {
        if (left is null || right is null)
        {
            return left is null && right is null;
        }
        if (left is JsonArray a && right is JsonArray b)
        {
            if (a.Count != b.Count)
            {
                return false;
            }
            for (int index = 0; index < a.Count; index++)
            {
                if (!NodeEquals(a[index], b[index]))
                {
                    return false;
                }
            }
            return true;
        }
        if (left is JsonObject oa && right is JsonObject ob)
        {
            if (oa.Count != ob.Count)
            {
                return false;
            }
            foreach (KeyValuePair<string, JsonNode?> pair in oa)
            {
                if (!ob.ContainsKey(pair.Key) || !NodeEquals(pair.Value, ob[pair.Key]))
                {
                    return false;
                }
            }
            return true;
        }
        JsonValueKind kind = left.GetValueKind();
        if (kind != right.GetValueKind())
        {
            if (kind == JsonValueKind.Number && right.GetValueKind() == JsonValueKind.Number)
            {
                return Number(left) == Number(right);
            }
            return false;
        }
        switch (kind)
        {
            case JsonValueKind.String:
                return left.GetValue<string>() == right.GetValue<string>();
            case JsonValueKind.True:
            case JsonValueKind.False:
                return left.GetValue<bool>() == right.GetValue<bool>();
            case JsonValueKind.Number:
                return Number(left) == Number(right);
            case JsonValueKind.Null:
                return true;
            default:
                return left.ToJsonString() == right.ToJsonString();
        }
    }

    private static double Number(JsonNode value)
    {
        return double.Parse(value.ToJsonString(), NumberStyles.Float, CultureInfo.InvariantCulture);
    }
}