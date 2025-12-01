use clap::{Parser, Subcommand, ValueEnum};
use serde::Deserialize;
use std::collections::HashMap;
use std::fmt;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::{self, PathBuf};
use std::process::Command;
use toml;

mod utils;
use utils::{find_it, is_executable, KdError, KdErrorKind};
mod config;
use config::{Config, KernelConfigOption, XfstestsConfig};

// Agh, so ugly
// TODO fix nrix to parse nix from rust

#[derive(Parser)]
#[command(version)]
#[command(name = "kd")]
#[command(about = "linux kernel development tool", long_about = None)]
struct Cli {
    /// Sets a custom config file
    #[arg(short, long, value_name = "FILE")]
    config: Option<PathBuf>,

    /// Turn debugging information on
    #[arg(short, long)]
    debug: bool,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(ValueEnum, Copy, Clone, Debug, PartialEq, Eq)]
enum Target {
    Iso,
    Qcow,
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            Target::Iso => write!(f, "iso"),
            Target::Qcow => write!(f, "qcow"),
        }
    }
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize development environment
    Init {
        #[arg(default_value = "default", help = "Environment name")]
        name: String,
    },

    // Build QCOW or ISO image
    Build {
        #[arg(long, allow_hyphen_values = true, help = "Nix arguments")]
        nix_args: Option<String>,
        /// lists test values
        #[arg(
            default_value_t = Target::Qcow,
            value_enum
        )]
        target: Target,
    },

    // Run lightweight VM
    Run {
        #[arg(long, allow_hyphen_values = true, help = "Nix arguments")]
        nix_args: Option<String>,
    },

    // Update VM system and shell packages
    Update {
        #[arg(long, allow_hyphen_values = true, help = "Nix arguments")]
        nix_args: Option<String>,
    },

    // Generate minimal Kernel config for VM
    Config {
        #[arg(short, long, default_value = ".config", help = "Output filename")]
        output: Option<String>,
    },
}

#[derive(Deserialize)]
struct NixConfig {
    args: Option<String>,
}

#[derive(Deserialize)]
struct AppConfig {
    _name: Option<String>,
    nix: Option<NixConfig>,
}

impl Default for AppConfig {
    fn default() -> Self {
        AppConfig {
            _name: None,
            nix: None,
        }
    }
}

impl AppConfig {
    fn load(path: &Option<PathBuf>) -> Result<Self, KdError> {
        let app_config_path = if let Some(path) = path {
            path
        } else if let Ok(xdg_config_home) = std::env::var("XDG_CONFIG_HOME") {
            &PathBuf::from(xdg_config_home).join("kd/config.toml")
        } else if let Ok(home) = std::env::var("HOME") {
            &PathBuf::from(home).join(".config/kd/config.toml")
        } else {
            &PathBuf::from("")
        };

        if !app_config_path.exists() {
            return AppConfig::create();
        }

        match std::fs::read_to_string(app_config_path) {
            Ok(data) => {
                let data = toml::from_str(&data)
                    .map_err(|e| KdError::new(KdErrorKind::TOMLError(e), format!("invalid TOML")));
                data
            }
            Err(error) => {
                return Err(KdError::new(
                    KdErrorKind::IOError(error),
                    format!("Failed to read {}", app_config_path.display()),
                ));
            }
        }
    }

    fn create() -> Result<Self, KdError> {
        // Create global config
        for var in vec!["XDG_CONFIG_HOME", "HOME"] {
            match std::env::var(var) {
                Ok(value) => {
                    let kd_path = if var == "HOME" { ".config/kd" } else { "kd" };
                    let global_config_dir = PathBuf::from(value).join(kd_path);
                    match std::fs::create_dir_all(&global_config_dir) {
                        Ok(()) => {
                            let global_config = global_config_dir.join("config.toml");
                            let mut file = std::fs::File::create(global_config);
                            match &mut file {
                                Ok(file) => {
                                    let res = file.write_all(b"# kd global config");
                                    if res.is_err() {
                                        println!(
                                        "Failed to write to $XDG_CONFIG_HOME/kd/config.toml: {:?}",
                                        res
                                    );
                                    }
                                }
                                Err(error) => {
                                    println!(
                                    "Failed to write to $XDG_CONFIG_HOME/kd/config.toml: {error}"
                                )
                                }
                            }
                        }
                        Err(error) => {
                            println!(
                                "Failed to create $XDG_CONFIG_HOME, won't create config: {error}"
                            );
                        }
                    }
                }
                Err(error) => {
                    println!("$XDG_CONFIG_HOME seems to be empty, won't create config: {error}");
                }
            };
        }

        Ok(AppConfig::default())
    }
}

