"""Cross-language Drut interop runner for generated Python.

Usage:

  interop.py check   MESSAGES_JSON OUT_JSON
  interop.py verify  IN_JSON
  interop.py invalid INVALID_JSON
  interop.py drut    VALID_JSON INVALID_JSON OUT_JSON
  interop.py optional

The generated package directory is taken from CYROGRAF_PYTHON_PACKAGE.
Only the two public text conversions are used for named messages; the
private runtime is exercised directly for primitive/list roots.
"""

import json
import os
import sys

PACKAGE = os.environ["CYROGRAF_PYTHON_PACKAGE"]
sys.path.insert(0, PACKAGE)

from generated_contracts import _wire  # noqa: E402
from generated_contracts import common as common  # noqa: E402
from generated_contracts import orders as orders  # noqa: E402


def roundtrip(text):
    value = _from_drut_registry[text] if False else None
    return value


registry = {
    "Orders.ReserveRequest": lambda text: orders.ReserveRequest.from_drut(text).to_drut(),
    "Orders.Reservation": lambda text: orders.Reservation.from_drut(text).to_drut(),
    "Orders.Problem": lambda text: orders.Problem.from_drut(text).to_drut(),
    "Orders.ReserveResponse": lambda text: orders.ReserveResponse.from_drut(text).to_drut(),
    "Orders.ReservationBatch": lambda text: orders.ReservationBatch.from_drut(text).to_drut(),
    "Orders.Guard": lambda text: orders.Guard.from_drut(text).to_drut(),
    "Orders.ListBox": lambda text: orders.ListBox.from_drut(text).to_drut(),
    "Orders.ResponseBox": lambda text: orders.ResponseBox.from_drut(text).to_drut(),
    "Orders.Scalars": lambda text: orders.Scalars.from_drut(text).to_drut(),
    "Common.UserCtx": lambda text: common.UserCtx.from_drut(text).to_drut(),
    "Common.Wrapper": lambda text: common.Wrapper.from_drut(text).to_drut(),
    "Common.Blob": lambda text: common.Blob.from_drut(text).to_drut(),
    "Common.Empty": lambda text: common.Empty.from_drut(text).to_drut(),
    "Common.VoidBox": lambda text: common.VoidBox.from_drut(text).to_drut(),
}

PRIMITIVES = {"void", "int", "float", "bool", "string", "date", "record"}


def fail(message):
    sys.stderr.write("FAIL: " + message + "\n")
    sys.exit(1)


def read_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def roundtrip_entry(item):
    ops = registry.get(item["type"])
    if ops is None:
        fail("unknown type " + item["type"])
    return ops(item["wire"])


def same_json(left, right):
    return json.loads(left) == json.loads(right)


def check(arguments):
    entries = read_json(arguments[0])
    results = []
    for item in entries:
        reencoded = roundtrip_entry(item)
        if item.get("semantic", False):
            matches = same_json(reencoded, item["wire"])
        else:
            matches = reencoded == item["wire"]
        if not matches:
            fail(item["id"] + " (" + item["type"] + "): " + reencoded + " != " + item["wire"])
        entry = {"id": item["id"], "type": item["type"], "wire": reencoded}
        if item.get("semantic", False):
            entry["semantic"] = True
        results.append(entry)
    with open(arguments[1], "w", encoding="utf-8") as handle:
        json.dump(results, handle, indent=2)
    print("python verified %d fixture(s)" % len(entries))


def verify(arguments):
    entries = read_json(arguments[0])
    for item in entries:
        reencoded = roundtrip_entry(item)
        if not same_json(reencoded, item["wire"]):
            fail(item["id"] + " (" + item["type"] + "): " + reencoded + " != " + item["wire"])
    print("python decoded %d message(s) from peer" % len(entries))


def invalid(arguments):
    entries = read_json(arguments[0])
    for item in entries:
        try:
            roundtrip_entry(item)
        except _wire.CyrografError:
            continue
        fail(item["id"] + " (" + item["type"] + "): invalid wire accepted")
    print("python rejected %d invalid message(s)" % len(entries))


