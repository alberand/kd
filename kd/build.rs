use clap::{ValueEnum, CommandFactory};
use clap_complete::{generate_to, Shell};
use std::env;
use std::io::Error;

#[path = "src/common.rs"] pub mod common;

include!("src/cli.rs");

fn main() -> Result<(), Error> {
    let outdir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("completions/");
    std::fs::create_dir_all(&outdir)?;

    println!("cargo:warning=completions go to {outdir:?}");

    let mut cmd = Cli::command();
    for &shell in Shell::value_variants() {
        generate_to(shell, &mut cmd, "kd", &outdir)?;
    }

    Ok(())
}
