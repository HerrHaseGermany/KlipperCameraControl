#!/bin/bash
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/camera_common.sh"

if [ "${1:-}" = "--autofocus" ]; then
    [ "$#" -eq 2 ] || kcc_error "Usage: set_camera_focus.sh --autofocus 0|1"
    [[ "$2" = 0 || "$2" = 1 ]] || kcc_error "Autofocus ON must be 0 or 1; received: $2"
    kcc_camera_init
    kcc_focus_control
    # Toggle only autofocus, without overwriting the lens position with a default.
    # Whether the camera retains its current position depends on its driver.
    kcc_set_control "$AUTOFOCUS_CONTROL=$2"
    echo "CameraControl: $AUTOFOCUS_CONTROL=$2"
else
    [ "$#" -le 1 ] || kcc_error "Usage: set_camera_focus.sh [VALUE]"
    FOCUS="${1-40}"
    kcc_validate_integer "$FOCUS" 0 250 5 Focus
    kcc_camera_init
    kcc_focus_control
    kcc_require_control focus_absolute
    # Separate calls guarantee autofocus is disabled before manual focusing.
    kcc_set_control "$AUTOFOCUS_CONTROL=0"
    kcc_set_control "focus_absolute=$FOCUS"
    echo "CameraControl: focus_absolute=$FOCUS"
fi
echo "CameraControl: camera=$CAMERA"