def optional():
    def expect(label, got, want):
        if got != want:
            fail(label + ": " + got + " != " + want)

    absent = orders.ReserveRequest(owner_id="o1", quantity=2).to_drut()
    expect("absent string", absent, '["o1",2,null]')
    empty = orders.ReserveRequest(owner_id="o1", quantity=2, note="").to_drut()
    expect("present empty string", empty, '["o1",2,""]')
    if absent == empty:
        fail("absent and empty string encode identically")
    if orders.ReserveRequest.from_drut(absent).note is not None:
        fail("decoded absent string is not None")
    if orders.ReserveRequest.from_drut(empty).note != "":
        fail("decoded empty string is not present")

    absent_list = orders.ListBox(items=None).to_drut()
    expect("absent list", absent_list, "[null]")
    empty_list = orders.ListBox(items=[]).to_drut()
    expect("empty list", empty_list, "[[]]")
    if absent_list == empty_list:
        fail("None and empty list encode identically")
    decoded_list = orders.ListBox.from_drut(empty_list)
    if decoded_list.items is None or len(decoded_list.items) != 0:
        fail("decoded empty list is not a present empty list")

    absent_variant = orders.ResponseBox(response=None).to_drut()
    expect("absent variant", absent_variant, "[null]")
    present_variant = orders.ResponseBox(
        response=orders.ReserveResponseUnavailable()).to_drut()
    expect("present void variant", present_variant, '[["Unavailable",null]]')

    try:
        orders.ReserveRequest.from_drut('["o1","x",null]')
    except _wire.CyrografError:
        pass
    else:
        fail("wrong required type accepted")

    rejected_inputs = [
        ("bool as Int", lambda: orders.Guard(big=True, small=0, ratio=1.0, label="x").to_drut()),
        ("bool as Float", lambda: orders.Guard(big=0, small=0, ratio=True, label="x").to_drut()),
        ("float as Int", lambda: orders.Guard(big=1.5, small=0, ratio=1.0, label="x").to_drut()),
        ("int as Float", lambda: orders.Guard(big=0, small=0, ratio=1, label="x").to_drut()),
    ]
    for label, call in rejected_inputs:
        try:
            call()
        except _wire.CyrografError:
            continue
        fail(label + " accepted by the runtime")
    print("python optional checks passed")


def case_bytes(item):
    if "wire_hex" in item:
        return bytes.fromhex(item["wire_hex"])
    if "wire" in item:
        return item["wire"].encode("utf-8")
    fail(item["id"] + ": case has neither wire nor wire_hex")


def decode_desc(desc, value):
    if isinstance(desc, str):
        if desc == "void":
            _wire.as_null(value, "")
            return None
        if desc == "int":
            return _wire.as_int(value, "")
        if desc == "float":
            return _wire.as_float(value, "")
        if desc == "bool":
            return _wire.as_bool(value, "")
        if desc in ("string", "date"):
            return _wire.as_string(value, "")
        if desc == "record":
            return _wire.as_record(value, "")
        raise ValueError("unknown type " + desc)
    if isinstance(desc, dict) and "list" in desc:
        inner = desc["list"]
        return [decode_desc(inner, item) for item in _wire.as_array(value, "")]
    raise ValueError("unsupported root descriptor")


def run_case(item):
    raw = case_bytes(item)
    text = raw.decode("utf-8")
    desc = item["type"]
    if isinstance(desc, str) and desc not in PRIMITIVES:
        ops = registry.get(desc)
        if ops is None:
            raise ValueError("unknown type " + desc)
        return json.loads(ops(text))
    value = _wire.parse_text(text)
    return json.loads(_wire.stringify(decode_desc(desc, value)))


def drut(arguments):
    valid = read_json(arguments[0])
    invalid_cases = read_json(arguments[1])
    results = []
    for item in valid:
        if item.get("utf8_invalid", False):
            results.append({"id": item["id"], "status": "inexpressible"})
            continue
        produced = run_case(item)
        desc = item["type"]
        named = isinstance(desc, str) and desc not in PRIMITIVES
        expected = json.loads(item["wire"]) if named else item["value"]
        if produced != expected:
            fail(item["id"] + ": produced value does not match")
        status = "executed" if item.get("category") == "public" else "executed-runtime"
        results.append({"id": item["id"], "status": status})
    for item in invalid_cases:
        if item.get("utf8_invalid", False):
            results.append({"id": item["id"], "status": "inexpressible"})
            continue
        try:
            run_case(item)
        except _wire.CyrografError:
            status = "rejected" if item.get("category") == "public" else "rejected-runtime"
            results.append({"id": item["id"], "status": status})
            continue
        fail(item["id"] + ": invalid wire accepted")
    with open(arguments[2], "w", encoding="utf-8") as handle:
        json.dump(results, handle, indent=2)
    print("python drut: %d executed, %d rejected" % (len(valid), len(invalid_cases)))


def main(argv):
    if len(argv) < 1:
        fail("usage: interop.py <check|verify|invalid|drut|optional>")
    mode = argv[0]
    if mode == "optional":
        optional()
        return
    if mode == "check":
        check(argv[1:])
    elif mode == "verify":
        verify(argv[1:])
    elif mode == "invalid":
        invalid(argv[1:])
    elif mode == "drut":
        drut(argv[1:])
    else:
        fail("unknown mode " + mode)


if __name__ == "__main__":
    main(sys.argv[1:])