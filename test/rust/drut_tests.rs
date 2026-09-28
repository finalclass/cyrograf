use crate::wire::{self, Val};
use crate::{common, orders, CyrografError};
use serde_json::Value;

const PRIMITIVES: [&str; 7] = ["void", "int", "float", "bool", "string", "date", "record"];

fn roundtrip(name: &str, text: &str) -> Result<String, CyrografError> {
    match name {
        "Orders.ReserveRequest" => Ok(orders::ReserveRequest::from_drut(text)?.to_drut()?),
        "Orders.Reservation" => Ok(orders::Reservation::from_drut(text)?.to_drut()?),
        "Orders.Problem" => Ok(orders::Problem::from_drut(text)?.to_drut()?),
        "Orders.ReserveResponse" => Ok(orders::ReserveResponse::from_drut(text)?.to_drut()?),
        "Orders.ReservationBatch" => Ok(orders::ReservationBatch::from_drut(text)?.to_drut()?),
        "Orders.Guard" => Ok(orders::Guard::from_drut(text)?.to_drut()?),
        "Orders.ListBox" => Ok(orders::ListBox::from_drut(text)?.to_drut()?),
        "Orders.ResponseBox" => Ok(orders::ResponseBox::from_drut(text)?.to_drut()?),
        "Orders.Scalars" => Ok(orders::Scalars::from_drut(text)?.to_drut()?),
        "Common.UserCtx" => Ok(common::UserCtx::from_drut(text)?.to_drut()?),
        "Common.Wrapper" => Ok(common::Wrapper::from_drut(text)?.to_drut()?),
        "Common.Blob" => Ok(common::Blob::from_drut(text)?.to_drut()?),
        "Common.Empty" => Ok(common::Empty::from_drut(text)?.to_drut()?),
        "Common.VoidBox" => Ok(common::VoidBox::from_drut(text)?.to_drut()?),
        _ => Err(CyrografError::new("UnknownType", "", name)),
    }
}

fn named(descriptor: &Value) -> Option<&str> {
    match descriptor {
        Value::String(name) if !PRIMITIVES.contains(&name.as_str()) => Some(name),
        _ => None,
    }
}

