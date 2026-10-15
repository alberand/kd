use anyhow::{bail, Context, Result};
use rnix::ast::make;
use rnix::{build as nix, Root};
use std::collections::HashMap;
use std::path;
use std::path::PathBuf;
use std::process::Command;

pub mod config;
use config::{KernelHeaders, System, Xfstests};

macro_rules! entry_opt {
    ($set:expr, $key:literal, $opt:expr) => {
        if let Some(v) = &$opt {
            $set = $set.entry($key, nix::string(v));
        }
    };
}

fn raw_expr(text: &str) -> Result<rnix::ast::Expr> {
    let parse = Root::parse(text);
    if !parse.errors().is_empty() {
        bail!(
            "Failed to parse generated Nix fragment {:?}: {:?}",
            text,
            parse.errors()
        );
    }
    parse
        .tree()
        .expr()
        .with_context(|| format!("Empty Nix fragment: {:?}", text))
}

fn nix_path(path: &str) -> rnix::ast::Expr {
    if path.starts_with("~/") {
        make::path_home(path).into()
    } else if path.starts_with('/') {
        make::path_abs(path).into()
    } else if path.starts_with("./") || path.starts_with("../") {
        make::path_rel(path).into()
    } else {
        make::path_rel(&format!("./{path}")).into()
    }
}

fn kernel_headers_expr(headers: &KernelHeaders) -> Result<rnix::ast::Expr> {
    let src = nurl(&headers.repo, &headers.rev)
        .context("Failed to fetch kernel source for headers")?;
    let args = nix::set()
        .entry("src", raw_expr(&src)?)
        .entry("version", nix::string(&headers.version));
    Ok(make::apply(nix::select("pkgs.kd.lib.buildKernelHeaders"), args.into()).into())
}

fn nurl(repo: &str, rev: &str) -> Result<String> {
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
        .context("Failed to fetch source with nurl")?;

    if !output.status.success() {
        bail!("{}", String::from_utf8_lossy(&output.stderr));
    }

    String::from_utf8(output.stdout).context("Failed to parse nurl output")
}

pub struct State {
    pub debug: bool,
    pub curdir: PathBuf,
    pub config: config::Config,
    pub args: Vec<String>,
    pub envs: HashMap<String, String>,
    pub name: Vec<String>,
}

impl Default for State {
    fn default() -> Self {
        Self {
            debug: false,
            curdir: PathBuf::default(),
            config: config::Config::default(),
            args: Vec::<String>::default(),
            envs: HashMap::<String, String>::default(),
            name: vec![],
        }
    }
}

impl State {
    pub fn new(config_path: Option<PathBuf>) -> Result<Self> {
        let curdir = std::env::current_dir().context("Unable to read current directory")?;
        let config_path = if let Some(config_path) = config_path {
            config_path
        } else {
            curdir.clone().join(".kd.kdl")
        };

        let config = config::Config::load(&config_path).map_err(|e| anyhow::anyhow!("{:?}", e))?;

        Ok(Self {
            debug: false,
            curdir,
            config,
            args: vec![],
            envs: HashMap::new(),
            name: vec![],
        })
    }

