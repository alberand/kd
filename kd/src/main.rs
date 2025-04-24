use clap::{Parser, Subcommand, ValueEnum};
use std::fmt;
use std::io::{ErrorKind, Write};
use std::path::PathBuf;
use std::process::Command;
use std::process::Stdio;
use tera::{Context, Tera};

mod utils;
use utils::{KdError, KdErrorKind};
mod config;
use config::{Config, KernelConfigOption};

// kd config CONFIG_XFS_FS=y
// kd build [vm|iso]
// kd run
// kd deploy [path]
//

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
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            Target::Vm => write!(f, "vm"),
            Target::Iso => write!(f, "iso"),
        }
    }
}

#[derive(Subcommand)]
enum Commands {
    /// Initialize development environment
    Init {
        #[arg(required = true, default_value = "default", help = "Environment name")]
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
        #[arg(short, long, help = "Output filename")]
        output: Option<String>,
    },
}

fn nurl(repo: &str, rev: &str) -> Result<String, KdError> {
    println!("Fetching source for {} at {}", repo, rev);
    let output = Command::new("nurl")
        .arg(repo)
        .arg(rev)
        .output()
        .map_err(|_| KdError::new(KdErrorKind::NurlFailed, "Failed to execute command".to_string()))
        .unwrap();

    if !output.status.success() {
        // TODO need to throw and error
        println!("{}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(KdErrorKind::NurlFailed, "command failed".to_string()))
    }

    String::from_utf8(output.stdout).map_err(|_| KdError::new(KdErrorKind::NurlFailed, "Failed to parse Nurl output".to_string()))
}

fn format_nix(code: String) -> Result<String, KdError> {
    // Actually run the command
    let output = Command::new("alejandra")
        .stdin({
            // Unfortunately, it's not possible to provide a direct string as an input to a command
            // We actually need to provide an actual file descriptor (as is a usual stdin "pipe")
            // So we create a new pair of pipes here...
            let (reader, mut writer) = std::io::pipe().unwrap();

            // ...write the string to one end...
            writer.write_all(code.as_bytes()).unwrap();

            // ...and then transform the other to pipe it into the command as soon as it spawns!
            Stdio::from(reader)
        })
        .output()
        .map_err(|_| KdError::new(KdErrorKind::AlejandraFailed, "Failed to execute command".to_string()))
        .unwrap();

    if !output.status.success() {
        // TODO need to throw and error
        println!("{}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(KdErrorKind::AlejandraFailed, "command failed".to_string()))
    }

    String::from_utf8(output.stdout).map_err(|_| KdError::new(KdErrorKind::AlejandraFailed, "Failed to parse Alejandra output".to_string()))
}

fn all_good() -> bool {
    let commands = vec!["nix", "nurl", "alejandra"];

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
            options.push(set_value_str("programs.xfstests.extraEnv", &format!("\"\"{}\"\"", &extra_env)));
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
        if subconfig.image.is_some()
            && (subconfig.version.is_some()
                || subconfig.rev.is_some()
                || subconfig.repo.is_some()
                || subconfig.config.is_some())
        {
            println!("None of the options in [kernel] would take effect if 'image' is set");
        }

        if subconfig.repo.is_some() && subconfig.rev.is_none() && subconfig.version.is_none() {
            println!("While using 'repo' rev/version need to be set");
            std::process::exit(1);
        }

        if subconfig.rev.is_some() && subconfig.version.is_none() {
            println!("Revision can not be used without 'version'");
            std::process::exit(1);
        }

        if let Some(_) = &subconfig.image {
            // pass
        } else if let Some(rev) = &subconfig.rev {
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
                    name: key.strip_prefix("CONFIG_").expect("Option doesn't start with CONFIG_").to_string(),
                    value: value.to_string().replace("\"", ""),
                });
            }
        };
    };

    let source = r#"
        {pkgs}: with pkgs; {
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
        }
    "#;
    tera.add_raw_template("top", source).unwrap();

    context.insert("options", &options);
    context.insert("kernel_options", &kernel_options);
    context.insert("kernel_config_options", &kernel_config_options);

    let formatted = format_nix(tera.render("top", &context).unwrap()).unwrap();

    println!("{}", formatted);

    println!("user config {:?}", &path);
    let mut file = std::fs::File::create(path).expect("Failed to create user config uconfig.nix");
    file.write_all(formatted.as_bytes())
        .expect("Failed to write out uconfig.nix data");

    Ok(())
}

