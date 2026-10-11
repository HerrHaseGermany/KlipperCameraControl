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
PRINTER_CONFIG_HELPER="$PROJECT_DIR/printer_config.sh"

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

echo
echo "=========================================="
echo " KlipperCameraControl removed"
echo "=========================================="
echo
echo "The repository and all backup files were preserved."
echo "Remove the KlipperCameraControl Update Manager entry manually if configured."
echo "Restart Klipper to apply the changes."
echo "If you edited the Moonraker configuration, restart Moonraker as well."
echo

exit 0
