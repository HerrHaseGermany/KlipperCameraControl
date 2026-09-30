#!/bin/bash

set -e

echo
echo "=========================================="
echo " KlipperCameraControl Installer"
echo "=========================================="
echo

# Resolve the user and all installation paths.
CAMERA_USER="${SUDO_USER:-$(id -un)}"
USER_HOME="$(getent passwd "$CAMERA_USER" | cut -d: -f6)"
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

KLIPPER_DIR="$USER_HOME/klipper"
CONFIG_DIR="$USER_HOME/printer_data/config"
CAMERA_TEMPLATE="$PROJECT_DIR/camera.cfg"
LIGHTBAR_TEMPLATE="$PROJECT_DIR/camera-lightbar.cfg"
EXPOSURE_SCRIPT="$PROJECT_DIR/set_camera_exposure.sh"
CAMERA_CONFIG="$CONFIG_DIR/camera.cfg"
LIGHTBAR_CONFIG="$CONFIG_DIR/camera-lightbar.cfg"
PRINTER_CONFIG="$CONFIG_DIR/printer.cfg"
MOONRAKER_CONFIG="$CONFIG_DIR/moonraker.conf"
UPDATE_CONFIG="$CONFIG_DIR/update_camera_control.cfg"
GCODE_SHELL="$KLIPPER_DIR/klippy/extras/gcode_shell_command.py"

echo "User:       $CAMERA_USER"
echo "Home:       $USER_HOME"
echo "Repository: $PROJECT_DIR"
echo "Klipper:    $KLIPPER_DIR"
echo "Config:     $CONFIG_DIR"
echo

# Validate the complete installation before changing anything.
if [ -z "$USER_HOME" ] || [ ! -d "$USER_HOME" ]; then
    echo "ERROR: Could not determine the user home directory."
    exit 1
fi

if [ ! -d "$KLIPPER_DIR" ]; then
    echo "ERROR: Klipper was not found at:"
    echo "$KLIPPER_DIR"
    exit 1
fi

if [ ! -d "$CONFIG_DIR" ]; then
    echo "ERROR: Klipper config directory was not found at:"
    echo "$CONFIG_DIR"
    exit 1
fi

for REQUIRED_FILE in "$CAMERA_TEMPLATE" "$LIGHTBAR_TEMPLATE" "$EXPOSURE_SCRIPT"; do
    if [ ! -f "$REQUIRED_FILE" ]; then
        echo "ERROR: Required repository file was not found:"
        echo "$REQUIRED_FILE"
        exit 1
    fi
done

if [ ! -f "$PRINTER_CONFIG" ]; then
    echo "ERROR: printer.cfg was not found at:"
    echo "$PRINTER_CONFIG"
    exit 1
fi

if [ ! -f "$MOONRAKER_CONFIG" ]; then
    echo "ERROR: moonraker.conf was not found at:"
    echo "$MOONRAKER_CONFIG"
    exit 1
fi

if [ ! -x /usr/bin/v4l2-ctl ]; then
    echo "ERROR: /usr/bin/v4l2-ctl was not found or is not executable."
    echo
    echo "Install v4l-utils and run the installer again:"
    echo
    echo "  sudo apt install v4l-utils"
    echo
    exit 1
fi

if [ ! -f "$GCODE_SHELL" ]; then
    echo "ERROR: gcode_shell_command.py is not installed."
    echo
    echo "KlipperCameraControl requires the Klipper"
    echo "gcode_shell_command.py extension."
    echo
    echo "Install that extension and run the installer again."
    exit 1
fi

echo "gcode_shell_command.py found."

# Camera presence is informative; installation remains possible without one.
CAMERA_FOUND=""
for DEVICE in /dev/v4l/by-id/usb-*-video-index0; do
    if [ -e "$DEVICE" ]; then
        CAMERA_FOUND="$DEVICE"
        break
    fi
done

