import generated_contracts.Orders;

public final class ConsumerNegative {

    private ConsumerNegative() {
    }

    public static void main(String[] arguments) {
        Orders.ReserveRequest value = Orders.ReserveRequest.fromValue("[]");
        System.out.println(value);
    }
}