fn is_in_env() -> bool {
    let path = std::env::current_dir();
    let config_path = match path {
        Ok(path) => path.join(".kd.toml"),
        Err(..) => return false,
    };

    if !config_path.exists() {
        return false;
    }

    true
}

fn main() {
    // TODO check if 'nix' exists
    let cli = Cli::parse();

    if !all_good() {
        std::process::exit(1);
    }

    let path = std::env::current_dir().expect("Don't have access to current working dir");
    let config = if let Some(config) = cli.config {
        Config::load(Some(config)).unwrap()
    } else {
        let config_path = PathBuf::from(path.clone()).join(".kd.toml");
        let result = Config::load(Some(config_path));
        match result {
            Ok(config) => config,
            Err(ref error) if error.kind() == ErrorKind::NotFound => Config::default(),
            Err(_) => Config::default(),
        }
    };

    match &cli.command {
        Some(Commands::Init { name }) => {
            init(name.as_str()).expect("Failed to initialize environment");
        }
        Some(Commands::Build { target }) => {
            if !is_in_env() {
                println!("Not in the 'kd' environment, run 'kd init' first. Can not find .kd.toml");
                std::process::exit(1);
            }

            let env_path = PathBuf::from(path).join(".kd").join(&config.name);
            let uconfig_path = PathBuf::from(env_path.clone()).join("uconfig.nix");
            generate_uconfig(&uconfig_path, &config).expect("Failed to generate user environment");

            let package = format!(
                "path:{}#{}",
                env_path
                    .to_str()
                    .expect("Can not convert env path to string"),
                target
            );
            Command::new("nix")
                .arg("build")
                .arg(&package)
                .spawn()
                .expect("Failed to spawn 'nix build'")
                .wait()
                .expect("'nix build' wasn't running");
        }
        Some(Commands::Run) => {
            if !is_in_env() {
                println!("Not in the 'kd' environment, run 'kd init' first. Can not find .kd.toml");
                std::process::exit(1);
            }

            let env_path = PathBuf::from(path).join(".kd").join(&config.name);
            let package = format!(
                "path:{}#vm",
                env_path
                    .to_str()
                    .expect("Can not convert env path to string")
            );
            Command::new("nix")
                .arg("run")
                .arg(&package)
                .spawn()
                .expect("Failed to spawn 'nix run'")
                .wait()
                .expect("'nix run' wasn't running");
        }
        Some(Commands::Update) => {
            if !is_in_env() {
                println!("Not in the 'kd' environment, run 'kd init' first. Can not find .kd.toml");
                std::process::exit(1);
            }

            let path = PathBuf::from(path).join(".kd").join(&config.name);
            let package = format!("path:{}", path.to_str().expect("cannot convert path to string"));
            Command::new("nix")
                .arg("flake")
                .arg("update")
                .arg("--flake")
                .arg(&package)
                .current_dir(&path)
                .spawn()
                .expect("Failed to spawn 'nix flake update'")
                .wait()
                .expect("'nix flake update' wasn't running");
        }
        Some(Commands::Config { output }) => {
            if !is_in_env() {
                println!("Not in the 'kd' environment, run 'kd init' first. Can not find .kd.toml");
                std::process::exit(1);
            }

            let path = PathBuf::from(path).join(".kd").join(&config.name);
            let package = format!("path:{}#kconfig", path.to_str().expect("cannot convert path to string"));
            Command::new("nix")
                .arg("build")
                .arg(&package)
                .current_dir(&path)
                .spawn()
                .expect("Failed to spawn 'nix build .#kconfig'")
                .wait()
                .expect("'nix build .#kconfig' wasn't running");
            if let Some(output) = output {
                let source = std::env::current_dir().unwrap().join("result");
                std::fs::copy(source, output).unwrap();
            }
        }
        None => {}
    }
}
