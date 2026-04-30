use kd::config::Config;
use kd::{generate_uconfig, State};
use anyhow::Result;

#[test]
fn kd_normal_config() -> Result<()> {
    let config = Config::load("tests/assets/config.toml");
    assert!(config.is_ok());
    assert!(config?.validate().is_ok());
    Ok(())
}

#[test]
fn kd_corrupted_config() -> Result<()> {
    let config = Config::load("tests/assets/corrupted.toml");
    assert!(config.is_err());
    Ok(())
}

//#[test]
//fn kd_xfstests_no_repo() -> Result<()> {
//    let config = Config::load("tests/assets/xfstests-no-repo.toml")?;
//    let mut state = State::default();
//    state.config = config;
//    state.name = "auto".to_string();
//    let nix_config = generate_uconfig(&mut state)?;
//    assert_eq!(nix_config, "{\n    uconfig = {pkgs, kd}: with pkgs; {\n        services.xfstests = { arguments = \"-r -s xfs_4k -g auto\"; };\nservices.xfsprogs = { src = builtins.fetchGit {\n  url = \"file:///home/aalbersh/Release/xfsprogs-dev\";\n  rev = \"922f14a9b77638b4a3fc604169df6799d16f8fd7\";\n  allRefs = true;\n}; };\n    };\n}\n");
//    Ok(())
//}
