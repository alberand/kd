use std::fmt;
use clap::ValueEnum;

#[derive(ValueEnum, Copy, Clone, Debug, PartialEq, Eq)]
pub enum Target {
    Qcow,
}

impl Default for Target {
    fn default() -> Self {
        Target::Qcow
    }
}

impl fmt::Display for Target {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            Target::Qcow => write!(f, "qcow"),
        }
    }
}

