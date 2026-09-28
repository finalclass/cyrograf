using GeneratedContracts.Orders;

public static class ConsumerNullableNegative
{
    public static string Describe(ReserveRequest request)
    {
        string note = request.Note;
        return note;
    }
}