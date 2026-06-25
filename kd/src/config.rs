use anyhow::{bail, Context, Result};
use knuffel::Decode;
use std::collections::HashMap;
use std::fs;
use std::path::{absolute, Path, PathBuf};

#[derive(Decode, Clone, Default, Debug)]
pub struct KernelConfigOption {
    #[knuffel(argument)]
    pub name: String,
    #[knuffel(argument)]
    pub value: String,
}

#[derive(Decode, Clone, Default, Debug)]
pub struct KernelHeaders {
    #[knuffel(property)]
    pub version: Option<String>,
    #[knuffel(property)]
    pub rev: Option<String>,
    #[knuffel(property)]
    pub repo: Option<String>,
}

#[derive(Decode, Clone, Debug)]
pub struct Flavor {
    #[knuffel(argument)]
    pub name: String,
}

#[derive(knuffel::Decode, Clone, Debug)]
pub struct KString {
    #[knuffel(argument)]
    pub path: String,
}

#[derive(Decode, Default, Clone, Debug)]
pub struct KernelConfig {
    #[knuffel(child)]
    pub prebuild: Option<KString>,
    #[knuffel(property)]
    pub version: Option<String>,
    #[knuffel(property)]
    pub rev: Option<String>,
    #[knuffel(property)]
    pub repo: Option<String>,
    #[knuffel(children(name = "config"))]
    pub config_options: Vec<KernelConfigOption>,
}

impl KernelConfig {
    pub fn config(&self) -> Option<HashMap<String, String>> {
        if self.config_options.is_empty() {
            None
        } else {
            let mut map = HashMap::new();
            for opt in &self.config_options {
                map.insert(opt.name.clone(), opt.value.clone());
            }
            Some(map)
        }
    }
}

#[derive(Decode, Default, Clone, Debug)]
pub struct XfstestsDevices {
    #[knuffel(property)]
    pub test: Option<String>,
    #[knuffel(property)]
    pub test_rtdev: Option<String>,
    #[knuffel(property)]
    pub test_logdev: Option<String>,
    #[knuffel(property)]
    pub scratch: Option<String>,
    #[knuffel(property)]
    pub scratch_rtdev: Option<String>,
    #[knuffel(property)]
    pub scratch_logdev: Option<String>,
}

#[derive(Decode, Default, Clone, Debug)]
pub struct XfstestsConfig {
    #[knuffel(property)]
    pub repo: Option<String>,
    #[knuffel(property)]
    pub rev: Option<String>,
    #[knuffel(child)]
    pub devices: Option<XfstestsDevices>,
    #[knuffel(property)]
    pub args: Option<String>,
    #[knuffel(property)]
    pub extra_env: Option<String>,
    #[knuffel(property)]
    pub filesystem: Option<String>,
    #[knuffel(property)]
    pub hooks: Option<String>,
    #[knuffel(child)]
    pub kernel_headers: Option<KernelHeaders>,
}

#[derive(Decode, Default, Clone, Debug)]
pub struct XfsprogsConfig {
    #[knuffel(property)]
    pub repo: Option<String>,
    #[knuffel(property)]
    pub rev: Option<String>,
    #[knuffel(child)]
    pub kernel_headers: Option<KernelHeaders>,
}

#[derive(Decode, Default, Clone, Debug)]
pub struct ScriptConfig {
    #[knuffel(property)]
    pub script: Option<String>,
}

#[derive(Decode, Clone, Debug)]
pub struct QemuOption {
    #[knuffel(argument)]
    pub value: String,
}

#[derive(Decode, Default, Clone, Debug)]
pub struct QemuConfig {
    #[knuffel(children(name = "option"))]
    pub options_vec: Vec<QemuOption>,
}

impl QemuConfig {
    pub fn options(&self) -> Option<Vec<String>> {
        if self.options_vec.is_empty() {
            None
        } else {
            Some(self.options_vec.iter().map(|o| o.value.clone()).collect())
        }
    }
}

