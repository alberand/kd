{
  stdenv,
  lib,
  perl,
  gmp,
  libmpc,
  mpfr,
  bison,
  flex,
  pahole,
  buildPackages,
  nixpkgs,
}: {
  src,
  version,
  kconfig ? {},
  debug ? false,
  iso ? false,
}: let
  defaultConfig = with lib.kernel; {
    # Kernel BUG()s on detected corruption of in memory data
    BUG_ON_DATA_CORRUPTION = yes;
    # When call to schedule() check stack and in case of overflow panic()
    SCHED_STACK_END_CHECK = yes;
    # The thing which shows stack trace (degrade performance by 10%)
    UNWINDER_FRAME_POINTER = yes;

    # Support kernel compressed with X
    # KERNEL_GLIB = yes;
    # Don't attach -dirty version (We won't be able to boot other kernel)
    LOCALVERSION_AUTO = no;

    # Save kernel config in the kernel (also enable /proc/config.gz)
    IKCONFIG = yes;
    IKCONFIG_PROC = yes;

    # Same as IKCONFIG but for headers in /sys/kernel/kheaders.tar.xz)
    IKHEADERS = yes;

    # 64bit kernel
    "64BIT" = yes;

    # initramfs/initrd support
    BLK_DEV_INITRD = yes;

    # Support of printk
    PRINTK = yes;
    PRINTK_TIME = no;
    # Write printk to VGA/serial port
    EARLY_PRINTK = yes;

    # Support elf and #! scripts
    BINFMT_ELF = yes;
    BINFMT_SCRIPT = yes;

    # Create a tmpfs/ramfs early at bootup.
    DEVTMPFS = yes;
    DEVTMPFS_MOUNT = yes;

    # Console
    TTY = yes;
    SERIAL_8250 = yes;
    SERIAL_8250_CONSOLE = yes;
    SERIAL_DEV_BUS = yes; # enables support for serial devices
    SERIAL_DEV_CTRL_TTYPORT = yes; # enables support for TTY serial devices

    # Required by profiles/qemu
    NET_9P_VIRTIO = yes;
    "9P_FS" = yes;
    BLK_DEV = yes;
    NETWORK_FILESYSTEMS = yes;

    # /proc
    PROC_FS = yes;
    # /sys
    SYSFS = yes;
    # /proc/sys
    SYSCTL = yes;

    # Can kernel load modules?
    MODULES = yes;
    MODULE_FORCE_LOAD = yes;
    MODULE_UNLOAD = yes;

    # No graphics
    DRM = no;

    # No sound
    SOUND = no;

    # QEMU stuff
    VIRTIO = yes;
    VIRTIO_BLK = yes;
    VIRTIO_MENU = yes;
    VIRTIO_PCI = yes;
    VIRTIO_NET = yes;
    VIRTIO_MMIO = yes;
    VIRTIO_BALLOON = yes;
    VIRTIO_CONSOLE = yes;
    SCSI_VIRTIO = yes;
    HW_RANDOM_VIRTIO = yes;

    # Hard disks protocol
    SCSI = yes;
    BLK_DEV_SD = yes;
    ATA = yes;

    # Filesystems
    EXT4_FS = yes;
    TMPFS = yes;
    OVERLAY_FS = yes;

    # Basic functionality
    HW_RANDOM = yes;
    PCI = yes;
    NET = yes;
    NETDEVICES = yes;
    NET_CORE = yes;
    INET = yes;
    CGROUPS = yes;
    SIGNALFD = yes;
    TIMERFD = yes;
    EPOLL = yes;
    FHANDLE = yes;
    CRYPTO_USER_API_HASH = yes;
    DMIID = yes;
    TMPFS_POSIX_ACL = yes;
    TMPFS_XATTR = yes;
    SECCOMP = yes;
    SHMEM = yes;
    RTC_CLASS = yes;
    UNIX = yes;
    INOTIFY_USER = yes;

    # Systemd required modules
    # boot.initrd.includeDefaultModules = false;
    KEYBOARD_ATKBD = yes;
    SERIO_I8042 = yes;
    MD = yes;
    BLK_DEV_DM = yes;

    # Enable kernel tracers
    FTRACE = yes;
    # Creates /proc/pid/stack which shows current stack for each process
    STACKTRACE = yes;
  };

  debugConfig = with lib.kernel; {
    # Debug
    DEBUG_FS = yes;
    DEBUG_KERNEL = yes;
    DEBUG_MISC = yes;
    DEBUG_BOOT_PARAMS = yes;
    DEBUG_STACK_USAGE = yes;
    DEBUG_SHIRQ = yes;
    DEBUG_ATOMIC_SLEEP = yes;
    DEBUG_KMEMLEAK = yes;
    DEBUG_INFO_DWARF5 = yes;
    DEBUG_INFO_COMPRESSED_NONE = yes;
    DEBUG_VM = yes;
    FUNCTION_TRACER = yes;
    FUNCTION_GRAPH_TRACER = yes;
    FUNCTION_GRAPH_RETVAL = yes;
    FPROBE = yes;
    FUNCTION_PROFILER = yes;
    FTRACE_SYSCALLS = yes;
    KEXEC = yes;
    SLUB_DEBUG = no;
    DEBUG_MEMORY_INIT = yes;
    KASAN = no;
    # Sending special commands with SysRq key (ALT+PrintScreen)
    MAGIC_SYSRQ = yes;
    # Lock usage statistics
    LOCK_STAT = yes;
    # Mathematically calculate and then report deadlocks before they occures
    PROVE_LOCKING = yes;
    # Max time spent in interrupt critical section
    IRQSOFF_TRACER = no;
    # Kernel debugger
    KGDB = no;
    # Detector of undefined behavior, in runtime
    UBSAN = no;
  };

  isoConfig = with lib.kernel; {
    # ISO
    SQUASHFS = yes;
    SQUASHFS_XZ = yes;
    SQUASHFS_ZSTD = yes;
    ISO9660_FS = yes;
    USB_UAS = module;
    BLK_DEV_LOOP = yes;
    CRYPTO_ZSTD = yes;
    SATA_AHCI = yes;
    SATA_NV = yes;
    SATA_VIA = yes;
    SATA_SIS = yes;
    SATA_ULI = yes;
    ATA_PIIX = yes;
    PATA_MARVELL = yes;
    MMC = yes;
    MMC_BLOCK = yes;
    HID_GENERIC = yes;
    HID_LENOVO = yes;
    HID_APPLE = yes;
    HID_ROCCAT = yes;
    LEDS_CLASS = yes;
    LEDS_CLASS_MULTICOLOR = yes;
    HID_LOGITECH_HIDPP = yes;
    HID_LOGITECH_DJ = yes;
    HID_MICROSOFT = yes;
    HID_CHERRY = yes;
    HID_CORSAIR = yes;
    # NVME
    NVME_CORE = yes;
    BLK_DEV_NVME = yes;
    # USB
    USB = yes;
    USB_PCI = yes;
    USB_SUPPORT = yes;
    USB_UHCI_HCD = yes;
    USB_OHCI_HCD = yes;
    USB_XHCI_PCI = yes;
    USB_XHCI_HCD = yes;

    # other
    NET_9P = yes;
    VT = yes;
    UNIX98_PTYS = yes;
    SCSI_LOWLEVEL = yes;
    WATCHDOG = yes;
    WATCHDOG_CORE = yes;
    I6300ESB_WDT = yes;
    DAX = yes;
    FS_DAX = yes;
    MEMORY_HOTPLUG = yes;
    MEMORY_HOTREMOVE = yes;
    ZONE_DEVICE = yes;
    SERIO_PCIPS2 = yes;
  };
