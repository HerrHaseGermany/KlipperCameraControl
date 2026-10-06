#!/bin/bash

set -e

echo
echo "=========================================="
echo " KlipperCameraControl Uninstaller"
echo "=========================================="
echo

CAMERA_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$CAMERA_USER" | cut -d: -f6)"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="$USER_HOME/printer_data/config"

PRINTER_CONFIG="$CONFIG_DIR/printer.cfg"
CAMERA_CONFIG="$CONFIG_DIR/camera.cfg"
LIGHTBAR_CONFIG="$CONFIG_DIR/camera-lightbar.cfg"
MOONRAKER_CONFIG="$CONFIG_DIR/moonraker.conf"
UPDATE_CONFIG="$CONFIG_DIR/update_camera_control.cfg"
PRINTER_CONFIG_HELPER="$PROJECT_DIR/printer_config.sh"

remove_moonraker_include() {
    local config_file="$1"
    local include_pattern="$2"
    local temp_config

    if [ ! -f "$config_file" ]; then
        return
    fi

    temp_config="$(mktemp "$CONFIG_DIR/.uninstall.cfg.XXXXXX")"
    awk -v pattern="$include_pattern" '$0 !~ pattern { print }' \
        "$config_file" > "$temp_config"
    chmod --reference="$config_file" "$temp_config"
    mv -- "$temp_config" "$config_file"
}

if [ -f "$PRINTER_CONFIG" ]; then
    if [ ! -f "$PRINTER_CONFIG_HELPER" ]; then
        echo "ERROR: printer_config.sh was not found:"
        echo "$PRINTER_CONFIG_HELPER"
        exit 1
    fi
    if ! command -v python3 >/dev/null 2>&1; then
        echo "ERROR: python3 was not found."
        exit 1
    fi

    . "$PRINTER_CONFIG_HELPER"
    TEMP_CONFIG="$(mktemp "$CONFIG_DIR/.printer.cfg.XXXXXX")"
    kcc_transform_printer_config uninstall "$PRINTER_CONFIG" "$TEMP_CONFIG"
    chmod --reference="$PRINTER_CONFIG" "$TEMP_CONFIG"
    mv -- "$TEMP_CONFIG" "$PRINTER_CONFIG"
    echo "KlipperCameraControl includes removed before SAVE_CONFIG (if present)."
fi

if [ -f "$CAMERA_CONFIG" ]; then
    rm -- "$CAMERA_CONFIG"
    echo "camera.cfg removed."
fi

if [ -f "$LIGHTBAR_CONFIG" ]; then
    rm -- "$LIGHTBAR_CONFIG"
    echo "camera-lightbar.cfg removed."
fi

remove_moonraker_include "$MOONRAKER_CONFIG" \
    '^[[:space:]]*\[include[[:space:]]+update_camera_control\.cfg\][[:space:]]*$'

if [ -f "$UPDATE_CONFIG" ]; then
    rm -- "$UPDATE_CONFIG"
    echo "Moonraker Update Manager configuration removed."
fi

echo
echo "=========================================="
echo " KlipperCameraControl removed"
echo "=========================================="
echo
echo "The repository and all backup files were preserved."
echo "Restart Klipper and Moonraker to apply the changes."
echo

exit 0
