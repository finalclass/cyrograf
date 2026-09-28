package generated_contracts;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Function;

public final class Interop {

    private static final Set<String> PRIMITIVES = Set.of(
            "void", "int", "float", "bool", "string", "date", "record");

    private static final Map<String, Function<String, String>> ROUNDTRIP = new LinkedHashMap<>();

    static {
        ROUNDTRIP.put("Orders.ReserveRequest", text -> Orders.ReserveRequest.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.Reservation", text -> Orders.Reservation.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.Problem", text -> Orders.Problem.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.ReserveResponse", text -> Orders.ReserveResponse.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.ReservationBatch", text -> Orders.ReservationBatch.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.Guard", text -> Orders.Guard.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.ListBox", text -> Orders.ListBox.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.ResponseBox", text -> Orders.ResponseBox.fromDrut(text).toDrut());
        ROUNDTRIP.put("Orders.Scalars", text -> Orders.Scalars.fromDrut(text).toDrut());
        ROUNDTRIP.put("Common.UserCtx", text -> Common.UserCtx.fromDrut(text).toDrut());
        ROUNDTRIP.put("Common.Wrapper", text -> Common.Wrapper.fromDrut(text).toDrut());
        ROUNDTRIP.put("Common.Blob", text -> Common.Blob.fromDrut(text).toDrut());
        ROUNDTRIP.put("Common.Empty", text -> Common.Empty.fromDrut(text).toDrut());
        ROUNDTRIP.put("Common.VoidBox", text -> Common.VoidBox.fromDrut(text).toDrut());
    }

    private Interop() {
    }

    static void fail(String message) {
        System.err.println("FAIL: " + message);
        System.exit(1);
    }

    @SuppressWarnings("unchecked")
    static Map<String, Object> asObject(Object value) {
        return (Map<String, Object>) value;
    }

    @SuppressWarnings("unchecked")
    static List<Object> asList(Object value) {
        return (List<Object>) value;
    }

    static Object readJson(Path path) throws Exception {
        return Wire.parseText(Files.readString(path, StandardCharsets.UTF_8));
    }

    static void writeJson(Path path, Object value) throws Exception {
        Files.writeString(path, Wire.stringify(value), StandardCharsets.UTF_8);
    }

    static Map<String, Object> entry(String id, String status) {
        Map<String, Object> map = new LinkedHashMap<>();
        map.put("id", id);
        map.put("status", status);
        return map;
    }

    static String roundtripEntry(Map<String, Object> item) {
        Object type = item.get("type");
        if (type instanceof String name) {
            Function<String, String> ops = ROUNDTRIP.get(name);
            if (ops == null) {
                fail("unknown type " + name);
            }
            return ops.apply((String) item.get("wire"));
        }
        fail("unsupported message type " + type);
        return null;
    }

    static void check(List<Object> arguments) throws Exception {
        List<Object> entries = asList(readJson(Path.of((String) arguments.get(0))));
        List<Object> results = new ArrayList<>();
        for (Object raw : entries) {
            Map<String, Object> item = asObject(raw);
            String reencoded = roundtripEntry(item);
            boolean semantic = Boolean.TRUE.equals(item.get("semantic"));
            boolean matches = semantic
                    ? jsonEqual(reencoded, (String) item.get("wire"))
                    : reencoded.equals(item.get("wire"));
            if (!matches) {
                fail(item.get("id") + " (" + item.get("type") + "): " + reencoded
                        + " != " + item.get("wire"));
            }
            Map<String, Object> result = new LinkedHashMap<>();
            result.put("id", item.get("id"));
            result.put("type", item.get("type"));
            result.put("wire", reencoded);
            if (semantic) {
                result.put("semantic", true);
            }
            results.add(result);
        }
        writeJson(Path.of((String) arguments.get(1)), results);
        System.out.println("java verified " + entries.size() + " fixture(s)");
    }

    static void verify(List<Object> arguments) throws Exception {
        List<Object> entries = asList(readJson(Path.of((String) arguments.get(0))));
        for (Object raw : entries) {
            Map<String, Object> item = asObject(raw);
            String reencoded = roundtripEntry(item);
            if (!jsonEqual(reencoded, (String) item.get("wire"))) {
                fail(item.get("id") + " (" + item.get("type") + "): " + reencoded
                        + " != " + item.get("wire"));
            }
        }
        System.out.println("java decoded " + entries.size() + " message(s) from peer");
    }

    static void invalid(List<Object> arguments) throws Exception {
        List<Object> entries = asList(readJson(Path.of((String) arguments.get(0))));
        for (Object raw : entries) {
            Map<String, Object> item = asObject(raw);
            try {
                roundtripEntry(item);
            } catch (CyrografException expected) {
                continue;
            }
            fail(item.get("id") + " (" + item.get("type") + "): invalid wire accepted");
        }
        System.out.println("java rejected " + entries.size() + " invalid message(s)");
    }

    static void optional() {
        expect("absent string",
                new Orders.ReserveRequest("o1", 2, Optional.empty()).toDrut(),
                "[\"o1\",2,null]");
        expect("present empty string",
                new Orders.ReserveRequest("o1", 2, Optional.of("")).toDrut(),
                "[\"o1\",2,\"\"]");
        if (Orders.ReserveRequest.fromDrut("[\"o1\",2,null]").note().isPresent()) {
            fail("decoded absent string is present");
        }
        if (!Orders.ReserveRequest.fromDrut("[\"o1\",2,\"\"]").note().orElseThrow().isEmpty()) {
            fail("decoded empty string is not present empty");
        }

        String absentList = new Orders.ListBox(Optional.empty()).toDrut();
        expect("absent list", absentList, "[null]");
        String emptyList = new Orders.ListBox(Optional.of(new ArrayList<>())).toDrut();
        expect("empty list", emptyList, "[[]]");
        if (absentList.equals(emptyList)) {
            fail("empty optional and present empty list encode identically");
        }
        if (!Orders.ListBox.fromDrut(emptyList).items().orElseThrow().isEmpty()) {
            fail("decoded empty list is not a present empty list");
        }

        String absentVariant = new Orders.ResponseBox(Optional.empty()).toDrut();
        expect("absent variant", absentVariant, "[null]");
        String presentVariant = new Orders.ResponseBox(
                Optional.of(new Orders.ReserveResponse.Unavailable())).toDrut();
        expect("present void variant", presentVariant, "[[\"Unavailable\",null]]");

        expectError("wrong required type", () -> Orders.ReserveRequest.fromDrut("[\"o1\",\"x\",null]"));
        expectError("null instead of Optional",
                () -> new Orders.ListBox(null).toDrut());
        expectError("null required reference",
                () -> new Common.Wrapper(null, Optional.empty()).toDrut());
        expectError("null required string",
                () -> new Orders.ReserveRequest(null, 2, Optional.empty()).toDrut());
        System.out.println("java optional checks passed");
    }

    static void expect(String label, String got, String want) {
        if (!got.equals(want)) {
            fail(label + ": " + got + " != " + want);
        }
    }

    static void expectError(String label, Runnable call) {
        try {
            call.run();
        } catch (CyrografException expected) {
            return;
        }
        fail(label + " accepted by the runtime");
    }

    static String caseText(Map<String, Object> item) {
        if (item.containsKey("wire")) {
            return (String) item.get("wire");
        }
        if (item.containsKey("wire_hex")) {
            return hexToString((String) item.get("wire_hex"));
        }
        fail(item.get("id") + ": case has neither wire nor wire_hex");
        return null;
    }

    static String hexToString(String hex) {
        byte[] bytes = new byte[hex.length() / 2];
        for (int index = 0; index < bytes.length; index++) {
            bytes[index] = (byte) Integer.parseInt(hex.substring(index * 2, index * 2 + 2), 16);
        }
        return new String(bytes, StandardCharsets.UTF_8);
    }

    static Object decodeDesc(Object desc, Object value) {
        if (desc instanceof String name) {
            switch (name) {
                case "void":
                    Wire.asNull(value, "");
                    return null;
                case "int":
                    return Wire.asInt(value, "");
                case "float":
                    return Wire.asFloat(value, "");
                case "bool":
                    return Wire.asBool(value, "");
                case "string":
                case "date":
                    return Wire.asString(value, "");
                case "record":
                    return Wire.asRecord(value, "");
                default:
                    fail("unknown primitive " + name);
                    return null;
            }
        }
        if (desc instanceof Map<?, ?> map && map.containsKey("list")) {
            Object inner = map.get("list");
            List<Object> out = new ArrayList<>();
            for (Object item : Wire.asArray(value, "", -1)) {
                out.add(decodeDesc(inner, item));
            }
            return out;
        }
        fail("unsupported root descriptor " + desc);
        return null;
    }

    static Object runCase(Map<String, Object> item) {
        String raw = caseText(item);
        Object desc = item.get("type");
        if (desc instanceof String name && !PRIMITIVES.contains(name)) {
            Function<String, String> ops = ROUNDTRIP.get(name);
            if (ops == null) {
                fail("unknown type " + name);
            }
            return Wire.parseText(ops.apply(raw));
        }
        Object value = Wire.parseText(raw);
        return Wire.parseText(Wire.stringify(decodeDesc(desc, value)));
    }

    static void drut(List<Object> arguments) throws Exception {
        List<Object> valid = asList(readJson(Path.of((String) arguments.get(0))));
        List<Object> invalidCases = asList(readJson(Path.of((String) arguments.get(1))));
        List<Object> results = new ArrayList<>();
        for (Object raw : valid) {
            Map<String, Object> item = asObject(raw);
            String id = (String) item.get("id");
            if (Boolean.TRUE.equals(item.get("utf8_invalid"))) {
                results.add(entry(id, "inexpressible"));
                continue;
            }
            Object produced = runCase(item);
            Object desc = item.get("type");
            boolean named = desc instanceof String name && !PRIMITIVES.contains(name);
            Object expected = named
                    ? Wire.parseText((String) item.get("wire"))
                    : item.get("value");
            if (!jsonEqual(produced, expected)) {
                fail(id + ": produced value does not match");
            }
            String status = "public".equals(item.get("category"))
                    ? "executed"
                    : "executed-runtime";
            results.add(entry(id, status));
        }
        for (Object raw : invalidCases) {
            Map<String, Object> item = asObject(raw);
            String id = (String) item.get("id");
            if (Boolean.TRUE.equals(item.get("utf8_invalid"))) {
                results.add(entry(id, "inexpressible"));
                continue;
            }
            try {
                runCase(item);
            } catch (CyrografException expected) {
                String status = "public".equals(item.get("category"))
                        ? "rejected"
                        : "rejected-runtime";
                results.add(entry(id, status));
                continue;
            }
            fail(id + ": invalid wire accepted");
        }
        writeJson(Path.of((String) arguments.get(2)), results);
        System.out.println("java drut: " + valid.size() + " executed, " + invalidCases.size()
                + " rejected");
    }

    static boolean jsonEqual(Object left, Object right) {
        if (left == null || right == null) {
            return left == right;
        }
        if (left instanceof Wire.Num || right instanceof Wire.Num) {
            return number(left) == number(right);
        }
        if (left instanceof Boolean || right instanceof Boolean) {
            return left.equals(right);
        }
        if (left instanceof String || right instanceof String) {
            return left.equals(right);
        }
        if (left instanceof List<?> a && right instanceof List<?> b) {
            if (a.size() != b.size()) {
                return false;
            }
            for (int index = 0; index < a.size(); index++) {
                if (!jsonEqual(a.get(index), b.get(index))) {
                    return false;
                }
            }
            return true;
        }
        if (left instanceof Map<?, ?> a && right instanceof Map<?, ?> b) {
            if (!a.keySet().equals(b.keySet())) {
                return false;
            }
            for (Object key : a.keySet()) {
                if (!jsonEqual(a.get(key), b.get(key))) {
                    return false;
                }
            }
            return true;
        }
        return left.equals(right);
    }

    static double number(Object value) {
        if (value instanceof Wire.Num num) {
            return Double.parseDouble(num.lexeme);
        }
        if (value instanceof Number num) {
            return num.doubleValue();
        }
        fail("not a number: " + value);
        return 0.0;
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length < 1) {
            fail("usage: Interop <check|verify|invalid|drut|optional>");
        }
        List<Object> rest = new ArrayList<>(List.of(arguments).subList(1, arguments.length));
        switch (arguments[0]) {
            case "check":
                check(rest);
                break;
            case "verify":
                verify(rest);
                break;
            case "invalid":
                invalid(rest);
                break;
            case "drut":
                drut(rest);
                break;
            case "optional":
                optional();
                break;
            default:
                fail("unknown mode " + arguments[0]);
        }
    }
}