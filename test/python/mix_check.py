"""Target-specific runtime checks for the Python generator.

Covers an optional Record, a List<Void> and an empty structure through the
public conversions only.
"""

import os
import sys

PACKAGE = os.environ["CYROGRAF_PYTHON_PACKAGE"]
sys.path.insert(0, PACKAGE)

from generated_contracts import _wire  # noqa: E402
from generated_contracts import python as models  # noqa: E402


def fail(message):
    sys.stderr.write("FAIL: " + message + "\n")
    sys.exit(1)


def expect(label, got, want):
    if got != want:
        fail(label + ": " + str(got) + " != " + str(want))


Mix = models.Mix
Empty = models.Empty

absent = Mix(name="n", voids=[]).to_drut()
expect("absent record", absent, '["n",null,[]]')
present = Mix(name="n", blob={"k": [1, 2], "n": None}, voids=[]).to_drut()
expect("present record", present, '["n",{"k":[1,2],"n":null},[]]')
if absent == present:
    fail("absent and present record encode identically")

decoded_absent = Mix.from_drut(absent)
if decoded_absent.blob is not None:
    fail("decoded absent record is not None")
decoded_present = Mix.from_drut(present)
expect("decoded record value", decoded_present.blob, {"k": [1, 2], "n": None})

voids = Mix(name="n", voids=[None, None]).to_drut()
expect("list of void", voids, '["n",null,[null,null]]')
expect("decoded list of void", Mix.from_drut(voids).voids, [None, None])

expect("empty structure", Empty().to_drut(), "[]")
if Empty.from_drut("[]") != Empty():
    fail("empty structure roundtrip")

try:
    _wire.parse_text('["n",{"k":1},[]]extra')
except _wire.CyrografError:
    pass
else:
    fail("trailing text accepted")

print("python mix checks passed")