#[derive(Default)]
struct State {
    curdir: PathBuf,
    envdir: PathBuf,
    config: Config,

    app_config: AppConfig,
    user_config: PathBuf,

    args: Vec<String>,
    envs: HashMap<String, String>,
}

impl State {
    fn new(cli: &Cli) -> Result<Self, KdError> {
        let app_config = AppConfig::load(&cli.config)?;

        let curdir = std::env::current_dir().map_err(|e| {
            KdError::new(
                KdErrorKind::IOError(e),
                "No able to get current working directory".to_string(),
            )
        })?;
        let config_path = curdir.clone().join(".kd.toml");

        if !config_path.exists() {
            return Err(KdError::new(
                KdErrorKind::RuntimeError,
                "Not in directory with .kd.toml config. Call 'kd init' first".to_string(),
            ));
        }

        let config = Config::load(&config_path)?;

        let envdir = curdir.clone().join(".kd").join(&config.name);

        let user_config = PathBuf::from(envdir.clone()).join("uconfig.nix");
        let args = if let Some(config) = &app_config.nix {
            if let Some(args) = &config.args {
                args.split(" ")
                    .map(|x| x.to_string())
                    .collect::<Vec<String>>()
            } else {
                vec![]
            }
        } else {
            vec![]
        };

        let envs = HashMap::new();

        Ok(Self {
            curdir,
            envdir,
            config,
            app_config,
            user_config,
            args: args,
            envs: envs,
        })
    }
}

fn nurl(repo: &str, rev: &str) -> Result<String, KdError> {
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
        .map_err(|_| {
            KdError::new(
                KdErrorKind::RuntimeError,
                "Failed to execute command".to_string(),
            )
        })
        .unwrap();

    if !output.status.success() {
        // TODO need to throw and error
        println!("{}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(
            KdErrorKind::RuntimeError,
            "command failed".to_string(),
        ));
    }

    String::from_utf8(output.stdout).map_err(|_| {
        KdError::new(
            KdErrorKind::RuntimeError,
            "Failed to parse Nurl output".to_string(),
        )
    })
}

