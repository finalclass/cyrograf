use generated_contracts::{common, orders};
use serde_json::Value;

fn fail(message: &str) -> ! {
    eprintln!("FAIL: {}", message);
    std::process::exit(1);
}

fn parse(text: &str) -> Value {
    serde_json::from_str(text).unwrap_or_else(|error| fail(&format!("invalid test JSON: {}", error)))
}

fn load(path: &str) -> Value {
    let text = std::fs::read_to_string(path).unwrap_or_else(|error| fail(&format!("cannot read {}: {}", path, error)));
    parse(&text)
}

fn json_equal(left: &Value, right: &Value) -> bool {
    match (left, right) {
        (Value::Null, Value::Null) => true,
        (Value::Bool(a), Value::Bool(b)) => a == b,
        (Value::Number(a), Value::Number(b)) => a.as_f64() == b.as_f64(),
        (Value::String(a), Value::String(b)) => a == b,
        (Value::Array(a), Value::Array(b)) => {
            a.len() == b.len() && a.iter().zip(b.iter()).all(|(x, y)| json_equal(x, y))
        }
        (Value::Object(a), Value::Object(b)) => {
            a.len() == b.len()
                && a.iter().all(|(key, value)| {
                    b.get(key).map(|other| json_equal(value, other)).unwrap_or(false)
                })
        }
        _ => false,
    }
}

fn roundtrip(name: &str, text: &str) -> Result<String, String> {
    let result = match name {
        "Orders.ReserveRequest" => orders::ReserveRequest::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.Reservation" => orders::Reservation::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.Problem" => orders::Problem::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.ReserveResponse" => orders::ReserveResponse::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.ReservationBatch" => orders::ReservationBatch::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.Guard" => orders::Guard::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.ListBox" => orders::ListBox::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.ResponseBox" => orders::ResponseBox::from_drut(text).and_then(|value| value.to_drut()),
        "Orders.Scalars" => orders::Scalars::from_drut(text).and_then(|value| value.to_drut()),
        "Common.UserCtx" => common::UserCtx::from_drut(text).and_then(|value| value.to_drut()),
        "Common.Wrapper" => common::Wrapper::from_drut(text).and_then(|value| value.to_drut()),
        "Common.Blob" => common::Blob::from_drut(text).and_then(|value| value.to_drut()),
        "Common.Empty" => common::Empty::from_drut(text).and_then(|value| value.to_drut()),
        "Common.VoidBox" => common::VoidBox::from_drut(text).and_then(|value| value.to_drut()),
        _ => return Err(format!("unknown type {}", name)),
    };
    result.map_err(|error| error.to_string())
}

fn check(input_path: &str, output_path: &str) {
    let entries = load(input_path);
    let entries = entries.as_array().expect("message corpus must be an array");
    let mut results = Vec::new();
    for entry in entries {
        let id = entry["id"].as_str().expect("id");
        let type_ = entry["type"].as_str().expect("type");
        let wire = entry["wire"].as_str().expect("wire");
        let reencoded = roundtrip(type_, wire)
            .unwrap_or_else(|error| fail(&format!("{} ({}): {}", id, type_, error)));
        let semantic = entry.get("semantic").and_then(Value::as_bool).unwrap_or(false);
        let matches = if semantic {
            json_equal(&parse(&reencoded), &parse(wire))
        } else {
            reencoded == wire
        };
        if !matches {
            fail(&format!("{} ({}): {} != {}", id, type_, reencoded, wire));
        }
        let mut result = serde_json::Map::new();
        result.insert("id".to_string(), Value::String(id.to_string()));
        result.insert("type".to_string(), Value::String(type_.to_string()));
        result.insert("wire".to_string(), Value::String(reencoded));
        if semantic {
            result.insert("semantic".to_string(), Value::Bool(true));
        }
        results.push(Value::Object(result));
    }
    std::fs::write(output_path, serde_json::to_string(&Value::Array(results)).unwrap())
        .expect("write output");
    println!("rust verified {} fixture(s)", entries.len());
}

