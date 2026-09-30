#!/bin/bash

set -e

echo
echo "=========================================="
echo " KlipperCameraControl Installer"
echo "=========================================="
echo

# =========================================================
# Pfade bestimmen
# =========================================================

CAMERA_USER="$(id -un)"
USER_HOME="$(getent passwd "$CAMERA_USER" | cut -d: -f6)"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KLIPPER_DIR="$USER_HOME/klipper"
CONFIG_DIR="$USER_HOME/printer_data/config"

CAMERA_TEMPLATE="$PROJECT_DIR/camera.cfg"
CAMERA_CONFIG="$CONFIG_DIR/camera.cfg"

MOONRAKER_CONFIG="$CONFIG_DIR/moonraker.conf"
UPDATE_CONFIG="$CONFIG_DIR/update_camera_control.cfg"

echo "User:       $CAMERA_USER"
echo "Home:       $USER_HOME"
echo "Repository: $PROJECT_DIR"
echo "Klipper:    $KLIPPER_DIR"
echo "Config:     $CONFIG_DIR"
echo

# =========================================================
# Installation prüfen
# =========================================================

if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "ERROR: Benutzerverzeichnis konnte nicht bestimmt werden."
    exit 1
fi

if [ ! -d "$KLIPPER_DIR" ]; then
    echo "ERROR: Klipper wurde nicht gefunden:"
    echo "$KLIPPER_DIR"
    exit 1
fi

if [ ! -d "$CONFIG_DIR" ]; then
    echo "ERROR: Klipper config directory wurde nicht gefunden:"
    echo "$CONFIG_DIR"
    exit 1
fi

if [ ! -f "$CAMERA_TEMPLATE" ]; then
    echo "ERROR: camera.cfg wurde im Repository nicht gefunden."
    exit 1
fi

if [ ! -f "$PROJECT_DIR/set_camera_exposure.sh" ]; then
    echo "ERROR: set_camera_exposure.sh wurde nicht gefunden."
    exit 1
fi

if ! command -v v4l2-ctl >/dev/null 2>&1; then
    echo "ERROR: v4l2-ctl wurde nicht gefunden."
    echo
    echo "Installiere das Paket v4l-utils und starte den Installer erneut:"
    echo
    echo "  sudo apt install v4l-utils"
    echo
    exit 1
fi

# =========================================================
# USB-Kamera prüfen
# =========================================================

CAMERA_FOUND=""

for DEVICE in /dev/v4l/by-id/usb-*-video-index0; do
    if [ -e "$DEVICE" ]; then
        CAMERA_FOUND="$DEVICE"
        break
    fi
done

if [ -n "$CAMERA_FOUND" ]; then
    echo "Kamera erkannt:"
    echo "  $CAMERA_FOUND"
else
    echo "WARNUNG: Keine USB-V4L2-Kamera erkannt."
    echo "Die Installation wird trotzdem fortgesetzt."
fi

echo

# =========================================================
# Shell-Skript ausführbar machen
# =========================================================

chmod +x "$PROJECT_DIR/set_camera_exposure.sh"

# =========================================================
# gcode_shell_command.py prüfen
# =========================================================

GCODE_SHELL="$KLIPPER_DIR/klippy/extras/gcode_shell_command.py"

if [ ! -e "$GCODE_SHELL" ]; then
    echo "ERROR: gcode_shell_command.py ist nicht installiert."
    echo
    echo "KlipperCameraControl benötigt die Klipper-Erweiterung"
    echo "gcode_shell_command.py."
    echo
    echo "Installiere diese Erweiterung zuerst und starte"
    echo "anschließend den Installer erneut."
    exit 1
fi

echo "gcode_shell_command.py gefunden."

# =========================================================
# Bestehende camera.cfg sichern
# =========================================================

if [ -f "$CAMERA_CONFIG" ]; then
    BACKUP="$CAMERA_CONFIG.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$CAMERA_CONFIG" "$BACKUP"

    echo "Bestehende camera.cfg gesichert:"
    echo "$BACKUP"
fi

# =========================================================
# camera.cfg installieren
# =========================================================

sed \
    "s|__KLIPPERCAMERACONTROL_PATH__|$PROJECT_DIR|g" \
    "$CAMERA_TEMPLATE" > "$CAMERA_CONFIG"

echo "camera.cfg installiert:"
echo "$CAMERA_CONFIG"

# =========================================================
# camera.cfg in printer.cfg einbinden
# =========================================================

PRINTER_CONFIG="$CONFIG_DIR/printer.cfg"

if [ ! -f "$PRINTER_CONFIG" ]; then
    echo "ERROR: printer.cfg wurde nicht gefunden."
    exit 1
fi

if ! grep -qF "[include camera.cfg]" "$PRINTER_CONFIG"; then
    printf '\n[include camera.cfg]\n' >> "$PRINTER_CONFIG"
    echo "[include camera.cfg] zu printer.cfg hinzugefügt."
else
    echo "camera.cfg ist bereits in printer.cfg eingebunden."
fi

# =========================================================
# Moonraker Update Manager
# =========================================================

cat > "$UPDATE_CONFIG" <<EOF_UPDATE
[update_manager KlipperCameraControl]
type: git_repo
path: $PROJECT_DIR
origin: https://github.com/HerrHaseGermany/KlipperCameraControl.git
primary_branch: main
install_script: install.sh
is_system_service: False
EOF_UPDATE

if [ ! -f "$MOONRAKER_CONFIG" ]; then
    echo "ERROR: moonraker.conf wurde nicht gefunden."
    exit 1
fi

if ! grep -qF "[include update_camera_control.cfg]" "$MOONRAKER_CONFIG"; then
    sed -i '1i[include update_camera_control.cfg]' "$MOONRAKER_CONFIG"
    echo "[include update_camera_control.cfg] zu moonraker.conf hinzugefügt."
else
    echo "Moonraker Include ist bereits vorhanden."
fi

echo "Moonraker Update Manager eingerichtet."

# =========================================================
# Fertig
# =========================================================

echo
echo "=========================================="
echo " KlipperCameraControl Installation fertig"
echo "=========================================="
echo
echo "Repository:"
echo "  $PROJECT_DIR"
echo
echo "Klipper-Konfiguration:"
echo "  $CAMERA_CONFIG"
echo
echo "WICHTIG:"
echo "Klipper und Moonraker neu starten."
echo

exit 0
