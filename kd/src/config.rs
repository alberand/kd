use serde::{Deserialize, Serialize};
use std::fs;
use std::io::Write;
use std::path::{absolute, Path, PathBuf};
use toml;
use toml::Table;

use super::utils::{KdError, KdErrorKind};

#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct KernelConfigOption {
    pub name: String,
    pub value: String,
}

#[derive(Serialize, Deserialize, Clone, Default, Debug)]
pub struct KernelHeaders {
    pub version: Option<String>,
    pub rev: Option<String>,
    pub repo: Option<String>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct KernelConfig {
    pub prebuild: Option<String>,
    pub version: Option<String>,
    pub rev: Option<String>,
    pub repo: Option<String>,
    pub flavors: Option<Vec<String>>,
    pub config: Option<Table>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct XfstestsDevices {
    pub test: Option<String>,
    pub test_rtdev: Option<String>,
    pub test_logdev: Option<String>,
    pub scratch: Option<String>,
    pub scratch_rtdev: Option<String>,
    pub scratch_logdev: Option<String>,
};

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct XfstestsConfig {
    pub repo: Option<String>,
    pub rev: Option<String>,
    pub devices: Option<XfstestsDevices>,
    pub args: Option<String>,
    pub extra_env: Option<String>,
    pub filesystem: Option<String>,
    pub hooks: Option<String>,
    pub kernel_headers: Option<KernelHeaders>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct XfsprogsConfig {
    pub repo: Option<String>,
    pub rev: Option<String>,
    pub kernel_headers: Option<KernelHeaders>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct ScriptConfig {
    pub script: String,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct QemuConfig {
    pub options: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct SystemConfig {
    pub kernel: Option<KernelConfig>,
    pub xfstests: Option<XfstestsConfig>,
    pub xfsprogs: Option<XfsprogsConfig>,
    pub script: Option<ScriptConfig>,
}

impl SystemConfig {
    pub fn merge(&mut self, config: SystemConfig) -> &Self {
        if let Some(kernel) = config.kernel {
            let mut new = KernelConfig::default();

            if let Some(prebuild) = kernel.prebuild {
                new.prebuild = Some(prebuild);
            }

            if let Some(version) = kernel.version {
                new.version = Some(version);
            }

            if let Some(rev) = kernel.rev {
                new.rev = Some(rev);
            }

            if let Some(repo) = kernel.repo {
                new.repo = Some(repo);
            }

            if let Some(flavors) = kernel.flavors {
                new.flavors = Some(flavors);
            }

            if let Some(config) = kernel.config {
                new.config = Some(config);
            }

            self.kernel = Some(new);
        }

        if let Some(xfstests) = config.xfstests {
            let mut new = XfstestsConfig::default();

            if let Some(repo) = xfstests.repo {
                new.repo = Some(repo);
            }

            if let Some(rev) = xfstests.rev {
                new.rev = Some(rev);
            }

            if let Some(args) = xfstests.args {
                new.args = Some(args);
            }

            if let Some(test_dev) = xfstests.test_dev {
                new.test_dev = Some(test_dev);
            }

            if let Some(scratch_dev) = xfstests.scratch_dev {
                new.scratch_dev = Some(scratch_dev);
            }

            if let Some(extra_env) = xfstests.extra_env {
                new.extra_env = Some(extra_env);
            }

            if let Some(filesystem) = xfstests.filesystem {
                new.filesystem = Some(filesystem);
            }

            if let Some(hooks) = xfstests.hooks {
                new.hooks = Some(hooks);
            }

            if let Some(kernel_headers) = xfstests.kernel_headers {
                new.kernel_headers = Some(kernel_headers);
            }

            self.xfstests = Some(new);
        }

        if let Some(xfsprogs) = config.xfsprogs {
            let mut new = XfsprogsConfig::default();

            if let Some(repo) = xfsprogs.repo {
                new.repo = Some(repo);
            }

            if let Some(rev) = xfsprogs.rev {
                new.rev = Some(rev);
            }

            if let Some(kernel_headers) = xfsprogs.kernel_headers {
                new.kernel_headers = Some(kernel_headers);
            }

            self.xfsprogs = Some(new);
        }

        if let Some(script) = config.script {
            self.script = Some(script);
        }

        self
    }
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct MatrixConfig {
    pub common: Option<SystemConfig>,
    pub run: Table,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct Config {
    pub packages: Option<Vec<String>>,
    pub kernel: Option<KernelConfig>,
    pub xfstests: Option<XfstestsConfig>,
    pub xfsprogs: Option<XfsprogsConfig>,
    pub script: Option<ScriptConfig>,
    pub qemu: Option<QemuConfig>,
    pub matrix: Option<MatrixConfig>,
}

impl Config {
    pub fn load<T: AsRef<Path>>(path: T) -> Result<Self, KdError> {
        if !path.as_ref().exists() {
            return Err(KdError::new(
                KdErrorKind::RuntimeError,
                "config file not found".to_string(),
            ));
        }

        let data = fs::read_to_string(path)
            .map_err(|e| KdError::new(KdErrorKind::IOError(e), "can not read".to_string()))?;
        let config: Config = toml::from_str(&data)
            .map_err(|e| KdError::new(KdErrorKind::TOMLError(e), "invalid TOML".to_string()))?;

        Ok(config)
    }

    pub fn _save<T: AsRef<Path>>(&self, path: T) -> Result<(), KdError> {
        let mut buffer = std::fs::File::create(path)
            .map_err(|e| KdError::new(KdErrorKind::IOError(e), "failed to create".to_string()))?;
        buffer
            .write_all(toml::to_string(self).unwrap().as_bytes())
            .map_err(|e| KdError::new(KdErrorKind::IOError(e), "failed to write".to_string()))?;

        Ok(())
    }

    pub fn validate(&self) -> Result<(), KdError> {
        if let Some(subconfig) = &self.kernel {
            let kernel = subconfig.version.is_some()
                || subconfig.rev.is_some()
                || subconfig.repo.is_some()
                || subconfig.config.is_some();
            if subconfig.prebuild.is_some() && kernel {
                println!("Note! You're using 'prebuild', none of the [kernel] options applies.");
            }
        }

        if let Some(subconfig) = &self.xfsprogs {
            if let Some(subconfig) = &subconfig.kernel_headers {
                if subconfig.repo.is_none() {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        "You are missing 'repo' parameter for kernel headers".to_owned(),
                    ));
                }
                if subconfig.rev.is_none() {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        "You are missing 'rev' parameter for kernel headers".to_owned(),
                    ));
                }
                if subconfig.version.is_none() {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        "You are missing 'version' parameter for kernel headers".to_owned(),
                    ));
                }
            }
        }

        if let Some(subconfig) = &self.xfstests {
            if let Some(subconfig) = &subconfig.kernel_headers {
                if subconfig.repo.is_none() {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        "You are missing 'repo' parameter for kernel headers".to_owned(),
                    ));
                }
                if subconfig.rev.is_none() {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        "You are missing 'rev' parameter for kernel headers".to_owned(),
                    ));
                }
                if subconfig.version.is_none() {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        "You are missing 'version' parameter for kernel headers".to_owned(),
                    ));
                }
            }

            if let Some(hooks) = &subconfig.hooks {
                let path = PathBuf::from(hooks);
                if !path.exists() {
                    let cwd =
                        std::env::current_dir().expect("Failed to retrieve current working dir");
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        format!("Failed to find '{:?}' dir (cwd is {:?})", path, cwd),
                    ));
                }
            }
        }

        if let Some(subconfig) = &self.kernel {
            if subconfig.repo.is_some() && subconfig.rev.is_none() && subconfig.version.is_none() {
                return Err(KdError::new(
                    KdErrorKind::ConfigError,
                    "While using 'repo' rev/version need to be set".to_owned(),
                ));
            }

            if subconfig.rev.is_some() && subconfig.version.is_none() {
                return Err(KdError::new(
                    KdErrorKind::ConfigError,
                    "Revision can not be used without 'version'".to_owned(),
                ));
            }

            if let Some(kernel) = &subconfig.prebuild {
                let curdir = std::env::current_dir().map_err(|e| {
                    KdError::new(
                        KdErrorKind::IOError(e),
                        "No able to get current working directory".to_string(),
                    )
                })?;

                let path = absolute(curdir.join(kernel))
                    .map_err(|e| {
                        KdError::new(
                            KdErrorKind::ConfigError,
                            format!("Failed to parse kernel path: {}", e.to_string()),
                        )
                    })
                    .unwrap();

                if !(path.exists()) {
                    return Err(KdError::new(
                        KdErrorKind::ConfigError,
                        format!("Kernel doesn't exists: {}", kernel),
                    ));
                }
            }
        }

        return Ok(());
    }
}