#[derive(Decode, Default, Clone, Debug)]
pub struct SystemConfig {
    #[knuffel(child)]
    pub kernel: Option<KernelConfig>,
    #[knuffel(child)]
    pub xfstests: Option<XfstestsConfig>,
    #[knuffel(child)]
    pub xfsprogs: Option<XfsprogsConfig>,
    #[knuffel(child)]
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

                if !kernel.config_options.is_empty() {
                    me.config_options = kernel.config_options;
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

#[derive(Decode, Clone, Debug)]
pub struct DevArg {
    #[knuffel(argument)]
    pub value: String,
}

#[derive(Decode, Default, Clone, Debug)]
pub struct DevConfig {
    #[knuffel(children(name = "arg"))]
    pub args_vec: Vec<DevArg>,
}

impl DevConfig {
    pub fn args(&self) -> Option<Vec<String>> {
        if self.args_vec.is_empty() {
            None
        } else {
            Some(self.args_vec.iter().map(|a| a.value.clone()).collect())
        }
    }
}

#[derive(Decode, Clone, Debug)]
pub struct Package {
    #[knuffel(argument)]
    pub name: String,
}

#[derive(Decode, Clone, Debug)]
pub struct NamedConfig {
    #[knuffel(argument)]
    pub name: String,
    #[knuffel(child)]
    pub kernel: Option<KernelConfig>,
    #[knuffel(child)]
    pub xfstests: Option<XfstestsConfig>,
    #[knuffel(child)]
    pub xfsprogs: Option<XfsprogsConfig>,
    #[knuffel(child)]
    pub script: Option<ScriptConfig>,
}

impl From<NamedConfig> for SystemConfig {
    fn from(nc: NamedConfig) -> Self {
        SystemConfig {
            kernel: nc.kernel,
            xfstests: nc.xfstests,
            xfsprogs: nc.xfsprogs,
            script: nc.script,
        }
    }
}

#[derive(Decode, Default, Clone, Debug)]
pub struct Config {
    #[knuffel(children(name = "package"))]
    pub packages_vec: Vec<Package>,
    #[knuffel(child)]
    pub kernel: Option<KernelConfig>,
    #[knuffel(child)]
    pub xfstests: Option<XfstestsConfig>,
    #[knuffel(child)]
    pub xfsprogs: Option<XfsprogsConfig>,
    #[knuffel(child)]
    pub script: Option<ScriptConfig>,
    #[knuffel(child)]
    pub qemu: Option<QemuConfig>,
    #[knuffel(child)]
    pub common: Option<SystemConfig>,
    #[knuffel(children(name = "named"))]
    pub named_vec: Vec<NamedConfig>,
    #[knuffel(child)]
    pub dev: Option<DevConfig>,
}

impl Config {
    pub fn load<T: AsRef<Path>>(path: T) -> Result<Self> {
        let data = fs::read_to_string(&path)
            .with_context(|| format!("Failed to read config from {:?}", path.as_ref()))?;
        let config: Config = knuffel::parse(path.as_ref().to_str().unwrap_or("config.kdl"), &data)
            .map_err(|e| anyhow::anyhow!("Invalid KDL: {:?}", e))?;

        Ok(config)
    }

    pub fn packages(&self) -> Option<Vec<String>> {
        if self.packages_vec.is_empty() {
            None
        } else {
            Some(self.packages_vec.iter().map(|p| p.name.clone()).collect())
        }
    }

    pub fn named(&self) -> HashMap<String, SystemConfig> {
        let mut map = HashMap::new();
        for nc in &self.named_vec {
            map.insert(nc.name.clone(), nc.clone().into());
        }
        map
    }

    pub fn validate(&self) -> Result<()> {
        if let Some(subconfig) = &self.kernel {
            let kernel = subconfig.version.is_some()
                || subconfig.rev.is_some()
                || subconfig.repo.is_some()
                || !subconfig.config_options.is_empty();
            if subconfig.prebuild.is_some() && kernel {
                println!("Note! You're using 'prebuild', none of the kernel options applies.");
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

                let path =
                    absolute(curdir.join(&kernel.path)).context("Failed to parse kernel path")?;

                if !(path.exists()) {
                    bail!("Kernel doesn't exists: {}", kernel.path);
                }
            }
        }

        return Ok(());
    }
}
