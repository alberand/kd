use anyhow::{bail, Context, Result};
use clap::Parser;
use std::fs::File;
use std::io::Write;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::process::{Command, Stdio};

use kd::*;
mod cli;
use cli::{Cli, Commands};

fn cmd_init(_: &State) -> Result<()> {
    let curdir = std::env::current_dir().context("No able to get current working directory")?;
    let config_path = curdir.clone().join(".kd.toml");
    match &mut File::create(&config_path) {
        Ok(target) => writeln!(target, include_str!("config.tmpl"))
            .context("Failed to write env name to .kd.toml")?,
        Err(error) => {
            bail!("Unable to create {}: {}", config_path.display(), error);
        }
    };

    let flake_dir = curdir.clone().join(".kd/flake");
    std::fs::create_dir_all(&flake_dir)
        .with_context(|| format!("Unable to create {}", flake_dir.display()))?;

    println!("Creating new environment");
    let mut cmd = Command::new("nix");
    cmd.arg("flake")
        .arg("init")
        .arg("--template")
        .arg("github:alberand/kd#default")
        .current_dir(&flake_dir);

    let output = cmd.output().expect("Failed to execute command");

    if !output.status.success() {
        println!("Failed to create Nix Flake:");
        println!("{}", String::from_utf8_lossy(&output.stderr));
        std::process::exit(1);
    }

    let user_config = PathBuf::from(flake_dir.clone()).join("uconfig.nix");
    File::create(&user_config)
        .with_context(|| format!("Unable to create {}", user_config.display()))?;

    let direnv = curdir.join(".envrc");
    if direnv.exists() {
        let mut backup = direnv.clone();
        backup.set_extension("bup");
        std::fs::copy(&direnv, backup).context("Failed to make backup of .envrc")?;
    }

    match &mut File::create(&direnv) {
        Ok(target) => {
            writeln!(target, "use flake path:.kd/flake").context("Failed to overwrite .envrc")?;
        }
        Err(error) => {
            bail!("Unable to create {}: {}", direnv.display(), error);
        }
    };

    // Check that these commands exists
    println!("All done!");
    println!("Active the environment with:");
    println!("direnv allow");

    Ok(())
}

fn cmd_build(state: &mut State) -> Result<()> {
    match generate_uconfig(state) {
        Ok(content) => {
            let mut file = std::fs::File::create(&state.user_config)
                .context("Failed to create user config uconfig.nix")?;
            file.write_all(content.as_bytes())
                .context("Failed to write out uconfig.nix data")?;
        }
        Err(error) => {
            bail!("Failed to generate nix config: {error}");
        }
    }

    let package = format!("path:{}#image", state.flake_dir.display());

    let mut cmd = Command::new("nix");
    cmd.arg("build").args(&state.args).arg(&package);

    if state.debug {
        println!("command: {:?}", cmd);
    }

    cmd.spawn()
        .context("Failed to spawn 'nix build'")?
        .wait()
        .context("'nix build' wasn't running")?;

    Ok(())
}

fn cmd_run(state: &mut State) -> Result<()> {
    match generate_uconfig(state) {
        Ok(content) => {
            let mut file = std::fs::File::create(&state.user_config)
                .context("Failed to create user config uconfig.nix")?;
            file.write_all(content.as_bytes())
                .context("Failed to write out uconfig.nix data")?;
        }
        Err(error) => {
            bail!("Failed to generate nix config: {error}")
        }
    }

    state
        .args
        .push(format!("path:{}#vm", state.flake_dir.display()));
    let mut cmd = Command::new("nix");
    cmd.arg("run")
        .args(state.args.clone())
        .envs(state.envs.clone());

    if state.debug {
        println!("command: {:?}", cmd);
    }

    cmd.spawn()
        .context("Failed to spawn 'nix run'")?
        .wait()
        .context("'nix run' wasn't running")?;

    Ok(())
}

