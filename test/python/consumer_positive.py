"""Positive consumer for the generated Python contracts.

Uses only the two public text conversions from api.md, reads typed fields and
runs a small roundtrip. It runs against an installed package and only relies on
the messages shared by the quick-start example and the API fixtures.
"""

from generated_contracts.orders import (
    ReserveRequest,
    ReserveResponse,
    ReserveResponseUnavailable,
)

text: str = ReserveRequest(owner_id="o1", quantity=2).to_drut()
request: ReserveRequest = ReserveRequest.from_drut(text)
owner: str = request.owner_id
quantity: int = request.quantity
note: str | None = request.note
assert owner == "o1" and quantity == 2 and note is None

variant: ReserveResponse = ReserveResponse.from_drut('["Unavailable",null]')
assert isinstance(variant, ReserveResponseUnavailable)
assert variant.to_drut() == '["Unavailable",null]'