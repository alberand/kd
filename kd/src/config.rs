use knuffel;
use miette::{Context, IntoDiagnostic};
use std::fs;
use std::path::Path;

trait Merge<T> {
    fn merge_with(&mut self, part: &T);
}

macro_rules! merge_clone {
    (($self:expr, $part:expr), $($field:ident),+ $(,)*) => {
        $(
            if let Some(x) = &$part.$field {
                $self.$field.clone_from(x);
            }
        )+
    };
}

macro_rules! merge_clone_opt {
    (($self:expr, $part:expr), $($field:ident),+ $(,)*) => {
        $(
            if $part.$field.is_some() {
                $self.$field.clone_from(&$part.$field);
            }
        )+
    };
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct KernelHeaders {
    #[knuffel(child, unwrap(argument), default)]
    pub version: String,
    #[knuffel(child, unwrap(argument), default)]
    pub rev: String,
    #[knuffel(child, unwrap(argument), default)]
    pub repo: String,
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct KernelHeadersPart {
    #[knuffel(child, unwrap(argument), default)]
    pub version: Option<String>,
    #[knuffel(child, unwrap(argument), default)]
    pub rev: Option<String>,
    #[knuffel(child, unwrap(argument), default)]
    pub repo: Option<String>,
}

impl Merge<KernelHeadersPart> for KernelHeaders {
    fn merge_with(&mut self, part: &KernelHeadersPart) {
        merge_clone!((self, part), version, rev, repo);
    }
}

#[derive(knuffel::DecodeScalar, Debug, Default, Eq, Clone, Copy, PartialEq)]
pub enum KernelConfigOptionValue {
    Y,
    #[default]
    N,
    M,
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct KernelConfigOption {
    #[knuffel(node_name)]
    pub name: String,
    #[knuffel(argument)]
    pub value: KernelConfigOptionValue,
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct KernelConfig(#[knuffel(children)] pub Vec<KernelConfigOption>);

impl Merge<KernelConfig> for KernelConfig {
    fn merge_with(&mut self, part: &KernelConfig) {
        for option in &part.0 {
            self.0.retain_mut(|val| {
                if option.name == *val.name {
                    *val = option.clone();
                };
                true
            });
        }
    }
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct Kernel {
    #[knuffel(child, unwrap(argument))]
    pub prebuild: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub version: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub rev: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub repo: Option<String>,

    #[knuffel(child, default)]
    pub config: KernelConfig,
}

impl Merge<Kernel> for Kernel {
    fn merge_with(&mut self, part: &Kernel) {
        merge_clone_opt!((self, part), prebuild, version, rev, repo);
        self.config.merge_with(&part.config);
    }
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct XfstestsDevices {
    #[knuffel(child, unwrap(argument))]
    pub test: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub test_rtdev: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub test_logdev: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub scratch: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub scratch_rtdev: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub scratch_logdev: Option<String>,
}

impl Merge<XfstestsDevices> for XfstestsDevices {
    fn merge_with(&mut self, part: &XfstestsDevices) {
        merge_clone_opt!(
            (self, part),
            test,
            test_rtdev,
            test_logdev,
            scratch,
            scratch_rtdev,
            scratch_logdev
        );
    }
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct Xfstests {
    #[knuffel(child, unwrap(argument))]
    pub repo: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub rev: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub args: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub filesystem: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub hooks: Option<String>,
    #[knuffel(child)]
    pub kernel_headers: Option<KernelHeaders>,
    #[knuffel(child)]
    pub devices: Option<XfstestsDevices>,
    #[knuffel(child, unwrap(argument))]
    pub extra_env: Option<String>,
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct XfstestsPart {
    #[knuffel(child, unwrap(argument))]
    pub repo: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub rev: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub args: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub filesystem: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub hooks: Option<String>,
    #[knuffel(child)]
    pub kernel_headers: Option<KernelHeaders>,
    #[knuffel(child)]
    pub devices: Option<XfstestsDevices>,
    #[knuffel(child, unwrap(argument))]
    pub extra_env: Option<String>,
}

impl Merge<XfstestsPart> for Xfstests {
    fn merge_with(&mut self, part: &XfstestsPart) {
        merge_clone_opt!(
            (self, part),
            repo,
            rev,
            args,
            filesystem,
            hooks,
            extra_env,
            kernel_headers,
            devices
        );
    }
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct Xfsprogs {
    #[knuffel(child, unwrap(argument))]
    pub repo: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub rev: Option<String>,
    #[knuffel(child)]
    pub kernel_headers: Option<KernelHeaders>,
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct XfsprogsPart {
    #[knuffel(child, unwrap(argument))]
    pub repo: Option<String>,
    #[knuffel(child, unwrap(argument))]
    pub rev: Option<String>,
    #[knuffel(child)]
    pub kernel_headers: Option<KernelHeaders>,
}

impl Merge<XfsprogsPart> for Xfsprogs {
    fn merge_with(&mut self, part: &XfsprogsPart) {
        merge_clone_opt!((self, part), repo, rev, kernel_headers);
    }
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct Script {
    #[knuffel(child, unwrap(argument))]
    pub script: String,
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct ScriptPart {
    #[knuffel(child, unwrap(argument))]
    pub script: Option<String>,
}

impl Merge<ScriptPart> for Script {
    fn merge_with(&mut self, part: &ScriptPart) {
        merge_clone!((self, part), script);
    }
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct Qemu {
    #[knuffel(children, unwrap(argument))]
    pub options: Vec<String>,
}

impl Merge<Qemu> for Qemu {
    fn merge_with(&mut self, part: &Qemu) {
        self.options.extend(part.options.clone());
    }
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct Developer {
    #[knuffel(children, unwrap(argument))]
    pub arg: Vec<String>,
}

impl Merge<Developer> for Developer {
    fn merge_with(&mut self, part: &Developer) {
        self.arg.extend(part.arg.clone());
    }
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct Packages(#[knuffel(arguments)] pub Vec<String>);

impl Merge<Packages> for Packages {
    fn merge_with(&mut self, part: &Packages) {
        self.0.extend(part.0.clone());
    }
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct System {
    #[knuffel(child)]
    pub packages: Option<Packages>,
    #[knuffel(child)]
    pub kernel: Option<Kernel>,
    #[knuffel(child)]
    pub xfstests: Option<Xfstests>,
    #[knuffel(child)]
    pub xfsprogs: Option<Xfsprogs>,
    #[knuffel(child)]
    pub script: Option<Script>,
    #[knuffel(child)]
    pub qemu: Option<Qemu>,
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct SystemPart {
    #[knuffel(child)]
    pub packages: Option<Packages>,
    #[knuffel(child)]
    pub kernel: Option<Kernel>,
    #[knuffel(child)]
    pub xfstests: Option<Xfstests>,
    #[knuffel(child)]
    pub xfsprogs: Option<Xfsprogs>,
    #[knuffel(child)]
    pub script: Option<Script>,
    #[knuffel(child)]
    pub qemu: Option<Qemu>,
}
impl Merge<SystemPart> for System {
    fn merge_with(&mut self, part: &SystemPart) {
        merge_clone_opt!(
            (self, part),
            packages,
            kernel,
            xfstests,
            xfsprogs,
            script,
            qemu
        );
    }
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct NamedSystem {
    #[knuffel(argument)]
    pub name: String,
    #[knuffel(flatten(child))]
    common: System,
}

#[derive(knuffel::Decode, Debug, Default, Clone, PartialEq, Eq)]
pub struct Configs {
    #[knuffel(flatten(child))]
    common: System,
    #[knuffel(children)]
    pub config: Vec<NamedSystem>,
}

#[derive(knuffel::Decode, Default, Clone, Debug, PartialEq, Eq)]
pub struct Config {
    #[knuffel(flatten(child))]
    common: System,

    #[knuffel(child)]
    pub configs: Option<Configs>,
    #[knuffel(child)]
    pub dev: Option<Developer>,
}

impl Config {
    pub fn load<T: AsRef<Path>>(path: T) -> miette::Result<Self> {
        let data = fs::read_to_string(&path)
            .into_diagnostic()
            .wrap_err_with(|| format!("cannot read {:?}", path.as_ref()))?;
        let path = path.as_ref().to_str().unwrap_or("config.kdl");
        let config = knuffel::parse::<Config>(path, &data)?;

        Ok(config)
    }
}
