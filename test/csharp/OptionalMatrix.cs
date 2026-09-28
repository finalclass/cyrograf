using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.IO;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using GeneratedContracts;
using GeneratedContracts.Api;

internal static class OptionalMatrix
{
    internal static void Run(string[] arguments)
    {
        if (arguments.Length < 1)
        {
            Fail("usage: optional <produce|consume> ...");
        }
        switch (arguments[0])
        {
            case "produce":
                Produce(arguments[1], arguments[2]);
                break;
            case "consume":
                Consume(arguments[1]);
                break;
            default:
                Fail("unknown optional mode " + arguments[0]);
                break;
        }
    }

    [DoesNotReturn]
    private static void Fail(string message)
    {
        Console.Error.WriteLine("FAIL: " + message);
        Environment.Exit(1);
    }

    private static List<(string Id, OptionalBox Value)> Cases()
    {
        return new List<(string, OptionalBox)>
        {
            ("absent", new OptionalBox("o1", null, null, null, null, null)),
            ("empty_string", new OptionalBox("o1", "", null, null, null, null)),
            ("zero", new OptionalBox("o1", null, 0, null, null, null)),
            ("false", new OptionalBox("o1", null, null, false, null, null)),
            ("empty_list", new OptionalBox("o1", null, null, null, new List<string>(), null)),
            ("variant_text", new OptionalBox("o1", null, null, null, null, new Choice.Text("x"))),
            ("variant_void", new OptionalBox("o1", null, null, null, null, new Choice.Empty())),
            ("all_present", new OptionalBox("o1", "", 0, false, new List<string>(), new Choice.Empty())),
        };
    }

    private static void CheckSemantics(string id, OptionalBox value)
    {
        bool absentText = value.Text is null;
        bool absentCount = value.Count is null;
        bool absentFlag = value.Flag is null;
        bool absentItems = value.Items is null;
        bool absentChoice = value.Choice is null;
        bool ok = id switch
        {
            "absent" => absentText && absentCount && absentFlag && absentItems && absentChoice,
            "empty_string" => value.Text == "" && absentCount && absentFlag && absentItems && absentChoice,
            "zero" => absentText && value.Count == 0 && absentFlag && absentItems && absentChoice,
            "false" => absentText && absentCount && value.Flag == false && absentItems && absentChoice,
            "empty_list" => absentText && absentCount && absentFlag
                && value.Items is { Count: 0 } && absentChoice,
            "variant_text" => absentText && absentCount && absentFlag && absentItems
                && value.Choice is Choice.Text text && text.Value == "x",
            "variant_void" => absentText && absentCount && absentFlag && absentItems
                && value.Choice is Choice.Empty,
            "all_present" => value.Text == "" && value.Count == 0 && value.Flag == false
                && value.Items is { Count: 0 } && value.Choice is Choice.Empty,
            _ => false,
        };
        if (!ok)
        {
            Fail("case " + id + " decoded to the wrong typed value");
        }
        if (value.OwnerId != "o1")
        {
            Fail("case " + id + " lost the required field");
        }
    }

    private static void Produce(string casesPath, string outputPath)
    {
        JsonArray cases = JsonNode.Parse(File.ReadAllText(casesPath, Encoding.UTF8))!.AsArray();
        Dictionary<string, string> expected = new(StringComparer.Ordinal);
        foreach (JsonNode? raw in cases)
        {
            JsonObject entry = raw!.AsObject();
            expected[entry["id"]!.GetValue<string>()] = entry["wire"]!.GetValue<string>();
        }
        JsonArray produced = new();
        foreach ((string id, OptionalBox value) in Cases())
        {
            string wire = value.ToDrut();
            if (!expected.TryGetValue(id, out string? want))
            {
                Fail("no canonical wire for case " + id);
            }
            if (want != wire)
            {
                Fail("case " + id + " encoded " + wire + ", expected " + want);
            }
            produced.Add(new JsonObject { ["id"] = id, ["wire"] = wire });
        }
        File.WriteAllText(outputPath, produced.ToJsonString(new JsonSerializerOptions { WriteIndented = true }));
        Console.WriteLine("csharp produced " + produced.Count + " optional case(s)");
    }

    private static void Consume(string peerPath)
    {
        JsonArray entries = JsonNode.Parse(File.ReadAllText(peerPath, Encoding.UTF8))!.AsArray();
        foreach (JsonNode? raw in entries)
        {
            JsonObject entry = raw!.AsObject();
            string id = entry["id"]!.GetValue<string>();
            string wire = entry["wire"]!.GetValue<string>();
            OptionalBox value = OptionalBox.FromDrut(wire);
            CheckSemantics(id, value);
            string reencoded = value.ToDrut();
            if (reencoded != wire)
            {
                Fail("case " + id + " re-encoded " + reencoded + ", received " + wire);
            }
        }
        Console.WriteLine("csharp consumed " + entries.Count + " optional case(s)");
    }
}