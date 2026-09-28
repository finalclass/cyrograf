package generated_contracts;

import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Optional;

public final class MixCheck {

    private MixCheck() {
    }

    static void fail(String message) {
        System.err.println("FAIL: " + message);
        System.exit(1);
    }

    static void expect(String label, String got, String want) {
        if (!got.equals(want)) {
            fail(label + ": " + got + " != " + want);
        }
    }

    public static void main(String[] arguments) {
        String absent = new Python.Mix("n", Optional.empty(), List.of()).toDrut();
        expect("absent record", absent, "[\"n\",null,[]]");
        Map<String, Object> record = new LinkedHashMap<>();
        record.put("k", List.of(1L, 2L));
        record.put("n", null);
        String present = new Python.Mix("n", Optional.of(record), List.of()).toDrut();
        expect("present record", present, "[\"n\",{\"k\":[1,2],\"n\":null},[]]");
        if (absent.equals(present)) {
            fail("absent and present record encode identically");
        }
        if (Python.Mix.fromDrut(absent).blob().isPresent()) {
            fail("decoded absent record is present");
        }
        if (!Python.Mix.fromDrut(present).blob().orElseThrow().equals(record)) {
            fail("decoded record value differs");
        }
        String voids = new Python.Mix("n", Optional.empty(),
                Arrays.asList((Void) null, (Void) null)).toDrut();
        expect("list of void", voids, "[\"n\",null,[null,null]]");
        if (!Python.Mix.fromDrut(voids).voids().equals(Arrays.asList(null, null))) {
            fail("decoded list of void differs");
        }
        expect("empty structure", Python.Empty.fromDrut("[]").toDrut(), "[]");
        try {
            Wire.parseText("[\"n\",{\"k\":1},[]]extra");
        } catch (CyrografException expected) {
            System.out.println("java mix checks passed");
            return;
        }
        fail("trailing text accepted");
    }
}