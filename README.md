# Pi Web Kiosk

Dual-monitor Raspberry Pi web kiosk with offline cache, live failover, periodic hard refresh, and daily reboot — fully JSON config‑driven.

![Raspberry Pi](https://img.shields.io/badge/Platform-Raspberry%20Pi-informational) ![License](https://img.shields.io/badge/License-MIT-green) ![Systemd](https://img.shields.io/badge/Init-systemd-blue) ![Offline First](https://img.shields.io/badge/Pattern-offline--first-lightgrey)

## Demo
The kiosk is used in [Department of Electrical and Electronic Engineering, BUET](https://eee.buet.ac.bd) 's main lobby.
[![Pi Web Kiosk demo](assets/thumb.png)](assets/demo.png)

## Overview
**Pi Web Kiosk** is a config-driven digital signage solution for Raspberry Pi. It launches two Chromium windows in kiosk mode across two HDMI displays. When the network is slow or offline, it serves content from a pre‑mirrored **offline cache** and switches back to the live site as soon as it’s reachable. Scheduled **hard refreshes**, a daily **auto‑reboot**, and **systemd** integration provide hands‑off reliability — all controlled via a single `config.json`.

## Key Features
- **Dual‑monitor layout:** Two independent kiosk windows on HDMI‑1 and HDMI‑2 (configurable position and resolution)
- **Offline‑first failover:** Cached content when offline, auto‑navigate to live when it’s back
- **Periodic hard refresh:** Reload both windows every _N_ hours (default: 3)
- **Daily reboot:** Reboot at a configured time (default: `00:00`)
- **Schedule control:** Turn displays ON/OFF by hour and weekday
- **Config‑driven:** URLs, cache paths, HDMI names, window sizes, timings, and Chromium flags in one JSON
- **Systemd integration:** Auto‑launch on boot, auto‑restart on crash, `journalctl` logs

## Repository Structure
```
pi-web-kiosk/
├─ scripts/
│  └─ signage-launcher.sh      # main kiosk logic (config-driven)
├─ config/
│  └─ config.json.example      # copy to /etc/pi-web-kiosk/config.json
├─ systemd/
│  └─ pi-web-kiosk.service     # systemd unit
├─ setup.sh                    # one-shot installer (optional)
├─ .gitignore
└─ README.md
```

## Requirements
- Raspberry Pi OS (Desktop recommended)
- Packages:
  ```bash
  sudo apt update
  sudo apt install -y chromium-browser x11-xserver-utils xorg jq curl wget git   || sudo apt install -y chromium x11-xserver-utils xorg jq curl wget git
  ```

## Quick Start
> Replace `<your-org>` with your GitHub org or username.

```bash
# 1) Clone to target path
sudo mkdir -p /opt/pi-web-kiosk
sudo chown -R "$USER:$USER" /opt/pi-web-kiosk
git clone https://github.com/<your-org>/pi-web-kiosk.git /opt/pi-web-kiosk

# 2) Prepare config
sudo mkdir -p /etc/pi-web-kiosk
sudo cp /opt/pi-web-kiosk/config/config.json.example /etc/pi-web-kiosk/config.json
sudo nano /etc/pi-web-kiosk/config.json  # set URLs, HDMI names, cache paths, hours

# 3) Make the launcher executable
sudo chmod +x /opt/pi-web-kiosk/scripts/signage-launcher.sh

# 4) (Optional) Test run
/opt/pi-web-kiosk/scripts/signage-launcher.sh /etc/pi-web-kiosk/config.json
# Ctrl+C to stop

# 5) Install systemd service
sudo cp /opt/pi-web-kiosk/systemd/pi-web-kiosk.service /etc/systemd/system/
sudo nano /etc/systemd/system/pi-web-kiosk.service   # verify User/WorkingDirectory/DISPLAY
sudo systemctl daemon-reload
sudo systemctl enable --now pi-web-kiosk.service

# 6) Check status & logs
systemctl status pi-web-kiosk.service
journalctl -u pi-web-kiosk.service -f
```

## Configuration
Edit `/etc/pi-web-kiosk/config.json`. Example keys:
```json
{
  "display": ":0",
  "urls": [
    "https://example.com/page1/",
    "https://example.com/page2/"
  ],
  "offline_cache": [
    "/path/to/offline/page1/index.html",
    "/path/to/offline/page2/index.html"
  ],
  "outputs": { "hdmi1": "HDMI-1", "hdmi2": "HDMI-2" },
  "layout": {
    "hdmi1": { "mode": "1920x1080", "pos": "0x0", "primary": true },
    "hdmi2": { "mode": "1920x1080", "pos": "1920x0", "right_of": "HDMI-1" }
  },
  "chromium": {
    "binary": "/usr/bin/chromium-browser",
    "profile1": "/tmp/profile1",
    "profile2": "/tmp/profile2",
    "window1": { "size": "1920,1080", "position": "0,0", "remote_debug_port": 9222 },
    "window2": { "size": "1920,1080", "position": "1920,0", "remote_debug_port": 9223 }
  },
  "log_file": "/var/log/pi-web-kiosk/signage.log",
  "schedule": { "start_hour": 8, "end_hour": 17, "active_days": [1,2,3,6,7] },
  "refresh_hours": 3,
  "daily_reboot_time": "00:00"
}
```

> **Notes**
> - `active_days`: `1=Mon … 7=Sun`. Example keeps Thu/Fri off.
> - Use `xrandr` to discover HDMI names (`HDMI-1`, `HDMI-2`) and modes.
> - The launcher uses decimal parsing for hours to avoid leading‑zero issues.

## Offline Mirror (Optional)
The first run can auto‑mirror your URLs into the offline paths. You can also pre‑mirror manually:
```bash
wget --mirror --convert-links --page-requisites --adjust-extension --no-parent   -P /path/to/offline-root-1 "https://example.com/page1/"
wget --mirror --convert-links --page-requisites --adjust-extension --no-parent   -P /path/to/offline-root-2 "https://example.com/page2/"
```

## Troubleshooting
- **White screen at start:** We open from `file://` offline cache first; the script then navigates to the live URL if reachable.
- **Permission denied (log file):** Ensure the service user owns the log directory. Adjust `log_file` path or file ownership.
- **No access to X session:** Ensure a graphical session is running. Set `Environment=DISPLAY=:0` (and optionally `XAUTHORITY`) in the service file.
- **Wrong turn‑on hour:** The script forces decimal hour parsing (`10#$H`) to avoid leading‑zero bugs.
- **Two windows on the same display:** Check `layout` and ensure `--window-position` and `xrandr` positions align with your desktop geometry.

## Uninstall
```bash
sudo systemctl disable --now pi-web-kiosk.service
sudo rm -f /etc/systemd/system/pi-web-kiosk.service
sudo systemctl daemon-reload
sudo rm -rf /opt/pi-web-kiosk /etc/pi-web-kiosk
```

## License
MIT — see `LICENSE`.
