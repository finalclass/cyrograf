package generated_contracts;

import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

public final class OptionalMatrix {

    private OptionalMatrix() {
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

    static List<Map<String, Object>> cases() {
        List<Map<String, Object>> cases = new ArrayList<>();
        cases.add(named("absent", new Api.OptionalBox("o1", Optional.empty(), Optional.empty(),
                Optional.empty(), Optional.empty(), Optional.empty())));
        cases.add(named("empty_string", new Api.OptionalBox("o1", Optional.of(""), Optional.empty(),
                Optional.empty(), Optional.empty(), Optional.empty())));
        cases.add(named("zero", new Api.OptionalBox("o1", Optional.empty(), Optional.of(0L),
                Optional.empty(), Optional.empty(), Optional.empty())));
        cases.add(named("false", new Api.OptionalBox("o1", Optional.empty(), Optional.empty(),
                Optional.of(false), Optional.empty(), Optional.empty())));
        cases.add(named("empty_list", new Api.OptionalBox("o1", Optional.empty(), Optional.empty(),
                Optional.empty(), Optional.of(new ArrayList<>()), Optional.empty())));
        cases.add(named("variant_text", new Api.OptionalBox("o1", Optional.empty(), Optional.empty(),
                Optional.empty(), Optional.empty(), Optional.of(new Api.Choice.Text("x")))));
        cases.add(named("variant_void", new Api.OptionalBox("o1", Optional.empty(), Optional.empty(),
                Optional.empty(), Optional.empty(), Optional.of(new Api.Choice.Empty()))));
        cases.add(named("all_present", new Api.OptionalBox("o1", Optional.of(""), Optional.of(0L),
                Optional.of(false), Optional.of(new ArrayList<>()),
                Optional.of(new Api.Choice.Empty()))));
        return cases;
    }

    static Map<String, Object> named(String id, Api.OptionalBox value) {
        Map<String, Object> entry = new LinkedHashMap<>();
        entry.put("id", id);
        entry.put("value", value);
        return entry;
    }

    static void checkSemantics(String id, Api.OptionalBox value) {
        boolean absentText = value.text().isEmpty();
        boolean absentCount = value.count().isEmpty();
        boolean absentFlag = value.flag().isEmpty();
        boolean absentItems = value.items().isEmpty();
        boolean absentChoice = value.choice().isEmpty();
        boolean ok;
        switch (id) {
            case "absent":
                ok = absentText && absentCount && absentFlag && absentItems && absentChoice;
                break;
            case "empty_string":
                ok = value.text().orElse(null) != null && value.text().orElseThrow().isEmpty()
                        && absentCount && absentFlag && absentItems && absentChoice;
                break;
            case "zero":
                ok = absentText && value.count().orElse(-1L) == 0L && absentFlag
                        && absentItems && absentChoice;
                break;
            case "false":
                ok = absentText && absentCount && Boolean.FALSE.equals(value.flag().orElse(null))
                        && absentItems && absentChoice;
                break;
            case "empty_list":
                ok = absentText && absentCount && absentFlag
                        && value.items().orElse(null) != null
                        && value.items().orElseThrow().isEmpty() && absentChoice;
                break;
            case "variant_text":
                ok = absentText && absentCount && absentFlag && absentItems
                        && value.choice().orElse(null) instanceof Api.Choice.Text text
                        && text.value().equals("x");
                break;
            case "variant_void":
                ok = absentText && absentCount && absentFlag && absentItems
                        && value.choice().orElse(null) instanceof Api.Choice.Empty;
                break;
            case "all_present":
                ok = value.text().orElseThrow().isEmpty() && value.count().orElseThrow() == 0L
                        && Boolean.FALSE.equals(value.flag().orElseThrow())
                        && value.items().orElseThrow().isEmpty()
                        && value.choice().orElseThrow() instanceof Api.Choice.Empty;
                break;
            default:
                fail("unknown case " + id);
                return;
        }
        if (!ok) {
            fail("case " + id + " decoded to the wrong typed value");
        }
        if (!value.ownerId().equals("o1")) {
            fail("case " + id + " lost the required field");
        }
    }

    static void produce(List<Object> arguments) throws Exception {
        Map<String, String> expected = new LinkedHashMap<>();
        for (Object raw : asList(readJson(Path.of((String) arguments.get(0))))) {
            Map<String, Object> entry = asObject(raw);
            expected.put((String) entry.get("id"), (String) entry.get("wire"));
        }
        List<Object> produced = new ArrayList<>();
        for (Map<String, Object> entry : cases()) {
            String id = (String) entry.get("id");
            Api.OptionalBox value = (Api.OptionalBox) entry.get("value");
            String wire = value.toDrut();
            String want = expected.get(id);
            if (want == null) {
                fail("no canonical wire for case " + id);
            }
            if (!want.equals(wire)) {
                fail("case " + id + " encoded " + wire + ", expected " + want);
            }
            Map<String, Object> output = new LinkedHashMap<>();
            output.put("id", id);
            output.put("wire", wire);
            produced.add(output);
        }
        writeJson(Path.of((String) arguments.get(1)), produced);
        System.out.println("java produced " + produced.size() + " optional case(s)");
    }

    static void consume(List<Object> arguments) throws Exception {
        List<Object> entries = asList(readJson(Path.of((String) arguments.get(0))));
        for (Object raw : entries) {
            Map<String, Object> entry = asObject(raw);
            String id = (String) entry.get("id");
            String wire = (String) entry.get("wire");
            Api.OptionalBox value = Api.OptionalBox.fromDrut(wire);
            checkSemantics(id, value);
            String reencoded = value.toDrut();
            if (!reencoded.equals(wire)) {
                fail("case " + id + " re-encoded " + reencoded + ", received " + wire);
            }
        }
        System.out.println("java consumed " + entries.size() + " optional case(s)");
    }

    public static void main(String[] arguments) throws Exception {
        if (arguments.length < 2) {
            fail("usage: OptionalMatrix <produce|consume> ARGS");
        }
        List<Object> rest = new ArrayList<>(List.of(arguments).subList(1, arguments.length));
        if (arguments[0].equals("produce")) {
            produce(rest);
        } else if (arguments[0].equals("consume")) {
            consume(rest);
        } else {
            fail("unknown mode " + arguments[0]);
        }
    }
}