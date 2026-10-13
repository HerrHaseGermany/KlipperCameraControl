"""Hardware-free regression tests: python3 -m unittest discover -s tests -v."""
import importlib.util
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('camera_config', ROOT / 'camera_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


class CameraTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.devices = self.base / 'devices'
        self.devices.mkdir()
        self.generic = self.devices / 'usb-AAA-video-index0'
        self.generic.touch()
        self.c922 = self.devices / 'usb-046d_C922_Pro_Stream_Webcam_SERIAL-video-index0'
        self.c922.touch()
        self.log = self.base / 'calls'
        self.log.touch()
        self.mock = self.base / 'v4l2-ctl'
        self.mock.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$KCC_TEST_LOG"
case "$3" in
    --list-ctrls)
        [ "${KCC_TEST_READ_FAIL:-0}" = 0 ] || { echo 'Permission denied' >&2; exit 1; }
        printf '%s\\n' "${KCC_TEST_CONTROLS:-focus_auto 0x009a090c (bool) : value=1
focus_absolute 0x009a090a (int) : min=0 max=250 step=5 value=40
exposure_absolute 0x009a0902 (int) : min=3 max=2047 step=1 value=200}"
        ;;
    --set-ctrl=*)
        [ "$3" != "${KCC_TEST_FAIL:-}" ] || { echo 'Device or resource busy' >&2; exit 1; }
        ;;
