# KlipperCameraControl

Version: `1.1.0`

KlipperCameraControl controls camera exposure, manual focus and autofocus directly from Klipper G-code, using stable USB V4L2 device paths and `v4l2-ctl`.

## Features

- Set camera exposure with a Klipper G-code macro
- Set manual focus from 0 through 250 in steps of 5 (default: 45)
- Enable or disable autofocus without setting a replacement focus value
- Validate exposure values from 3 through 2047
- Detect cameras through stable `/dev/v4l/by-id/usb-*-video-index0` paths
- Optional automatic exposure switching based on a Klipper lightbar output
- Optional manual Moonraker Update Manager integration
- Repeatable install and uninstall scripts

## Requirements

- Klipper and Moonraker
- A Linux V4L2 USB camera supporting `exposure_absolute`
- For focus: `focus_absolute` and `focus_auto` (or `focus_automatic_continuous`)
- `v4l2-ctl` from the `v4l-utils` package
- Bash and Python 3 (no additional Python packages needed for installation)
- Klipper's `gcode_shell_command.py` extension
- The usual Klipper paths at `~/klipper` and `~/printer_data/config`

On Debian-based systems, install the camera utility with:

```bash
sudo apt install v4l-utils
```

## Installation

Clone the repository into the Klipper host user's home directory and run the installer as that user:

```bash
cd ~
git clone https://github.com/HerrHaseGermany/KlipperCameraControl.git
cd KlipperCameraControl
./install.sh
```

The installer verifies the prerequisites, makes both camera scripts executable, installs `camera.cfg` and the optional lightbar template, and adds exactly one `[include camera.cfg]` to `printer.cfg` before `SAVE_CONFIG`. It adds missing sections while preserving existing macros, defaults, timeouts, device overrides and lightbar settings. It updates recognized camera script paths and upgrades the legacy exposure macro's integer validation while keeping its default value.

Changed configs (including `printer.cfg`) receive timestamped `.backup-*` copies. Repeated installation with unchanged settings creates neither additional sections nor backups. Duplicate camera definitions in active includes, including wildcard includes, cause an error before any configs are changed. Remove the extra definition/include and rerun the installer. Custom macro bodies are preserved; review them against `camera.cfg` when upgrading.

Restart Klipper afterward. To enable updates through Moonraker, follow the optional setup below.

For an existing installation, run on the CB2:

```bash
cd /home/biqu/KlipperCameraControl
git pull --ff-only
./install.sh
```

Use `git pull` after the new version has been committed and made available in your remote repository. Restart Klipper from Mainsail, then test the commands below. Installing the macros does not restart Crowsnest.

## Manual exposure control

Set an exposure value between 3 and 2047:

```text
CAM_EXPOSURE VALUE=250
```

The default is `100`. Invalid values are rejected by both the supplied Klipper macro and the shell script. Use plain decimal integers: decimals, text, signs and leading zeroes are rejected rather than converted. The exposure command retains its existing behavior: it sets absolute exposure and does not change the auto-exposure mode. Configure manual exposure in Crowsnest or with `v4l2-ctl` first.

## Manual focus and autofocus

The Logitech C922 uses focus values from `0` to `250`, in steps of `5`:

```text
CAM_FOCUS VALUE=10
CAM_FOCUS VALUE=45
CAM_FOCUS VALUE=100
CAM_FOCUS VALUE=250
CAM_FOCUS
CAM_AUTOFOCUS ON=1
CAM_AUTOFOCUS ON=0
```

`CAM_FOCUS` without a value defaults to `45`. Each manual focus command disables autofocus first, then sets `focus_absolute`. Values such as `41`, `40.5`, `040`, and `abc` produce an error in Mainsail before a shell command runs.

`CAM_AUTOFOCUS` requires `ON=0` or `ON=1`. Disabling autofocus only toggles the automatic mode, allowing the current lens position to remain where the driver supports it; it does not force the default focus value. Actual lens retention depends on the camera and driver. `CAMERA_FOCUS` is not a provided command; use `CAM_FOCUS`.

