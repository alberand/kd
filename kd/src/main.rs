use clap::{Parser, Subcommand, ValueEnum};
use std::fmt;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::Command;
use std::process::Stdio;
use tera::{Context, Tera};

mod utils;
use utils::{KdError, KdErrorKind};
mod config;
use config::{Config, KernelConfigOption};

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
    #[arg(short, long, action = clap::ArgAction::Count)]
    debug: u8,

    #[command(subcommand)]
    command: Option<Commands>,
}

#[derive(ValueEnum, Copy, Clone, Debug, PartialEq, Eq)]
enum Target {
    Vm,
    Iso,
    Qcow,
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            Target::Vm => write!(f, "vm"),
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

    Build {
        /// lists test values
        #[arg(
            default_value_t = Target::Vm,
            value_enum
        )]
        target: Target,
    },

    Run,

    Update,

    Config {
        #[arg(short, long, default_value = ".config", help = "Output filename")]
        output: Option<String>,
    },
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
                KdErrorKind::NurlFailed,
                "Failed to execute command".to_string(),
            )
        })
        .unwrap();

    if !output.status.success() {
        // TODO need to throw and error
        println!("{}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(
            KdErrorKind::NurlFailed,
            "command failed".to_string(),
        ));
    }

    String::from_utf8(output.stdout).map_err(|_| {
        KdError::new(
            KdErrorKind::NurlFailed,
            "Failed to parse Nurl output".to_string(),
        )
    })
}

fn all_good() -> bool {
    let commands = vec!["nix", "nurl"];

    for command in commands {
        let status = Command::new(command)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .expect(&format!("Failed to exexute command: {}", command));
        if !status.success() {
            println!("Exit code: {}", status.code().unwrap());
            return false;
        }
    }

    if dirs::home_dir().is_none() {
        println!("Can not determine your $HOME directory. Please, set it");
        return false;
    }

    true
}

fn init(name: &str) -> Result<(), KdError> {
    // TODO this need to be checked in all good
    let workdir = std::env::current_dir().expect("Can not detect current working directory");
    let mut target = PathBuf::from(&workdir);
    let path = PathBuf::from(&workdir).join(".kd").join(name);
    if let Err(error) = std::fs::create_dir_all(&path) {
        return Err(KdError::new(KdErrorKind::FlakeInitError, error.to_string()));
    }
    // TODO handle
    println!("Creating new environment '{}'", name);
    let output = Command::new("nix")
        .arg("flake")
        .arg("init")
        .arg("--template")
        .arg("github:alberand/kd#x86_64-linux.default")
        .current_dir(&path)
        .output()
        .expect("Failed to execute command");
    if !output.status.success() {
        println!("{}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(
            KdErrorKind::FlakeInitError,
            "Failed to created Flake".to_string(),
        ));
    }

    target.push(".kd.toml");
    let mut writer = std::fs::File::create(target).expect("Failed to create .kd.toml config");
    writeln!(writer, "name = \"{}\"", name).expect("Failed to write env name to .kd.toml");

    println!("Update your .kd.toml configuration");

    Ok(())
}

