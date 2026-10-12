"""Render macros with Klipper's Jinja delimiters; optional Jinja2 dependency."""
import importlib.util
from pathlib import Path
import textwrap
import unittest

try:
    import jinja2
except ImportError:
    jinja2 = None

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('camera_config', ROOT / 'camera_config.py')
config = importlib.util.module_from_spec(spec)
spec.loader.exec_module(config)


@unittest.skipIf(jinja2 is None, 'Install tests/requirements.txt to test macro rendering')
class MacroTests(unittest.TestCase):
    def setUp(self):
        self.environment = jinja2.Environment(block_start_string='{%', block_end_string='%}',
                                              variable_start_string='{', variable_end_string='}')
        self.blocks = config.sections((ROOT / 'camera.cfg').read_text())[1]

    def render(self, macro, params):
        body = textwrap.dedent(self.blocks['gcode_macro ' + macro.lower()].split('gcode:\n', 1)[1])
        def fail(message):
            raise ValueError(message)
        return self.environment.from_string(body).render(params=params, action_raise_error=fail)

    def test_valid_commands_and_defaults(self):
        for value in ['0', '10', '40', '100', '250']:
            self.assertIn('CMD=camera_focus PARAMS=' + value,
                          self.render('CAM_FOCUS', {'VALUE': value}))
        self.assertIn('PARAMS=40', self.render('CAM_FOCUS', {}))
        self.assertIn('PARAMS=100', self.render('CAM_EXPOSURE', {}))
        for value in ['3', '200', '1000', '2047']:
            self.assertIn('CMD=camera_exposure PARAMS=' + value,
                          self.render('CAM_EXPOSURE', {'VALUE': value}))
        for value in ['0', '1']:
            self.assertIn('CMD=camera_autofocus PARAMS=' + value,
                          self.render('CAM_AUTOFOCUS', {'ON': value}))

    def test_invalid_values_abort_rendering(self):
        for macro, key, values in [
            ('CAM_FOCUS', 'VALUE', ['', 'abc', '40abc', '40.0', '040', '08', '-5', '5.9',
                                    '+40', ' 40', '251', '1', '999999999999999999999999']),
            ('CAM_EXPOSURE', 'VALUE', ['', 'abc', '100foo', '100.9', '0100', '2', '2048']),
            ('CAM_AUTOFOCUS', 'ON', ['', 'abc', 'true', '01', '1.0', '2', '-1']),
        ]:
            for value in values:
                with self.subTest(macro=macro, value=value), self.assertRaises(ValueError):
                    self.render(macro, {key: value})
        with self.assertRaises(ValueError):
            self.render('CAM_AUTOFOCUS', {})

    def test_legacy_exposure_keeps_default_and_rejects_text(self):
        legacy = ('[gcode_macro CAM_EXPOSURE]\ngcode:\n'
                  '    {% set value = params.VALUE|default(200)|int %}\n'
                  '    RUN_SHELL_COMMAND CMD=camera_exposure PARAMS={value}\n')
        self.blocks = config.sections(config.merge((ROOT / 'camera.cfg').read_text(), legacy, ROOT))[1]
        self.assertIn('PARAMS=200', self.render('CAM_EXPOSURE', {}))
        with self.assertRaises(ValueError):
            self.render('CAM_EXPOSURE', {'VALUE': '200.9'})
