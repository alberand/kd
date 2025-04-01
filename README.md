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

    # Deploy ISO to libvirtd machine
    $ kd deploy [path]

    # Generate minimal QEMU config
    $ kd config vm

    # Generate minimal ISO config
    $ kd config iso

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
[kernel]
repository = "git@github.com:torvalds/linux.git"
rev = "v6.14"

[xfstests]
args = "-s xfs_4k -g auto"

[xfsprogs]
repository = "git@github.com:alberand/xfsprogs.git"
rev = "dc00e8f7de86fe862df3a9f3fda11b710d10434b"
```
