use clap::{Parser, Subcommand};
use std::path::PathBuf;
use crate::common::Target;

#[derive(Parser)]
#[command(version)]
#[command(name = "kd")]
#[command(about = "linux kernel development tool", long_about = None)]
pub struct Cli {
    /// Sets a custom config file
    #[arg(short, long, value_name = "FILE")]
    pub config: Option<PathBuf>,

    /// Turn debugging information on
    #[arg(short, long)]
    pub debug: bool,

    #[command(subcommand)]
    pub command: Option<Commands>,
}


#[derive(Subcommand)]
pub enum Commands {
    /// Initialize development environment
    Init {},

    /// Build QCOW image
    Build {
        /// lists test values
        #[arg(
            default_value_t = Target::Qcow,
            value_enum
        )]
        target: Target,
        #[arg(long, help = "Name of a test config to use")]
        name: Option<String>,
    },

    /// Run QEMU test system
    Run {
        #[arg(long, help = "Name of a test config to use")]
        name: Option<String>,
    },

    /// Update 'kd' environment
    Update {},

    /// Generate minimal kernel config for VM
    Config {
        #[arg(short, long, default_value = ".config", help = "Output filename")]
        output: Option<String>,
        #[arg(long, help = "Name of a test config to use")]
        name: Option<String>,
    },

    /// Developer tools
    Debug {
        #[arg(short, long, action = clap::ArgAction::SetTrue, help = "Output config")]
        config: bool,
        #[arg(long, help = "Name of a config to use")]
        name: Option<String>,
    },
}
