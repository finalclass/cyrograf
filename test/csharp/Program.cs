using System;

internal static class Program
{
    private static int Main(string[] arguments)
    {
        if (arguments.Length < 1)
        {
            Console.Error.WriteLine("usage: cyrograf-csharp <interop|optional|mix|consumer> ...");
            return 2;
        }
        string mode = arguments[0];
        string[] rest = arguments[1..];
        switch (mode)
        {
            case "interop":
                Interop.Run(rest);
                return 0;
            case "optional":
                OptionalMatrix.Run(rest);
                return 0;
            case "mix":
                MixCheck.Run();
                return 0;
            case "consumer":
                ConsumerPositive.Run();
                return 0;
            default:
                Console.Error.WriteLine("unknown mode " + mode);
                return 2;
        }
    }
}