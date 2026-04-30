use anyhow::{bail, Context, Result};
use std::collections::HashMap;
use std::path::{self, PathBuf};

pub mod config;
pub mod utils;
use config::{
    Config, KernelConfig, KernelConfigOption, SystemConfig, XfsprogsConfig, XfstestsConfig,
};

// Agh, so ugly
// TODO fix nrix to parse nix from rust

pub struct State {
    pub debug: bool,
    pub curdir: PathBuf,
    pub envdir: PathBuf,
    pub flake_dir: PathBuf,
    pub config: Config,
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
            config: Config::default(),
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
            curdir.clone().join(".kd.toml")
        };

        let config = Config::load(&config_path)?;
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

pub fn uconfig_set_value(name: &str, value: &str) -> String {
    format!("{name} = {value};")
}

pub fn uconfig_set_value_str(name: &str, value: &str) -> String {
    uconfig_set_value(name, &format!("\"{}\"", &value))
}

pub fn uconfig_xfsprogs(config: &XfsprogsConfig) -> String {
    let mut options: Vec<String> = vec![];
    if let Some(rev) = &config.rev {
        if let Some(repo) = &config.repo {
            let src = utils::nurl(&repo, &rev).expect("Failed to parse xfsprogs source repo");
            options.push(uconfig_set_value("src", &src));
        }
    };

    if let Some(headers) = &config.kernel_headers {
        if let (Some(version), Some(rev), Some(repo)) =
            (&headers.version, &headers.rev, &headers.repo)
        {
            let src = utils::nurl(&repo, &rev)
                .expect("Failed to fetch kernel source for xfsprogs headers");
            let value =
                format!("kd.lib.buildKernelHeaders {{ src = {src}; version = \"{version}\"; }}");
            options.push(uconfig_set_value("kernelHeaders", &value));
        };
    }

    format!("services.xfsprogs = {{ {} }};", &options.join("\n"))
}

pub fn uconfig_xfstests(config: &XfstestsConfig) -> String {
    let mut options: Vec<String> = vec![];

    if let Some(rev) = &config.rev {
        let repo = if let Some(repo) = &config.repo {
            repo
        } else {
            &XfstestsConfig::default().repo.unwrap()
        };

        let src = utils::nurl(&repo, &rev).expect("Failed to fetch xfstests");
        options.push(uconfig_set_value("src", &src));
    };

    if let Some(args) = &config.args {
        options.push(uconfig_set_value_str("arguments", &args));
    };

    if let Some(devices) = &config.devices {
        let mut dev_options: Vec<String> = vec![];

        if let Some(test_dev) = &devices.test {
            dev_options.push(uconfig_set_value_str("test.main", &test_dev));
        };

        if let Some(rtdev) = &devices.test_rtdev {
            dev_options.push(uconfig_set_value_str("test.rtdev", &rtdev));
        };

        if let Some(logdev) = &devices.test_logdev {
            dev_options.push(uconfig_set_value_str("test.logdev", &logdev));
        };

        if let Some(scratch_dev) = &devices.scratch {
            dev_options.push(uconfig_set_value_str("scratch.main", &scratch_dev));
        };

        if let Some(rtdev) = &devices.scratch_rtdev {
            dev_options.push(uconfig_set_value_str("scratch.rtdev", &rtdev));
        };

        if let Some(logdev) = &devices.scratch_logdev {
            dev_options.push(uconfig_set_value_str("scratch.logdev", &logdev));
        };

        options.push(format!("dev = {{ {} }};", &dev_options.join("\n")));
    };

    if let Some(filesystem) = &config.filesystem {
        options.push(uconfig_set_value_str("filesystem", &filesystem));
    };

    if let Some(extra_env) = &config.extra_env {
        options.push(uconfig_set_value(
            "extraEnv",
            &format!("''\n{}\n''", &extra_env),
        ));
    };

    if let Some(hooks) = &config.hooks {
        let path = PathBuf::from(hooks);
        let path = path.to_str().expect("Failed to retrieve hooks path");
        options.push(uconfig_set_value("hooks", path));
    };

    if let Some(headers) = &config.kernel_headers {
        if let (Some(version), Some(rev), Some(repo)) =
            (&headers.version, &headers.rev, &headers.repo)
        {
            let src = utils::nurl(&repo, &rev)
                .expect("Failed to fetch kernel source for xfstests headers");
            let value =
                format!("kd.lib.buildKernelHeaders {{ src = {src}; version = \"{version}\"; }}");
            options.push(uconfig_set_value("kernelHeaders", &value));
        };
    }

    format!("services.xfstests = {{ {} }};", &options.join("\n"))
}

