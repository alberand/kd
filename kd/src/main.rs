use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::process::Command;
use std::process::Stdio;
use tera::{Context, Tera};
use std::io::{ErrorKind, Write};

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

#[derive(Subcommand)]
enum Commands {
    /// Initialize development environment
    Init {
        #[arg(short, long)]
        name: String,
    },

    Build {
        /// lists test values
        target: String,
    },

    Run,
}

fn nurl(repo: &str, rev: &str) -> Result<String, std::string::FromUtf8Error> {
    let output = Command::new("nurl")
        .arg(repo)
        .arg(rev)
        .output()
        .expect("Failed to execute command");

    if !output.status.success() {
        // TODO need to throw and error
        println!("failed: {:?}", String::from_utf8(output.stderr));
    }

    String::from_utf8(output.stdout)
}

fn format_nix(code: String) -> Result<String, std::string::FromUtf8Error> {
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
        .expect("Failed to execute command");

    if !output.status.success() {
        // TODO need to throw and error
        println!("failed: {:?}", String::from_utf8(output.stderr));
    }

    String::from_utf8(output.stdout)
}

fn all_good() -> bool {
    let commands = vec![
        "nix",
        "nurl",
        "alejandra",
    ];

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
    let mut path = PathBuf::from(&workdir); //dirs::home_dir().expect("Failed to find home dir");
    path.push(".kd");
    path.push(name);
    if let Err(error) = std::fs::create_dir_all(&path) {
        return Err(KdError::new(KdErrorKind::FlakeInitError, error.to_string()));
    }
    // TODO handle
    let _ = std::env::set_current_dir(&path);
    println!("Creating new environment '{}'", name);
    let output = Command::new("nix")
       .arg("flake")
       .arg("init")
       .arg("--template")
       .arg("github:alberand/kd#x86_64-linux.default")
       .output()
       .expect("Failed to execute command");
    if !output.status.success() {
        println!("{}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(KdErrorKind::FlakeInitError, "Failed to created Flake".to_string()));
    }

    target.push(".kd.toml");
    std::fs::rename("kd.sample.toml", target).expect("Failed to copy sample .kd.toml config");
    println!("Update your .kd.toml configuration");

    Ok(())
}

fn version_to_modversion(version: &str) -> Result<String, KdError> {
    if !version.starts_with("v") {
        return Err(KdError::new(KdErrorKind::BadKernelVersion, "doesn't start with 'v'".to_string()))
    }

    if let Some(version) = version.strip_prefix("v") {
        if version.chars().take_while(|ch| *ch == '.').count() == 2 {
            return Ok(version.to_string())
        }
        return Ok(format!("\"{version}.0\""))
    }

    Err(KdError::new(KdErrorKind::BadKernelVersion, "no version after 'v'".to_string()))
}

/// TODO all this parsing should be just done nrix
fn generate_uconfig(wd: &PathBuf, config: &Config) -> Result<(), KdError> {
    // TODO handle
    let _ = std::env::set_current_dir(wd);

    let mut tera = Tera::default();
    let mut context = Context::new();
    let mut options = vec![];
    let mut kernel_options = vec![];
    let kernel_config_options: Vec<String> = vec![];
    let set_value = |name: &str, value: &str| { format!("{name} = {value};") };

    if let Some(subconfig) = &config.xfstests {
        if let Some(rev) = &subconfig.rev {
            if let Some(repo) = &subconfig.repo {
                let src = nurl(&repo, &rev).expect("Failed to parse xfstests source repo");
                options.push(set_value("programs.xfstests.src", &src));
            }
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
        if subconfig.image.is_some() && (subconfig.version.is_some() || subconfig.rev.is_some()
            || subconfig.repo.is_some() || subconfig.config.is_some()) {
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
        } else if let Some(version) = &subconfig.version {
            if let Some(rev) = &subconfig.rev {
                let repo = if let Some(repo) = &subconfig.repo {
                    repo
                } else {
                    "git@github.com:torvalds/linux.git"
                };
                let src = nurl(&repo, &rev).expect("Failed to parse kernel source repo");
                kernel_options.push(set_value("version", &format!("\"{}\"", version)));
                kernel_options.push(set_value("modDirVersion",
                        &version_to_modversion(&version)?));
                kernel_options.push(set_value("src", &src));
            }
        } else {
            println!("Either kernel image or version/rev has to be set");
            std::process::exit(1);
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
                {% if kernel_config_options %}
                kconfig = with pkgs.lib.kernel; {
                  {% for option in kernel_config_options %}
                      "{{ option.name }}" = {{ option.value }};
                  {% endfor%}
                };
                {% endif %}
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

    Ok(())
}

fn main() {
    // TODO check if 'nix' exists
    let cli = Cli::parse();

    if !all_good() {
        std::process::exit(1);
    }

    let config = if let Some(config) = cli.config {
        Config::load(Some(config)).unwrap()
    } else {
        let mut path = std::env::current_dir().expect("Don't have access to current working dir");
        path.push(".kd.toml");
        let result = Config::load(Some(path));
        match result {
            Ok(config) => config,
            Err(ref error) if error.kind() == ErrorKind::NotFound => {
                Config::default()
            },
            Err(_) => Config::default()
        }
    };

    match &cli.command {
        Some(Commands::Init { name }) => {
            init(name.as_str()).expect("Failed to initialize environment");
        },
        Some(Commands::Build { target: _ }) => {
            let mut path = dirs::home_dir().expect("Failed to find home dir");
            path.push(".kd");
            generate_uconfig(&path, &config).expect("Failed to generate user environment");
        },
        Some(Commands::Run) => {
            println!("Run command");
        },
        None => {}
    }
}
