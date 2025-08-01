# KD - kernel dev toolset

Development environment for Linux kernel.

In development, everything changing :) That's my setup for linux kernel work.

NixOS/Nix and direnv is necessary.

# Usage

Activate environment in the kernel directory:

    $ echo "use flake github:alberand/kd" > .envrc && direnv allow
    ... will take a long time

Now create environment with your feature name:

    # Init env
    $ kd init kfeature

Run VM:

    # Run VM
    $ kd run

You can also generate minimal config or build a deployable image for longer test
runs:

    # Generate minimal kernel config for QEMU
    $ kd config

    # Build QCOW2 or ISO
    $ kd build [qcow|iso]

Edit your `.kd.toml` config to adjust environment to your needs.

If you know Nix you can edit VM configuration direction in
`.kd/kfeature/uconfig.nix`. **Note** that `kd build` command overwrites
`uconfig.nix`!

The `run` command runs flake in the `./.kd/kfeature`.

# Config Examples

## Developing new feature with userspace commands and new tests

The `prebuild = true` is quite important. Instead of using Nix to build your
kernel in reproducible way, the `kd` will just take your compiled kernel from
the current directory.

```toml
[kernel]
# Use already build kernel from the current directory
prebuild = true

[xfstests]
repository = "git@github.com:alberand/xfstests.git"
rev = "eb01a1c8b1007bcad534730d38a8dda4c005c15e"
args = ""
hooks = "/home/aalbersh/Projects/kernel/fsverity/hooks"
config = "./xfstests.config"

[xfsprogs]
repository = "git@github.com:alberand/xfsprogs.git"
rev = "dc00e8f7de86fe862df3a9f3fda11b710d10434b"

[script]
script = "./test.sh"
```

## Developing kernel, xfsprogs and xfstests at the same time

This config has a `gdb` package included into VM. The xfstests and xfsprogs
packages are pointing to local repositories for quicker iterations.

```toml
name = "default"
packages = [ "gdb" ]

[kernel]
prebuild = true

[kernel.config]
CONFIG_XFS_FS = "yes"
CONFIG_XFS_QUOTA = "yes"
CONFIG_XFS_RT = "yes"
CONFIG_XFS_ONLINE_SCRUB = "yes"
CONFIG_XFS_ONLINE_REPAIR = "yes"
CONFIG_XFS_POSIX_ACL = "yes"
CONFIG_XFS_DEBUG = "yes"

CONFIG_FS_VERITY = "yes"
CONFIG_FS_VERITY_BUILTIN_SIGNATURES = "yes"

[xfstests]
repo = "file:///home/aalbersh/Projects/xfstests-dev"
rev = "b602eccc851aae190e5a4319171481bc4c90888b"
args = "-d -s xfs_1k_quota generic/572 generic/574"
hooks = "/home/aalbersh/Projects/kernel/fsverity/tmp/hooks"

[xfsprogs]
repo = "file:///home/aalbersh/Projects/xfsprogs-dev"
rev = "adf2358f1aa2f625d910c1c84fd89a9cd4412d2b"
```

## Testing xfsprogs package

This is config used for xfsprogs package testing with latest kernel.

```toml
name = "xfsprogs-testing"

[kernel.config]
CONFIG_XFS_FS = "yes"
CONFIG_XFS_QUOTA = "yes"
CONFIG_XFS_RT = "yes"
CONFIG_XFS_ONLINE_SCRUB = "yes"
CONFIG_XFS_ONLINE_REPAIR = "yes"
CONFIG_XFS_POSIX_ACL = "yes"

CONFIG_DM_FLAKEY = "yes"
CONFIG_DM_SNAPSHOT = "yes"
CONFIG_DM_DELAY = "yes"
CONFIG_DM_THIN_PROVISIONING = "yes"
CONFIG_SCSI_DEBUG = "yes"
CONFIG_USER_NS = "yes"
CONFIG_DAX = "yes"
CONFIG_IO_URING = "yes"

[xfstests]
args = "-r -s xfs_4k -g all -x deprecated,dangerous_fuzzers,broken,recoveryloop"
test_dev = "/dev/vdb"
scratch_dev = "/dev/vdc"

[xfsprogs]
repo = "git://git.kernel.org/pub/scm/linux/kernel/git/aalbersh/xfsprogs-dev.git"
rev = "v6.14.0"
```

# TODO
- [ ] Do I really need to use TOML instead of just plain Nix? devenv does it but
      Nix isn't that nice for configuration
- [ ] Convert `nurl` to front-end + lib to call use the lib directly
- [ ] After decision on TOML necessity, convert `kd` from string manipulation to
      parsing Nix code with rnix-parse
- [ ] Add Initrd generator without kernel/modules
- [ ] Make `kd run` without Nix evaluation, it can put all the things in right
      places and execute a script with qemu
