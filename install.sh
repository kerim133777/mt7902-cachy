#!/bin/bash

set -e

G='\033[38;5;82m'
C='\033[38;5;51m'
NC='\033[0m'

KVER=$(uname -r)
CORES=$(nproc)
FW_DIR="/lib/firmware/mediatek"
BT_SRC=$(find /usr/src -maxdepth 1 -type d -name "mt7902-bluetooth-*" | head -n 1)
TUNING="-O3 -march=native -flto=thin -fuse-ld=lld -pipe"

log() { echo -e "${C}[LOG]${NC} $(date +%H:%M:%S) | $1"; }
success() { echo -e "${G}[OK]${NC} $1"; }

[[ $EUID -ne 0 ]] && echo "Run as root" && exit 1

log "Installing system updates..."
pacman -Sy --needed --noconfirm linux-cachyos-headers base-devel clang lld llvm zstd git bc > /dev/null
success "Updates finished."

log "Checking hardware files..."
if [[ ! -f "$FW_DIR/BT_RAM_CODE_MT7902_1_1_hdr.bin" ]]; then
    git clone --depth 1 https://github.com/OnlineLearningTutorials/mt7902_temp.git /tmp/fw_sync > /dev/null
    mkdir -p "$FW_DIR"
    cp -v /tmp/fw_sync/mt7902_firmware/latest/* "$FW_DIR/"
    rm -rf /tmp/fw_sync
fi
success "Files checked."

if [[ -d "$BT_SRC" ]]; then
    log "Fixing Bluetooth..."
    cd "$BT_SRC"
    sed -i '/#define false/d; /#define true/d; /#define hci_discovery_active/d' *.c
    sed -i 's/kmalloc_obj/kmalloc/g; s/kzalloc_obj/kzalloc/g' *.c
    sed -i 's/hci_discovery_active(hdev)/false/g' *.c
    VER=$(basename "$BT_SRC" | sed 's/mt7902-bluetooth-//')
    dkms remove mt7902-bluetooth/"$VER" --all 2>/dev/null || true
    dkms add mt7902-bluetooth/"$VER" && dkms install mt7902-bluetooth/"$VER"
    cd - > /dev/null
    success "Bluetooth fixed."
fi

if [[ -d "wifi-source" ]]; then
    log "Compiling Wi-Fi..."
    cd wifi-source
    make clean LLVM=1 > /dev/null 2>&1 || true
    
    # Removed > /dev/null to show CC/LD/BTF logs
    make -C /lib/modules/"$KVER"/build M="$PWD" LLVM=1 CC=clang HOSTCC=clang EXTRA_CFLAGS="$TUNING" modules -j"$CORES"
    
    DEST="/lib/modules/$KVER/kernel/drivers/net/wireless/mediatek/mt76"
    mkdir -p "$DEST/mt7921"
    cp mt76.ko mt76-connac-lib.ko mt792x-lib.ko "$DEST/"
    cp mt7921/mt7921e.ko mt7921/mt7921-common.ko "$DEST/mt7921/"
    zstd --rm -19 -f "$DEST"/*.ko "$DEST/mt7921"/*.ko > /dev/null
    cd ..
    success "Wi-Fi fixed."
fi

log "Saving settings..."
echo "options mt7921e disable_aspm=1" > /etc/modprobe.d/mt7902.conf

systemctl stop bluetooth || true
modprobe -r mt7921e btusb btmtk mt7921_common mt792x_lib mt76_connac_lib mt76 2>/dev/null || true
depmod -a "$KVER"
echo "mt7921e" > /etc/modules-load.d/mt7902.conf
modprobe mt76
modprobe mt7921e
modprobe btmtk
modprobe btusb
systemctl start bluetooth

log "Hardware Status:"
dmesg | grep -i "mt7921" | tail -n 3

success "All tasks complete. Your system is ready."
