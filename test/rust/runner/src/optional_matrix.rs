use generated_contracts::api::{Choice, OptionalBox};
use serde_json::Value;

fn fail(message: &str) -> ! {
    eprintln!("FAIL: {}", message);
    std::process::exit(1);
}

fn cases() -> Vec<(&'static str, OptionalBox)> {
    vec![
        ("absent", OptionalBox {
            owner_id: "o1".to_string(),
            text: None,
            count: None,
            flag: None,
            items: None,
            choice: None,
        }),
        ("empty_string", OptionalBox {
            owner_id: "o1".to_string(),
            text: Some(String::new()),
            count: None,
            flag: None,
            items: None,
            choice: None,
        }),
        ("zero", OptionalBox {
            owner_id: "o1".to_string(),
            text: None,
            count: Some(0),
            flag: None,
            items: None,
            choice: None,
        }),
        ("false", OptionalBox {
            owner_id: "o1".to_string(),
            text: None,
            count: None,
            flag: Some(false),
            items: None,
            choice: None,
        }),
        ("empty_list", OptionalBox {
            owner_id: "o1".to_string(),
            text: None,
            count: None,
            flag: None,
            items: Some(Vec::new()),
            choice: None,
        }),
        ("variant_text", OptionalBox {
            owner_id: "o1".to_string(),
            text: None,
            count: None,
            flag: None,
            items: None,
            choice: Some(Choice::Text("x".to_string())),
        }),
        ("variant_void", OptionalBox {
            owner_id: "o1".to_string(),
            text: None,
            count: None,
            flag: None,
            items: None,
            choice: Some(Choice::Empty),
        }),
        ("all_present", OptionalBox {
            owner_id: "o1".to_string(),
            text: Some(String::new()),
            count: Some(0),
            flag: Some(false),
            items: Some(Vec::new()),
            choice: Some(Choice::Empty),
        }),
    ]
}

fn check_semantics(id: &str, value: &OptionalBox) {
    let absent_items = value.items.is_none();
    let expected = match id {
        "absent" => value.text.is_none() && value.count.is_none() && value.flag.is_none()
            && absent_items && value.choice.is_none(),
        "empty_string" => value.text.as_deref() == Some("")
            && value.count.is_none() && value.flag.is_none() && absent_items && value.choice.is_none(),
        "zero" => value.text.is_none() && value.count == Some(0)
            && value.flag.is_none() && absent_items && value.choice.is_none(),
        "false" => value.text.is_none() && value.count.is_none() && value.flag == Some(false)
            && absent_items && value.choice.is_none(),
        "empty_list" => value.text.is_none() && value.count.is_none() && value.flag.is_none()
            && value.items.as_ref().map(|items| items.len()) == Some(0) && value.choice.is_none(),
        "variant_text" => value.text.is_none() && value.count.is_none() && value.flag.is_none()
            && absent_items
            && matches!(&value.choice, Some(Choice::Text(text)) if text == "x"),
        "variant_void" => value.text.is_none() && value.count.is_none() && value.flag.is_none()
            && absent_items && matches!(value.choice, Some(Choice::Empty)),
        "all_present" => value.text.as_deref() == Some("") && value.count == Some(0)
            && value.flag == Some(false)
            && value.items.as_ref().map(|items| items.len()) == Some(0)
            && matches!(value.choice, Some(Choice::Empty)),
        _ => false,
    };
    if !expected {
        fail(&format!("case {} decoded to the wrong typed value", id));
    }
    if value.owner_id != "o1" {
        fail(&format!("case {} lost the required field", id));
    }
}

fn produce(cases_path: &str, output_path: &str) {
    let text = std::fs::read_to_string(cases_path).expect("read cases");
    let parsed = serde_json::from_str::<Value>(&text).expect("cases JSON");
    let entries = parsed.as_array().expect("cases array");
    let mut expected = std::collections::HashMap::new();
    for entry in entries {
        expected.insert(
            entry["id"].as_str().unwrap().to_string(),
            entry["wire"].as_str().unwrap().to_string(),
        );
    }
    let mut produced = Vec::new();
    for (id, value) in cases() {
        let wire = value.to_drut().expect("encode");
        match expected.get(id) {
            Some(want) if want == &wire => {}
            Some(want) => fail(&format!("case {} encoded {}, expected {}", id, wire, want)),
            None => fail(&format!("no canonical wire for case {}", id)),
        }
        produced.push(serde_json::json!({ "id": id, "wire": wire }));
    }
    std::fs::write(output_path, serde_json::to_string(&Value::Array(produced)).unwrap())
        .expect("write output");
    println!("rust produced {} optional case(s)", entries.len());
}

fn consume(peer_path: &str) {
    let text = std::fs::read_to_string(peer_path).expect("read peer");
    let entries = serde_json::from_str::<Value>(&text).expect("peer JSON");
    let entries = entries.as_array().expect("peer array");
    for entry in entries {
        let id = entry["id"].as_str().unwrap();
        let wire = entry["wire"].as_str().unwrap();
        let value = OptionalBox::from_drut(wire).expect("decode peer case");
        check_semantics(id, &value);
        let reencoded = value.to_drut().expect("re-encode");
        if reencoded != wire {
            fail(&format!("case {} re-encoded {}, received {}", id, reencoded, wire));
        }
    }
    println!("rust consumed {} optional case(s)", entries.len());
}

pub(crate) fn run(arguments: &[String]) {
    if arguments.is_empty() {
        fail("missing optional mode");
    }
    match arguments[0].as_str() {
        "produce" => produce(&arguments[1], &arguments[2]),
        "consume" => consume(&arguments[1]),
        other => fail(&format!("unknown optional mode {}", other)),
    }
}