/// TODO all this parsing should be just done nrix
fn generate_uconfig(state: &mut State) -> Result<(), KdError> {
    let mut options = vec![];
    let mut kernel_options = vec![];
    let mut kernel_config_options: Vec<KernelConfigOption> = vec![];

    let set_value = |name: &str, value: &str| format!("{name} = {value};");
    let set_value_str = |name: &str, value: &str| set_value(name, &format!("\"{}\"", &value));

    if let Some(packages) = &state.config.packages {
        let mut list = String::from("with pkgs; [");
        for package in packages {
            list.push_str(package);
            list.push_str("\n");
        }
        list.push_str("]");

        options.push(set_value("environment.systemPackages", &list));
    }

    if let Some(subconfig) = &state.config.xfstests {
        if let Some(rev) = &subconfig.rev {
            let repo = if let Some(repo) = &subconfig.repo {
                repo
            } else {
                &XfstestsConfig::default().repo.unwrap()
            };

            let src = nurl(&repo, &rev).unwrap();
            options.push(set_value("services.xfstests.src", &src));
        };

        if let Some(args) = &subconfig.args {
            options.push(set_value_str("services.xfstests.arguments", &args));
        };

        if let Some(test_dev) = &subconfig.test_dev {
            options.push(set_value_str("services.xfstests.test-dev", &test_dev));
        };

        if let Some(scratch_dev) = &subconfig.scratch_dev {
            options.push(set_value_str("services.xfstests.scratch-dev", &scratch_dev));
        };

        if let Some(filesystem) = &subconfig.filesystem {
            options.push(set_value_str("services.xfstests.filesystem", &filesystem));
        };

        if let Some(extra_env) = &subconfig.extra_env {
            options.push(set_value(
                "services.xfstests.extraEnv",
                &format!("''\n{}\n''", &extra_env),
            ));
        };

        if let Some(hooks) = &subconfig.hooks {
            let path = PathBuf::from(hooks);
            if !path.exists() {
                let cwd = std::env::current_dir().expect("Failed to retrieve current working dir");
                println!("Failed to find '{:?}' dir (cwd is {:?})", path, cwd);
                std::process::exit(1);
            }
            let path = path.to_str().expect("Failed to retrieve hooks path");
            options.push(set_value("services.xfstests.hooks", path));
        };
    };

    if let Some(subconfig) = &state.config.xfsprogs {
        if let Some(rev) = &subconfig.rev {
            if let Some(repo) = &subconfig.repo {
                let src = nurl(&repo, &rev).expect("Failed to parse xfsprogs source repo");
                options.push(set_value("services.xfsprogs.src", &src));
            }
        };
    };

    if let Some(subconfig) = &state.config.kernel {
        if let Some(kernel) = &subconfig.prebuild {
            let path = path::absolute(&state.curdir.join(kernel))
                .map_err(|e| {
                    KdError::new(
                        KdErrorKind::ConfigError,
                        format!("Failed to parse kernel path: {}", e.to_string()),
                    )
                })
                .unwrap();

            if !(path.exists()) {
                println!("Kernel doesn't exists at: {kernel}");
                std::process::exit(1);
            }

            state.envs.insert(
                format!("NIXPKGS_QEMU_KERNEL_{}", &state.config.name),
                path.display().to_string(),
            );
        }

        if subconfig.repo.is_some() && subconfig.rev.is_none() && subconfig.version.is_none() {
            println!("While using 'repo' rev/version need to be set");
            std::process::exit(1);
        }

        if subconfig.rev.is_some() && subconfig.version.is_none() {
            println!("Revision can not be used without 'version'");
            std::process::exit(1);
        }

        if let Some(rev) = &subconfig.rev {
            if let Some(version) = &subconfig.version {
                let repo = if let Some(repo) = &subconfig.repo {
                    repo
                } else {
                    "git@github.com:torvalds/linux.git"
                };
                let src = nurl(&repo, &rev).expect("Failed to parse kernel source repo");
                kernel_options.push(set_value_str("version", version));
                kernel_options.push(set_value("src", &src));
            } else {
                println!("If rev is set version need to be set to the latest kernel release");
                std::process::exit(1);
            }
        };

        if let Some(flavors) = &subconfig.flavors {
            let value = format!(r#"with pkgs.kconfigs; [{}]"#, flavors.join(" "));
            kernel_options.push(set_value("flavors", &value));
        };

        if let Some(config) = &subconfig.config {
            for (key, value) in config.iter() {
                kernel_config_options.push(KernelConfigOption {
                    name: key
                        .strip_prefix("CONFIG_")
                        .expect("Option doesn't start with CONFIG_")
                        .to_string(),
                    value: value.to_string().replace("\"", ""),
                });
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

            options.push(set_value("virtualisation.qemu.options", &list));
        };
    };

    let s_options = options.join("\n");
    let s_kernel_options = format!("kernel = {{ {} }};", kernel_options.join("\n"));
    let s_kernel_config_options = format!(
        "kernel.kconfig = with pkgs.lib.kernel; {{ {} }};",
        kernel_config_options
            .into_iter()
            .map(|x| format!("{name} = {value};", name = x.name, value = x.value))
            .collect::<Vec<String>>()
            .join("\n")
    );

    let uconfig = format!(
        include_str!("uconfig.tmpl"),
        name = &state.config.name,
        s_options = s_options,
        s_kernel_options = s_kernel_options,
        s_kernel_config_options = s_kernel_config_options
    );

    let mut file = std::fs::File::create(&state.user_config)
        .expect("Failed to create user config uconfig.nix");
    file.write_all(uconfig.as_bytes())
        .expect("Failed to write out uconfig.nix data");

    Ok(())
}

fn main() {
    // Check that these commands exists
    for command in vec!["nix", "nurl"] {
        let path = match find_it(command) {
            Some(value) => value,
            None => {
                println!("Can not find '{}' in $PATH", command);
                std::process::exit(1);
            }
        };

        if !is_executable(&path) {
            println!("'{}' is not an executable", path.display());
            std::process::exit(1);
        }
    }

    let cli = Cli::parse();
    let mut state = State::new(&cli).unwrap_or_else(|error| {
        if let Some(Commands::Init {ref name}) = &cli.command {
            // we good to go as we doing init
            State::default()
        } else {
            println!("Initialization failed: {}", error);
            std::process::exit(1);
        }
    });

    match &cli.command {
        Some(Commands::Init { name }) => {
            let name = name.as_str();

            let curdir = std::env::current_dir().unwrap_or_else(|e| {
                println!("No able to get current working directory: {}", e);
                std::process::exit(1);
            });

            let path = PathBuf::from(&curdir).join(".kd").join(name);
            if let Err(error) = std::fs::create_dir_all(&path) {
                println!("Unable to create {}: {}", path.display(), error);
                std::process::exit(1);
            }

            println!("Creating new environment '{}'", name);
            let mut cmd = Command::new("nix");
            cmd.arg("flake")
                .arg("init")
                .arg("--template")
                .arg("github:alberand/kd#default")
                .current_dir(&path);

            if cli.debug {
                println!("command: {:?}", cmd);
            }

            let output = cmd.output().expect("Failed to execute command");

            if !output.status.success() {
                println!("Failed to create Nix Flake:");
                println!("{}", String::from_utf8_lossy(&output.stderr));
                std::process::exit(1);
            }

            let target = PathBuf::from(&curdir).join(".kd.toml");
            if target.exists() {
                // nothing to do, config already here
                std::process::exit(0);
            }
            let mut writer = std::fs::File::create(target).unwrap_or_else(|e| {
                println!("Failed to create .kd.toml config: {e}");
                std::process::exit(1);
            });
            writeln!(writer, include_str!("config.tmpl"), name).unwrap_or_else(|e| {
                println!("Failed to write env name to .kd.toml: {e}");
                std::process::exit(1);
            });

            println!("Update your .kd.toml configuration");
        }

        Some(Commands::Build { nix_args, target }) => {
            if let Err(error) = state.config.validate() {
                println!("Invalid config: {error}");
                std::process::exit(1);
            }

            if let Some(args) = nix_args {
                let args = args.split(" ").map(|x| x.to_string());
                for arg in args {
                    state.args.push(arg)
                }
            }

            match generate_uconfig(&mut state) {
                Ok(_) => {}
                Err(error) => {
                    println!("Failed to generate nix config: {error}");
                    std::process::exit(1);
                }
            }

            let package = format!("path:{}#{}", state.envdir.display(), target.to_string());

            let mut cmd = Command::new("nix");
            cmd.arg("build").args(state.args).arg(&package);

            if cli.debug {
                println!("command: {:?}", cmd);
            }

            cmd.spawn()
                .expect("Failed to spawn 'nix build'")
                .wait()
                .expect("'nix build' wasn't running");
        }

        Some(Commands::Run { nix_args }) => {
            if let Err(error) = state.config.validate() {
                println!("Invalid config: {error}");
                std::process::exit(1);
            }

            if let Some(args) = nix_args {
                let args = args.split(" ").map(|x| x.to_string());
                for arg in args {
                    state.args.push(arg)
                }
            }

            match generate_uconfig(&mut state) {
                Ok(_) => {}
                Err(error) => {
                    println!("Failed to generate nix config: {error}");
                    std::process::exit(1);
                }
            }

            state
                .args
                .push(format!("path:{}#vm", state.envdir.display()));
            let mut cmd = Command::new("nix");
            cmd.arg("run").args(state.args).envs(state.envs);

            if cli.debug {
                println!("command: {:?}", cmd);
            }

            cmd.spawn()
                .expect("Failed to spawn 'nix run'")
                .wait()
                .expect("'nix run' wasn't running");
        }

        Some(Commands::Update { nix_args }) => {
            if let Some(args) = nix_args {
                let args = args.split(" ").map(|x| x.to_string());
                for arg in args {
                    state.args.push(arg)
                }
            }

            let package = format!("path:{}", state.envdir.display());
            let mut cmd = Command::new("nix");
            cmd.arg("flake")
                .arg("update")
                .arg("--flake")
                .arg(&package)
                .current_dir(&state.envdir);

            if cli.debug {
                println!("command: {:?}", &cmd);
            }

            cmd.spawn()
                .expect("Failed to spawn 'nix flake update'")
                .wait()
                .expect("'nix flake update' wasn't running");
        }

        Some(Commands::Config { output }) => {
            if let Err(error) = state.config.validate() {
                println!("Invalid config: {error}");
                std::process::exit(1);
            }

            match generate_uconfig(&mut state) {
                Ok(_) => {}
                Err(error) => {
                    println!("Failed to generate nix config: {error}");
                    std::process::exit(1);
                }
            }

            let package = format!("path:{}#kconfig", state.envdir.display());
            let mut cmd = Command::new("nix");
            cmd.arg("build").arg(&package).current_dir(&state.envdir);

            if cli.debug {
                println!("command: {:?}", cmd);
            }

            cmd.spawn()
                .expect("Failed to spawn 'nix build .#kconfig'")
                .wait()
                .expect("'nix build .#kconfig' wasn't running");

            let output = if let Some(output) = output {
                PathBuf::from(output)
            } else {
                state.curdir.clone().join(".config")
            };

            if output.exists() {
                let mut backup = output.clone();
                backup.set_extension("bup");
                std::fs::copy(&output, backup).unwrap();
            }

            let source = state
                .curdir
                .clone()
                .join(".kd")
                .join(&state.config.name)
                .join("result");
            std::fs::copy(source, &output).unwrap();
            std::fs::set_permissions(output, std::fs::Permissions::from_mode(0o644)).unwrap();
        }
        None => {}
    }
}
