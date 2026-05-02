#!/bin/bash

# MT7902 Combined DKMS Installer (Standalone & Optimized)
set -e

# Colors for terminal output
G='\033[38;5;82m'
C='\033[38;5;51m'
NC='\033[0m'

KVER=$(uname -r)
CORES=$(nproc)
WIFI_VER="1.0"
SOURCE_REPO="https://github.com/OnlineLearningTutorials/mt7902_temp.git"

log() { echo -e "${C}[LOG]${NC} $(date +%H:%M:%S) | $1"; }
success() { echo -e "${G}[OK]${NC} $1"; }

[[ $EUID -ne 0 ]] && echo "Please run with sudo" && exit 1

# --- 0. Conflict Cleanup ---
# Removes old "ghost" modules that cause "Bad return status" errors
log "Cleaning up old/conflicting modules..."
dkms remove gen4-mt7902/0.1 --all 2>/dev/null || true
rm -rf /usr/src/gen4-mt7902-0.1 2>/dev/null || true

# --- 1. Source Staging & Organization ---
log "Checking and staging sources for Kernel 7.0..."
rm -rf /tmp/mt7902_sync
git clone --depth 1 "$SOURCE_REPO" /tmp/mt7902_sync > /dev/null

WIFI_SRC_DIR="/usr/src/mt7902-wifi-$WIFI_VER"
mkdir -p "$WIFI_SRC_DIR"

if [[ -d "/tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76" ]]; then
    cp -r /tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76/* "$WIFI_SRC_DIR/"
    [[ -d "/tmp/mt7902_sync/wlan_mt7902" ]] && cp -r /tmp/mt7902_sync/wlan_mt7902 "$WIFI_SRC_DIR/mt7902"
    success "Source staged in $WIFI_SRC_DIR"
else
    log "Error: Kernel 7.0 source not found in repo."
    exit 1
fi

# --- 2. Create WiFi DKMS Config ---
log "Creating WiFi DKMS configuration..."
cat <<EOF > "$WIFI_SRC_DIR/dkms.conf"
PACKAGE_NAME="mt7902-wifi"
PACKAGE_VERSION="$WIFI_VER"
BUILT_MODULE_NAME[0]="mt76"
DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless/mediatek/mt76"
BUILT_MODULE_NAME[1]="mt76-connac-lib"
DEST_MODULE_LOCATION[1]="/kernel/drivers/net/wireless/mediatek/mt76"
BUILT_MODULE_NAME[2]="mt792x-lib"
DEST_MODULE_LOCATION[2]="/kernel/drivers/net/wireless/mediatek/mt76"
BUILT_MODULE_NAME[3]="mt7921-common"
BUILT_MODULE_LOCATION[3]="mt7921/"
DEST_MODULE_LOCATION[3]="/kernel/drivers/net/wireless/mediatek/mt76/mt7921"
BUILT_MODULE_NAME[4]="mt7921e"
BUILT_MODULE_LOCATION[4]="mt7921/"
DEST_MODULE_LOCATION[4]="/kernel/drivers/net/wireless/mediatek/mt76/mt7921"
AUTOINSTALL="yes"
MAKE="make -C /lib/modules/\$(uname -r)/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build LLVM=1 CC=clang HOSTCC=clang modules"
CLEAN="make -C /lib/modules/\$(uname -r)/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

# --- 3. Bluetooth Patching & Registration ---
BT_SRC=$(find /usr/src -maxdepth 1 -type d -name "mt7902-bluetooth-*" | head -n 1)
if [[ -d "$BT_SRC" ]]; then
    log "Applying Bluetooth patches for Kernel 7.0..."
    cd "$BT_SRC"
    sed -i '/#define false/d; /#define true/d' *.c 2>/dev/null || true
    sed -i 's/kmalloc_obj/kmalloc/g; s/kzalloc_obj/kzalloc/g' *.c 2>/dev/null || true
    BT_V=$(basename "$BT_SRC" | sed 's/mt7902-bluetooth-//')
    dkms add mt7902-bluetooth/"$BT_V" 2>/dev/null || true
    dkms install mt7902-bluetooth/"$BT_V" || true
    cd - > /dev/null
fi

# --- 4. WiFi DKMS Installation ---
log "Registering and installing WiFi DKMS module..."
dkms add mt7902-wifi/"$WIFI_VER" 2>/dev/null || true
dkms install mt7902-wifi/"$WIFI_VER"

# --- 5. Persistence & Automation ---
log "Configuring hardware persistence..."

# Force modules to load on boot
echo -e "mt76\nbtmtk\nbtusb\mt7921e" | sudo tee /etc/modules-load.d/mt7902.conf

# Blacklist the 'Original' broken modules to prevent conflicts
echo -e "blacklist mt7921_common\nblacklist mt7921_lib" | sudo tee /etc/modprobe.d/mt7902-blacklist.conf

# Enable Auto-Power for Bluetooth
if [ -f /etc/bluetooth/main.conf ]; then
    sed -i 's/#AutoEnable=true/AutoEnable=true/' /etc/bluetooth/main.conf
fi

# Power management tweak for WiFi stability
echo "options mt7921e disable_aspm=1" > /etc/modprobe.d/mt7902.conf

# --- 6. THE "HART" RESTART ---
log "Reloading module stack..."
systemctl stop bluetooth || true

# Unload old versions
modprobe -r mt7921e btusb btmtk mt7921_common mt76_connac_lib mt76 2>/dev/null || true

# Refresh and load new ones
depmod -a "$KVER"
modprobe mt76
modprobe btmtk
modprobe btusb
modprobe mt7921e 2>/dev/null || true

# Restart services
systemctl start bluetooth
systemctl restart NetworkManager

rm -rf /tmp/mt7902_sync
success "MT7902 Full Stack Installed! WiFi and Bluetooth are now automated and DKMS-managed."
