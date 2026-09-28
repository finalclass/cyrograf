mod consumer_positive;
mod interop;
mod mix_check;
mod optional_matrix;

fn main() {
    let arguments: Vec<String> = std::env::args().collect();
    if arguments.len() < 2 {
        eprintln!("usage: cyrograf-rust-tests <interop|optional|mix|consumer> ...");
        std::process::exit(2);
    }
    match arguments[1].as_str() {
        "interop" => interop::run(&arguments[2..]),
        "optional" => optional_matrix::run(&arguments[2..]),
        "mix" => mix_check::run(),
        "consumer" => consumer_positive::run(),
        other => {
            eprintln!("unknown mode {}", other);
            std::process::exit(2);
        }
    }
}