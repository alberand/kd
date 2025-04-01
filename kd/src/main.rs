use clap::{Parser, Subcommand};
use std::path::PathBuf;
use std::process::Command;
use std::process::Stdio;
use tera::{Context, Tera};
use std::io::{ErrorKind, Write};

mod utils;
use utils::{KdError, KdErrorKind};
mod config;
use config::Config;

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
    let mut path = dirs::home_dir().expect("Failed to find home dir");
    path.push(".kd");
    path.push(name);
    if let Err(error) = std::fs::create_dir_all(&path) {
        return Err(KdError::new(KdErrorKind::FlakeInitError, "can not create flake dir".to_string()));
    }
    std::env::set_current_dir(&path);
    println!("Creating new environment '{}'", name);
    let output = Command::new("nix")
       .arg("flake")
       .arg("init")
       .arg("--template")
       .arg("github:alberand/kd#x86_64-linux.default")
       .output()
       .expect("Failed to execute command");
    if !output.status.success() {
        //panic!("Failed to create Flake: {}", String::from_utf8_lossy(&output.stderr));
        return Err(KdError::new(KdErrorKind::FlakeInitError, "Failed to created Flake".to_string()));
    }

    Ok(())
}

fn generate_uconfig(wd: &PathBuf, config: &Config) -> Result<(), KdError> {
    std::env::set_current_dir(wd);

    let xfstests: String = if let Some(subconfig) = &config.xfstests {
        let output = if let Some(rev) = &subconfig.rev {
            nurl(subconfig.repo, &rev).expect("Failed to parse xfstests source repo")
        } else {
            println!("no rev");
            String::from("")
        };

        output
    } else {
        String::from("")
    };

    let xfsprogs: String = if let Some(subconfig) = &config.xfsprogs {
        let output = if let Some(rev) = &subconfig.rev {
            nurl(&subconfig.repo, &rev).expect("Failed to parse xfsprogs source repo")
        } else {
            String::from("")
        };

        output
    } else {
        String::from("")
    };


    let mut tera = Tera::default();

    let source = r#"
        {pkgs}: with pkgs; {
            programs.xfstests.src = {{ xfstests }};
            programs.xfsprogs.src = {{ xfsprogs }};
            kernel = {
              version = "v6.13";
              modDirVersion = "6.13.0";
              src = {{ kernel }};
              kconfig = with pkgs.lib.kernel; {
                XFS_FS = yes;
                FS_VERITY = yes;
              };
            };
        }
    "#;
    tera.add_raw_template("top", source).unwrap();

    let mut context = Context::new();
    context.insert("xfstests", &xfstests);
    context.insert("xfsprogs", &xfsprogs);
    context.insert("kernel", "");

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
        let path = Some(PathBuf::from(r"~/.config/kd/config"));
        let result = Config::load(path);
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
        Some(Commands::Build { target }) => {
            println!("build command {:?}", target);
            let mut path = dirs::home_dir().expect("Failed to find home dir");
            path.push(".kd");
            path.push(name);
            generate_uconfig(&path, &config).expect("Failed to generate user environment");
        },
        Some(Commands::Run) => {
            println!("Run command");
        },
        None => {}
    }
}
