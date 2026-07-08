#!/bin/bash
# Fix Raspberry Pi WiFi dropping by disabling power management
# Symptom: Pi becomes unreachable over WiFi intermittently
# Root cause: wlan0 Power Management is ON by default

set -e

echo "Disabling WiFi power management..."
sudo iwconfig wlan0 power off

echo "Making it persistent across reboots..."
sudo tee /etc/network/if-up.d/wifi-powersave-off > /dev/null << 'SCRIPT'
#!/bin/sh
if [ "$IFACE" = "wlan0" ]; then
    iwconfig wlan0 power off
fi
SCRIPT
sudo chmod +x /etc/network/if-up.d/wifi-powersave-off

echo "Enabling persistent journald logs (survive reboots)..."
sudo mkdir -p /var/log/journal
sudo systemctl restart systemd-journald

echo "Done. Verify with: iwconfig wlan0 | grep Power"
