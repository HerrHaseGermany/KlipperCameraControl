#!/bin/bash
# Shared device detection and V4L2 error handling. Sourced by camera scripts.
kcc_error() {
    echo "CameraControl ERROR: $*" >&2
    exit 1
}

# Reject noncanonical integers before arithmetic (including overflow/octal).
kcc_validate_integer() {
    local value="$1" minimum="$2" maximum="$3" step="$4" label="$5"
    if ! [[ "$value" =~ ^(0|[1-9][0-9]{0,3})$ ]] ||
        (( value < minimum || value > maximum || (value - minimum) % step != 0 )); then
        kcc_error "$label must be an integer from $minimum to $maximum (step $step); received: $value"
    fi
}

kcc_detect_camera() {
    local device device_dir="${KCC_DEVICE_DIR:-/dev/v4l/by-id}"
    CAMERA="${KCC_DEVICE:-}"
    if [ -z "$CAMERA" ]; then
        # Prefer the C922, then retain generic USB camera support.
        for device in "$device_dir"/usb-*C922*-video-index0 "$device_dir"/usb-*-video-index0; do
            if [ -e "$device" ]; then
                CAMERA="$device"
                break
            fi
        done
    fi
    [ -n "$CAMERA" ] && [ -e "$CAMERA" ]
}

kcc_camera_init() {
    V4L2_CTL="${KCC_V4L2_CTL:-/usr/bin/v4l2-ctl}"
    [ -x "$V4L2_CTL" ] || kcc_error "v4l2-ctl is unavailable: $V4L2_CTL. Install v4l-utils."
    kcc_detect_camera ||
        kcc_error "No accessible USB V4L2 camera found: ${CAMERA:-${KCC_DEVICE_DIR:-/dev/v4l/by-id}}. Check connection and KCC_DEVICE."
    CONTROLS="$("$V4L2_CTL" -d "$CAMERA" --list-ctrls 2>&1)" ||
        kcc_error "Cannot read controls for $CAMERA (check permissions): $CONTROLS"
}

kcc_has_control() {
    [[ "$CONTROLS" =~ (^|$'\n')[[:blank:]]*$1[[:blank:]] ]]
}

kcc_require_control() {
    kcc_has_control "$1" || kcc_error "Camera $CAMERA does not support $1."
}

kcc_focus_control() {
    if kcc_has_control focus_auto; then
        AUTOFOCUS_CONTROL=focus_auto
    elif kcc_has_control focus_automatic_continuous; then
        AUTOFOCUS_CONTROL=focus_automatic_continuous
    else
        kcc_error "Camera $CAMERA does not support autofocus (focus_auto)."
    fi
}

kcc_set_control() {
    local output
    output="$("$V4L2_CTL" -d "$CAMERA" --set-ctrl="$1" 2>&1)" ||
        kcc_error "Failed to set $1 on $CAMERA: $output"
}
