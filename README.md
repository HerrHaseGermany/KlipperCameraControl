# KlipperCameraControl

Version: `1.0.1`

KlipperCameraControl provides camera exposure control directly from Klipper G-code. It finds a stable USB V4L2 camera device automatically and sets its absolute exposure through `v4l2-ctl`.

## Features

- Set camera exposure with a Klipper G-code macro
- Validate exposure values from 3 through 2047
- Detect cameras through stable `/dev/v4l/by-id/usb-*-video-index0` paths
- Optional automatic exposure switching based on a Klipper lightbar output
- Optional manual Moonraker Update Manager integration
- Repeatable install and uninstall scripts

## Requirements

- Klipper and Moonraker
- A Linux V4L2 USB camera supporting `exposure_absolute`
- `v4l2-ctl` from the `v4l-utils` package
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

The installer verifies the prerequisites, installs `camera.cfg` in the Klipper config directory, and adds exactly one `[include camera.cfg]` to `printer.cfg`. Restart Klipper afterward. To enable updates through Moonraker, follow the optional setup below.

## Manual exposure control

Set an exposure value between 3 and 2047:

```text
CAM_EXPOSURE VALUE=250
```

Invalid values are rejected by both the Klipper macro and the shell script.

## Automatic camera detection

`set_camera_exposure.sh` selects the first available USB V4L2 `video-index0` device matching:

```text
/dev/v4l/by-id/usb-*-video-index0
```

This stable device path is used instead of a potentially changing `/dev/videoX` number. The script also verifies that the selected camera supports `exposure_absolute` before changing it.

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

The lightbar state is checked every 0.5 seconds after an initial 2-second delay. Exposure is set to `250` when the lightbar is on and `1000` when it is off.

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

Moonraker updates the repository but does not run `install.sh`. After updates that change the camera config templates, run `./install.sh` from the repository directory and restart Klipper to apply them. The installer backs up existing camera configs before replacing them; reapply your custom settings as needed.

See the [Moonraker Update Manager configuration reference](https://moonraker.readthedocs.io/en/stable/configuration/#git-repo-configuration) for further options.

## Uninstallation

From the repository directory, run:

```bash
./uninstall.sh
```

The uninstaller removes the installed camera configs and their Klipper includes. It preserves this repository, backup files, unrelated Klipper configuration, and all Moonraker configuration. Restart Klipper afterward. If you configured an Update Manager entry, remove it manually from your chosen configuration file and restart Moonraker.

## Tested hardware and software

- Klipper
- Moonraker
- Mainsail
- BTT Manta M5P
- BTT CB2
- Logitech C922 Pro Stream Webcam
- Linux V4L2
- `v4l2-ctl`

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE).
