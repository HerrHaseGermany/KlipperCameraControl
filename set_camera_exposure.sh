#!/bin/bash

set -e

VALUE="$1"

# =========================================================
# Exposure-Wert prüfen
# =========================================================

if ! [[ "$VALUE" =~ ^[0-9]+$ ]]; then
    echo "CameraControl ERROR: Invalid exposure value: $VALUE"
    exit 1
fi

if [ "$VALUE" -lt 3 ] || [ "$VALUE" -gt 2047 ]; then
    echo "CameraControl ERROR: Exposure must be between 3 and 2047"
    exit 1
fi

# =========================================================
# Kamera automatisch erkennen
#
# Bevorzugt wird video-index0 eines USB-V4L2-Geräts.
# Dadurch bleibt der Pfad auch stabil, wenn sich z.B.
# /dev/video9 nach einem Neustart ändert.
# =========================================================

CAMERA=""

for DEVICE in /dev/v4l/by-id/usb-*-video-index0; do
    if [ -e "$DEVICE" ]; then
        CAMERA="$DEVICE"
        break
    fi
done

if [ -z "$CAMERA" ]; then
    echo "CameraControl ERROR: No USB V4L2 camera found."
    exit 1
fi

# =========================================================
# Prüfen, ob Exposure unterstützt wird
# =========================================================

if ! /usr/bin/v4l2-ctl -d "$CAMERA" --list-ctrls 2>/dev/null \
    | grep -q "exposure_absolute"; then

    echo "CameraControl ERROR: Camera does not support exposure_absolute:"
    echo "$CAMERA"
    exit 1
fi

# =========================================================
# Exposure setzen
# =========================================================

/usr/bin/v4l2-ctl \
    -d "$CAMERA" \
    -c exposure_absolute="$VALUE"

echo "CameraControl: exposure_absolute=$VALUE"
echo "CameraControl: camera=$CAMERA"

exit 0
