use anyhow::{bail, Context, Result};
use std::collections::HashMap;
use std::path::PathBuf;
use std::process::Command;

pub mod config;

fn _nurl(repo: &str, rev: &str) -> Result<String> {
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

pub struct State {
    pub debug: bool,
    pub curdir: PathBuf,
    pub config: config::Config,
    pub args: Vec<String>,
    pub envs: HashMap<String, String>,
    pub name: Vec<String>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            debug: false,
            curdir: PathBuf::default(),
            config: config::Config::default(),
            args: Vec::<String>::default(),
            envs: HashMap::<String, String>::default(),
            name: vec![],
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

        let config = config::Config::load(&config_path).map_err(|e| anyhow::anyhow!("{:?}", e))?;

        Ok(Self {
            debug: false,
            curdir,
            config,
            args: vec![],
            envs: HashMap::new(),
            name: vec![],
        })
    }
}

/// TODO all this parsing should be just done nrix
pub fn generate_uconfig(_state: &mut State) -> Result<String> {
    Ok("".to_string())
}