fn failure(code: &str, message: &str) -> CyrografError {
    CyrografError::new(code, "", message)
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

fn hex_to_bytes(hex: &str) -> Result<Vec<u8>, CyrografError> {
    let bytes = hex.as_bytes();
    if bytes.len() % 2 != 0 {
        return Err(failure("InvalidHex", "odd hex length"));
    }
    let mut output = Vec::with_capacity(bytes.len() / 2);
    let mut index = 0;
    while index < bytes.len() {
        let high = (bytes[index] as char)
            .to_digit(16)
            .ok_or_else(|| failure("InvalidHex", "invalid hex digit"))?;
        let low = (bytes[index + 1] as char)
            .to_digit(16)
            .ok_or_else(|| failure("InvalidHex", "invalid hex digit"))?;
        output.push((high * 16 + low) as u8);
        index += 2;
    }
    Ok(output)
}

fn case_text(item: &Value) -> Result<String, CyrografError> {
    if let Some(text) = item.get("wire").and_then(Value::as_str) {
        return Ok(text.to_string());
    }
    if let Some(hex) = item.get("wire_hex").and_then(Value::as_str) {
        let bytes = hex_to_bytes(hex)?;
        return String::from_utf8(bytes).map_err(|_| failure("InvalidUtf8", "wire bytes"));
    }
    Err(failure("MalformedCase", "case has neither wire nor wire_hex"))
}

fn decode_desc(descriptor: &Value, value: &Val) -> Result<Value, CyrografError> {
    if let Value::String(name) = descriptor {
        return match name.as_str() {
            "void" => {
                wire::decode_void(value, "")?;
                Ok(Value::Null)
            }
            "int" => Ok(Value::from(wire::as_int(value, "")?)),
            "float" => Ok(Value::from(wire::as_float(value, "")?)),
            "bool" => Ok(Value::Bool(wire::as_bool(value, "")?)),
            "string" | "date" => Ok(Value::String(wire::as_string(value, "")?.to_string())),
            "record" => Ok(Value::Object(wire::as_record(value, "")?)),
            other => Err(failure("UnknownPrimitive", other)),
        };
    }
    if let Value::Object(object) = descriptor {
        if let Some(inner) = object.get("list") {
            let array = wire::as_array(value, "", None)?;
            let mut output = Vec::with_capacity(array.len());
            for item in array {
                output.push(decode_desc(inner, item)?);
            }
            return Ok(Value::Array(output));
        }
    }
    Err(failure("UnsupportedDescriptor", "root descriptor"))
}

fn run_case(item: &Value) -> Result<Value, CyrografError> {
    let raw = case_text(item)?;
    let descriptor = item.get("type").ok_or_else(|| failure("MalformedCase", "type"))?;
    if let Some(name) = named(descriptor) {
        let text = roundtrip(name, &raw)?;
        return serde_json::from_str(&text)
            .map_err(|_| failure("InvalidJson", "roundtrip output"));
    }
    let value = wire::parse_text(&raw)?;
    decode_desc(descriptor, &value)
}

fn category(item: &Value) -> String {
    if let Some(category) = item.get("category").and_then(Value::as_str) {
        return category.to_string();
    }
    if named(&item["type"]).is_some() {
        "public".to_string()
    } else {
        "runtime".to_string()
    }
}

fn inexpressible(item: &Value) -> bool {
    item.get("utf8_invalid").and_then(Value::as_bool).unwrap_or(false)
}

fn entry(id: &str, status: &str) -> Value {
    serde_json::json!({ "id": id, "status": status })
}

fn read_array(path: &str) -> Value {
    let text = std::fs::read_to_string(path).expect("read corpus");
    serde_json::from_str(&text).expect("corpus JSON")
}

#[test]
fn drut_corpus() {
    let valid_path = std::env::var("CYROGRAF_DRUT_VALID").expect("CYROGRAF_DRUT_VALID");
    let invalid_path = std::env::var("CYROGRAF_DRUT_INVALID").expect("CYROGRAF_DRUT_INVALID");
    let output_path = std::env::var("CYROGRAF_DRUT_OUT").expect("CYROGRAF_DRUT_OUT");

    let valid = read_array(&valid_path);
    let valid = valid.as_array().unwrap();
    let invalid = read_array(&invalid_path);
    let invalid = invalid.as_array().unwrap();

    let mut results = Vec::new();
    for item in valid {
        let id = item["id"].as_str().unwrap();
        if inexpressible(item) {
            results.push(entry(id, "inexpressible"));
            continue;
        }
        let produced = match run_case(item) {
            Ok(value) => value,
            Err(error) => panic!("{}: {}", id, error),
        };
        let expected = if named(&item["type"]).is_some() {
            serde_json::from_str(item["wire"].as_str().unwrap()).unwrap()
        } else {
            item["value"].clone()
        };
        if !json_equal(&produced, &expected) {
            panic!("{}: produced value does not match the expected value", id);
        }
        let status = if category(item) == "public" { "executed" } else { "executed-runtime" };
        results.push(entry(id, status));
    }
    for item in invalid {
        let id = item["id"].as_str().unwrap();
        if inexpressible(item) {
            results.push(entry(id, "inexpressible"));
            continue;
        }
        match run_case(item) {
            Err(_) => {
                let status = if category(item) == "public" { "rejected" } else { "rejected-runtime" };
                results.push(entry(id, status));
            }
            Ok(_) => panic!("{}: invalid wire accepted", id),
        }
    }
    std::fs::write(&output_path, serde_json::to_string(&Value::Array(results)).unwrap())
        .expect("write results");
    println!("rust drut: {} executed, {} rejected", valid.len(), invalid.len());
}