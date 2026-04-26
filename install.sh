#!/bin/bash

# MT7902 Optimized Installer (Standalone Edition)
set -e

# Colors for terminal output
G='\033[38;5;82m'
C='\033[38;5;51m'
NC='\033[0m'

KVER=$(uname -r)
CORES=$(nproc)
FW_DIR="/lib/firmware/mediatek"
# The repo used as the base source for driver files
SOURCE_REPO="https://github.com/OnlineLearningTutorials/mt7902_temp.git"

log() { echo -e "${C}[LOG]${NC} $(date +%H:%M:%S) | $1"; }
success() { echo -e "${G}[OK]${NC} $1"; }

[[ $EUID -ne 0 ]] && echo "Please run with sudo" && exit 1

# --- 1. Dependency & Source Sync ---
log "Checking for source files..."
if [[ ! -d "wifi-source" ]]; then
    log "wifi-source not found. Cloning from repository..."
    
    rm -rf /tmp/mt7902_sync
    git clone --depth 1 "$SOURCE_REPO" /tmp/mt7902_sync > /dev/null
    
    # 1. Try to find a folder with 'wifi' in the name
    WIFI_PATH=$(find /tmp/mt7902_sync -maxdepth 2 -type d -name "*wifi*" | head -n 1)
    
    if [[ -n "$WIFI_PATH" ]]; then
        cp -r "$WIFI_PATH" ./wifi-source
    else
        # 2. If no folder found, the root of the repo is likely the source
        log "No subfolder found. Using repository root as source..."
        mkdir -p wifi-source
        cp -r /tmp/mt7902_sync/* ./wifi-source/
    fi
    
    success "Wi-Fi source synchronized."
    rm -rf /tmp/mt7902_sync
fi

# Ensure firmware is present
if [[ ! -f "$FW_DIR/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]]; then
    log "Firmware missing. Deploying from source..."
    mkdir -p "$FW_DIR"
    cp /tmp/mt7902_sync/mt7902_firmware/latest/* "$FW_DIR/" 2>/dev/null || true
    success "Firmware deployed."
fi
rm -rf /tmp/mt7902_sync

# --- 2. System Prep ---
log "Updating toolchain..."
pacman -Sy --needed --noconfirm linux-cachyos-headers base-devel clang lld llvm zstd bc > /dev/null

# --- 3. Bluetooth Patching (Kernel 7.0+) ---
BT_SRC=$(find /usr/src -maxdepth 1 -type d -name "mt7902-bluetooth-*" | head -n 1)
if [[ -d "$BT_SRC" ]]; then
    log "Patching Bluetooth for Kernel $KVER..."
    cd "$BT_SRC"
    sed -i '/#define false/d; /#define true/d' *.c
    sed -i 's/kmalloc_obj/kmalloc/g; s/kzalloc_obj/kzalloc/g' *.c
    VER=$(basename "$BT_SRC" | sed 's/mt7902-bluetooth-//')
    dkms remove mt7902-bluetooth/"$VER" --all 2>/dev/null || true
    dkms add mt7902-bluetooth/"$VER" && dkms install mt7902-bluetooth/"$VER"
    cd - > /dev/null
fi

# --- 4. Wi-Fi Compilation (Clang Optimized) ---
log "Building Wi-Fi driver with Clang/LLVM..."
cd wifi-source
make clean LLVM=1 > /dev/null 2>&1 || true
make -C /lib/modules/"$KVER"/build M="$PWD" LLVM=1 CC=clang HOSTCC=clang EXTRA_CFLAGS="-O3 -march=native -flto=thin" modules -j"$CORES"

# Deploying optimized modules
DEST="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76"
mkdir -p "$DEST/mt7921"
cp mt76.ko mt76-connac-lib.ko mt792x-lib.ko "$DEST/"
cp mt7921/mt7921e.ko mt7921/mt7921-common.ko "$DEST/mt7921/"
zstd --rm -19 -f "$DEST"/*.ko "$DEST/mt7921"/*.ko > /dev/null
cd ..

# --- 5. Final Reset ---
log "Applying stability tweaks and reloading modules..."
echo "options mt7921e disable_aspm=1" > /etc/modprobe.d/mt7902.conf
modprobe -r mt7921e btusb btmtk mt7921_common mt76 2>/dev/null || true
depmod -a "$KVER"
modprobe mt7921e
systemctl restart bluetooth

success "Install complete! Your MT7902 is now optimized for CachyOS."
