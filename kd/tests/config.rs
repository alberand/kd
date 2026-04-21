use kd::config::Config;
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
