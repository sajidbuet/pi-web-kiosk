#!/usr/bin/env bash
# signage-launcher.sh - Dual monitor web kiosk with offline cache + live update (config-driven)

set -Eeuo pipefail

CONFIG_PATH="${1:-/etc/pi-web-kiosk/config.json}"

jq() { command jq "$@"; }  # ensure using system jq

req() {
  local val
  val="$(command jq -er "$1" "$CONFIG_PATH")" || {
    echo "[$(date)] CONFIG ERROR: Missing key: $1" >&2
    exit 1
  }
  printf "%s" "$val"
}

opt() {
  command jq -r "$1 // empty" "$CONFIG_PATH"
}

# ==== LOAD CONFIG ====
DISPLAY_VAL="$(req '.display')"

URL1="$(req '.urls[0]')"
URL2="$(req '.urls[1]')"

CACHE1="$(req '.offline_cache[0]')"
CACHE2="$(req '.offline_cache[1]')"

HDMI1="$(req '.outputs.hdmi1')"
HDMI2="$(req '.outputs.hdmi2')"

CHROMIUM_BIN="$(req '.chromium.binary')"
PROFILE1="$(req '.chromium.profile1')"
PROFILE2="$(req '.chromium.profile2')"

WIN1_SIZE="$(req '.chromium.window1.size')"
WIN1_POS="$(req '.chromium.window1.position')"
PORT1="$(req '.chromium.window1.remote_debug_port')"

WIN2_SIZE="$(req '.chromium.window2.size')"
WIN2_POS="$(req '.chromium.window2.position')"
PORT2="$(req '.chromium.window2.remote_debug_port')"

LOGFILE="$(req '.log_file')"

START_HOUR="$(req '.schedule.start_hour')"
END_HOUR="$(req '.schedule.end_hour')"

mapfile -t ACTIVE_DAYS < <(command jq -r '.schedule.active_days[]' "$CONFIG_PATH")

REFRESH_HOURS="$(opt '.refresh_hours')"; REFRESH_HOURS="${REFRESH_HOURS:-3}"
DAILY_REBOOT_TIME="$(opt '.daily_reboot_time')"; DAILY_REBOOT_TIME="${DAILY_REBOOT_TIME:-00:00}"

# Layout
HDMI1_MODE="$(req '.layout.hdmi1.mode')"
HDMI1_POS="$(req '.layout.hdmi1.pos')"
HDMI1_PRIMARY="$(opt '.layout.hdmi1.primary')"

HDMI2_MODE="$(req '.layout.hdmi2.mode')"
HDMI2_POS="$(req '.layout.hdmi2.pos')"
HDMI2_RIGHT_OF="$(opt '.layout.hdmi2.right_of')"

# Holiday config
HOL_PROVIDER="$(opt '.holiday.provider')"; HOL_PROVIDER="${HOL_PROVIDER:-none}"
HOL_COUNTRY="$(opt '.holiday.country_code')"; HOL_COUNTRY="${HOL_COUNTRY:-BD}"
HOL_CAL_APIKEY="$(opt '.holiday.calendarific.api_key')"
HOL_ICS_URL="$(opt '.holiday.ics.url')"
HOL_TREAT_OBS="$(opt '.holiday.treat_observances_as_holiday')"; HOL_TREAT_OBS="${HOL_TREAT_OBS:-true}"

# ==== ENV / LOGGING ====
export DISPLAY="$DISPLAY_VAL"

mkdir -p "$(dirname "$LOGFILE")"
touch "$LOGFILE"
exec >>"$LOGFILE" 2>&1
echo "[$(date)] --- signage-launcher (config: $CONFIG_PATH) ---"

# Single instance lock
LOCKFILE="/tmp/signage-launcher.lock"
if [[ -e "$LOCKFILE" ]] && kill -0 "$(cat "$LOCKFILE")" 2>/dev/null; then
  echo "[$(date)] Another instance (PID $(cat "$LOCKFILE")) already running. Exiting."
  exit 1
fi
echo $$ >"$LOCKFILE"
trap 'rm -f "$LOCKFILE"' EXIT

# Flags
LAST_REBOOT_FLAG="/tmp/signage_last_reboot_date"
LAST_REFRESH_FLAG="/tmp/signage_last_refresh_tick"
LAST_STATUS_FLAG="/tmp/signage_last_status_tick"

# Power settings
xset s off || true
xset -dpms || true
xset s noblank || true

# Prepare offline dirs
mkdir -p "$(dirname "$CACHE1")"
mkdir -p "$(dirname "$CACHE2")"

# Bootstrap cache if missing
bootstrap_cache() {
  if [[ ! -f "$CACHE1" || ! -f "$CACHE2" ]]; then
    echo "[$(date)] Cache missing, preparing initial offline mirrors..."
    rm -rf "$(dirname "$CACHE1")"
    rm -rf "$(dirname "$CACHE2")"
    wget --mirror --convert-links --page-requisites --adjust-extension --no-parent -P "$(dirname "$(dirname "$CACHE1")")" "$URL1" || true
    wget --mirror --convert-links --page-requisites --adjust-extension --no-parent -P "$(dirname "$(dirname "$CACHE2")")" "$URL2" || true
  fi
}

