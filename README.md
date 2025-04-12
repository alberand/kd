# KD - kernel dev toolset

Development environment for Linux kernel.

In development, everything changing :)

NixOS/Nix and direnv is necessary.

# Usage

Activate environment in the kernel directory:

    $ echo "use flake github:alberand/kd" > .envrc
    $ direnv allow
    ... will take a long time

The following commands are available:

    # Init env
    $ kd init kfeature

    # Build VM or ISO
    $ kd build [vm|iso]

    # Run VM
    $ kd run

The `build` command will create a Nix Flake in `./.kd/kfeature`. Edit this flake
as you wish.

The `run` command runs flake in the `./.kd/kfeature`.

The `.kd.toml` config in the working directory (the one with .envrc) can be used
to modify VM configuration without diving into Nix language.

# Config Examples

## Developing new feature with userspace commands and new tests

```toml
[kernel]
kernel = "arch/x86_64/boot/bzImage"

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


