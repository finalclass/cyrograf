using System;
using System.Collections.Generic;
using System.Diagnostics.CodeAnalysis;
using System.Text.Json;
using GeneratedContracts;
using GeneratedContracts.Python;

internal static class MixCheck
{
    internal static void Run()
    {
        string absent = new Mix("n", null, new List<CyrografUnit>()).ToDrut();
        Expect("absent record", absent, "[\"n\",null,[]]");

        Dictionary<string, JsonElement> record = new()
        {
            ["k"] = JsonDocument.Parse("[1,2]").RootElement.Clone(),
            ["n"] = JsonDocument.Parse("null").RootElement.Clone(),
        };
        string present = new Mix("n", record, new List<CyrografUnit>()).ToDrut();
        Expect("present record", present, "[\"n\",{\"k\":[1,2],\"n\":null},[]]");
        if (absent == present)
        {
            Fail("absent and present record encode identically");
        }
        if (Mix.FromDrut(absent).Blob is not null)
        {
            Fail("decoded absent record is present");
        }
        Dictionary<string, JsonElement>? decoded = Mix.FromDrut(present).Blob;
        if (decoded is null || decoded["k"].GetRawText() != "[1,2]")
        {
            Fail("decoded record value differs");
        }

        string voids = new Mix("n", null,
            new List<CyrografUnit> { CyrografUnit.Value, CyrografUnit.Value }).ToDrut();
        Expect("list of void", voids, "[\"n\",null,[null,null]]");
        if (Mix.FromDrut(voids).Voids.Count != 2)
        {
            Fail("decoded list of void differs");
        }
        Expect("empty structure", Empty.FromDrut("[]").ToDrut(), "[]");
        try
        {
            Dictionary<string, JsonElement> undefined = new() { ["x"] = default };
            new Mix("n", undefined, new List<CyrografUnit>()).ToDrut();
            Fail("undefined JsonElement accepted");
        }
        catch (CyrografException)
        {
            // An Undefined JsonElement is not valid Wire input.
        }
        try
        {
            Wire.ParseText("[\"n\",{\"k\":1},[]]extra");
        }
        catch (CyrografException)
        {
            Console.WriteLine("csharp mix checks passed");
            return;
        }
        Fail("trailing text accepted");
    }

    [DoesNotReturn]
    private static void Fail(string message)
    {
        Console.Error.WriteLine("FAIL: " + message);
        Environment.Exit(1);
    }

    private static void Expect(string label, string got, string want)
    {
        if (got != want)
        {
            Fail(label + ": " + got + " != " + want);
        }
    }
}