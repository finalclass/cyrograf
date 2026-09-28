import generated_contracts.Orders;

import java.util.Optional;

public final class ConsumerPositive {

    private ConsumerPositive() {
    }

    public static void main(String[] arguments) {
        String text = new Orders.ReserveRequest("o1", 2, Optional.empty()).toDrut();
        Orders.ReserveRequest request = Orders.ReserveRequest.fromDrut(text);
        if (!request.ownerId().equals("o1") || request.quantity() != 2 || request.note().isPresent()) {
            throw new AssertionError("roundtrip lost typed values");
        }

        Orders.ReserveResponse reserved = Orders.ReserveResponse.fromDrut("[\"Reserved\",[\"r-9\"]]");
        String identifier = switch (reserved) {
            case Orders.ReserveResponse.Reserved value -> value.value().id();
            case Orders.ReserveResponse.Rejected value -> value.value().code();
            case Orders.ReserveResponse.Unavailable ignored -> "unavailable";
        };
        if (!identifier.equals("r-9")) {
            throw new AssertionError("typed variant payload is wrong");
        }

        Orders.ReserveResponse unavailable = Orders.ReserveResponse.fromDrut("[\"Unavailable\",null]");
        if (!(unavailable instanceof Orders.ReserveResponse.Unavailable)) {
            throw new AssertionError("variant case is wrong");
        }
        if (!unavailable.toDrut().equals("[\"Unavailable\",null]")) {
            throw new AssertionError("variant re-encoded differently");
        }
        System.out.println("java consumer ok");
    }
}