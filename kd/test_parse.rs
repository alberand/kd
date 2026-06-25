use std::fs;

fn main() {
    let data = fs::read_to_string("tests/assets/config.kdl").unwrap();
    let config: kd::config::Config = knuffel::parse("config.kdl", &data).unwrap();
    println!("Parsed successfully: {:?}", config);
}
