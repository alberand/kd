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

Now you can do following:

    # Generate minimal kernel config for QEMU
    $ kd config

    # Build QCOW2 or ISO
    $ kd build [qcow|iso]

    # Run VM
    $ kd run

Edit your `.kd.toml` config to adjust environment to your needs.

If you know Nix you can edit VM configuration direction in
`.kd/kfeature/uconfig.nix`. **Note** that `kd build` command overwrites
`uconfig.nix`!

The `run` command runs flake in the `./.kd/kfeature`.

# Config Examples

## Developing new feature with userspace commands and new tests

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

[dummy]
script = "./test.sh"
```

## Testing xfsprogs package

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
