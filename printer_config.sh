#!/bin/bash

# Transform printer.cfg without changing unrelated bytes. The installer removes
# legacy camera includes below SAVE_CONFIG as a one-time migration. Uninstall
# only removes managed includes from the editable section.
kcc_transform_printer_config() {
    local action="$1"
    local source_file="$2"
    local destination_file="$3"

    python3 - "$action" "$source_file" "$destination_file" <<'PYTHON'
import re
import sys


action, source_path, destination_path = sys.argv[1:]

with open(source_path, "rb") as source:
    data = source.read()

lines = data.splitlines(keepends=True)


def content(line):
    return line.rstrip(b"\r\n")


save_config_re = re.compile(
    rb"^[ \t]*#\*# <[-]+ SAVE_CONFIG [-]+>[ \t]*$"
)
camera_re = re.compile(
    rb"^[ \t]*\[include[ \t]+camera\.cfg\][ \t]*$"
)
lightbar_re = re.compile(
    rb"^[ \t]*\[include[ \t]+camera-lightbar\.cfg\][ \t]*$"
)
include_re = re.compile(
    rb"^[ \t]*\[include[ \t]+[^\]\r\n]+\][ \t]*$"
)
comment_or_blank_re = re.compile(rb"^[ \t]*(?:[#;].*)?$")

marker_index = next(
    (index for index, line in enumerate(lines) if save_config_re.match(content(line))),
    None,
)

if marker_index is None:
    editable = lines
    protected = []
else:
    editable = lines[:marker_index]
    protected = lines[marker_index:]

if action == "install":
    initial_include_indices = []
    for index, line in enumerate(editable):
        line_content = content(line)
        if include_re.match(line_content):
            initial_include_indices.append(index)
            continue
        if comment_or_blank_re.match(line_content):
            continue
        break

    retained = [
        (index, line)
        for index, line in enumerate(editable)
        if not camera_re.match(content(line))
    ]

    if initial_include_indices:
        non_camera_indices = [
            index
            for index in initial_include_indices
            if not camera_re.match(content(editable[index]))
        ]
        if non_camera_indices:
            last_include_index = non_camera_indices[-1]
            insertion_index = sum(
                1 for original_index, _ in retained
                if original_index <= last_include_index
            )
        else:
            first_camera_index = initial_include_indices[0]
            insertion_index = sum(
                1 for original_index, _ in retained
                if original_index < first_camera_index
            )
    else:
        insertion_index = len(retained)

    retained_lines = [line for _, line in retained]
    newline = b"\r\n" if any(line.endswith(b"\r\n") for line in lines) else b"\n"

    if insertion_index > 0 and not retained_lines[insertion_index - 1].endswith((b"\n", b"\r")):
        retained_lines[insertion_index - 1] += newline

    retained_lines.insert(insertion_index, b"[include camera.cfg]" + newline)

    # Migration exception: remove only exact active camera include lines from
    # below SAVE_CONFIG. Every other protected byte remains untouched.
    if protected:
        protected = [
            line for line in protected
            if not camera_re.match(content(line))
        ]

    result = b"".join(retained_lines + protected)
elif action == "uninstall":
    editable = [
        line for line in editable
        if not camera_re.match(content(line))
        and not lightbar_re.match(content(line))
    ]
    result = b"".join(editable + protected)
else:
    raise SystemExit(f"Unknown printer.cfg action: {action}")

with open(destination_path, "wb") as destination:
    destination.write(result)
PYTHON
}