pub fn uconfig_kernel(config: &KernelConfig) -> String {
    let mut options: Vec<String> = vec![];

    if let Some(rev) = &config.rev {
        if let Some(version) = &config.version {
            let repo = if let Some(repo) = &config.repo {
                repo
            } else {
                "git@github.com:torvalds/linux.git"
            };
            let src = utils::nurl(&repo, &rev).expect("Failed to parse kernel source repo");
            options.push(uconfig_set_value_str("version", version));
            options.push(uconfig_set_value("src", &src));
        }
    };

    if let Some(flavors) = &config.flavors {
        let value = format!(r#"with pkgs.kconfigs; [{}]"#, flavors.join(" "));
        options.push(uconfig_set_value("flavors", &value));
    };

    format!("kernel = {{ {} }};", options.join("\n"))
}

/// TODO all this parsing should be just done nrix
pub fn generate_uconfig(state: &mut State) -> Result<String> {
    let mut options = vec![];

    if let Some(packages) = &state.config.packages {
        let mut list = String::from("with pkgs; [");
        for package in packages {
            list.push_str(package);
            list.push_str("\n");
        }
        list.push_str("]");

        options.push(uconfig_set_value("environment.systemPackages", &list));
    }

    let merged: SystemConfig = if state.name != "" {
        if let Some(named) = &state.config.named {
            if !named.contains_key(&state.name) {
                bail!("Config doesn't define requested run: {}", &state.name);
            }
            let mut result = if let Some(common) = &state.config.common {
                common.clone()
            } else {
                SystemConfig::default()
            };

            let run_config: SystemConfig =
                named.get(&state.name).unwrap().clone().try_into().unwrap();
            result = result.merge(run_config).clone();
            result
        } else {
            SystemConfig {
                xfstests: state.config.xfstests.clone(),
                xfsprogs: state.config.xfsprogs.clone(),
                kernel: state.config.kernel.clone(),
                ..SystemConfig::default()
            }
        }
    } else {
        SystemConfig {
            xfstests: state.config.xfstests.clone(),
            xfsprogs: state.config.xfsprogs.clone(),
            kernel: state.config.kernel.clone(),
            ..SystemConfig::default()
        }
    };

    if let Some(config) = &merged.xfstests {
        options.push(uconfig_xfstests(&config));
    };

    if let Some(subconfig) = &merged.xfsprogs {
        options.push(uconfig_xfsprogs(&subconfig));
    };

    if let Some(subconfig) = &merged.kernel {
        if let Some(kernel) = &subconfig.prebuild {
            let path = path::absolute(&state.curdir.join(kernel))
                .context("Failed to parse kernel path")?;

            state.envs.insert(
                format!("NIXPKGS_QEMU_KERNEL_kd"),
                path.display().to_string(),
            );
        } else {
            options.push(uconfig_kernel(&subconfig));
            if let Some(config) = &subconfig.config {
                let mut config_options: Vec<KernelConfigOption> = vec![];
                for (key, value) in config.iter() {
                    config_options.push(KernelConfigOption {
                        name: key
                            .strip_prefix("CONFIG_")
                            .expect("Option doesn't start with CONFIG_")
                            .to_string(),
                        value: value.to_string().replace("\"", ""),
                    });
                }
                let kernel_config_options = format!(
                    "with pkgs.lib.kernel; {{ {} }}",
                    config_options
                        .into_iter()
                        .map(|x| format!("{name} = {value};", name = x.name, value = x.value))
                        .collect::<Vec<String>>()
                        .join("\n")
                );
                options.push(uconfig_set_value("kernel.kconfig", &kernel_config_options))
            }
        };
    };

    if let Some(subconfig) = &state.config.qemu {
        if let Some(qemu_options) = &subconfig.options {
            let mut list = String::from("[");
            for option in qemu_options {
                list.push_str("\"");
                list.push_str(option);
                list.push_str("\"\n");
            }
            list.push_str("]");

            options.push(uconfig_set_value("virtualisation.qemu.options", &list));
        };
    };

    Ok(format!(
        include_str!("uconfig.tmpl"),
        s_options = options.join("\n")
    ))
}
