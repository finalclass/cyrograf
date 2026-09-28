using System;
using GeneratedContracts.Orders;

public static class ConsumerNegative
{
    public static void Run()
    {
        ReserveRequest value = ReserveRequest.FromValue("[]");
        Console.WriteLine(value);
    }
}