in_schedule() {
  local DAY HOUR
  DAY="$(date +%u)"
  HOUR="$(date +%H)"
  HOUR=$((10#$HOUR))  # avoid octal

  local ok_day=1
  for d in "${ACTIVE_DAYS[@]}"; do
    [[ "$d" == "$DAY" ]] && ok_day=0 && break
  done

  if [[ $ok_day -eq 0 && $HOUR -ge $START_HOUR && $HOUR -le $END_HOUR ]]; then
    return 0
  else
    return 1
  fi
}

turn_on_monitors() {
  # HDMI-1
  if [[ "${HDMI1_PRIMARY,,}" == "true" ]]; then
    /usr/bin/xrandr --output "$HDMI1" --mode "$HDMI1_MODE" --pos "$HDMI1_POS" --primary
  else
    /usr/bin/xrandr --output "$HDMI1" --mode "$HDMI1_MODE" --pos "$HDMI1_POS"
  fi
  # HDMI-2
  if [[ -n "$HDMI2_RIGHT_OF" && "$HDMI2_RIGHT_OF" != "null" ]]; then
    /usr/bin/xrandr --output "$HDMI2" --mode "$HDMI2_MODE" --pos "$HDMI2_POS" --right-of "$HDMI2_RIGHT_OF"
  else
    /usr/bin/xrandr --output "$HDMI2" --mode "$HDMI2_MODE" --pos "$HDMI2_POS"
  fi
}

turn_off_monitors() {
  /usr/bin/xrandr --output "$HDMI1" --off
  /usr/bin/xrandr --output "$HDMI2" --off
}

check_status() {
  local TS XR out
  TS="$(date '+%Y-%m-%d %H:%M:%S')"
  XR="$(xrandr --query)"
  if in_schedule; then
    echo "$TS [status] within schedule... monitors should be ON..."
  else
    echo "$TS [status] outside schedule... monitors should be OFF..."
  fi
  for out in "$HDMI1" "$HDMI2"; do
    if echo "$XR" | grep -q "^$out connected"; then
      if echo "$XR" | awk -v o="$out" '
        $0 ~ "^"o" " {inblk=1; next}
        /^[A-Za-z0-9-]+ (dis|con)connected/ {inblk=0}
        inblk && /\*/ {found=1}
        END {exit found?0:1}
      '; then
        echo "$TS [$out] monitor ON"
      else
        echo "$TS [$out] monitor OFF (connected, no active mode)"
      fi
    elif echo "$XR" | grep -q "^$out disconnected"; then
      echo "$TS [$out] not detected"
    else
      echo "$TS [$out] status unknown"
    fi
  fi
}

launch_chromium_if_needed() {
  if ! pgrep -f "chromium" >/dev/null; then
    sleep 2
    echo "[$(date)] Launching Chromium with offline cache..."
    "$CHROMIUM_BIN" \
      --noerrdialogs --kiosk --disable-translate --disable-infobars --no-first-run --fast --fast-start \
      --remote-debugging-port="$PORT1" \
      --window-size="$WIN1_SIZE" --window-position="$WIN1_POS" \
      --disable-logging --v=0 \
      --user-data-dir="$PROFILE1" "file://$CACHE1" >/dev/null 2>&1 &

    sleep 2

    "$CHROMIUM_BIN" \
      --noerrdialogs --kiosk --disable-translate --disable-infobars --no-first-run --fast --fast-start \
      --remote-debugging-port="$PORT2" \
      --window-size="$WIN2_SIZE" --window-position="$WIN2_POS" \
      --disable-logging --v=0 \
      --user-data-dir="$PROFILE2" "file://$CACHE2" >/dev/null 2>&1 &

    sleep 8
  fi
}

nav_to_url() {
  local PORT="$1" URL="$2" TID
  echo "[$(date)] Checking $URL for live availability..."
  if curl -s --head "$URL" | grep -q "200 OK"; then
    TID="$(curl -s "http://localhost:$PORT/json/list" | command jq -r '.[0].id')"
    if [[ -n "$TID" && "$TID" != "null" ]]; then
      echo "[$(date)] Navigating port $PORT -> $URL"
      curl -s -X POST "http://localhost:$PORT/json/send/$TID" \
        -H "Content-Type: application/json" \
        -d "{\"id\":1,\"method\":\"Page.navigate\",\"params\":{\"url\":\"$URL\"}}" >/dev/null
    else
      echo "[$(date)] No debugger target on port $PORT"
    fi
  else
    echo "[$(date)] $URL not reachable, keeping cache"
  fi
}

maybe_nav_to_live() {
  nav_to_url "$PORT1" "$URL1"
  nav_to_url "$PORT2" "$URL2"
}

maybe_daily_reboot() {
  local HM TODAY
  HM="$(date +%H%M)"
  TODAY="$(date +%F)"
  local REBOOT_HM="${DAILY_REBOOT_TIME//:/}"
  if [[ "$HM" == "$REBOOT_HM" ]]; then
    if [[ ! -f "$LAST_REBOOT_FLAG" || "$(cat "$LAST_REBOOT_FLAG")" != "$TODAY" ]]; then
      echo "[$(date)] Daily reboot $DAILY_REBOOT_TIME reached. Rebooting..."
      echo "$TODAY" >"$LAST_REBOOT_FLAG"
      /sbin/reboot
    fi
  fi
}

maybe_periodic_refresh() {
  local H M TICK
  H="$(date +%H)"
  M="$(date +%M)"
  if [[ "$M" == "00" && $((10#$H % REFRESH_HOURS)) -eq 0 ]]; then
    TICK="$(date +%F-%H)"
    if [[ ! -f "$LAST_REFRESH_FLAG" || "$(cat "$LAST_REFRESH_FLAG")" != "$TICK" ]]; then
      echo "[$(date)] Periodic refresh tick ($TICK) – reloading both windows (ignoreCache=true)"
      for P in "$PORT1" "$PORT2"; do
        local TID
        TID="$(curl -s "http://localhost:$P/json/list" | command jq -r '.[0].id')"
        if [[ -n "$TID" && "$TID" != "null" ]]; then
          curl -s -X POST "http://localhost:$P/json/send/$TID" \
            -H "Content-Type: application/json" \
            -d '{"id":1,"method":"Page.reload","params":{"ignoreCache":true}}' >/dev/null
        else
          echo "[$(date)] No debugger target for refresh on port $P"
        fi
      done
      maybe_nav_to_live
      echo "$TICK" >"$LAST_REFRESH_FLAG"
    fi
  fi
}

maybe_hourly_status() {
  local HM TICK
  HM="$(date +%H%M)"
  TICK="$(date +%F-%H)"
  if [[ "$HM" =~ 00$ ]]; then
    if [[ ! -f "$LAST_STATUS_FLAG" || "$(cat "$LAST_STATUS_FLAG")" != "$TICK" ]]; then
      check_status
      echo "$TICK" >"$LAST_STATUS_FLAG"
    fi
  fi
}

today_iso() { date +%F; }          # 2025-09-24
today_yyyymmdd() { date +%Y%m%d; } # 20250924

is_holiday_today_nager() {
  local year country today json
  year="$(date +%Y)"
  country="${HOL_COUNTRY:-BD}"
  today="$(today_iso)"
  json="$(curl -fsS "https://date.nager.at/api/v3/PublicHolidays/${year}/${country}" || true)"
  [[ -z "$json" ]] && return 1
  if command jq -e --arg d "$today" '.[] | select(.date == $d)' >/dev/null 2>&1 <<<"$json"; then
    return 0
  fi
  return 1
}

is_holiday_today_calendarific() {
  [[ -z "$HOL_CAL_APIKEY" ]] && return 1
  local country year month day json
  country="${HOL_COUNTRY:-BD}"
  year="$(date +%Y)"; month="$(date +%m)"; day="$(date +%d)"
  json="$(curl -fsS "https://calendarific.com/api/v2/holidays?api_key=${HOL_CAL_APIKEY}&country=${country}&year=${year}&month=${month}&day=${day}" || true)"
  [[ -z "$json" ]] && return 1
  if $HOL_TREAT_OBS; then
    command jq -e '.response.holidays | length > 0' >/dev/null 2>&1 <<<"$json"
  else
    command jq -e '[.response.holidays[] | select(.type[] | ascii_downcase == "national")] | length > 0' >/dev/null 2>&1 <<<"$json"
  fi
}

is_holiday_today_ics() {
  [[ -z "$HOL_ICS_URL" ]] && return 1
  local ymd ics
  ymd="$(today_yyyymmdd)"
  ics="$(curl -fsS "$HOL_ICS_URL" || true)"
  [[ -z "$ics" ]] && return 1
  if grep -q "DTSTART.*:${ymd}" <<<"$ics"; then
    return 0
  fi
  return 1
}

is_public_holiday_today() {
  case "${HOL_PROVIDER,,}" in
    nager)         is_holiday_today_nager && return 0 || return 1 ;;
    calendarific)  is_holiday_today_calendarific && return 0 || return 1 ;;
    ics)           is_holiday_today_ics && return 0 || return 1 ;;
    ""|none|*)     return 1 ;;
  esac
}

# ==== STARTUP ====
echo "[$(date)] LAUNCH pid=$$ ppid=$PPID user=$(whoami)"
bootstrap_cache
turn_on_monitors
check_status
launch_chromium_if_needed
maybe_nav_to_live

# ==== MAIN LOOP (per-minute) ====
while true; do
  maybe_daily_reboot
  maybe_periodic_refresh
  maybe_hourly_status

  HOL=false
  if is_public_holiday_today; then
    echo "[$(date)] Holiday detected by provider=$HOL_PROVIDER (country=$HOL_COUNTRY) – forcing displays OFF."
    HOL=true
  fi

  if $HOL; then
    turn_off_monitors
  else
    if in_schedule; then
      turn_on_monitors
    else
      turn_off_monitors
    fi
  fi

  sleep 60
done
