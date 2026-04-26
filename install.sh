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
    log "wifi-source not found. Cloning from repository..."
    
    rm -rf /tmp/mt7902_sync
    git clone --depth 1 "$SOURCE_REPO" /tmp/mt7902_sync > /dev/null
    
    # FIX: Point directly to the Kernel 7.0 source since we are on CachyOS 7.0
    if [[ -d "/tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76" ]]; then
        log "Found Kernel 7.0 specific drivers. Staging..."
        mkdir -p wifi-source
        cp -r /tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76/* ./wifi-source/
        # Copy the mt7902 subfolder specifically if it exists
        if [[ -d "/tmp/mt7902_sync/wlan_mt7902" ]]; then
            cp -r /tmp/mt7902_sync/wlan_mt7902 ./wifi-source/mt7902
        fi
    else
        log "Falling back to generic sync..."
        cp -r /tmp/mt7902_sync/* ./wifi-source/
    fi
    success "Wi-Fi source synchronized and organized for Kernel 7.0."
fi

# Ensure firmware is present
if [[ ! -f "$FW_DIR/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]]; then
    log "Firmware missing. Deploying..."
    mkdir -p "$FW_DIR"
    # Try to find firmware in the cloned repo
    find /tmp/mt7902_sync -name "*.bin" -exec cp {} "$FW_DIR/" \; 2>/dev/null || true
    success "Firmware deployed."
fi
rm -rf /tmp/mt7902_sync

# --- 2. System Prep ---
log "Updating toolchain..."
pacman -Sy --needed --noconfirm linux-cachyos-headers base-devel clang lld llvm zstd bc > /dev/null

# --- 3. Bluetooth Patching (Kernel 7.0+) ---
# We look for the DKMS source we installed earlier
BT_SRC=$(find /usr/src -maxdepth 1 -type d -name "mt7902-bluetooth-*" | head -n 1)
if [[ -d "$BT_SRC" ]]; then
    log "Patching Bluetooth for Kernel $KVER..."
    cd "$BT_SRC"
    # Fix compatibility for Kernel 7.0+
    sed -i '/#define false/d; /#define true/d' *.c 2>/dev/null || true
    sed -i 's/kmalloc_obj/kmalloc/g; s/kzalloc_obj/kzalloc/g' *.c 2>/dev/null || true
    VER=$(basename "$BT_SRC" | sed 's/mt7902-bluetooth-//')
    dkms remove mt7902-bluetooth/"$VER" --all 2>/dev/null || true
    dkms add mt7902-bluetooth/"$VER" && dkms install mt7902-bluetooth/"$VER"
    cd - > /dev/null
fi

# --- 4. Wi-Fi Compilation (Clang Optimized) ---
log "Building Wi-Fi driver with Clang/LLVM..."
cd wifi-source
# Clean old objects
make clean LLVM=1 > /dev/null 2>&1 || true
# The actual build
make -C /lib/modules/"$KVER"/build M="$PWD" LLVM=1 CC=clang HOSTCC=clang EXTRA_CFLAGS="-O3 -march=native -flto=thin" modules -j"$CORES"

# Deploying optimized modules
log "Deploying modules to kernel tree..."
DEST="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76"
mkdir -p "$DEST/mt7921"
cp mt76.ko mt76-connac-lib.ko mt792x-lib.ko "$DEST/" 2>/dev/null || true
# Support both possible folder structures
if [[ -d "mt7921" ]]; then
    cp mt7921/mt7921e.ko mt7921/mt7921-common.ko "$DEST/mt7921/" 2>/dev/null || true
elif [[ -d "mt7902" ]]; then
    mkdir -p "$DEST/mt7902"
    cp mt7902/*.ko "$DEST/mt7902/" 2>/dev/null || true
fi

# Compress for CachyOS (uses zstd by default)
zstd --rm -19 -f "$DEST"/*.ko "$DEST/mt7921"/*.ko 2>/dev/null || true
cd ..

# --- 5. Final Hard Reset ---
log "Applying stability tweaks and performing 'Hart' restart..."
echo "options mt7921e disable_aspm=1" > /etc/modprobe.d/mt7902.conf

# Stop services
systemctl stop bluetooth || true

# Unload modules
modprobe -r mt7921e btusb btmtk mt7921_common mt76 2>/dev/null || true

# Reload everything
depmod -a "$KVER"
modprobe mt76
modprobe btmtk
modprobe btusb
modprobe mt7921e 2>/dev/null || modprobe mt7902 2>/dev/null || true

# Start services
systemctl restart bluetooth
systemctl restart NetworkManager

success "Install complete! Your MT7902 is now optimized for CachyOS Kernel 7.0."