if [ -n "$CAMERA_FOUND" ]; then
    echo "Camera detected:"
    echo "  $CAMERA_FOUND"
else
    echo "WARNING: No USB V4L2 camera was detected."
    echo "Installation will continue."
fi
echo

chmod +x "$EXPOSURE_SCRIPT"

backup_config() {
    local source_file="$1"
    local backup_file

    if [ ! -f "$source_file" ]; then
        return
    fi

    backup_file="$source_file.backup-$(date +%Y%m%d-%H%M%S)"
    while [ -e "$backup_file" ]; do
        backup_file="$backup_file-1"
    done
    cp -- "$source_file" "$backup_file"
    echo "Existing $(basename "$source_file") backed up to:"
    echo "$backup_file"
}

backup_config "$CAMERA_CONFIG"
backup_config "$LIGHTBAR_CONFIG"

# Install the generic camera config with the absolute repository path.
PROJECT_DIR_ESCAPED="$(printf '%s\n' "$PROJECT_DIR" | sed 's/[&|\\]/\\&/g')"
sed "s|__KLIPPERCAMERACONTROL_PATH__|$PROJECT_DIR_ESCAPED|g" \
    "$CAMERA_TEMPLATE" > "$CAMERA_CONFIG"
cp -- "$LIGHTBAR_TEMPLATE" "$LIGHTBAR_CONFIG"

echo "camera.cfg installed:"
echo "$CAMERA_CONFIG"
echo "Optional camera-lightbar.cfg installed:"
echo "$LIGHTBAR_CONFIG"

# Remove all managed include duplicates, then append exactly one camera include.
TEMP_CONFIG="$(mktemp "$CONFIG_DIR/.printer.cfg.XXXXXX")"
awk '
    $0 ~ /^[[:space:]]*\[include[[:space:]]+camera\.cfg\][[:space:]]*$/ { next }
    { print }
    END { print "[include camera.cfg]" }
' "$PRINTER_CONFIG" > "$TEMP_CONFIG"
chmod --reference="$PRINTER_CONFIG" "$TEMP_CONFIG"
mv -- "$TEMP_CONFIG" "$PRINTER_CONFIG"
echo "Ensured exactly one [include camera.cfg] in printer.cfg."

# Configure Moonraker Update Manager in a project-owned include file.
cat > "$UPDATE_CONFIG" <<EOF_UPDATE
[update_manager KlipperCameraControl]
type: git_repo
path: $PROJECT_DIR
origin: https://github.com/HerrHaseGermany/KlipperCameraControl.git
primary_branch: main
install_script: install.sh
is_system_service: False
EOF_UPDATE

# Normalize the project-owned Moonraker include to exactly one occurrence.
TEMP_CONFIG="$(mktemp "$CONFIG_DIR/.moonraker.conf.XXXXXX")"
awk '
    $0 ~ /^[[:space:]]*\[include[[:space:]]+update_camera_control\.cfg\][[:space:]]*$/ { next }
    { lines[++count] = $0 }
    END {
        print "[include update_camera_control.cfg]"
        for (i = 1; i <= count; i++) print lines[i]
    }
' "$MOONRAKER_CONFIG" > "$TEMP_CONFIG"
chmod --reference="$MOONRAKER_CONFIG" "$TEMP_CONFIG"
mv -- "$TEMP_CONFIG" "$MOONRAKER_CONFIG"
echo "Moonraker Update Manager configured."

echo
echo "=========================================="
echo " KlipperCameraControl installation complete"
echo "=========================================="
echo
echo "Repository:"
echo "  $PROJECT_DIR"
echo
echo "Klipper configuration:"
echo "  $CAMERA_CONFIG"
echo
echo "Optional lightbar integration:"
echo "  If your Klipper configuration defines [output_pin lightbar],"
echo "  add [include camera-lightbar.cfg] to printer.cfg."
echo
echo "Restart Klipper and Moonraker to apply the changes."
echo

exit 0