fn verify(input_path: &str) {
    let entries = load(input_path);
    let entries = entries.as_array().expect("message corpus must be an array");
    for entry in entries {
        let id = entry["id"].as_str().expect("id");
        let type_ = entry["type"].as_str().expect("type");
        let wire = entry["wire"].as_str().expect("wire");
        let reencoded = roundtrip(type_, wire)
            .unwrap_or_else(|error| fail(&format!("{} ({}): {}", id, type_, error)));
        if !json_equal(&parse(&reencoded), &parse(wire)) {
            fail(&format!("{} ({}): {} != {}", id, type_, reencoded, wire));
        }
    }
    println!("rust decoded {} message(s) from peer", entries.len());
}

fn invalid(input_path: &str) {
    let entries = load(input_path);
    let entries = entries.as_array().expect("invalid corpus must be an array");
    for entry in entries {
        let id = entry["id"].as_str().expect("id");
        let type_ = entry["type"].as_str().expect("type");
        let wire = entry["wire"].as_str().expect("wire");
        if roundtrip(type_, wire).is_ok() {
            fail(&format!("{} ({}): invalid wire accepted", id, type_));
        }
    }
    println!("rust rejected {} invalid message(s)", entries.len());
}

fn expect(label: &str, got: &str, want: &str) {
    if got != want {
        fail(&format!("{}: {} != {}", label, got, want));
    }
}

fn expect_error(label: &str, call: impl FnOnce() -> Result<String, String>) {
    if call().is_ok() {
        fail(&format!("{} accepted by the runtime", label));
    }
}

fn unwrap_text(result: Result<String, generated_contracts::CyrografError>) -> Result<String, String> {
    result.map_err(|error| error.to_string())
}

fn optional() {
    let absent = orders::ReserveRequest {
        owner_id: "o1".to_string(),
        quantity: 2,
        note: None,
    };
    let present = orders::ReserveRequest {
        owner_id: "o1".to_string(),
        quantity: 2,
        note: Some(String::new()),
    };
    expect("absent string", &absent.to_drut().unwrap(), "[\"o1\",2,null]");
    expect("present empty string", &present.to_drut().unwrap(), "[\"o1\",2,\"\"]");
    if orders::ReserveRequest::from_drut("[\"o1\",2,null]").unwrap().note.is_some() {
        fail("decoded absent string is present");
    }
    if orders::ReserveRequest::from_drut("[\"o1\",2,\"\"]").unwrap().note.as_deref() != Some("") {
        fail("decoded empty string is not present empty");
    }

    let absent_list = orders::ListBox { items: None };
    let empty_list = orders::ListBox { items: Some(Vec::new()) };
    expect("absent list", &absent_list.to_drut().unwrap(), "[null]");
    expect("empty list", &empty_list.to_drut().unwrap(), "[[]]");
    if absent_list.to_drut().unwrap() == empty_list.to_drut().unwrap() {
        fail("empty optional and present empty list encode identically");
    }
    if orders::ListBox::from_drut("[[]]").unwrap().items.map(|items| items.len()) != Some(0) {
        fail("decoded empty list is not a present empty list");
    }

    let absent_variant = orders::ResponseBox { response: None };
    let present_variant = orders::ResponseBox {
        response: Some(orders::ReserveResponse::Unavailable),
    };
    expect("absent variant", &absent_variant.to_drut().unwrap(), "[null]");
    expect("present void variant", &present_variant.to_drut().unwrap(), "[[\"Unavailable\",null]]");

    expect_error("wrong required type", || {
        unwrap_text(orders::ReserveRequest::from_drut("[\"o1\",\"x\",null]").and_then(|value| value.to_drut()))
    });
    expect_error("null required string", || {
        unwrap_text(orders::ReserveRequest::from_drut("[null,2,null]").and_then(|value| value.to_drut()))
    });
    println!("rust optional checks passed");
}

pub(crate) fn run(arguments: &[String]) {
    if arguments.is_empty() {
        fail("missing interop mode");
    }
    match arguments[0].as_str() {
        "check" => check(&arguments[1], &arguments[2]),
        "verify" => verify(&arguments[1]),
        "invalid" => invalid(&arguments[1]),
        "optional" => optional(),
        other => fail(&format!("unknown interop mode {}", other)),
    }
}