use generated_contracts::orders::ReserveRequest;

fn main() {
    let value = ReserveRequest::from_drut("[\"o1\",2,null]").unwrap();
    let _ = value.encode_value();
}