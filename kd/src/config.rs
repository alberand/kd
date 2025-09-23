use serde::{Deserialize, Serialize};
use std::fs;
use std::io::{Error, ErrorKind, Write};
use std::path::PathBuf;
use toml;
use toml::Table;

use super::utils::KdError;

#[derive(Serialize, Deserialize)]
pub struct KernelConfigOption {
    pub name: String,
    pub value: String,
}

#[derive(Serialize, Deserialize, Default)]
pub struct KernelConfig {
    pub prebuild: Option<bool>,
    pub version: Option<String>,
    pub rev: Option<String>,
    pub repo: Option<String>,
    pub flavors: Option<Vec<String>>,
    pub config: Option<Table>,
}

fn default_xfstests() -> Option<String> {
    Some("git://git.kernel.org/pub/scm/fs/xfs/xfstests-dev.git".to_string())
}

#[derive(Serialize, Deserialize, Default)]
pub struct XfstestsConfig {
    #[serde(default = "default_xfstests")]
    pub repo: Option<String>,
    pub rev: Option<String>,
    pub args: Option<String>,
    pub test_dev: Option<String>,
    pub scratch_dev: Option<String>,
    pub extra_env: Option<String>,
    pub filesystem: Option<String>,
    pub hooks: Option<String>,
}

fn default_xfsprogs() -> Option<String> {
    Some("git://git.kernel.org/pub/scm/fs/xfs/xfsprogs-dev.git".to_string())
}

fn default_name() -> String {
    "default".to_string()
}

#[derive(Serialize, Deserialize)]
pub struct XfsprogsConfig {
    #[serde(default = "default_xfsprogs")]
    pub repo: Option<String>,
    pub rev: Option<String>,
}

#[derive(Serialize, Deserialize, Default)]
pub struct ScriptConfig {
    pub script: String,
}

#[derive(Serialize, Deserialize, Default)]
pub struct QemuConfig {
    pub options: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Default)]
pub struct Config {
    #[serde(default = "default_name")]
    pub name: String,
    pub packages: Option<Vec<String>>,
    pub kernel: Option<KernelConfig>,
    pub xfstests: Option<XfstestsConfig>,
    pub xfsprogs: Option<XfsprogsConfig>,
    pub script: Option<ScriptConfig>,
    pub qemu: Option<QemuConfig>,
}

impl Config {
    pub fn load(path: PathBuf) -> Result<Self, Error> {
        if !path.exists() {
            return Err(Error::new(ErrorKind::NotFound, "config file not found"));
        }

        let data = fs::read_to_string(path).expect("Unable to read file");
        let config: Config = toml::from_str(&data).unwrap();

        Ok(config)
    }

    pub fn _save(&self, path: PathBuf) -> Result<(), Error> {
        let mut buffer = std::fs::File::create(path)?;
        buffer.write_all(toml::to_string(self).unwrap().as_bytes())
    }

    pub fn validate(&self) -> Result<(), KdError> {
        if let Some(subconfig) = &self.kernel {
            let kernel = subconfig.version.is_some() ||
                subconfig.rev.is_some() ||
                subconfig.repo.is_some() ||
                subconfig.config.is_some();
            if subconfig.prebuild.is_some() && kernel {
                println!("Note! You're using 'prebuild', none of the [kernel] options applies.");
            }
        }

        return Ok(())
    }
}