esac
''')
        self.mock.chmod(0o755)
        self.env = dict(os.environ, KCC_DEVICE_DIR=str(self.devices),
                        KCC_V4L2_CTL=str(self.mock), KCC_TEST_LOG=str(self.log))
        self.env.pop('KCC_DEVICE', None)

    def run_script(self, script, *args, ok=True):
        result = subprocess.run(['bash', str(ROOT / script), *args], env=self.env,
                                capture_output=True, text=True)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        if not ok:
            self.assertIn('CameraControl ERROR:', result.stderr)
        return result

    def test_focus_values_and_order(self):
        for value in ['0', '10', '40', '45', '100', '250']:
            self.log.write_text('')
            self.run_script('set_camera_focus.sh', value)
            calls = self.log.read_text().splitlines()
            self.assertEqual(len(calls), 3)
            self.assertTrue(calls[1].endswith('--set-ctrl=focus_auto=0'))
            self.assertTrue(calls[2].endswith('--set-ctrl=focus_absolute=' + value))
            self.assertTrue(all(str(self.c922) in call for call in calls))
        self.run_script('set_camera_focus.sh')
        self.assertTrue(self.log.read_text().rstrip().endswith('focus_absolute=45'))

    def test_invalid_focus_never_contacts_device(self):
        for value in ['', '-5', '251', '255', '1', '08', '040', '40.0', '40abc',
                      ' 40', '+40', '999999999999999999999999', '1;echo bad']:
            self.run_script('set_camera_focus.sh', value, ok=False)
        self.run_script('set_camera_focus.sh', '40', 'extra', ok=False)
        self.assertEqual(self.log.read_text(), '')

    def test_autofocus_does_not_reset_focus(self):
        for value in ['0', '1']:
            self.run_script('set_camera_focus.sh', '--autofocus', value)
        self.assertNotIn('--set-ctrl=focus_absolute', self.log.read_text())
        self.log.write_text('')
        for args in [('--autofocus',), ('--autofocus', '2'), ('--autofocus', '1.0'),
                     ('--autofocus', '01'), ('--autofocus', '1', 'extra')]:
            self.run_script('set_camera_focus.sh', *args, ok=False)
        self.assertEqual(self.log.read_text(), '')

    def test_generic_fallback_and_device_override(self):
        self.c922.unlink()
        self.run_script('set_camera_focus.sh', '40')
        self.assertIn(str(self.generic), self.log.read_text())
        self.env['KCC_DEVICE'] = str(self.generic)
        self.run_script('set_camera_exposure.sh', '200')
        self.env['KCC_DEVICE'] = str(self.base / 'missing')
        self.run_script('set_camera_focus.sh', '40', ok=False)
        self.env.pop('KCC_DEVICE')
        self.generic.unlink()
        self.run_script('set_camera_focus.sh', '40', ok=False)

    def test_unsupported_controls_and_driver_errors(self):
        self.env['KCC_TEST_CONTROLS'] = 'focus_auto_extra 0x123 (bool) : value=1'
        self.run_script('set_camera_focus.sh', '40', ok=False)
        self.env['KCC_TEST_CONTROLS'] = 'focus_auto 0x123 (bool) : value=1'
        self.run_script('set_camera_focus.sh', '40', ok=False)
        self.assertNotIn('--set-ctrl', self.log.read_text())
        self.env.pop('KCC_TEST_CONTROLS')
        self.env['KCC_TEST_READ_FAIL'] = '1'
        result = self.run_script('set_camera_focus.sh', '40', ok=False)
        self.assertIn('Permission denied', result.stderr)
        self.env.pop('KCC_TEST_READ_FAIL')
        self.env['KCC_TEST_FAIL'] = '--set-ctrl=focus_auto=0'
        self.log.write_text('')
        self.run_script('set_camera_focus.sh', '40', ok=False)
        self.assertNotIn('--set-ctrl=focus_absolute', self.log.read_text())
        self.env['KCC_TEST_FAIL'] = '--set-ctrl=focus_absolute=40'
        self.run_script('set_camera_focus.sh', '40', ok=False)

    def test_modern_autofocus_control_name(self):
        self.env['KCC_TEST_CONTROLS'] = ('focus_automatic_continuous 0x123 (bool) : value=1\n'
                                         'focus_absolute 0x124 (int) : value=40')
        self.run_script('set_camera_focus.sh', '40')
        self.assertIn('--set-ctrl=focus_automatic_continuous=0', self.log.read_text())

    def test_exposure_compatibility_and_validation(self):
        for value in ['3', '100', '200', '250', '1000', '2047']:
            self.run_script('set_camera_exposure.sh', value)
        self.assertNotIn('--set-ctrl=focus', self.log.read_text())
        self.log.write_text('')
        for args in [(), ('2',), ('2048',), ('250.5',), ('0250',), ('abc',),
                     ('99999999999999999999999',), ('200', 'extra')]:
            self.run_script('set_camera_exposure.sh', *args, ok=False)
        self.assertEqual(self.log.read_text(), '')

    def install_fixture(self):
        home = self.base / 'home'
        extras = home / 'klipper/klippy/extras'
        extras.mkdir(parents=True)
        (extras / 'gcode_shell_command.py').touch()
        folder = home / 'printer_data/config'
        folder.mkdir(parents=True)
        (folder / 'printer.cfg').write_text('[printer]\nkinematics: cartesian\n'
                                           '#*# <---- SAVE_CONFIG ---->\n#*# z_offset = 1.2\n')
        getent = self.base / 'getent'
        getent.write_text('#!/bin/bash\nprintf "biqu:x:1000:1000::%s:/bin/bash\\n" '
                          + repr(str(home)) + '\n')
        getent.chmod(0o755)
        self.env['PATH'] = str(self.base) + os.pathsep + self.env['PATH']
        self.env['SUDO_USER'] = 'biqu'
        return folder

    def test_repeat_install_preserves_settings_and_backups(self):
        folder = self.install_fixture()
        legacy = ('[gcode_shell_command camera_exposure]\n'
                  'command: /home/biqu/old/set_camera_exposure.sh\ntimeout: 9.\nverbose: True\n'
                  '[gcode_macro CAM_EXPOSURE]\ndescription: My exposure\ngcode:\n'
                  '    {% set value = params.VALUE|default(200)|int %}\n'
                  '    RUN_SHELL_COMMAND CMD=camera_exposure PARAMS={value}\n'
                  '[gcode_macro USER_CAMERA]\ngcode:\n    G4 P100\n')
        (folder / 'camera.cfg').write_text(legacy)
        (folder / 'camera-lightbar.cfg').write_text(
            (ROOT / 'camera-lightbar.cfg').read_text().replace('VALUE=1000', 'VALUE=500'))
        self.run_script('install.sh')
        camera = (folder / 'camera.cfg').read_text()
        self.assertIn('default(200)', camera)
        self.assertIn('raw != value|string', camera)
        self.assertIn('timeout: 9.', camera)
        self.assertIn('[gcode_macro USER_CAMERA]', camera)
        self.assertIn('VALUE=500', (folder / 'camera-lightbar.cfg').read_text())
        self.assertEqual(camera.count('[gcode_macro CAM_FOCUS]'), 1)
        self.assertEqual((folder / 'printer.cfg').read_text().count('[include camera.cfg]'), 1)
        files = {p.name: p.read_bytes() for p in folder.iterdir() if p.is_file()}
        self.run_script('install.sh')
        self.assertEqual(files, {p.name: p.read_bytes() for p in folder.iterdir() if p.is_file()})
        self.assertEqual((folder / 'camera.cfg').stat().st_mode & 0o777, 0o644)

    def test_duplicate_definitions_abort_before_changes(self):
        folder = self.install_fixture()
        printer = folder / 'printer.cfg'
        printer.write_text('[include other*.cfg]\n' + printer.read_text())
        (folder / 'other-macros.cfg').write_text('[gcode_macro CAM_FOCUS]\ngcode:\n    G4 P0\n')
        original = printer.read_bytes()
        result = self.run_script('install.sh', ok=False)
        self.assertIn('Duplicate', result.stderr)
        self.assertEqual(printer.read_bytes(), original)
        self.assertFalse((folder / 'camera.cfg').exists())
        self.assertFalse(list(folder.glob('*.backup-*')))

    def test_lightbar_focus_customizations_survive_repeated_install(self):
        folder = self.install_fixture()
        lightbar = folder / 'camera-lightbar.cfg'
        custom = (ROOT / 'camera-lightbar.cfg').read_text().replace(
            '            CAM_FOCUS VALUE=45', '\t\t\tCAM_FOCUS VALUE=45')
        lightbar.write_text(custom)
        for _ in range(2):
            self.run_script('install.sh')
            self.assertEqual(lightbar.read_text(), custom)
        self.assertFalse(list(folder.glob('camera-lightbar.cfg.backup-*')))

        # A user's focus value must also take precedence over the template.
        custom = custom.replace('CAM_FOCUS VALUE=45', 'CAM_FOCUS VALUE=100')
        lightbar.write_text(custom)
        self.run_script('install.sh')
        self.assertEqual(lightbar.read_text(), custom)
        self.assertFalse(list(folder.glob('camera-lightbar.cfg.backup-*')))

    def test_fresh_install_and_custom_focus_preservation(self):
        folder = self.install_fixture()
        self.run_script('install.sh')
        camera = folder / 'camera.cfg'
        fresh = config.merge((ROOT / 'camera.cfg').read_text(), None, ROOT)
        self.assertEqual(camera.read_text(), fresh)
        camera.write_text(camera.read_text().replace('default(45)', 'default(100)'))
        self.run_script('install.sh')
        self.assertIn('default(100)', camera.read_text())
        self.assertNotIn('default(45)', camera.read_text())

    def test_merge_quotes_paths_and_rejects_duplicate_sections(self):
        project = Path('/home/biqu/camera control')
        merged = config.merge((ROOT / 'camera.cfg').read_text(), None, project)
        self.assertIn("command: '/home/biqu/camera control/set_camera_focus.sh'", merged)
        self.assertEqual(config.merge((ROOT / 'camera.cfg').read_text(), merged, project), merged)
        with self.assertRaises(ValueError):
            config.merge((ROOT / 'camera.cfg').read_text(),
                         '[gcode_macro CAM_FOCUS]\n[gcode_macro cam_focus]\n', ROOT)


if __name__ == '__main__':
    unittest.main()
