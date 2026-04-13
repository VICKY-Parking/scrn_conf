#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/start-myway-kiosk.conf}"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "[kiosk] Missing config file: $CONFIG_FILE" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "$CONFIG_FILE"

require_config() {
  local key="$1"
  if [ -z "${!key:-}" ]; then
    echo "[kiosk] Required config '$key' is missing or empty in $CONFIG_FILE" >&2
    exit 1
  fi
}

require_config "KIOSK_URL"
require_config "TOUCH_DEVICE_NAME"
require_config "NO_MORE_GESTURES_EXT_PATH"
require_config "CHROME_BIN"
require_config "ENABLE_TOUCH_CALIBRATION"


log() {
  echo "[kiosk] $1"
}

wait_for_x() {
  local retries=30
  local count=0

  until xset q >/dev/null 2>&1; do
    count=$((count + 1))
    if [ "$count" -ge "$retries" ]; then
      log "X server is not ready."
      exit 1
    fi
    sleep 1
  done
}

detect_display() {
  local output
  output="$(xrandr --query | awk '/ connected primary /{print $1; exit}')"

  if [ -z "${output:-}" ]; then
    output="$(xrandr --query | awk '/ connected /{print $1; exit}')"
  fi

  if [ -z "${output:-}" ]; then
    log "No connected display found."
    exit 1
  fi

  echo "$output"
}

disable_onscreen_keyboard() {
  log "Disabling on-screen keyboard settings..."

  gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled false || true
  gsettings set org.gnome.desktop.interface toolkit-accessibility false || true
  gsettings set org.gnome.desktop.input-sources show-all-sources false || true
  gsettings set org.gnome.desktop.a11y always-show-universal-access-status false || true

  # Kill common on-screen keyboard processes
  pkill -f onboard || true
  pkill -f caribou || true
  pkill -f maliit-keyboard || true
  pkill -f ibus || true
}

disable_screen_sleep() {
  log "Disabling screen blanking and DPMS..."
  xset s off >/dev/null 2>&1 || true
  if ! xset -dpms >/dev/null 2>&1; then
    log "DPMS extension not available on this X server, skipping."
  fi
  xset s noblank >/dev/null 2>&1 || true
}

rotate_display_right() {
  local display="$1"
  log "Rotating display '$display' to the right..."
  if ! xrandr --output "$display" --auto --rotate right >/dev/null 2>&1; then
    log "Display rotation failed (xrandr BadMatch). Continuing without rotation."
  fi
}

enable_touch_device() {
  if xinput list --name-only | grep -Fxq "$TOUCH_DEVICE_NAME"; then
    log "Enabling touch device '$TOUCH_DEVICE_NAME'..."
    xinput enable "$TOUCH_DEVICE_NAME" || true
  else
    log "Touch device '$TOUCH_DEVICE_NAME' not found."
  fi
}

map_touch_to_display() {
  local display="$1"

  if xinput list --name-only | grep -Fxq "$TOUCH_DEVICE_NAME"; then
    log "Mapping touch device '$TOUCH_DEVICE_NAME' to display '$display'..."
    xinput map-to-output "$TOUCH_DEVICE_NAME" "$display" || true
  fi
}

reset_touch_matrix() {
  if xinput list --name-only | grep -Fxq "$TOUCH_DEVICE_NAME"; then
    log "Resetting touch matrix to default..."
    xinput set-prop "$TOUCH_DEVICE_NAME" \
      "Coordinate Transformation Matrix" \
      1 0 0 \
      0 1 0 \
      0 0 1 || true
  fi
}


calibrate_touch_device() {
  if xinput list --name-only | grep -Fxq "$TOUCH_DEVICE_NAME"; then

    log "Calibrating touch device '$TOUCH_DEVICE_NAME'..."
    xinput set-prop "$TOUCH_DEVICE_NAME" \
        "Coordinate Transformation Matrix" \
        0 1 0 \
        -1 0 1 \
        0 0 1 || true
  fi
}




start_chrome_kiosk() {
  log "Starting Chrome in kiosk mode..."

  pkill -f "$CHROME_BIN" || true
  sleep 2

  local -a chrome_args=(
    --kiosk
    --start-fullscreen
    --force-device-scale-factor=1.25
    --no-first-run
    --load-extension
    --noerrdialogs
    --disable-infobars
    --disable-session-crashed-bubble
    --disable-features=TranslateUI,OverscrollHistoryNavigation,TouchpadOverscrollHistoryNavigation,PullToRefresh
    --disable-virtual-keyboard
    --touch-events=enabled
    --overscroll-history-navigation=0
    --disable-pinch
  )

  chrome_args+=("$KIOSK_URL")
  "$CHROME_BIN" "${chrome_args[@]}" >/tmp/myway-kiosk-chrome.log 2>&1 &
}

main() {
  wait_for_x
  disable_onscreen_keyboard
  disable_screen_sleep

  DISPLAY_OUTPUT="$(detect_display)"
  log "Detected display: $DISPLAY_OUTPUT"

  #rotate_display_right "$DISPLAY_OUTPUT"
  sleep 1

  enable_touch_device
 # reset_touch_matrix

  
   map_touch_to_display "$DISPLAY_OUTPUT"
   #calibrate_touch_device


  start_chrome_kiosk

  log "Kiosk startup completed."
}

log "Waiting 15 seconds before startup..."
sleep 5
main "$@"