The installer preserves existing macro defaults. To adopt `45` on an existing installation, change `default(40)` to `default(45)` in the `CAM_FOCUS` macro in `~/printer_data/config/camera.cfg`, then restart Klipper.

## Automatic camera detection

Both scripts use `camera_common.sh`: it prefers a connected C922 and otherwise selects the first available USB V4L2 `video-index0` device matching:

```text
/dev/v4l/by-id/usb-*-video-index0
```

This stable device path is used instead of a potentially changing `/dev/videoX` number. The selected camera's required controls are checked before changing it. The focus range is intended for the C922; other cameras must support the requested values and controls. Exposure-only cameras remain usable with `CAM_EXPOSURE`.

With multiple cameras, select one explicitly by adding `env KCC_DEVICE=...` to **each** installed shell command in `camera.cfg`, keeping the autofocus argument:

```ini
command: env KCC_DEVICE=/dev/v4l/by-id/usb-046d_C922_Pro_Stream_Webcam_E6599CCF-video-index0 /home/biqu/KlipperCameraControl/set_camera_focus.sh
```

For `camera_autofocus`, append `--autofocus`; for `camera_exposure`, use `set_camera_exposure.sh`. The installer preserves these overrides. For direct shell calls, export `KCC_DEVICE`. `KCC_V4L2_CTL` can override the utility path; `KCC_DEVICE_DIR` overrides the detection directory, primarily for testing.

## Crowsnest and startup settings

Use the same stable camera path in `crowsnest.conf`. For the C922 controls reported on this CB2:

```ini
[cam 1]
mode: ustreamer
enable_rtsp: false
rtsp_port: 8554
port: 8080
device: /dev/v4l/by-id/usb-046d_C922_Pro_Stream_Webcam_E6599CCF-video-index0
resolution: 1920x1080
max_fps: 30
v4l2ctl: exposure_auto=1,exposure_auto_priority=0,exposure_absolute=200,focus_auto=0,focus_absolute=45,power_line_frequency=1
```

Use the control names shown by your own `v4l2-ctl --list-ctrls-menus`; names can differ between utility/driver versions. `power_line_frequency=1` selects 50 Hz on this camera. Focus changes through these macros take effect at runtime without restarting Crowsnest. They are not saved to `crowsnest.conf` and may be overwritten at service startup, camera reconnection, or by other tools. Crowsnest's V4 code also contains a focus workaround which can reapply a configured focus value. See its [V4L2 control implementation](https://github.com/mainsail-crew/crowsnest/blob/master/libs/v4l2_control.sh) and [camera configuration reference](https://crowsnest.mainsail.xyz/configuration/cam-section).

For an existing `[cam 1]` section, set `focus_absolute=45` in its `v4l2ctl` line in `~/printer_data/config/crowsnest.conf`, keeping the other controls. Restart Crowsnest to apply the startup setting.

After deliberately restarting Crowsnest or rebooting the CB2, verify the actual values:

```bash
v4l2-ctl -d /dev/v4l/by-id/usb-046d_C922_Pro_Stream_Webcam_E6599CCF-video-index0 --list-ctrls-menus
```

Startup persistence on this printer still needs to be verified. Check `~/printer_data/logs/crowsnest.log` if configured controls are not applied. Keep automatic mode settings before their corresponding manual values in `v4l2ctl`.

On this camera, `exposure_absolute=200` means 20 ms, while `1000` means 100 ms. A 30 FPS target provides approximately 33.3 ms per frame; long exposures can conflict with that target. The optional lightbar's existing off value of `1000` remains available. The [Linux camera control reference](https://docs.kernel.org/userspace-api/media/v4l/ext-ctrls-camera.html) explains exposure units, frame intervals and automatic modes.

## Troubleshooting

