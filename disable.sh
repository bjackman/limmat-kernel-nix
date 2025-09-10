#!/bin/bash

# This is the result of telling an AI to slave away disabling configs from
# defconfig_kvm_guest.config+OVERLAY_FS and repeatedly trying to boot a NixOS
# VM. It was able to disable all of these. TODO: Find some neat way to encode
# this in the Limmat config. Also try to minimize further. Or, ideally start
# from tinyconfig and just build up what is needed.

scripts/config -d CONFIG_ACPI_NHLT
scripts/config -d CONFIG_CARDBUS
scripts/config -d CONFIG_HID
scripts/config -d CONFIG_I2C_HID
scripts/config -d CONFIG_INPUT_JOYSTICK
scripts/config -d CONFIG_INPUT_TABLET
scripts/config -d CONFIG_INPUT_TOUCHSCREEN
scripts/config -d CONFIG_NET_VENDOR_FUJITSU
scripts/config -d CONFIG_NET_VENDOR_XIRCOM
scripts/config -d CONFIG_PANTHERLORD_FF
scripts/config -d CONFIG_PCCARD
scripts/config -d CONFIG_PCCARD_NONSTATIC
scripts/config -d CONFIG_PCMCIA
scripts/config -d CONFIG_PCMCIA_LOAD_CIS
scripts/config -d CONFIG_REGMAP
scripts/config -d CONFIG_RTL_CARDS
scripts/config -d CONFIG_SND
scripts/config -d CONFIG_SOUND
scripts/config -d CONFIG_USB_HID
scripts/config -d CONFIG_USB_HIDDEV
scripts/config -d CONFIG_WLAN
scripts/config -d CONFIG_YENTA
scripts/config -d AGP
scripts/config -d DRM
scripts/config -d VGA_CONSOLE
scripts/config -d WIRELESS
scripts/config -d NFS_FS
scripts/config -d AUTOFS_FS
scripts/config -d ISO9660_FS
scripts/config -d JOLIET
scripts/config -d ZISOFS
scripts/config -d FAT_FS
scripts/config -d VFAT_FS
scripts/config -d MSDOS_FS
scripts/config -d EFI_PARTITION
scripts/config -d SCSI_MOD
scripts/config -d ATA
scripts/config -d MD
scripts/config -d BLK_DEV_DM
scripts/config -d DM_ZERO
scripts/config -d DM_MIRROR
scripts/config -d HAMRADIO
scripts/config -d I2C
scripts/config -d PNP
scripts/config -d HIBERNATION
scripts/config -d SUSPEND
scripts/config -d PM
scripts/config -d X86_MCE
scripts/config -d PERF_EVENTS
scripts/config -d PROFILING
scripts/config -d KPROBES
scripts/config -d UPROBES
scripts/config -d FTRACE
scripts/config -d MAGIC_SYSRQ
scripts/config -d DEBUG_FS
scripts/config -d TRACING
scripts/config -d SECURITY
scripts/config -d CRYPTO
scripts/config -d KEYS
scripts/config -d DEBUG_INFO
scripts/config -d DEBUG_KERNEL
scripts/config -d SLUB_DEBUG
scripts/config -d SCHED_DEBUG
scripts/config -d TIMER_STATS
scripts/config -d STACK_VALIDATION
scripts/config -d SCHED_SMT
scripts/config -d IRQ_WORK
scripts/config -d CPU_FREQ
scripts/config -d CPU_IDLE
scripts/config -d X86_PM_TIMER
scripts/config -d HPET_TIMER
scripts/config -d DMI
scripts/config -d CPU_SUP_INTEL
scripts/config -d IOSF_MBI
scripts/config -d X86_IO_APIC
scripts/config -d X86_LOCAL_APIC
scripts/config -d X86_X2APIC
scripts/config -d X86_MPPARSE
scripts/config -d GDB_SCRIPTS
scripts/config -d BINFMT_MISC
scripts/config -d SGETMASK_SYSCALL
scripts/config -d FHANDLE
scripts/config -d POSIX_TIMERS
scripts/config -d PCSPKR_PLATFORM
scripts/config -d FUTEX_PI
scripts/config -d EPOLL
scripts/config -d SIGNALFD
scripts/config -d TIMERFD
scripts/config -d EVENTFD
scripts/config -d SHMEM
scripts/config -d AIO
scripts/config -d IO_URING
scripts/config -d ADVISE_SYSCALLS
scripts/config -d USER_NS
scripts/config -d PID_NS
scripts/config -d IPC_NS
scripts/config -d UTS_NS
scripts/config -d NET_NS
scripts/config -d NAMESPACES
scripts/config -d CHECKPOINT_RESTORE
scripts/config -d SECCOMP
scripts/config -d BLK_DEV_BSG
scripts/config -d PARTITION_ADVANCED
scripts/config -d SLAB_FREELIST_RANDOM
scripts/config -d SLAB_FREELIST_HARDENED
scripts/config -d SLUB
scripts/config -d PROFILING
scripts/config -d KPROBES
scripts/config -d UPROBES
scripts/config -d FTRACE
scripts/config -d FUNCTION_TRACER
scripts/config -d STACKTRACE
scripts/config -d BLK_DEV_LOOP
scripts/config -d BLK_DEV_RAM
scripts/config -d PM_DEBUG
scripts/config -d ACPI_DEBUG
scripts/config -d KEXEC
scripts/config -d CRASH_DUMP
scripts/config -d HOTPLUG_CPU
scripts/config -d COMPAT_VDSO
scripts/config -d X86_X32
scripts/config -d COMPAT
scripts/config -d SYSVIPC
scripts/config -d POSIX_MQUEUE
scripts/config -d CROSS_MEMORY_ATTACH
scripts/config -d AUDIT
scripts/config -d FAILOVER
scripts/config -d ETHTOOL_NETLINK
scripts/config -d NET_SELFTESTS
scripts/config -d NETFILTER
scripts/config -d NETLABEL -d NETWORK_SECMARK
scripts/config -d NET_SCHED
scripts/config -d INET6 -d IP_MULTICAST -d IP_PIMSM_V1 -d IP_PIMSM_V2 -d TCP_CONG_CUBIC -d RFKILL -d NETCONSOLE
scripts/config -d BTRFS_FS -d F2FS_FS -d XFS_FS -d GFS2_FS -d JFS_FS -d NILFS2_FS -d BCACHEFS_FS -d SQUASHFS -d EROFS_FS -d MINIX_FS -d MSDOS_FS -d VFAT_FS -d EXFAT_FS -d NTFS3_FS -d HFS_FS -d HFSPLUS_FS -d UFS_FS
scripts/config -d DEBUG_BUGVERBOSE -d DEBUG_WX -d DEBUG_MEMORY_INIT -d SLUB_DEBUG -d PTDUMP -d X86_VERBOSE_BOOTUP -d EARLY_PRINTK -d DYNAMIC_DEBUG
scripts/config -d CRYPTO_RSA -d CRYPTO_AES -d CRYPTO_CBC -d CRYPTO_CTR -d CRYPTO_ECB -d CRYPTO_CCM -d CRYPTO_GCM -d CRYPTO_CMAC -d CRYPTO_HMAC -d CRYPTO_SHA256 -d CRYPTO_SHA512 -d CRYPTO_SHA3 -d CRYPTO_LZO -d CRYPTO_DRBG -d CRYPTO_JITTERENTROPY
scripts/config -d VIRTUALIZATION -d KVM_GUEST
scripts/config -d USB_NET_DRIVERS -d USB_XHCI_HCD -d USB_EHCI_HCD -d USB_OHCI_HCD -d USB_UHCI_HCD -d USB_PRINTER -d USB_STORAGE
scripts/config -d SCSI_MOD -d BLK_DEV_SD -d BLK_DEV_SR -d CHR_DEV_SG -d SCSI_LOWLEVEL
scripts/config -d ACPI_BATTERY -d ACPI_VIDEO -d ACPI_DOCK -d ACPI_FAN -d ACPI_BUTTON -d ACPI_EC -d ACPI_AC
scripts/config -d INPUT_JOYSTICK -d INPUT_TABLET -d INPUT_TOUCHSCREEN -d INPUT_MOUSE
scripts/config -d WATCHDOG -d CLOCKSOURCE_WATCHDOG
scripts/config -d HWMON -d TIGON3_HWMON -d POWER_SUPPLY_HWMON
scripts/config -d HOTPLUG_PCI -d PCI_STUB
scripts/config -d IOMMU_SUPPORT -d AMD_IOMMU -d INTEL_IOMMU
scripts/config -d FW_LOADER -d EFI
scripts/config -d SECURITY -d DEFAULT_SECURITY_DAC
scripts/config -d CRYPTO_LIB_UTILS -d CRYPTO_LIB_AES -d CRYPTO_LIB_GF128MUL -d CRYPTO_LIB_BLAKE2S_GENERIC -d CRYPTO_LIB_POLY1305_RSIZE -d CRYPTO_LIB_SHA1 -d CRYPTO_LIB_SHA256 -d CRYPTO_LIB_SHA512 -d ZLIB_INFLATE
scripts/config -d BLK_DEV_FD
scripts/config -d NETDEVICES
scripts/config -d PM -d CPU_FREQ_DEFAULT_GOV_POWERSAVE
scripts/config -d MEMORY_HOTPLUG -d X86_BOOTPARAM_MEMORY_CORRUPTION_CHECK
scripts/config -d CGROUP_MISC -d INPUT_MISC -d MISC_FILESYSTEMS
scripts/config -d X86_VMX_FEATURE_NAMES -d X86_DISABLED_FEATURE_VME -d X86_DISABLED_FEATURE_K6_MTRR -d X86_DISABLED_FEATURE_CYRIX_ARR -d X86_DISABLED_FEATURE_CENTAUR_MCR -d X86_DISABLED_FEATURE_LAM -d X86_DISABLED_FEATURE_ENQCMD -d X86_DISABLED_FEATURE_SGX -d X86_DISABLED_FEATURE_XENPV -d X86_DISABLED_FEATURE_TDX_GUEST -d X86_DISABLED_FEATURE_USER_SHSTK -d X86_DISABLED_FEATURE_FRED -d X86_DISABLED_FEATURE_SEV_SNP
scripts/config -d NUMA
scripts/config -d SCHEDSTATS -d MQ_IOSCHED_DEADLINE -d MQ_IOSCHED_KYBER
scripts/config -d FTRACE -d STACKTRACE_SUPPORT
scripts/config -d PERF_EVENTS -d PERF_EVENTS_INTEL_UNCORE -d PERF_EVENTS_INTEL_RAPL -d PERF_EVENTS_INTEL_CSTATE -d PERF_EVENTS_AMD_UNCORE
scripts/config -d CGROUP_SCHED
scripts/config -d BLK_DEV_WRITE_MOUNTED -d BLK_DEV_INTEGRITY
scripts/config -d SWAP
scripts/config -d CPU_FREQ -d CPU_IDLE
scripts/config -d NEW_LEDS -d LEDS_TRIGGERS
scripts/config -d THERMAL -d X86_THERMAL_VECTOR -d X86_PKG_TEMP_THERMAL
scripts/config -d DMADEVICES -d ISA_DMA_API
scripts/config -d HUGETLBFS
scripts/config -d X86_INTEL_MEMORY_PROTECTION_KEYS
scripts/config -d BUG -d DEBUG_BUGVERBOSE
scripts/config -d FUTEX
scripts/config -d ELF_CORE
scripts/config -d MODULE_UNLOAD -d MODULE_FORCE_UNLOAD
scripts/config -d BPF
scripts/config -d WATCHDOG
scripts/config -d CLOCKSOURCE_WATCHDOG
scripts/config -d PRINTK -d EARLY_PRINTK
scripts/config -d HIGH_RES_TIMERS -d POSIX_TIMERS
scripts/config -d PRINTK
scripts/config -d TIMERFD
scripts/config -d EVENTFD
scripts/config -d EPOLL
scripts/config -d SIGNALFD
scripts/config -d AIO
scripts/config -d MEMBARRIER
scripts/config -d NAMESPACES
scripts/config -d TIME_NS
scripts/config -d IRQ_WORK -d GENERIC_IRQ_PROBE
scripts/config -d FIRMWARE_MEMMAP -d FIRMWARE_TABLE
scripts/config -d DEFAULT_SECURITY_DAC
scripts/config -d SYSCTL
scripts/config -d PROC_FS
scripts/config -d SYSFS
scripts/config -d CONFIG_NET_IP_TUNNEL
scripts/config -d CONFIG_NET_PTP_CLASSIFY
scripts/config -d CONFIG_NET_RX_BUSY_POLL
scripts/config -d CONFIG_NET_FLOW_LIMIT
