#!/bin/bash
set -euo pipefail
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/camera_common.sh"

[ "$#" -eq 1 ] || kcc_error "Usage: set_camera_exposure.sh VALUE"
VALUE="$1"
kcc_validate_integer "$VALUE" 3 2047 1 Exposure
kcc_camera_init
kcc_require_control exposure_absolute
kcc_set_control "exposure_absolute=$VALUE"
echo "CameraControl: exposure_absolute=$VALUE"
echo "CameraControl: camera=$CAMERA"
