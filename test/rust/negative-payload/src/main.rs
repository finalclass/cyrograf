use generated_contracts::orders::ReserveResponse;

fn main() {
    let value = ReserveResponse::from_drut("[\"Unavailable\",null]").unwrap();
    let _: String = value;
}