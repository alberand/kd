use std::error::Error;
use std::fmt;
use std::process::Command;
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

pub fn nurl(repo: &str, rev: &str) -> Result<String, KdError> {
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