/// TODO all this parsing should be just done nrix
fn generate_uconfig(path: &PathBuf, config: &Config) -> Result<(), KdError> {
    let mut tera = Tera::default();
    let mut context = Context::new();
    let mut options = vec![];
    let mut kernel_options = vec![];
    let mut kernel_config_options: Vec<KernelConfigOption> = vec![];
    let set_value = |name: &str, value: &str| format!("{name} = {value};");
    let set_value_str = |name: &str, value: &str| set_value(name, &format!("\"{}\"", &value));

    if let Some(subconfig) = &config.xfstests {
        if let Some(rev) = &subconfig.rev {
            let repo = if let Some(repo) = &subconfig.repo {
                repo
            } else {
                &config::XfstestsConfig::default().repo.unwrap()
            };

            let src = nurl(&repo, &rev).unwrap();
            options.push(set_value("programs.xfstests.src", &src));
        };

        if let Some(args) = &subconfig.args {
            options.push(set_value_str("programs.xfstests.arguments", &args));
        };

        if let Some(test_dev) = &subconfig.test_dev {
            options.push(set_value_str("programs.xfstests.test-dev", &test_dev));
        };

        if let Some(scratch_dev) = &subconfig.scratch_dev {
            options.push(set_value_str("programs.xfstests.scratch-dev", &scratch_dev));
        };

        if let Some(mkfs_opts) = &subconfig.mkfs_opts {
            options.push(set_value_str("programs.xfstests.mkfs_opts", &mkfs_opts));
        };

        if let Some(extra_env) = &subconfig.extra_env {
            options.push(set_value_str(
                "programs.xfstests.extraEnv",
                &format!("\"\"{}\"\"", &extra_env),
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
            options.push(set_value("programs.xfstests.hooks", path));
        };
    };

    if let Some(subconfig) = &config.xfsprogs {
        if let Some(rev) = &subconfig.rev {
            if let Some(repo) = &subconfig.repo {
                let src = nurl(&repo, &rev).expect("Failed to parse xfsprogs source repo");
                options.push(set_value("programs.xfsprogs.src", &src));
            }
        };
    };

    if let Some(subconfig) = &config.kernel {
        if let Some(_) = &subconfig.prebuild {
            let path = std::env::current_dir()
                .expect("Don't have access to current working dir")
                .join(format!(".kd/{}/build", &config.name));
            options.push(set_value("kernel.prebuild", path.to_str().unwrap()));
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

    let source = r#"
    {
        name = "{{ name }}";
        uconfig = {pkgs}: with pkgs; {
            {% for option in options %}
                {{ option }}
            {% endfor%}
            {% if kernel_options %}
            kernel = {
                {% for option in kernel_options %}
                    {{ option }}
                {% endfor%}
            };
            {% endif %}
            {% if kernel_config_options %}
            kernel.kconfig = with pkgs.lib.kernel; {
              {% for option in kernel_config_options %}
                  {{ option.name }} = {{ option.value }};
              {% endfor%}
            };
            {% endif %}
        };
    }
    "#;
    tera.add_raw_template("top", source).unwrap();

    context.insert("name", &config.name);
    context.insert("options", &options);
    context.insert("kernel_options", &kernel_options);
    context.insert("kernel_config_options", &kernel_config_options);

    let uconfig = tera.render("top", &context).unwrap();
    let mut file = std::fs::File::create(path).expect("Failed to create user config uconfig.nix");
    file.write_all(uconfig.as_bytes())
        .expect("Failed to write out uconfig.nix data");
    // format_nix(&path).unwrap();

    Ok(())
}

struct State {
    curdir: PathBuf,
    envdir: PathBuf,
    config: Config,
}

impl State {
    fn new() -> Self {
        let curdir = std::env::current_dir().expect("Don't have access to current working dir");
        let config_path = curdir.clone().join(".kd.toml");
        let config_path_str = config_path.clone().into_os_string().into_string().unwrap();

        if !config_path.exists() {
            println!("Not in directory with .kd.toml config. Call 'kd init' first");
            std::process::exit(1);
        }

        let config = match Config::load(config_path) {
            Ok(config) => config,
            Err(error) => {
                println!("Error loading config '{}': {}", config_path_str, error);
                std::process::exit(1);
            }
        };

        let envdir = curdir.clone().join(".kd").join(&config.name);
        Self {
            curdir,
            envdir,
            config,
        }
    }
}

fn main() {
    // TODO check if 'nix' exists
    let cli = Cli::parse();

    if !all_good() {
        std::process::exit(1);
    }

    match &cli.command {
        Some(Commands::Init { name }) => {
            init(name.as_str()).expect("Failed to initialize environment");
        }
        Some(Commands::Build { target }) => {
            let state = State::new();

            let mut extra_args: Vec<String> = vec![];
            let uconfig_path = PathBuf::from(state.envdir.clone()).join("uconfig.nix");
            generate_uconfig(&uconfig_path, &state.config)
                .expect("Failed to generate user environment");

            let mut target = target.to_string();
            if let Some(subconfig) = state.config.kernel {
                if let Some(prebuild) = &subconfig.prebuild {
                    if *prebuild {
                        extra_args.push("--impure".to_string());
                        target = "prebuild".to_string();

                        let build_path = state.envdir.join("build");
                        let kernel_path = state.curdir.join("arch/x86_64/boot/bzImage");

                        if build_path.exists() {
                            std::fs::remove_dir_all(build_path.clone()).unwrap();
                        }
                        std::fs::create_dir_all(build_path.clone()).unwrap();
                        Command::new("make")
                            .env("INSTALL_MOD_PATH", build_path.clone())
                            .stdout(Stdio::null())
                            .arg("-C")
                            .arg(&state.curdir)
                            .arg("modules_install")
                            .spawn()
                            .expect("Failed to spawn 'nix build'")
                            .wait()
                            .expect("'nix build' wasn't running");
                        Command::new("make")
                            .env("INSTALL_PATH", build_path.clone())
                            .stdout(Stdio::null())
                            .arg("-C")
                            .arg(&state.curdir)
                            .arg("install")
                            .spawn()
                            .expect("Failed to spawn 'nix build'")
                            .wait()
                            .expect("'nix build' wasn't running");

                        std::fs::copy(kernel_path, build_path.join("bzImage")).unwrap();
                    }
                }
            }

            let package = format!(
                "path:{}#{}",
                state
                    .envdir
                    .to_str()
                    .expect("Can not convert env path to string"),
                target
            );
            Command::new("nix")
                .arg("build")
                .args(extra_args)
                .arg(&package)
                .spawn()
                .expect("Failed to spawn 'nix build'")
                .wait()
                .expect("'nix build' wasn't running");
        }
        Some(Commands::Run) => {
            let state = State::new();

            let mut extra_args: Vec<String> = vec![];
            let mut target = "vm".to_string();
            if let Some(subconfig) = state.config.kernel {
                if let Some(prebuild) = &subconfig.prebuild {
                    if *prebuild {
                        extra_args.push("--impure".to_string());
                        target = "prebuild".to_string();
                    }
                }
            }

            let package = format!(
                "path:{}#{}",
                state
                    .envdir
                    .to_str()
                    .expect("Can not convert env path to string"),
                target
            );
            Command::new("nix")
                .arg("run")
                .args(extra_args)
                .arg(&package)
                .spawn()
                .expect("Failed to spawn 'nix run'")
                .wait()
                .expect("'nix run' wasn't running");
        }
        Some(Commands::Update) => {
            let state = State::new();

            let package = format!(
                "path:{}",
                state
                    .envdir
                    .to_str()
                    .expect("cannot convert path to string")
            );
            Command::new("nix")
                .arg("flake")
                .arg("update")
                .arg("--flake")
                .arg(&package)
                .current_dir(&state.envdir)
                .spawn()
                .expect("Failed to spawn 'nix flake update'")
                .wait()
                .expect("'nix flake update' wasn't running");
        }
        Some(Commands::Config { output }) => {
            let state = State::new();

            let uconfig_path = state.envdir.clone().join("uconfig.nix");
            generate_uconfig(&uconfig_path, &state.config)
                .expect("Failed to generate user environment");

            let package = format!(
                "path:{}#kconfig",
                state
                    .envdir
                    .to_str()
                    .expect("cannot convert path to string")
            );
            Command::new("nix")
                .arg("build")
                .arg(&package)
                .current_dir(&state.envdir)
                .spawn()
                .expect("Failed to spawn 'nix build .#kconfig'")
                .wait()
                .expect("'nix build .#kconfig' wasn't running");

            let curdir = std::env::current_dir().expect("Can not detect current working directory");
            let output = if let Some(output) = output {
                PathBuf::from(output)
            } else {
                curdir.clone().join(".config")
            };

            if output.exists() {
                let mut backup = output.clone();
                backup.set_extension("bup");
                std::fs::copy(&output, backup).unwrap();
            }

            let source = curdir
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