fn cmd_update(state: &State) -> Result<()> {
    let package = format!("path:{}", state.flake_dir.display());
    let mut cmd = Command::new("nix");
    cmd.arg("flake")
        .arg("update")
        .arg("--flake")
        .arg(&package)
        .current_dir(&state.flake_dir);

    if state.debug {
        println!("command: {:?}", &cmd);
    }

    cmd.spawn()
        .context("Failed to spawn 'nix flake update'")?
        .wait()
        .context("'nix flake update' wasn't running")?;

    Ok(())
}

fn cmd_config(state: &mut State, output: Option<String>) -> Result<()> {
    match generate_uconfig(state) {
        Ok(content) => {
            let mut file = std::fs::File::create(&state.user_config)
                .context("Failed to create user config uconfig.nix")?;
            file.write_all(content.as_bytes())
                .context("Failed to write out uconfig.nix data")?;
        }
        Err(error) => {
            bail!("Failed to generate nix config: {error}")
        }
    }

    let package = format!("path:{}#kconfig", state.flake_dir.display());
    let mut cmd = Command::new("nix");
    cmd.arg("build").arg(&package).current_dir(&state.envdir);

    if state.debug {
        println!("command: {:?}", cmd);
    }

    cmd.spawn()
        .context("Failed to spawn 'nix build .#kconfig'")?
        .wait()
        .context("'nix build .#kconfig' wasn't running")?;

    let output = if let Some(output) = output {
        PathBuf::from(output)
    } else {
        state.curdir.clone().join(".config")
    };

    if output.exists() {
        let mut backup = output.clone();
        backup.set_extension("bup");
        std::fs::copy(&output, backup).context("Failed to create config backup")?;
    }

    let source = state.envdir.clone().join("result");
    std::fs::copy(source, &output).context("Failed to copy config to .config")?;
    std::fs::set_permissions(output, std::fs::Permissions::from_mode(0o644))
        .context("Failed to set 644 permission on config")
}

fn cmd_debug(state: &mut State, output: &bool) -> Result<()> {
    match generate_uconfig(state) {
        Ok(content) => {
            if *output {
                let mut cmd = Command::new("alejandra")
                    .stdin(Stdio::piped())
                    .arg("--quiet")
                    .spawn()
                    .context("alejandra (nix code formatter) failed to run")?;
                write!(
                    cmd.stdin
                        .as_mut()
                        .context("No input content for alejandra")?,
                    "{}",
                    content
                )
                .unwrap();
                cmd.wait().context("'alejandra' failed to run")?;
            }
            Ok(())
        }
        Err(error) => {
            bail!("Failed to generate nix config: {error}")
        }
    }
}

fn main() -> Result<()> {
    let cli = Cli::parse();

    // All the command require .kd.toml. Only init can go without the config as it creates it
    let mut state = State::new(cli.config).unwrap_or_else(|error| {
        if let Some(Commands::Init {}) = &cli.command {
            // we good to go as we doing init
            State::default()
        } else {
            println!("Initialization failed: {}", error);
            std::process::exit(1);
        }
    });

    state.debug = cli.debug;
    if let Err(error) = state.config.validate() {
        println!("Invalid config: {error}");
        std::process::exit(1);
    }

    if state.debug {
        state.args.push("--show-trace".to_string());
    }

    if let Some(config) = &state.config.dev {
        if let Some(args) = &config.args {
            for arg in args {
                state.args.push(arg.to_string())
            }
        }
    }

    match &cli.command {
        Some(Commands::Init {}) => cmd_init(&state).context("Initialization failed"),

        Some(Commands::Build { name }) => {
            if let Some(name) = &name {
                state.name = name.clone();
            }

            cmd_build(&mut state)
        }

        Some(Commands::Run { name }) => {
            if let Some(name) = &name {
                state.name = name.clone();
            }

            cmd_run(&mut state)
        }

        Some(Commands::Update {}) => cmd_update(&state),

        Some(Commands::Config { output, name }) => {
            if let Some(name) = &name {
                state.name = name.clone();
            }

            cmd_config(&mut state, output.clone())
        }

        Some(Commands::Debug { config, name }) => {
            if let Some(name) = &name {
                state.name = name.clone();
            }

            cmd_debug(&mut state, config)
        }

        None => Ok(()),
    }
}
