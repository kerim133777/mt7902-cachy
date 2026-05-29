
# MT7902 Linux Fix (Kernel 7.0+)

An optimized, "set-and-forget" driver fix for the **MediaTek MT7902** wireless combo card. This repository automates the DKMS build process and system configuration to ensure both **WiFi** and **Bluetooth** work seamlessly on **CachyOS**, **Arch Linux**, and other modern distributions.

## Why this fix?

Modern Linux kernels (7.0+) often lack the specific driver hooks for the MT7902 card. This repo dynamically patches the source code to provide kernel-level support, manages the build via **DKMS** for persistence, and injects a `systemd` service to ensure the Bluetooth hardware is initialized correctly on every boot.

## Prerequisites

Before installing, ensure your system is prepared for module compilation:

```bash
sudo pacman -S base-devel dkms linux-cachyos-headers

```

## Installation

```bash
git clone https://github.com/kerim133777/mt7902-cachy.git
cd mt7902-cachy
sudo bash install.sh

```

> [!IMPORTANT]
> **A reboot is required** after installation to finalize the hardware state and clear out the old module stack.

## Uninstallation

If you need to revert to system defaults:

```bash
# 1. Remove DKMS Modules
sudo dkms remove mt7902-wifi/1.0 --all 2>/dev/null || true
sudo dkms remove $(dkms status | grep "mt7902-bluetooth" | awk -F'[,/]' '{print $1"/"$2}' | xargs) --all 2>/dev/null || true

# 2. Remove configuration files
sudo rm /etc/modprobe.d/mt7902-blacklist.conf
sudo rm /etc/modules-load.d/mt7902.conf

# 3. Restore Official Drivers & Headers
sudo pacman -S linux-cachyos-headers linux-firmware

```

## Key Features

* **DKMS Managed**: Automatically rebuilds the driver after kernel updates.
* **Bluetooth Persistence**: Configures the system to load Bluetooth modules and auto-power the controller on boot.
* **Conflict Cleanup**: Automatically detects and removes old "ghost" modules (like `gen4-mt7902`) that cause build failures.
* **Systemd Automation**: Includes a helper service (`mt7902-fix.service`) to ensure radio initialization works even after power-state changes.

## Tested Hardware

* **Acer Extensa 215-55** (i3-1215U)
* Devices utilizing the **MediaTek MT7902** integrated card.

## Troubleshooting

If Bluetooth does not appear immediately after reboot, verify the controller status:

```bash
bluetoothctl show

```

If it says `Powered: no`, run `bluetoothctl power on`.

## License

Licensed under the **MIT License**.
