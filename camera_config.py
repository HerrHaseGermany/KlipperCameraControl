#!/usr/bin/env python3
"""Merge camera sections and check managed definitions in Klipper includes."""
import glob
import fnmatch
import re
import shlex
import sys
from pathlib import Path

HEADER = re.compile(r'^[ \t]*\[([^\]\n]+)\][ \t]*(?:[#;].*)?$', re.MULTILINE)
MANAGED = {
    'gcode_shell_command camera_exposure', 'gcode_shell_command camera_focus',
    'gcode_shell_command camera_autofocus', 'gcode_macro cam_exposure',
    'gcode_macro cam_focus', 'gcode_macro cam_autofocus',
    'gcode_macro _lightbar_state', 'delayed_gcode watch_lightbar',
}


def sections(text):
    matches = list(HEADER.finditer(text))
    result = {}
    for index, match in enumerate(matches):
        name = match[1].strip().lower()
        if name in result:
            raise ValueError('Duplicate section: ' + match[1])
        end = matches[index + 1].start() if index + 1 < len(matches) else len(text)
        result[name] = text[match.start():end]
    return text[:matches[0].start()] if matches else text, result


def merge(template, existing, project):
    rendered = template.replace('__KLIPPERCAMERACONTROL_PATH__', str(project))
    prefix, defaults = sections(rendered)
    if existing is None:
        current = defaults.copy()
        original_names = set()
    else:
        prefix, current = sections(existing)
        original_names = set(current)
        for name, block in defaults.items():
            if name not in current:
                current[name] = block
    for name, block in current.items():
        if name in defaults and name.startswith('gcode_shell_command '):
            script = ('set_camera_exposure.sh' if name.endswith('camera_exposure')
                      else 'set_camera_focus.sh')
            def update_command(match):
                tokens = shlex.split(match[1])
                for index, token in enumerate(tokens):
                    if Path(token).name == script:
                        tokens[index] = str(project / script)
                return 'command: ' + ' '.join(shlex.quote(token) for token in tokens)
            # Quotes make repository paths containing spaces safe for shlex.
            # For a fresh template, quote its full path before tokenizing.
            if name not in original_names:
                block = block.replace(str(project / script), shlex.quote(str(project / script)))
            block = re.sub(r'^command:[ \t]*(.*)$', update_command, block, flags=re.MULTILINE)
        if name == 'gcode_macro cam_exposure':
            # Upgrade the legacy integer conversion while keeping its default,
            # surrounding user code, description and other settings intact.
            block = re.sub(
                r'^( +)\{% set value = params.VALUE\|default\(([^\n]+)\)\|int %\}',
                lambda m: m[1] + '{% set raw = params.VALUE|default(' + m[2] + ')|string %}\n'
                + m[1] + '{% set value = raw|int(-1) %}\n'
                + m[1] + '{% if raw != value|string %}\n'
                + m[1] + '    { action_raise_error("Exposure must be an integer between 3 and 2047") }\n'
                + m[1] + '{% endif %}', block, flags=re.MULTILINE)
        current[name] = block
    # Separate appended sections even if an existing file has no final newline.
    return prefix + '\n\n'.join(block.rstrip('\n') for block in current.values()) + '\n'


def check_definitions(printer, camera, lightbar, staged_printer=None):
    overrides = {
        printer.resolve(): (staged_printer or printer).read_text(),
        (printer.parent / 'camera.cfg').resolve(): camera.read_text(),
        (printer.parent / 'camera-lightbar.cfg').resolve(): lightbar.read_text(),
    }
    found = {}

    def visit(path, stack):
        path = path.resolve()
        if path in stack:
            raise ValueError('Recursive Klipper include: ' + str(path))
        text = overrides[path] if path in overrides else path.read_text()
        # SAVE_CONFIG is protected, and not an active include source.
        text = re.split(r'^#\*# <[-]+ SAVE_CONFIG [-]+>.*$', text, flags=re.MULTILINE)[0]
        for match in HEADER.finditer(text):
            name = match[1].strip()
            normalized = name.lower()
            if normalized.startswith('include '):
                pattern = str(path.parent / name.split(None, 1)[1])
                paths = sorted(glob.glob(pattern))
                # A new camera.cfg may not exist on disk yet.
                for target in overrides:
                    if fnmatch.fnmatch(str(target), pattern) and str(target) not in paths:
                        paths.append(str(target))
                for included in paths:
                    visit(Path(included), stack + [path])
            elif normalized in MANAGED:
                if normalized in found:
                    raise ValueError(f'Duplicate [{name}] in {found[normalized]} and {path}; '
                                     'remove the extra definition/include before installing.')
                found[normalized] = path
    visit(printer, [])


def main():
    action, *args = sys.argv[1:]
    if action == 'merge':
        template, existing, project, destination = map(Path, args)
        destination.write_text(merge(template.read_text(),
                                    existing.read_text() if existing.exists() else None, project))
    elif action == 'check':
        # The staged printer file must resolve includes relative to CONFIG_DIR.
        printer, staged_printer, camera, lightbar = map(Path, args)
        check_definitions(printer, camera, lightbar, staged_printer)
    else:
        raise ValueError('Unknown action: ' + action)


if __name__ == '__main__':
    try:
        main()
    except (ValueError, OSError) as error:
        sys.exit('CameraControl ERROR: ' + str(error))
