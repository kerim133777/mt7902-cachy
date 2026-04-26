#!/bin/bash

# MT7902 Optimized Installer (Standalone Edition - Acer Extensa / CachyOS Fix)
set -e

# Colors for terminal output
G='\033[38;5;82m'
C='\033[38;5;51m'
NC='\033[0m'

KVER=$(uname -r)
CORES=$(nproc)
FW_DIR="/lib/firmware/mediatek"
SOURCE_REPO="https://github.com/OnlineLearningTutorials/mt7902_temp.git"

log() { echo -e "${C}[LOG]${NC} $(date +%H:%M:%S) | $1"; }
success() { echo -e "${G}[OK]${NC} $1"; }

[[ $EUID -ne 0 ]] && echo "Please run with sudo" && exit 1

# --- 1. Dependency & Source Sync ---
log "Checking for source files..."
if [[ ! -d "wifi-source" ]]; then
    log "wifi-source not found. Cloning and staging for Kernel 7.0..."
    
    rm -rf /tmp/mt7902_sync
    git clone --depth 1 "$SOURCE_REPO" /tmp/mt7902_sync > /dev/null
    
    if [[ -d "/tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76" ]]; then
        mkdir -p wifi-source
        cp -r /tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76/* ./wifi-source/
        [[ -d "/tmp/mt7902_sync/wlan_mt7902" ]] && cp -r /tmp/mt7902_sync/wlan_mt7902 ./wifi-source/mt7902
    fi
    success "Wi-Fi source synchronized."
fi

# Ensure firmware is present
if [[ ! -f "$FW_DIR/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]]; then
    log "Deploying firmware..."
    mkdir -p "$FW_DIR"
    find /tmp/mt7902_sync -name "*.bin" -exec cp {} "$FW_DIR/" \; 2>/dev/null || true
fi
rm -rf /tmp/mt7902_sync

# --- 2. System Prep ---
log "Updating toolchain..."
pacman -Sy --needed --noconfirm linux-cachyos-headers base-devel clang lld llvm zstd bc > /dev/null

# --- 3. Bluetooth Patching ---
BT_SRC=$(find /usr/src -maxdepth 1 -type d -name "mt7902-bluetooth-*" | head -n 1)
if [[ -d "$BT_SRC" ]]; then
    log "Patching Bluetooth for Kernel $KVER..."
    cd "$BT_SRC"
    sed -i '/#define false/d; /#define true/d' *.c 2>/dev/null || true
    sed -i 's/kmalloc_obj/kmalloc/g; s/kzalloc_obj/kzalloc/g' *.c 2>/dev/null || true
    VER=$(basename "$BT_SRC" | sed 's/mt7902-bluetooth-//')
    dkms remove mt7902-bluetooth/"$VER" --all 2>/dev/null || true
    dkms add mt7902-bluetooth/"$VER" && dkms install mt7902-bluetooth/"$VER"
    cd - > /dev/null
fi

# --- 4. Wi-Fi Compilation ---
log "Building Wi-Fi driver with Clang/LLVM..."
cd wifi-source
make clean LLVM=1 > /dev/null 2>&1 || true
make -C /lib/modules/"$KVER"/build M="$PWD" LLVM=1 CC=clang HOSTCC=clang EXTRA_CFLAGS="-O3 -march=native -flto=thin" modules -j"$CORES"

log "Deploying modules..."
DEST="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76"
mkdir -p "$DEST/mt7921"
cp mt76.ko mt76-connac-lib.ko mt792x-lib.ko "$DEST/" 2>/dev/null || true
[[ -d "mt7921" ]] && cp mt7921/mt7921e.ko mt7921/mt7921-common.ko "$DEST/mt7921/" 2>/dev/null || true
zstd --rm -19 -f "$DEST"/*.ko "$DEST/mt7921"/*.ko 2>/dev/null || true
cd ..

# --- 5. THE "HART" RESTART (Integrated Fix) ---
log "Performing hard hardware reset..."

# Disable power management tweaks
echo "options mt7921e disable_aspm=1" > /etc/modprobe.d/mt7902.conf

# 1. Stop Bluetooth first (essential to unlock driver)
systemctl stop bluetooth || true

# 2. Unload modules in reverse order of dependency
log "Unloading old driver stack..."
modprobe -r mt7921e 2>/dev/null || true
modprobe -r btusb 2>/dev/null || true
modprobe -r btmtk 2>/dev/null || true
modprobe -r mt7921_common 2>/dev/null || true
modprobe -r mt76_connac_lib 2>/dev/null || true
modprobe -r mt76 2>/dev/null || true

# 3. Reload everything fresh
log "Reloading new driver stack..."
depmod -a "$KVER"
modprobe mt76
modprobe btmtk
modprobe btusb
modprobe mt7921e 2>/dev/null || modprobe mt7902 2>/dev/null || true

# 4. Restart Services
systemctl restart bluetooth
systemctl restart NetworkManager

success "Install complete! Your MT7902 hardware has been hard-restarted and optimized."
