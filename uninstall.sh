#!/bin/bash

set -e

echo
echo "=========================================="
echo " KlipperCameraControl Uninstaller"
echo "=========================================="
echo

CAMERA_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$CAMERA_USER" | cut -d: -f6)"
CONFIG_DIR="$USER_HOME/printer_data/config"

PRINTER_CONFIG="$CONFIG_DIR/printer.cfg"
CAMERA_CONFIG="$CONFIG_DIR/camera.cfg"
LIGHTBAR_CONFIG="$CONFIG_DIR/camera-lightbar.cfg"
MOONRAKER_CONFIG="$CONFIG_DIR/moonraker.conf"
UPDATE_CONFIG="$CONFIG_DIR/update_camera_control.cfg"

remove_include() {
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

remove_include "$PRINTER_CONFIG" \
    '^[[:space:]]*\[include[[:space:]]+camera\.cfg\][[:space:]]*$'
remove_include "$PRINTER_CONFIG" \
    '^[[:space:]]*\[include[[:space:]]+camera-lightbar\.cfg\][[:space:]]*$'
echo "KlipperCameraControl includes removed from printer.cfg (if present)."

if [ -f "$CAMERA_CONFIG" ]; then
    rm -- "$CAMERA_CONFIG"
    echo "camera.cfg removed."
fi

if [ -f "$LIGHTBAR_CONFIG" ]; then
    rm -- "$LIGHTBAR_CONFIG"
    echo "camera-lightbar.cfg removed."
fi

remove_include "$MOONRAKER_CONFIG" \
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