in
  stdenv.mkDerivation rec {
    inherit version src;
    pname = "linux-config";

    ignoreConfigErrors = false;
    generateConfig = (nixpkgs + "/pkgs/os-specific/linux/kernel/generate-config.pl");

    kernelConfig = passthru.moduleStructuredConfig.intermediateNixConfig;
    passAsFile = ["kernelConfig"];

    depsBuildBuild = [stdenv.cc];
    nativeBuildInputs = [perl gmp libmpc mpfr bison flex pahole];

    makeFlags =
      lib.optionals (stdenv.hostPlatform.linux-kernel ? makeFlags)
      stdenv.hostPlatform.linux-kernel.makeFlags;

    postPatch = ''
      # Ensure that depmod gets resolved through PATH
      sed -i Makefile -e 's|= /sbin/depmod|= depmod|'

      # Don't include a (random) NT_GNU_BUILD_ID, to make the build more deterministic.
      # This way kernels can be bit-by-bit reproducible depending on settings
      # (e.g. MODULE_SIG and SECURITY_LOCKDOWN_LSM need to be disabled).
      # See also https://kernelnewbies.org/BuildId
      sed -i Makefile -e 's|--build-id=[^ ]*|--build-id=none|'

      # Some linux-hardened patches now remove certain files in the scripts directory, so the file may not exist.
      [[ -f scripts/ld-version.sh ]] && patchShebangs scripts/ld-version.sh

      # Set randstruct seed to a deterministic but diversified value. Note:
      # we could have instead patched gen-random-seed.sh to take input from
      # the buildFlags, but that would require also patching the kernel's
      # toplevel Makefile to add a variable export. This would be likely to
      # cause future patch conflicts.
      for file in scripts/gen-randstruct-seed.sh; do
        if [ -f "$file" ]; then
          substituteInPlace "$file" \
            --replace NIXOS_RANDSTRUCT_SEED \
            $(echo ${src} ${placeholder "configfile"} | sha256sum | cut -d ' ' -f 1 | tr -d '\n')
          break
        fi
      done

      patchShebangs scripts

      # also patch arch-specific install scripts
      for i in $(find arch -name install.sh); do
          patchShebangs "$i"
      done

      # Patch kconfig to print "###" after every question so that
      # generate-config.pl from the generic builder can answer them.
      sed -e '/fflush(stdout);/i\printf("###");' -i scripts/kconfig/conf.c
    '';

    buildPhase = ''
      export buildRoot="''${buildRoot:-build}"
      export HOSTCC=$CC_FOR_BUILD
      export HOSTCXX=$CXX_FOR_BUILD
      export HOSTAR=$AR_FOR_BUILD
      export HOSTLD=$LD_FOR_BUILD

      # Get a basic config file for later refinement with $generateConfig.
      echo "Generating 'olddefconfig' config"
      make $makeFlags \
          -C . \
          O="$buildRoot" \
          ARCH=x86_64 \
          HOSTCC=$HOSTCC \
          HOSTCXX=$HOSTCXX \
          HOSTAR=$HOSTAR \
          HOSTLD=$HOSTLD \
          CC=$CC \
          OBJCOPY=$OBJCOPY \
          OBJDUMP=$OBJDUMP \
          READELF=$READELF \
          $makeFlags \
          olddefconfig

      # Create the config file.
      echo "Generating kernel configuration"
      ln -s "$kernelConfigPath" "$buildRoot/kernel-config"
      DEBUG=1 \
        ARCH=x86_64 \
        KERNEL_CONFIG="$buildRoot/kernel-config" \
        PREFER_BUILTIN=false \
        BUILD_ROOT="$buildRoot" \
        SRC=. \
        MAKE_FLAGS="$makeFlags" \
        perl -w $generateConfig
    '';

    installPhase = "mv $buildRoot/.config $out";

    enableParallelBuilding = true;

    passthru = rec {
      # The result is a set of two attributes
      moduleStructuredConfig =
        (lib.evalModules {
          modules = [
            (nixpkgs + "/nixos/modules/system/boot/kernel_config.nix")
            {
              settings =
                kconfig
                // defaultConfig
                // (lib.optionalAttrs debug debugConfig)
                // (lib.optionalAttrs iso isoConfig);
              _file = "structuredExtraConfig";
            }
          ];
        })
        .config;

      structuredConfig = moduleStructuredConfig.settings;
    };
  }
