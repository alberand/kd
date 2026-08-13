use anyhow::{bail, Context, Result};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

pub mod config;

fn nurl(repo: &str, rev: &str) -> Result<String> {
    println!("Fetching source for {} at {}", repo, rev);
    let output = Command::new("nurl")
        .arg("--fetcher")
        .arg("builtins.fetchGit")
        .arg("--arg")
        .arg("allRefs")
        .arg("true")
        .arg(repo)
        .arg(rev)
        .output()
        .context("Failed to fetch source with nurl")?;

    if !output.status.success() {
        bail!("{}", String::from_utf8_lossy(&output.stderr));
    }

    String::from_utf8(output.stdout).context("Failed to parse nurl output")
}

// Agh, so ugly
// TODO fix nrix to parse nix from rust

pub struct State {
    pub debug: bool,
    pub curdir: PathBuf,
    pub envdir: PathBuf,
    pub flake_dir: PathBuf,
    pub config: config::Config,
    pub user_config: PathBuf,
    pub args: Vec<String>,
    pub envs: HashMap<String, String>,
    pub name: String,
}

impl Default for State {
    fn default() -> Self {
        Self {
            debug: false,
            curdir: PathBuf::default(),
            envdir: PathBuf::default(),
            flake_dir: PathBuf::default(),
            config: config::Config::default(),
            user_config: PathBuf::default(),
            args: Vec::<String>::default(),
            envs: HashMap::<String, String>::default(),
            name: String::default(),
        }
    }
}

impl State {
    pub fn new(config_path: Option<PathBuf>) -> Result<Self> {
        let curdir = std::env::current_dir().context("Unable to read current directory")?;
        let config_path = if let Some(config_path) = config_path {
            config_path
        } else {
            curdir.clone().join(".kd.kdl")
        };

        let config = config::Config::load(&config_path)
            .map_err(|e| anyhow::anyhow!("{:?}", e))?;
        let envdir = curdir.clone().join(".kd");
        let flake_dir = envdir.clone().join("flake");
        let user_config = flake_dir.clone().join("uconfig.nix");

        Ok(Self {
            debug: false,
            curdir,
            envdir,
            flake_dir,
            config,
            user_config,
            args: vec![],
            envs: HashMap::new(),
            name: String::default(),
        })
    }
}

/// TODO all this parsing should be just done nrix
pub fn generate_uconfig(state: &mut State) -> Result<String> {
    Ok("".to_string())
}
