use kd::config::Config;
use insta::assert_debug_snapshot;

#[test]
fn kd_normal_config() {
    let config = Config::load("tests/assets/config.kdl").unwrap();
    assert_debug_snapshot!(config, @r#"
Config {
    common: System {
        packages: None,
        kernel: Some(
            Kernel {
                prebuild: None,
                version: Some(
                    "v7.0-rc1",
                ),
                rev: Some(
                    "ca58485b0b9566d5bfa3cfe1d88fdee5b78e1516",
                ),
                repo: Some(
                    "git@github.com:alberand/linux.git",
                ),
                config: KernelConfig(
                    [
                        KernelConfigOption {
                            name: "CONFIG_FS_VERITY",
                            value: Y,
                        },
                        KernelConfigOption {
                            name: "CONFIG_FS_VERITY_BUILTIN_SIGNATURES",
                            value: Y,
                        },
                    ],
                ),
            },
        ),
        xfstests: Some(
            Xfstests {
                repo: Some(
                    "git@github.com:alberand/linux.git",
                ),
                rev: Some(
                    "ca58485b0b9566d5bfa3cfe1d88fdee5b78e1516",
                ),
                args: Some(
                    "-d -s xfs_4k -g auto",
                ),
                filesystem: None,
                hooks: None,
                kernel_headers: Some(
                    KernelHeaders {
                        version: "v7.0-rc2",
                        rev: "ca58485b0b9566d5bfa3cfe1d88fdee5b78e1516",
                        repo: "git@github.com:alberand/linux.git",
                    },
                ),
                devices: Some(
                    XfstestsDevices {
                        test: Some(
                            "/dev/sda",
                        ),
                        test_rtdev: Some(
                            "/dev/sda",
                        ),
                        test_logdev: Some(
                            "/dev/sda",
                        ),
                        scratch: Some(
                            "/dev/sda",
                        ),
                        scratch_rtdev: Some(
                            "/dev/sda",
                        ),
                        scratch_logdev: Some(
                            "/dev/sda",
                        ),
                    },
                ),
                extra_env: None,
            },
        ),
        xfsprogs: Some(
            Xfsprogs {
                repo: Some(
                    "git@github.com:alberand/linux.git",
                ),
                rev: Some(
                    "ca58485b0b9566d5bfa3cfe1d88fdee5b78e1516",
                ),
                kernel_headers: None,
            },
        ),
        script: None,
        qemu: None,
    },
    configs: Some(
        Configs {
            common: System {
                packages: None,
                kernel: Some(
                    Kernel {
                        prebuild: Some(
                            "arch/x86/boot/bzImage",
                        ),
                        version: Some(
                            "v7.0-rc1",
                        ),
                        rev: Some(
                            "3d2d783f553d73824a6f5eaf26065de97dea0871",
                        ),
                        repo: Some(
                            "git@github.com:alberand/linux.git",
                        ),
                        config: KernelConfig(
                            [
                                KernelConfigOption {
                                    name: "CONFIG_FS_VERITY",
                                    value: Y,
                                },
                                KernelConfigOption {
                                    name: "CONFIG_FS_VERITY_BUILTIN_SIGNATURES",
                                    value: Y,
                                },
                            ],
                        ),
                    },
                ),
                xfstests: Some(
                    Xfstests {
                        repo: Some(
                            "file:///home/alberand/Projects/xfstests-dev",
                        ),
                        rev: Some(
                            "c0bea11ded74fe4d763018b5b233be14c298c048",
                        ),
                        args: None,
                        filesystem: None,
                        hooks: None,
                        kernel_headers: None,
                        devices: None,
                        extra_env: None,
                    },
                ),
                xfsprogs: Some(
                    Xfsprogs {
                        repo: Some(
                            "file:///home/alberand/Projects/xfsprogs-dev",
                        ),
                        rev: Some(
                            "6a3a4ed7d5a06576f5934c0b907303137320e011",
                        ),
                        kernel_headers: None,
                    },
                ),
                script: None,
                qemu: None,
            },
            config: [
                NamedSystem {
                    name: "verity",
                    common: System {
                        packages: Some(
                            Packages(
                                [
                                    "fsverity-utils",
                                ],
                            ),
                        ),
                        kernel: None,
                        xfstests: Some(
                            Xfstests {
                                repo: None,
                                rev: None,
                                args: Some(
                                    "-d -s xfs_1k -s xfs_4k -s xfs_8k -g verity",
                                ),
                                filesystem: None,
                                hooks: None,
                                kernel_headers: None,
                                devices: None,
                                extra_env: None,
                            },
                        ),
                        xfsprogs: None,
                        script: None,
                        qemu: None,
                    },
                },
            ],
        },
    ),
    dev: None,
}
    "#);
}

//#[test]
//fn kd_corrupted_config() -> Result<()> {
//    let config = Config::load("tests/assets/corrupted.kdl");
//    assert!(config.is_err());
//    Ok(())
//}
