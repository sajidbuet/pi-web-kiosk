# Pi Web Kiosk

Dual-monitor Raspberry Pi web kiosk with offline cache, live failover, periodic hard refresh, and daily reboot — fully JSON config‑driven.

![Raspberry Pi](https://img.shields.io/badge/Platform-Raspberry%20Pi-informational) ![License](https://img.shields.io/badge/License-MIT-green) ![Systemd](https://img.shields.io/badge/Init-systemd-blue) ![Offline First](https://img.shields.io/badge/Pattern-offline--first-lightgrey)

## Overview
**Pi Web Kiosk** is a config-driven digital signage solution for Raspberry Pi. It launches two Chromium windows in kiosk mode across two HDMI displays. When the network is slow or offline, it serves content from a pre‑mirrored **offline cache** and switches back to the live site as soon as it’s reachable. Scheduled **hard refreshes**, a daily **auto‑reboot**, and **systemd** integration provide hands‑off reliability — all controlled via a single `config.json`.

## Demo
The kiosk is used in [Department of Electrical and Electronic Engineering, BUET](https://eee.buet.ac.bd) 's main lobby.
[![Pi Web Kiosk demo](assets/demo.jpg)](assets/demo.jpg)



## Features

- Two Chromium kiosk windows on extended desktop (e.g., HDMI-1 left, HDMI-2 right)
- Offline mirror bootstrap + auto fallback
- Live switch when URL is reachable (keeps cache if not)
- Periodic hard refresh every N hours (default 3)
- Daily reboot at a configurable time (default 00:00)
- Schedule window (start/end hours, active weekdays)
- All settings in `config.json`

## Requirements

- Raspberry Pi OS (Desktop recommended)
- Packages:
  ```bash
  sudo apt update
  sudo apt install -y chromium-browser x11-xserver-utils xorg jq curl wget git
  ```
  > If `chromium-browser` is not available, use `chromium`.

## Installation

```bash
# 1) Clone
sudo mkdir -p /opt/pi-web-kiosk
sudo chown -R $USER:$USER /opt/pi-web-kiosk
git clone https://github.com/<your-org>/pi-web-kiosk.git /opt/pi-web-kiosk

# 2) Config
sudo mkdir -p /etc/pi-web-kiosk
sudo cp /opt/pi-web-kiosk/config/config.json.example /etc/pi-web-kiosk/config.json
sudo nano /etc/pi-web-kiosk/config.json
# - Set your USER paths, URLs, schedule, HDMI names, etc.

# 3) Make script executable
sudo chmod +x /opt/pi-web-kiosk/scripts/signage-launcher.sh

# 4) (Optional) Test-run in terminal
/opt/pi-web-kiosk/scripts/signage-launcher.sh /etc/pi-web-kiosk/config.json
# Ctrl+C to stop

# 5) Install systemd service
sudo cp /opt/pi-web-kiosk/systemd/pi-web-kiosk.service /etc/systemd/system/
# Edit to match your user, paths, and DISPLAY:
sudo nano /etc/systemd/system/pi-web-kiosk.service

# 6) Enable & start
sudo systemctl daemon-reload
sudo systemctl enable --now pi-web-kiosk.service

# 7) Check status/logs
systemctl status pi-web-kiosk.service
journalctl -u pi-web-kiosk.service -f
```

## File Structure

```
pi-web-kiosk/
├─ scripts/
│  └─ signage-launcher.sh
├─ config/
│  └─ config.json.example
├─ systemd/
│  └─ pi-web-kiosk.service
├─ .gitignore
└─ README.md
```

## Configuration

Edit `/etc/pi-web-kiosk/config.json`. Example keys:

- `"display"`: `":0"`
- `"urls"`: two live URLs
- `"offline_cache"`: absolute paths to the two cached `index.html` files
- `"outputs"`: HDMI names as seen in `xrandr`
- `"layout"`: resolution & positions (second screen can be `right_of` first)
- `"chromium"`: binary path, per-window size/position, remote-debug ports, profiles
- `"log_file"`: where to write run logs
- `"schedule"`: `start_hour`, `end_hour`, `active_days` (1=Mon … 7=Sun)
- `"refresh_hours"`: periodic hard refresh spacing (default 3)
- `"daily_reboot_time"`: e.g., `"00:00"`

> **Tip:** If you changed monitor names/resolutions, run `xrandr` to confirm available outputs/modes.

## Offline Mirror

On first run the script mirrors `urls` into the `offline_cache` parents. You can prefill caches manually too:
```bash
wget --mirror --convert-links --page-requisites --adjust-extension --no-parent -P /path/to/offline-root-1 "https://example.com/page1/"
wget --mirror --convert-links --page-requisites --adjust-extension --no-parent -P /path/to/offline-root-2 "https://example.com/page2/"
```

## Common Issues

- **White screen at Chromium start:** we launch from `file://` offline cache first, then try switching to the live URL; this avoids the blank window if network is slow.
- **Permission denied on log file:** ensure the service runs as the intended desktop user and `log_file` directory is writable by that user.
- **Service can't access X:** set `Environment=DISPLAY=:0` (and optionally `XAUTHORITY`) in the service. Make sure a graphical session is active.
- **Turned on at wrong hour (leading-zero bug):** we force decimal parsing (`10#$H`) in the script.


## Holiday‑aware display control

The kiosk can turn **displays OFF on public holidays** based on a configurable provider. Holidays **override** the normal schedule (if today is a holiday, displays stay OFF even during working hours).

### Configuration (`/etc/pi-web-kiosk/config.json`)
```json
"holiday": {
  "provider": "nager",                     // "nager" | "calendarific" | "ics" | "none"
  "country_code": "BD",                    // ISO 3166-1 alpha-2 code
  "calendarific": { "api_key": "" },       // only used if provider = "calendarific"
  "ics": {
    "url": "https://calendar.google.com/calendar/ical/en.bd.official%23holiday%40group.v.calendar.google.com/public/basic.ics"
  },
  "treat_observances_as_holiday": true     // when supported by provider, count observances as holidays
}
```

### Providers
- **nager** (default): Free, no API key. Queries `https://date.nager.at/` by year and checks today’s date.
- **calendarific**: Commercial API with key; supports rich filtering.
- **ics**: Any iCalendar (ICS) URL (e.g., Google Public Holidays for Bangladesh); simple DTSTART date match.
- **none**: Disable holiday logic.

### Examples
- **Switch country (Nager):** set `"country_code": "US"` (or `"IN"`, `"GB"`, etc.).
- **Use Google ICS (Bangladesh):**
  ```json
  "provider": "ics",
  "ics": {
    "url": "https://calendar.google.com/calendar/ical/en.bd.official%23holiday%40group.v.calendar.google.com/public/basic.ics"
  }
  ```
- **Use Calendarific (Bangladesh):**
  ```json
  "provider": "calendarific",
  "country_code": "BD",
  "calendarific": { "api_key": "YOUR_API_KEY" }
  ```

> Notes:
> - The check runs once per loop; it’s lightweight (Nager returns JSON for the year which we scan for today).
> - If the provider is unreachable, the script **falls back to normal schedule**.
> - To show special holiday content instead of turning displays off, you can extend the script to launch a third URL set when `is_public_holiday_today` is true.

## Uninstall

```bash
sudo systemctl disable --now pi-web-kiosk.service
sudo rm -f /etc/systemd/system/pi-web-kiosk.service
sudo systemctl daemon-reload
sudo rm -rf /opt/pi-web-kiosk /etc/pi-web-kiosk
```

## License

MIT (see LICENSE).
