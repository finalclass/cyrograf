"""Negative consumer: these statements must fail mypy strict.

The generated public surface has no third conversion and keeps optional fields
strictly separate from their value. The test only checks that mypy rejects the
file; it is never executed.
"""

from generated_contracts.orders import (
    ReserveRequest,
    Reservation,
    ReserveResponseReserved,
)

missing = ReserveRequest(owner_id="o1", quantity=1).from_value('["o1",1,null]')

wrong_payload = ReserveResponseReserved(value="not a Reservation")

request = ReserveRequest(owner_id="o1", quantity=1)
unchecked = request.note.upper()
valid = Reservation(id="r-9")