- **Unknown command:** run the updated installer, verify `[include camera.cfg]` in `printer.cfg`, then restart Klipper. Use `CAM_FOCUS`, not `CAMERA_FOCUS`.
- **Invalid value:** focus requires whole numbers `0–250` in steps of `5`; exposure requires `3–2047`; autofocus requires `ON=0` or `ON=1`.
- **No camera / cannot read controls:** check `ls -l /dev/v4l/by-id/`, the device override, USB connection and the Klipper user's video-device permissions.
- **Unsupported control / busy device:** inspect `--list-ctrls-menus` and the reported driver error. A failed write exits nonzero and prints `CameraControl ERROR` through the verbose shell command in Mainsail. A failure after disabling autofocus leaves autofocus disabled; no focus success message is printed.
- **Settings revert:** check Crowsnest startup settings and other camera-control clients. Check whether the optional lightbar integration is changing exposure.
- **Duplicate definitions:** remove the extra managed section or redundant include identified by the installer. If a wildcard already includes `camera.cfg`, adjust the wildcard so the explicit camera include loads it once.

## Regression tests

Tests simulate V4L2 calls and a complete Klipper installation in a temporary directory. They do not require a camera, root, or a running printer:

```bash
python3 -m unittest discover -s tests -v
bash tests/test_printer_config.sh
```

The optional macro-rendering tests require Jinja2 (`python3 -m pip install -r tests/requirements.txt`). They test Klipper's template delimiters and ensure invalid inputs cannot produce shell commands. Hardware behavior, stream quality, 30 FPS and startup persistence need a final check on the CB2.

## Optional lightbar integration

The generic camera controller has no lightbar dependency. If the Klipper configuration defines exactly:

```ini
[output_pin lightbar]
```

add the optional config to `printer.cfg`:

```ini
[include camera-lightbar.cfg]
```

Place this include in the normal editable configuration section before Klipper's `SAVE_CONFIG` block, preferably next to `[include camera.cfg]`. Never add or edit configuration inside the auto-generated `SAVE_CONFIG` block.

The lightbar state is checked every 0.5 seconds after an initial 2-second delay. On each state change, exposure is set to `250` when the lightbar is on and `1000` when it is off; manual focus is set to `45` in both states.

Customize the installed `~/printer_data/config/camera-lightbar.cfg`. The current installer preserves existing lightbar macro bodies, including added `CAM_FOCUS` commands and custom values. Existing installations do not automatically receive the new focus commands; add `CAM_FOCUS VALUE=45` directly after each `CAM_EXPOSURE` command if desired. Keep user settings in the installed config, since the repository's `camera-lightbar.cfg` is an updateable template.

Older installers replaced the installed lightbar config. If custom settings were lost, check `camera-lightbar.cfg.backup-*` in the config directory and restore the desired commands before running the current installer.

## Moonraker Update Manager

Add this entry to `moonraker.conf` or your existing included Update Manager configuration file:

```ini
[update_manager KlipperCameraControl]
type: git_repo
channel: dev
path: ~/KlipperCameraControl
origin: https://github.com/HerrHaseGermany/KlipperCameraControl.git
primary_branch: main
is_system_service: False
```

Adjust `path` to your repository location. If you use a separate configuration file, ensure it is included from `moonraker.conf`, for example with `[include my_update_manager.conf]`. Define the entry only once, then restart Moonraker.

The installer and uninstaller leave Moonraker configuration untouched. Files such as `update_camera_control.cfg` created by older versions are preserved; when moving the entry to your own file, remove the old entry and any obsolete include manually.

Moonraker updates the repository but does not run `install.sh`. After updates that change camera config templates, run `./install.sh` and restart Klipper. The installer adds missing sections and preserves existing custom settings, with backups for changed files.

See the [Moonraker Update Manager configuration reference](https://moonraker.readthedocs.io/en/stable/configuration/#git-repo-configuration) for further options.

## Uninstallation

From the repository directory, run:

```bash
./uninstall.sh
```

The uninstaller removes the installed camera configs and their Klipper includes. It preserves this repository, backup files, unrelated Klipper configuration, and all Moonraker configuration. Restart Klipper afterward. If you configured an Update Manager entry, remove it manually from your chosen configuration file and restart Moonraker.

## Target hardware and software

- Klipper
- Moonraker
- Mainsail
- BTT Manta M5P
- BTT CB2
- Logitech C922 Pro Stream Webcam
- Linux V4L2
- `v4l2-ctl`

Exposure and direct V4L2 focus settings were reported working on this setup. The new macros and installer are covered by simulated regression tests; their final printer verification remains pending.

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