    pub fn uconfig(&mut self) -> Result<String> {
        // "First name only": use the first requested named config, if any.
        let name = self.name.first().map(|s| s.as_str());
        let merged: System = self
            .config
            .select(name)
            .map_err(|e| anyhow::anyhow!("{:?}", e))?;

        let mut set = nix::set();

        if let Some(packages) = &merged.packages {
            let items = packages.0.iter().map(|p| nix::select(&format!("pkgs.{p}")));
            set = set.entry(
                "environment.systemPackages",
                nix::list().items(items).into(),
            );
        }

        if let Some(config) = &merged.xfstests {
            let mut xfstests = nix::set();

            if let Some(rev) = &config.rev {
                let default = Xfstests::default().repo.unwrap_or_default();
                let repo = config.repo.as_deref().unwrap_or(&default);
                let src = nurl(repo, rev).context("Failed to fetch xfstests source")?;
                xfstests = xfstests.entry("src", raw_expr(&src)?);
            }

            entry_opt!(xfstests, "arguments", config.args);

            if let Some(devices) = &config.devices {
                let mut dev = nix::set();
                entry_opt!(dev, "test.main", devices.test);
                entry_opt!(dev, "test.rtdev", devices.test_rtdev);
                entry_opt!(dev, "test.logdev", devices.test_logdev);
                entry_opt!(dev, "scratch.main", devices.scratch);
                entry_opt!(dev, "scratch.rtdev", devices.scratch_rtdev);
                entry_opt!(dev, "scratch.logdev", devices.scratch_logdev);
                xfstests = xfstests.entry("dev", dev.into());
            }

            entry_opt!(xfstests, "filesystem", config.filesystem);
            entry_opt!(xfstests, "extraEnv", config.extra_env);

            if let Some(hooks) = &config.hooks {
                xfstests = xfstests.entry("hooks", nix_path(hooks));
            }

            if let Some(headers) = &config.kernel_headers {
                xfstests = xfstests.entry("kernelHeaders", kernel_headers_expr(headers)?);
            }

            set = set.entry("services.xfstests", xfstests.into());
        }

        if let Some(config) = &merged.xfsprogs {
            let mut xfsprogs = nix::set();

            if let (Some(repo), Some(rev)) = (&config.repo, &config.rev) {
                let src = nurl(repo, rev).context("Failed to fetch xfsprogs source")?;
                xfsprogs = xfsprogs.entry("src", raw_expr(&src)?);
            }

            if let Some(headers) = &config.kernel_headers {
                xfsprogs = xfsprogs.entry("kernelHeaders", kernel_headers_expr(headers)?);
            }

            set = set.entry("services.xfsprogs", xfsprogs.into());
        }

        if let Some(kernel) = &merged.kernel {
            if let Some(prebuild) = &kernel.prebuild {
                let path = path::absolute(self.curdir.join(prebuild))
                    .context("Failed to parse kernel path")?;
                self.envs.insert(
                    "NIXPKGS_QEMU_KERNEL_kd".to_string(),
                    path.display().to_string(),
                );
            } else {
                let mut knl = nix::set();
                if let (Some(rev), Some(version)) = (&kernel.rev, &kernel.version) {
                    let default_repo = "git@github.com:torvalds/linux.git".to_string();
                    let repo = kernel.repo.as_ref().unwrap_or(&default_repo);
                    let src = nurl(repo, rev).context("Failed to parse kernel source repo")?;
                    knl = knl.entry("version", nix::string(version));
                    knl = knl.entry("src", raw_expr(&src)?);
                }
                set = set.entry("kernel", knl.into());

                if !kernel.config.0.is_empty() {
                    let mut kconfig = nix::set();
                    for option in &kernel.config.0 {
                        let name = option.name.strip_prefix("CONFIG_").unwrap_or(&option.name);
                        kconfig = kconfig.entry(name, nix::ident(&option.value.to_string()));
                    }
                    let kconfig = make::with_expr(nix::select("pkgs.lib.kernel"), kconfig.into());
                    set = set.entry("kernel.kconfig", kconfig.into());
                }
            }
        }

        if let Some(qemu) = &merged.qemu {
            if !qemu.options.is_empty() {
                let items = qemu.options.iter().map(|o| nix::string(o));
                set = set.entry(
                    "virtualisation.qemu.options",
                    nix::list().items(items).into(),
                );
            }
        }

        let params = make::pattern(
            vec![make::pat_entry("pkgs", None), make::pat_entry("kd", None)],
            true,
            None,
        );
        let lambda = make::lambda(params.into(), set.into());

        let generated = lambda.to_string();
        let parse = Root::parse(&generated);
        if !parse.errors().is_empty() {
            bail!("Generated invalid Nix: {:?}", parse.errors());
        }

        Ok(generated)
    }
}
