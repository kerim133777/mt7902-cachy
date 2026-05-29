#!/bin/bash
set -e

# --- Configuration & Constants ---
WIFI_VER="1.0"
SOURCE_REPO="https://github.com/OnlineLearningTutorials/mt7902_temp.git"
REQUIRED_PKGS=("git" "dkms" "make" "gcc" "linux-cachyos-headers" "bluez")

# --- Helper Functions ---
log() { echo -e "\033[38;5;51m[LOG]\033[0m $(date +%H:%M:%S) | $1"; }
error() { echo -e "\033[31m[ERROR]\033[0m $1"; exit 1; }

check_deps() {
    log "Checking dependencies..."
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! pacman -Qs "$pkg" > /dev/null; then
            error "Missing required package: $pkg. Please install it first."
        fi
    done
}

cleanup_old() {
    log "Cleaning existing modules..."
    dkms remove gen4-mt7902/0.1 --all 2>/dev/null || true
    dkms remove mt7902-wifi/"$WIFI_VER" --all 2>/dev/null || true
    rm -rf /usr/src/gen4-mt7902-0.1 /usr/src/mt7902-wifi-"$WIFI_VER" 2>/dev/null || true
}

install_wifi() {
    log "Staging WiFi sources..."
    rm -rf /tmp/mt7902_sync
    git clone --depth 1 "$SOURCE_REPO" /tmp/mt7902_sync > /dev/null
    
    local src_dir="/usr/src/mt7902-wifi-$WIFI_VER"
    mkdir -p "$src_dir"
    cp -r /tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76/* "$src_dir/"
    [[ -d "/tmp/mt7902_sync/wlan_mt7902" ]] && cp -r /tmp/mt7902_sync/wlan_mt7902 "$src_dir/mt7902"

    cat <<EOF > "$src_dir/dkms.conf"
PACKAGE_NAME="mt7902-wifi"
PACKAGE_VERSION="$WIFI_VER"
BUILT_MODULE_NAME[0]="mt76"
BUILT_MODULE_NAME[1]="mt76-connac-lib"
BUILT_MODULE_NAME[2]="mt792x-lib"
BUILT_MODULE_NAME[3]="mt7921-common"
BUILT_MODULE_NAME[4]="mt7921e"
DEST_MODULE_LOCATION[0]="/kernel/drivers/net/wireless/mediatek/mt76"
DEST_MODULE_LOCATION[1]="/kernel/drivers/net/wireless/mediatek/mt76"
DEST_MODULE_LOCATION[2]="/kernel/drivers/net/wireless/mediatek/mt76"
DEST_MODULE_LOCATION[3]="/kernel/drivers/net/wireless/mediatek/mt76/mt7921"
DEST_MODULE_LOCATION[4]="/kernel/drivers/net/wireless/mediatek/mt76/mt7921"
AUTOINSTALL="yes"
MAKE="make -C /lib/modules/\$(uname -r)/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C /lib/modules/\$(uname -r)/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

    dkms add mt7902-wifi/"$WIFI_VER"
    dkms install mt7902-wifi/"$WIFI_VER"
}

setup_service() {
    log "Configuring systemd service..."
    cat <<EOF > /usr/local/bin/mt7902-init.sh
#!/bin/bash
modprobe -r mt7921e btusb btmtk mt7921_common mt76_connac_lib mt76 2>/dev/null
sleep 2
modprobe mt76 && modprobe btmtk && modprobe btusb && modprobe mt7921e
sleep 3
rfkill unblock bluetooth
bluetoothctl power on 2>/dev/null || true
EOF
    chmod +x /usr/local/bin/mt7902-init.sh
    
    cat <<EOF > /etc/systemd/system/mt7902-fix.service
[Unit]
Description=MT7902 WiFi/BT Fix
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/mt7902-init.sh
[Install]
WantedBy=multi-user.target
EOF
    systemctl enable --now mt7902-fix.service
}

# --- Execution ---
[[ $EUID -ne 0 ]] && error "Must run as root."

check_deps
cleanup_old
install_wifi
# [Insert Bluetooth patch logic here]
setup_service

echo -e "blacklist mt7921_common\nblacklist mt7921_lib" > /etc/modprobe.d/mt7902-blacklist.conf

log "Installation complete. Verifying interface..."
if ip link show | grep -q "wlan"; then
    echo -e "\033[38;5;82mSUCCESS: WiFi interface detected.\033[0m"
else
    echo -e "\033[31mWARNING: Could not detect wlan interface. Please reboot.\033[0m"
fi
