import generated_contracts.Wire;

public final class WireNegative {

    private WireNegative() {
    }

    public static void main(String[] arguments) {
        System.out.println(Wire.parseText("[]"));
    }
}