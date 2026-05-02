
# MT7902 Linux Fix (Kernel 7.0+)

An optimized, "set-and-forget" driver fix for the **MediaTek MT7902** wireless combo card. This repository automates the DKMS build process and system configuration to ensure both **WiFi** and **Bluetooth** work seamlessly on **CachyOS**, **Arch Linux**, and other modern distributions.

## Key Features
*   **DKMS Managed**: Automatically rebuilds the driver after kernel updates.
*   **Bluetooth Persistence**: Configures the system to load Bluetooth modules and auto-power the controller on boot.
*   **Conflict Cleanup**: Automatically detects and removes old "ghost" modules (like `gen4-mt7902`) that cause build failures.
*   **Stability Tweak**: Disables ASPM (Active State Power Management) for the MT7921e to prevent connection drops.

## Tested Hardware
- **Acer Extensa 215-55** (i3-1215U)
- Devices utilizing the **MediaTek MT7902** integrated card.

## Installation

```bash
git clone https://github.com/kerim133777/mt7902-cachy.git
cd mt7902-cachy
chmod +x install.sh
sudo ./install.sh
```

**Note:** A reboot is required after installation to finalize the hardware state and clear out the old module stack.

## Uninstallation
If you need to revert to system defaults:

1. **Remove DKMS Modules**:
```bash
sudo dkms remove mt7902-wifi/1.0 --all 2>/dev/null || echo "WiFi module already removed."
sudo dkms remove $(dkms status | grep "mt7902-bluetooth" | awk -F'[,/]' '{print $1"/"$2}' | xargs) --all 2>/dev/null || echo "Bluetooth module already removed."
```

2. **Remove Configuration Files**:
```bash
sudo rm /etc/modprobe.d/mt7902.conf
sudo rm /etc/modules-load.d/mediatek-bt.conf
```

3. **Restore Official Drivers & Headers**:
```bash
sudo pacman -S linux-cachyos-headers linux-firmware
```

## Troubleshooting
If Bluetooth does not appear immediately after reboot, verify the controller status in the terminal:
```bash
bluetoothctl show
```
If it says `Powered: no`, run `bluetoothctl power on`.

## License
Licensed under the **MIT License**.
