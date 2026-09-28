use generated_contracts::python::{Empty, Mix};

fn fail(message: &str) -> ! {
    eprintln!("FAIL: {}", message);
    std::process::exit(1);
}

fn expect(label: &str, got: &str, want: &str) {
    if got != want {
        fail(&format!("{}: {} != {}", label, got, want));
    }
}

pub(crate) fn run() {
    let absent = Mix {
        name: "n".to_string(),
        blob: None,
        voids: Vec::new(),
    };
    expect("absent record", &absent.to_drut().unwrap(), "[\"n\",null,[]]");

    let record = serde_json::json!({"k": [1, 2], "n": null})
        .as_object()
        .unwrap()
        .clone();
    let present = Mix {
        name: "n".to_string(),
        blob: Some(record),
        voids: Vec::new(),
    };
    expect("present record", &present.to_drut().unwrap(), "[\"n\",{\"k\":[1,2],\"n\":null},[]]");
    if absent.to_drut().unwrap() == present.to_drut().unwrap() {
        fail("absent and present record encode identically");
    }
    if Mix::from_drut("[\"n\",null,[]]").unwrap().blob.is_some() {
        fail("decoded absent record is present");
    }
    let decoded = Mix::from_drut("[\"n\",{\"k\":[1,2],\"n\":null},[]]").unwrap();
    match decoded.blob {
        Some(map) if map.get("k") == Some(&serde_json::json!([1, 2])) => {}
        _ => fail("decoded record value differs"),
    }

    let voids = Mix {
        name: "n".to_string(),
        blob: None,
        voids: vec![(), ()],
    };
    expect("list of void", &voids.to_drut().unwrap(), "[\"n\",null,[null,null]]");
    if Mix::from_drut("[\"n\",null,[null,null]]").unwrap().voids.len() != 2 {
        fail("decoded list of void differs");
    }

    expect("empty structure", &Empty::from_drut("[]").unwrap().to_drut().unwrap(), "[]");
    if Mix::from_drut("[\"n\",{\"k\":1},[]]extra").is_ok() {
        fail("trailing text accepted");
    }
    if Mix::from_drut("[\"n\",{\"k\":1,\"k\":2},[]]").is_ok() {
        fail("duplicate record key accepted");
    }
    println!("rust mix checks passed");
}