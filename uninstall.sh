#!/bin/bash

set -e

echo
echo "=========================================="
echo " KlipperCameraControl Uninstaller"
echo "=========================================="
echo

# =========================================================
# Pfade bestimmen
# =========================================================

CAMERA_USER="$(id -un)"
USER_HOME="$(getent passwd "$CAMERA_USER" | cut -d: -f6)"

CONFIG_DIR="$USER_HOME/printer_data/config"

PRINTER_CONFIG="$CONFIG_DIR/printer.cfg"
CAMERA_CONFIG="$CONFIG_DIR/camera.cfg"

MOONRAKER_CONFIG="$CONFIG_DIR/moonraker.conf"
UPDATE_CONFIG="$CONFIG_DIR/update_camera_control.cfg"

# =========================================================
# camera.cfg Include entfernen
# =========================================================

if [ -f "$PRINTER_CONFIG" ]; then
    sed -i '\|^\[include camera\.cfg\]$|d' "$PRINTER_CONFIG"
    echo "[include camera.cfg] aus printer.cfg entfernt."
fi

# =========================================================
# Installierte camera.cfg entfernen
# =========================================================

if [ -f "$CAMERA_CONFIG" ]; then
    rm -f "$CAMERA_CONFIG"
    echo "camera.cfg entfernt."
fi

# =========================================================
# Moonraker Update Manager entfernen
# =========================================================

if [ -f "$MOONRAKER_CONFIG" ]; then
    sed -i '\|^\[include update_camera_control\.cfg\]$|d' "$MOONRAKER_CONFIG"
    echo "Moonraker Include entfernt."
fi

if [ -f "$UPDATE_CONFIG" ]; then
    rm -f "$UPDATE_CONFIG"
    echo "Update-Manager-Konfiguration entfernt."
fi

# =========================================================
# Fertig
# =========================================================

echo
echo "=========================================="
echo " KlipperCameraControl entfernt"
echo "=========================================="
echo
echo "Das Repository selbst wurde nicht gelöscht."
echo
echo "Klipper und Moonraker neu starten."
echo

exit 0
