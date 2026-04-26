
# MT7902 Linux Fix:

An optimized, minimalist driver fix for the **MediaTek MT7902** wireless card. Specifically built for **CachyOS** and **Arch Linux** on **Kernel 7.0+**.

## Features
- **Bluetooth Repair**: Patches memory conflicts and redefinition errors for 7.x kernels.
- **Wi-Fi Optimization**: Compiles the mt7921e driver using the Clang/LLVM toolchain with ThinLTO.
- **Zero-Latency Gaming**: Disables ASPM (Power Management) to eliminate ping spikes.
- **Live Logs**: Displays real-time compilation data (CC/LD/BTF) during install.
- **Auto-Sync**: Automatically resets hardware modules after installation.

## Tested Hardware
- **Acer Extensa 215-55**
- Devices using the **MediaTek MT7902** card.

## Installation
```bash
git clone https://github.com/kerim133777/mt7902-cachy.git
cd mt7902-cachy
chmod +x install.sh
sudo ./install.sh
```

## Uninstallation
If you need to revert to system defaults:

1. **Remove Configuration Files**:
```bash
sudo rm /etc/modprobe.d/mt7902.conf
sudo rm /etc/modules-load.d/mt7902.conf
```

2. **Restore Official Drivers**:
```bash
sudo pacman -S linux-cachyos-headers
```

## License
Licensed under the **MT License**.
