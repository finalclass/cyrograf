using System;
using GeneratedContracts.Orders;

public static class ConsumerPositive
{
    public static void Run()
    {
        string text = new ReserveRequest("o1", 2, null).ToDrut();
        ReserveRequest request = ReserveRequest.FromDrut(text);
        if (request.OwnerId != "o1" || request.Quantity != 2 || request.Note is not null)
        {
            throw new InvalidOperationException("roundtrip lost typed values");
        }

        ReserveRequest withNote = new ReserveRequest("o1", 2, "hi");
        if (withNote.Note is not null && withNote.Note.Length != 2)
        {
            throw new InvalidOperationException("nullable narrowing is wrong");
        }

        ReserveResponse reserved = ReserveResponse.FromDrut("[\"Reserved\",[\"r-9\"]]");
        string identifier = reserved switch
        {
            ReserveResponse.Reserved value => value.Value.Id,
            ReserveResponse.Rejected value => value.Value.Code,
            ReserveResponse.Unavailable => "unavailable",
            _ => "unknown",
        };
        if (identifier != "r-9")
        {
            throw new InvalidOperationException("typed variant payload is wrong");
        }

        ReserveResponse unavailable = ReserveResponse.FromDrut("[\"Unavailable\",null]");
        if (unavailable is not ReserveResponse.Unavailable)
        {
            throw new InvalidOperationException("variant case is wrong");
        }
        if (unavailable.ToDrut() != "[\"Unavailable\",null]")
        {
            throw new InvalidOperationException("variant re-encoded differently");
        }
        Console.WriteLine("csharp consumer ok");
    }
}