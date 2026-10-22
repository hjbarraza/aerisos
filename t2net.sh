#!/bin/bash
# Tether network + wifi/bt firmware, all in one. Run on the T2 Mac booted into Arch.
# Enable USB tethering on the phone first. When the macOS version menu appears,
# pick Sonoma (or anything Monterey or later).
[ "$EUID" -eq 0 ] || exec sudo bash "$0" "$@"
set -e

printf '[Match]\nName=usb* en*u*\n[Network]\nDHCP=yes\n' > /etc/systemd/network/20-tether.network
systemctl restart systemd-networkd
echo "waiting for network..."
for _ in $(seq 1 15); do
  ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 && break
  sleep 2
done
ping -c1 -W2 1.1.1.1 >/dev/null 2>&1 || { echo "no internet. Enable USB tethering on the phone, replug, rerun."; exit 1; }
curl -sm5 https://wiki.t2linux.org >/dev/null 2>&1 || echo 'nameserver 1.1.1.1' > /etc/resolv.conf

cd /root
curl -sLO https://wiki.t2linux.org/tools/firmware.sh
bash firmware.sh get_from_online

echo "=== wifi ==="
sleep 3
ip link | grep -i wlan || { echo "no wlan device. Photograph the output above."; exit 1; }
echo "Connect with: iwctl station wlan0 scan ; iwctl station wlan0 get-networks ; iwctl station wlan0 connect <SSID>"
