"""One endpoint of the cross-language optional-field exchange for Python.

  optional_matrix.py produce CASES_JSON OUT_JSON
  optional_matrix.py consume PEER_JSON

The generated package directory is taken from CYROGRAF_PYTHON_PACKAGE.
"""

import json
import os
import sys

PACKAGE = os.environ["CYROGRAF_PYTHON_PACKAGE"]
sys.path.insert(0, PACKAGE)

from generated_contracts import _wire  # noqa: E402
from generated_contracts import api as api  # noqa: E402

CASES = [
    ("absent", api.OptionalBox(owner_id="o1")),
    ("empty_string", api.OptionalBox(owner_id="o1", text="")),
    ("zero", api.OptionalBox(owner_id="o1", count=0)),
    ("false", api.OptionalBox(owner_id="o1", flag=False)),
    ("empty_list", api.OptionalBox(owner_id="o1", items=[])),
    ("variant_text", api.OptionalBox(owner_id="o1", choice=api.ChoiceText(value="x"))),
    ("variant_void", api.OptionalBox(owner_id="o1", choice=api.ChoiceEmpty())),
    ("all_present", api.OptionalBox(
        owner_id="o1", text="", count=0, flag=False, items=[], choice=api.ChoiceEmpty())),
]


def fail(message):
    sys.stderr.write("FAIL: " + message + "\n")
    sys.exit(1)


def read_json(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def check_semantics(case_id, value):
    absent = lambda field: field is None  # noqa: E731
    expected = {
        "absent": (absent(value.text) and absent(value.count) and absent(value.flag)
                   and absent(value.items) and absent(value.choice)),
        "empty_string": (value.text == "" and absent(value.count) and absent(value.flag)
                         and absent(value.items) and absent(value.choice)),
        "zero": (absent(value.text) and value.count == 0 and absent(value.flag)
                 and absent(value.items) and absent(value.choice)),
        "false": (absent(value.text) and absent(value.count) and value.flag is False
                  and absent(value.items) and absent(value.choice)),
        "empty_list": (absent(value.text) and absent(value.count) and absent(value.flag)
                       and value.items == [] and absent(value.choice)),
        "variant_text": (absent(value.text) and absent(value.count) and absent(value.flag)
                         and absent(value.items)
                         and value.choice == api.ChoiceText(value="x")),
        "variant_void": (absent(value.text) and absent(value.count) and absent(value.flag)
                         and absent(value.items) and value.choice == api.ChoiceEmpty()),
        "all_present": (value.text == "" and value.count == 0 and value.flag is False
                        and value.items == [] and value.choice == api.ChoiceEmpty()),
    }.get(case_id)
    if expected is None:
        fail("unknown case " + case_id)
    if not expected:
        fail("case " + case_id + " decoded to the wrong typed value")
    if value.owner_id != "o1":
        fail("case " + case_id + " lost the required field")


def produce(arguments):
    expected = {entry["id"]: entry["wire"] for entry in read_json(arguments[0])}
    produced = []
    for case_id, value in CASES:
        wire = value.to_drut()
        want = expected.get(case_id)
        if want is None:
            fail("no canonical wire for case " + case_id)
        if want != wire:
            fail("case " + case_id + " encoded " + wire + ", expected " + want)
        produced.append({"id": case_id, "wire": wire})
    with open(arguments[1], "w", encoding="utf-8") as handle:
        json.dump(produced, handle, indent=2)
    print("python produced %d optional case(s)" % len(produced))


def consume(arguments):
    entries = read_json(arguments[0])
    for entry in entries:
        value = api.OptionalBox.from_drut(entry["wire"])
        check_semantics(entry["id"], value)
        reencoded = value.to_drut()
        if reencoded != entry["wire"]:
            fail("case " + entry["id"] + " re-encoded " + reencoded
                 + ", received " + entry["wire"])
    print("python consumed %d optional case(s)" % len(entries))


def main(argv):
    if len(argv) < 2:
        fail("usage: optional_matrix.py <produce|consume>")
    if argv[0] == "produce":
        produce(argv[1:])
    elif argv[0] == "consume":
        consume(argv[1:])
    else:
        fail("unknown mode " + argv[0])


if __name__ == "__main__":
    main(sys.argv[1:])