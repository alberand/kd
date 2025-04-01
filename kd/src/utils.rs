use std::error::Error;
use std::fmt;

#[derive(Debug, PartialEq, Eq, Clone)]
pub enum KdErrorKind {
    FlakeInitError,
}

impl fmt::Display for KdErrorKind {
    fn fmt(&self, f: &mut fmt::Formatter) -> fmt::Result {
        match *self {
            KdErrorKind::FlakeInitError => write!(f, "can not create flake"),
        }
    }
}

impl Error for KdErrorKind {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match *self {
            KdErrorKind::FlakeInitError => None,
        }
    }
}

#[derive(Debug)]
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
        write!(f, "{}: {}", self.kind, self.message)
    }
}

impl Clone for KdError {
    fn clone(&self) -> Self {
        Self {
            kind: self.kind.clone(),
            message: self.message.clone(),
        }
    }
}
