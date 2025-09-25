use std::error::Error;
use std::fmt;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};
use toml;

#[derive(Debug)]
pub enum KdErrorKind {
    IOError(std::io::Error),
    TOMLError(toml::de::Error),
    RuntimeError,
    ConfigError,
}

impl fmt::Display for KdErrorKind {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            KdErrorKind::IOError(ref source) => source.fmt(f),
            KdErrorKind::TOMLError(ref source) => source.fmt(f),
            KdErrorKind::RuntimeError => write!(f, "runtime error"),
            KdErrorKind::ConfigError => write!(f, "config error"),
        }
    }
}

impl Error for KdErrorKind {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            KdErrorKind::IOError(source) => Some(source),
            KdErrorKind::TOMLError(source) => Some(source),
            KdErrorKind::RuntimeError => None,
            KdErrorKind::ConfigError => None,
        }
    }
}

impl From<std::io::Error> for KdErrorKind {
    fn from(error: std::io::Error) -> Self {
        KdErrorKind::IOError(error)
    }
}

impl From<toml::de::Error> for KdErrorKind {
    fn from(error: toml::de::Error) -> Self {
        KdErrorKind::TOMLError(error)
    }
}

pub struct KdError {
    kind: KdErrorKind,
    message: String,
}

impl KdError {
    pub fn new(kind: KdErrorKind, message: String) -> Self {
        Self { kind, message }
    }
}

impl fmt::Display for KdError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(f, "{}: {}", self.message, self.kind)
    }
}

impl fmt::Debug for KdError {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        write!(
            f,
            "KdError {{ kind: {}, message: {} }}",
            self.kind, self.message
        )
    }
}

pub fn find_it<P>(exe_name: P) -> Option<PathBuf>
where
    P: AsRef<Path>,
{
    std::env::var_os("PATH").and_then(|paths| {
        std::env::split_paths(&paths)
            .filter_map(|dir| {
                let full_path = dir.join(&exe_name);
                if full_path.is_file() {
                    Some(full_path)
                } else {
                    None
                }
            })
            .next()
    })
}

pub fn is_executable(path: &PathBuf) -> bool {
    let metadata = match path.metadata() {
        Ok(metadata) => metadata,
        Err(_) => return false,
    };
    let permissions = metadata.permissions();
    metadata.is_file() && permissions.mode() & 0o111 != 0
}
