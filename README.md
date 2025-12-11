# KD - kernel dev toolset

Development environment for Linux kernel.

**Note!** In development, everything changing :) That's my setup for linux
kernel work.

NixOS/Nix and direnv are required.

# Usage

Initial step to get kd on your system:

    $ echo "use flake github:alberand/kd" > .envrc && direnv allow
    ... will take a long time

The command above just created `.envrc` file which tells `direnv` to use shell
environment from the "Nix Flake". The flake itself is located at github.

Now create environment:

    $ kd init

The command above creates a "Nix Flake" in `.kd` directory. This flake defines
shell to work with Linux kernel. Along the `.kd` dir, command above updated
`.envrc` to point to the local `.kd` directory instead of github.com.

Now you can modify `.kd.toml` file and run VM:

    $ kd run

You can also generate minimal config or build a deployable image for longer test
runs:

    $ kd config

    # Very handy for a longer test runs. I deploy these qcow images with `virsh`
    # to my remote test machine running libvirtd
    $ kd build [qcow|iso]

If you know Nix you can edit VM configuration direction in
`.kd/kfeature/uconfig.nix`.

**Note** that `kd build/run` command overwrites `uconfig.nix`!

# Config Examples

## Simple

The following config will build a VM with latest kernel (see
`sources/kernel.json` at the github.com/alberand/kd), xfstests pinned to
`eb01a1...` and xfsprogs pinned to `dc00e8f...`. When VM boots, `xfstests`
systemd unit will run `auto` test group.

```toml
[xfstests]
repository = "git@github.com:alberand/xfstests.git"
rev = "eb01a1c8b1007bcad534730d38a8dda4c005c15e"
args = "-g auto"

[xfsprogs]
repository = "git@github.com:alberand/xfsprogs.git"
rev = "dc00e8f7de86fe862df3a9f3fda11b710d10434b"
```

What's great is that all the compiled utilities are stored on the host, in the
`/nix/store`. So, if you update xfsprogs's commit, only xfsprogs is getting
recompiled.

## Custom Kernel

Let's say you are working on a kernel feature of fix and need to test it. The
following config pins kernel to specific commits and enables some necessary
configuration options.

```toml
[kernel]
repo = "git@github.com:alberand/linux.git"
rev = "7d0a66e4bb9081d75c82ec4957c50034cb0ea449"
version = "v6.18"

[kernel.config]
CONFIG_FS_VERITY = "yes"
CONFIG_FS_VERITY_BUILTIN_SIGNATURES = "yes"
```

## Prebuild kernel

Ok, that's good, but what if you already compiled kernel to check that your
changes are correct. You can use `prebuild` option. Instead of compiling kernel
again, `kd` will take your kernel at `arch/x86/boot/bzImage`.

```toml
[kernel]
prebuild = true
```

Note that none of the options in `[kernel]` or `[kernel.config]` do anything
when used with `preubild`.

Note that we just using an artifact (compiled kernel) and generated system will
not fully correspond to it (no kernel modules in initrd, no kernel headers, all
app built against headers will be built against default kernel, no Nix adhocs
for specific kernel versions etc.).

## Adding tools

Booted system is NixOS, this is small system defined in system.nix. As of 2025 I
haven't done any network configuration, so, no way to install tools directly
from the system buy you can add them in config.

```toml
packages = ["gdb"]

[kernel]
# Use already build kernel from the current directory
prebuild = true
```

List of the packages can be found at https://search.nixos.org/packages

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

## Matrix testing

Sometimes you need to test your change/fix/feature in many different kernel
configurations. Such as,
- new kernel but xfstests/xfsprogs compiled against old kernel headers,
- old kernel but xfstests compiled against new kernel headers,
- new kernel and xfsprogs compiled against new kernel headers but xfstests
  compiled against old kernel headers,
- etc.

This matrix testing let's you setup many different configuration which you would
like to try and then run them (manually so far, but I'm playing with kexec) with
`kd run --matrix name`. Here is config for 8 different configs with common
section for all of them.

```
[matrix.common.kernel]
rev = "038d61fd642278bab63ee8ef722c50d10ab01e8f"
version = "v6.16"

[matrix.common.kernel.config]
CONFIG_QUOTA = "yes"
CONFIG_XFS_QUOTA = "yes"

[matrix.common.xfstests]
args = "-s xfs_4k_quota xfs/508"
rev = "4936d48ac0d3632d07f6dec310be145d973212a6"
repo = "file:///home/alberand/Projects/xfstests-dev"

[matrix.common.xfsprogs]
repo = "file:///home/alberand/Projects/xfsprogs-dev"

[matrix.run.alpha.xfsprogs]
# Good - yes; Good - yes
# both fixes
rev = "7692fde9e4697f7c623619652c699c4575b01932"

[matrix.run.beta]
[matrix.run.beta.xfsprogs]
# Good - yes; Good - yes
# both fixes
rev = "7692fde9e4697f7c623619652c699c4575b01932"
[matrix.run.beta.xfsprogs.kernel_headers]
rev = "038d61fd642278bab63ee8ef722c50d10ab01e8f"
version = "v6.16"
repo = "git@github.com:torvalds/linux.git"

[matrix.run.gamma]
[matrix.run.gamma.xfsprogs]
# Good - yes
# only argument fix
rev = "c7e7b140829ff3c6b6a42322c84564fbfb14c1e4"

[matrix.run.delta]
[matrix.run.delta.xfsprogs]
# Good - yes
# only argument fix
rev = "c7e7b140829ff3c6b6a42322c84564fbfb14c1e4"
[matrix.run.delta.xfsprogs.kernel_headers]
rev = "038d61fd642278bab63ee8ef722c50d10ab01e8f"
version = "v6.16"
repo = "git@github.com:torvalds/linux.git"

[matrix.run.epsilon]
[matrix.run.epsilon.xfsprogs]
# Fail - yes
# only struct fix
rev = "680d46221cc526a21f61704233b8a3fcdda1d35a"

[matrix.run.zeta.xfsprogs]
# Fail - yes
# only struct fix
rev = "680d46221cc526a21f61704233b8a3fcdda1d35a"
[matrix.run.zeta.xfsprogs.kernel_headers]
rev = "038d61fd642278bab63ee8ef722c50d10ab01e8f"
version = "v6.16"
repo = "git@github.com:torvalds/linux.git"

[matrix.run.eta]
[matrix.run.eta.xfsprogs]
# Fail - yes
# clean v6.17
rev = "14d9a689d8b086a7b2c4b027c55861e5f2a82745"

[matrix.run.theta]
[matrix.run.theta.xfsprogs]
# Good - yes
# clean v6.17
rev = "14d9a689d8b086a7b2c4b027c55861e5f2a82745"
[matrix.run.theta.xfsprogs.kernel_headers]
rev = "038d61fd642278bab63ee8ef722c50d10ab01e8f"
version = "v6.16"
repo = "git@github.com:torvalds/linux.git"
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
- [ ] Minimize image as in https://nixcademy.com/posts/minimizing-nixos-images/
