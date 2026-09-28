use generated_contracts::orders::{Reservation, ReserveRequest, ReserveResponse};

pub(crate) fn run() {
    let request = ReserveRequest {
        owner_id: "o1".to_string(),
        quantity: 2,
        note: Some("hi".to_string()),
    };
    let text = request.to_drut().expect("encode");
    let decoded = ReserveRequest::from_drut(&text).expect("decode");
    assert_eq!(decoded.owner_id, "o1");
    assert_eq!(decoded.quantity, 2);
    assert_eq!(decoded.note.as_deref(), Some("hi"));

    let response = ReserveResponse::Reserved(Reservation { id: "r-9".to_string() });
    let response_text = response.to_drut().expect("encode variant");
    match ReserveResponse::from_drut(&response_text).expect("decode variant") {
        ReserveResponse::Reserved(value) => assert_eq!(value.id, "r-9"),
        _ => panic!("wrong variant case"),
    }
    println!("rust consumer ok {}", text);
}