#!/bin/bash

set -eu

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
. "$PROJECT_DIR/printer_config.sh"

TEST_DIR="$(mktemp -d)"
trap 'rm -rf -- "$TEST_DIR"' EXIT

transform() {
    local action="$1"
    local fixture="$2"
    local output="$fixture.output"

    kcc_transform_printer_config "$action" "$fixture" "$output"
    mv -- "$output" "$fixture"
}

assert_files_equal() {
    if ! cmp -s "$1" "$2"; then
        echo "FAIL: files differ: $1 $2" >&2
        diff -u "$1" "$2" >&2 || true
        exit 1
    fi
}

# SAVE_CONFIG, initial include block, duplicates, commented include, optional
# lightbar include, and a legacy camera include below SAVE_CONFIG.
cat > "$TEST_DIR/with-save.cfg" <<'EOF_FIXTURE'
# Printer includes
[include mainsail.cfg]
#[include disabled.cfg]
[include camera.cfg]
[include camera-lightbar.cfg]
[include camera.cfg]

[printer]
kinematics: corexy

#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.
#*#
#*# [bed_mesh default]
#*# points =
#*#   0.1, 0.2
[include camera.cfg]
#*# z_offset = 1.234
EOF_FIXTURE

cat > "$TEST_DIR/with-save.expected" <<'EOF_EXPECTED'
# Printer includes
[include mainsail.cfg]
#[include disabled.cfg]
[include camera-lightbar.cfg]
[include camera.cfg]

[printer]
kinematics: corexy

#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW. The contents are auto-generated.
#*#
#*# [bed_mesh default]
#*# points =
#*#   0.1, 0.2
#*# z_offset = 1.234
EOF_EXPECTED

transform install "$TEST_DIR/with-save.cfg"
assert_files_equal "$TEST_DIR/with-save.expected" "$TEST_DIR/with-save.cfg"
cp -- "$TEST_DIR/with-save.cfg" "$TEST_DIR/with-save.once"
transform install "$TEST_DIR/with-save.cfg"
assert_files_equal "$TEST_DIR/with-save.once" "$TEST_DIR/with-save.cfg"

# Without SAVE_CONFIG and without an initial include block, append the include.
cat > "$TEST_DIR/without-save.cfg" <<'EOF_FIXTURE'
[printer]
kinematics: cartesian
EOF_FIXTURE

cat > "$TEST_DIR/without-save.expected" <<'EOF_EXPECTED'
[printer]
kinematics: cartesian
[include camera.cfg]
EOF_EXPECTED

transform install "$TEST_DIR/without-save.cfg"
assert_files_equal "$TEST_DIR/without-save.expected" "$TEST_DIR/without-save.cfg"
transform install "$TEST_DIR/without-save.cfg"
assert_files_equal "$TEST_DIR/without-save.expected" "$TEST_DIR/without-save.cfg"

# With SAVE_CONFIG but no initial include block, insert immediately before it.
cat > "$TEST_DIR/no-include-block.cfg" <<'EOF_FIXTURE'
[printer]
kinematics: cartesian
#*# <---------------------- SAVE_CONFIG ---------------------->
#*# pid_kp = 22.2
EOF_FIXTURE

cat > "$TEST_DIR/no-include-block.expected" <<'EOF_EXPECTED'
[printer]
kinematics: cartesian
[include camera.cfg]
#*# <---------------------- SAVE_CONFIG ---------------------->
#*# pid_kp = 22.2
EOF_EXPECTED

transform install "$TEST_DIR/no-include-block.cfg"
assert_files_equal "$TEST_DIR/no-include-block.expected" "$TEST_DIR/no-include-block.cfg"

# Uninstall removes both managed includes only above SAVE_CONFIG. The protected
# block, including an include-looking line, remains byte-for-byte unchanged.
cat > "$TEST_DIR/uninstall.cfg" <<'EOF_FIXTURE'
[include mainsail.cfg]
[include camera.cfg]
[include camera-lightbar.cfg]
[printer]
kinematics: corexy
#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW.
[include camera.cfg]
#*# z_offset = 2.345
EOF_FIXTURE

cat > "$TEST_DIR/uninstall.expected" <<'EOF_EXPECTED'
[include mainsail.cfg]
[printer]
kinematics: corexy
#*# <---------------------- SAVE_CONFIG ---------------------->
#*# DO NOT EDIT THIS BLOCK OR BELOW.
[include camera.cfg]
#*# z_offset = 2.345
EOF_EXPECTED

transform uninstall "$TEST_DIR/uninstall.cfg"
assert_files_equal "$TEST_DIR/uninstall.expected" "$TEST_DIR/uninstall.cfg"

echo "printer.cfg regression tests passed"
