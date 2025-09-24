#!/usr/bin/env bash
set -euo pipefail

echo "[*] Installing dependencies..."
sudo apt update
sudo apt install -y chromium-browser x11-xserver-utils xorg jq curl wget git || sudo apt install -y chromium

echo "[*] Creating directories..."
sudo mkdir -p /opt/pi-web-kiosk /etc/pi-web-kiosk
sudo cp -r . /opt/pi-web-kiosk
sudo cp config/config.json.example /etc/pi-web-kiosk/config.json

echo "[*] Marking scripts executable..."
sudo chmod +x /opt/pi-web-kiosk/scripts/signage-launcher.sh
sudo chmod +x /opt/pi-web-kiosk/setup.sh || true

echo "[*] Installing systemd service..."
sudo cp /opt/pi-web-kiosk/systemd/pi-web-kiosk.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now pi-web-kiosk.service

echo "[*] Done. View logs with: journalctl -u pi-web-kiosk.service -f"
