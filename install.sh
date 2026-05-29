#!/bin/bash
set -e

G='\033[38;5;82m'
C='\033[38;5;51m'
NC='\033[0m'

KVER=$(uname -r)
WIFI_VER="1.0"
SOURCE_REPO="https://github.com/OnlineLearningTutorials/mt7902_temp.git"

log() { echo -e "${C}[LOG]${NC} $(date +%H:%M:%S) | $1"; }
success() { echo -e "${G}[OK]${NC} $1"; }

[[ $EUID -ne 0 ]] && echo "Please run with sudo" && exit 1

dkms remove gen4-mt7902/0.1 --all 2>/dev/null || true
dkms remove mt7902-wifi/1.0 --all 2>/dev/null || true
rm -rf /usr/src/gen4-mt7902-0.1 2>/dev/null || true
rm -rf /usr/src/mt7902-wifi-1.0 2>/dev/null || true

rm -rf /tmp/mt7902_sync
git clone --depth 1 "$SOURCE_REPO" /tmp/mt7902_sync > /dev/null

WIFI_SRC_DIR="/usr/src/mt7902-wifi-$WIFI_VER"
mkdir -p "$WIFI_SRC_DIR"

if [[ -d "/tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76" ]]; then
    cp -r /tmp/mt7902_sync/linux-7.0/drivers/net/wireless/mediatek/mt76/* "$WIFI_SRC_DIR/"
    [[ -d "/tmp/mt7902_sync/wlan_mt7902" ]] && cp -r /tmp/mt7902_sync/wlan_mt7902 "$WIFI_SRC_DIR/mt7902"
else
    exit 1
fi

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
MAKE="make -C /lib/modules/\$(uname -r)/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build modules"
CLEAN="make -C /lib/modules/\$(uname -r)/build M=\${dkms_tree}/\${PACKAGE_NAME}/\${PACKAGE_VERSION}/build clean"
EOF

BT_SRC=$(find /usr/src -maxdepth 1 -type d -name "mt7902-bluetooth-*" | head -n 1)
if [[ -d "$BT_SRC" ]]; then
    cd "$BT_SRC"
    sed -i 's/ LLVM=1 CC=clang HOSTCC=clang//g' dkms.conf 2>/dev/null || true
    sed -i '/#define false/d; /#define true/d' *.c 2>/dev/null || true
    sed -i 's/kmalloc_obj/kmalloc/g; s/kzalloc_obj/kzalloc/g' *.c 2>/dev/null || true
    BT_V=$(basename "$BT_SRC" | sed 's/mt7902-bluetooth-//')
    dkms add mt7902-bluetooth/"$BT_V" 2>/dev/null || true
    dkms install mt7902-bluetooth/"$BT_V" || true
    cd - > /dev/null
fi

dkms add mt7902-wifi/"$WIFI_VER" 2>/dev/null || true
dkms install mt7902-wifi/"$WIFI_VER"

cat <<EOF | sudo tee /usr/local/bin/mt7902-init.sh > /dev/null
#!/bin/bash
modprobe -r mt7921e btusb btmtk mt7921_common mt76_connac_lib mt76 2>/dev/null
sleep 2
modprobe mt76
modprobe btmtk
modprobe btusb
modprobe mt7921e
sleep 3
rfkill unblock bluetooth
bluetoothctl power on 2>/dev/null || true
EOF
sudo chmod +x /usr/local/bin/mt7902-init.sh

cat <<EOF | sudo tee /etc/systemd/system/mt7902-fix.service > /dev/null
[Unit]
Description=MT7902 WiFi/BT Fix
After=multi-user.target
[Service]
Type=oneshot
ExecStart=/usr/local/bin/mt7902-init.sh
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl enable --now mt7902-fix.service

echo -e "blacklist mt7921_common\nblacklist mt7921_lib" | sudo tee /etc/modprobe.d/mt7902-blacklist.conf > /dev/null

if [ -f /etc/bluetooth/main.conf ]; then
    sed -i 's/#AutoEnable=true/AutoEnable=true/' /etc/bluetooth/main.conf
fi

systemctl restart bluetooth
rm -rf /tmp/mt7902_sync
success "MT7902 Full Stack Installed and Power-Managed."
