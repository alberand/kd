{lib}:
with lib.kernel; {
  default = {
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

    # Loockups & hangs detections
    DEBUG_KERNEL = yes;
    LOCKUP_DETECTOR = yes;
    SOFTLOCKUP_DETECTOR = yes;
    HARDLOCKUP_DETECTOR = yes;
    DETECT_HUNG_TASK = yes;
    WQ_WATCHDOG = yes;

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
    XFS_FS = yes;
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
    HIBERNATION = no;

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

    # THP
    TRANSPARENT_HUGEPAGE = yes;
    TRANSPARENT_HUGEPAGE_ALWAYS = yes;
    THP_SWAP = yes;

    NFS_FS = no;
    ACPI = yes;
    I2C = no;
    INPUT_MOUSE = no;
    INPUT_JOYSTICK = no;
    INPUT_TABLET = no;
    INPUT_TOUCHSCREEN = no;
  };

  debug = {
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
    SLUB_DEBUG = yes;
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

  iso = {
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

  xfstests = {
    DM_FLAKEY = yes;
    DM_SNAPSHOT = yes;
    DM_DELAY = yes;
    DM_THIN_PROVISIONING = yes;
    DM_LOG_WRITES = yes;
    USER_NS = yes;
    DAX = yes;
    IO_URING = yes;
    DEBUG_FS = yes;
    
    SCSI_DEBUG = module;
  };

  xfsprogs = {
    DM_FLAKEY = yes;
    DM_SNAPSHOT = yes;
    DM_DELAY = yes;
    DM_THIN_PROVISIONING = yes;
    DM_LOG_WRITES = yes;
    USER_NS = yes;
    DAX = yes;
    IO_URING = yes;
    
    SCSI_DEBUG = module;
  };

  xfs = {
    XFS_FS = yes;
    XFS_SUPPORT_V4 = yes;
    XFS_SUPPORT_ASCII_CI = yes;
    XFS_QUOTA = yes;
    XFS_POSIX_ACL = yes;
    XFS_RT = yes;
    XFS_DRAIN_INTENTS = yes;
    XFS_LIVE_HOOKS = yes;
    XFS_MEMORY_BUFS = yes;
    XFS_BTREE_IN_MEM = yes;
    XFS_ONLINE_SCRUB = yes;
    XFS_ONLINE_SCRUB_STATS = yes;
    XFS_ONLINE_REPAIR = yes;
    XFS_DEBUG = yes;
    XFS_DEBUG_EXPENSIVE = yes;
    XFS_ASSERT_FATAL = no;
  };
}
