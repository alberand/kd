use anyhow::{bail, Context, Result};
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{absolute, Path, PathBuf};
use toml;
use toml::Table;

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
}

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
            if self.kernel.is_none() {
                self.kernel = Some(KernelConfig::default());
            }

            if let Some(me) = &mut self.kernel {
                if let Some(prebuild) = kernel.prebuild {
                    me.prebuild = Some(prebuild);
                }

                if let Some(version) = kernel.version {
                    me.version = Some(version);
                }

                if let Some(rev) = kernel.rev {
                    me.rev = Some(rev);
                }

                if let Some(repo) = kernel.repo {
                    me.repo = Some(repo);
                }

                if let Some(flavors) = kernel.flavors {
                    me.flavors = Some(flavors);
                }

                if let Some(config) = kernel.config {
                    me.config = Some(config);
                }
            }
        }

        if let Some(xfstests) = config.xfstests {
            if self.xfstests.is_none() {
                self.xfstests = Some(XfstestsConfig::default());
            }

            if let Some(me) = &mut self.xfstests {
                if let Some(repo) = xfstests.repo {
                    me.repo = Some(repo);
                }

                if let Some(rev) = xfstests.rev {
                    me.rev = Some(rev);
                }

                if let Some(args) = xfstests.args {
                    me.args = Some(args);
                }

                if let Some(devices) = xfstests.devices {
                    me.devices = Some(devices);
                };

                if let Some(extra_env) = xfstests.extra_env {
                    me.extra_env = Some(extra_env);
                }

                if let Some(filesystem) = xfstests.filesystem {
                    me.filesystem = Some(filesystem);
                }

                if let Some(hooks) = xfstests.hooks {
                    me.hooks = Some(hooks);
                }

                if let Some(kernel_headers) = xfstests.kernel_headers {
                    me.kernel_headers = Some(kernel_headers);
                }
            }
        }

        if let Some(xfsprogs) = config.xfsprogs {
            if self.xfsprogs.is_none() {
                self.xfsprogs = Some(XfsprogsConfig::default());
            }

            if let Some(me) = &mut self.xfsprogs {
                if let Some(repo) = xfsprogs.repo {
                    me.repo = Some(repo);
                }

                if let Some(rev) = xfsprogs.rev {
                    me.rev = Some(rev);
                }

                if let Some(kernel_headers) = xfsprogs.kernel_headers {
                    me.kernel_headers = Some(kernel_headers);
                }
            }
        }

        if let Some(script) = config.script {
            self.script = Some(script);
        }

        self
    }
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct DevConfig {
    pub args: Option<Vec<String>>,
}

#[derive(Serialize, Deserialize, Default, Clone, Debug)]
pub struct Config {
    pub packages: Option<Vec<String>>,
    pub kernel: Option<KernelConfig>,
    pub xfstests: Option<XfstestsConfig>,
    pub xfsprogs: Option<XfsprogsConfig>,
    pub script: Option<ScriptConfig>,
    pub qemu: Option<QemuConfig>,
    pub common: Option<SystemConfig>,
    pub named: Option<Table>,
    pub dev: Option<DevConfig>,
}

impl Config {
    pub fn load<T: AsRef<Path>>(path: T) -> Result<Self> {
        let data = fs::read_to_string(path).context("Failed to read config")?;
        let config: Config = toml::from_str(&data).context("Invalid TOML")?;

        Ok(config)
    }

    pub fn validate(&self) -> Result<()> {
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
                    bail!("You are missing 'repo' parameter for kernel headers");
                }
                if subconfig.rev.is_none() {
                    bail!("You are missing 'rev' parameter for kernel headers");
                }
                if subconfig.version.is_none() {
                    bail!("You are missing 'version' parameter for kernel headers");
                }
            }
        }

        if let Some(subconfig) = &self.xfstests {
            if let Some(subconfig) = &subconfig.kernel_headers {
                if subconfig.repo.is_none() {
                    bail!("You are missing 'repo' parameter for kernel headers");
                }
                if subconfig.rev.is_none() {
                    bail!("You are missing 'rev' parameter for kernel headers");
                }
                if subconfig.version.is_none() {
                    bail!("You are missing 'version' parameter for kernel headers");
                }
            }

            if let Some(hooks) = &subconfig.hooks {
                let path = PathBuf::from(hooks);
                if !path.exists() {
                    let cwd = std::env::current_dir()
                        .context("Failed to retrieve current working dir")?;
                    bail!("Failed to find '{:?}' dir (cwd is {:?})", path, cwd);
                }
            }
        }

        if let Some(subconfig) = &self.kernel {
            if subconfig.repo.is_some() && subconfig.rev.is_none() && subconfig.version.is_none() {
                bail!("While using 'repo' rev/version need to be set");
            }

            if subconfig.rev.is_some() && subconfig.version.is_none() {
                bail!("Revision can not be used without 'version'");
            }

            if let Some(kernel) = &subconfig.prebuild {
                let curdir =
                    std::env::current_dir().context("No able to get current working directory")?;

                let path = absolute(curdir.join(kernel)).context("Failed to parse kernel path")?;

                if !(path.exists()) {
                    bail!("Kernel doesn't exists: {}", kernel);
                }
            }
        }

        return Ok(());
    }
}
