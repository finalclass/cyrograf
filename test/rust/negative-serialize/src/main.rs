use generated_contracts::orders::ReserveRequest;

fn main() {
    let value = ReserveRequest::from_drut("[\"o1\",2,null]").unwrap();
    let _ = serde_json::to_string(&value);
}