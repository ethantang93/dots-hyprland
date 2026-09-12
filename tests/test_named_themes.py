"""Run with python -m unittest discover -s tests -p test_named_themes.py."""
import importlib.util
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
import time
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / 'dots/.config/quickshell/ii/scripts/colors/named-theme.py'
spec = importlib.util.spec_from_file_location('named_theme', SCRIPT)
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)
REAL_COMMAND = theme.command


class NamedThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        config, state, data = [self.base / s for s in ('config', 'state', 'data')]
        self.paths = dict(CONFIG=config, STATE=state, DATA=data,
                          THEMES=config / 'omarchy/themes', GENERATED=state / 'quickshell/user/generated',
                          SETTINGS=config / 'illogical-impulse/config.json',
                          ACTIVE=config / 'illogical-impulse/named-theme.json',
                          SNAPSHOT=state / 'ii-named-themes/restore.json')
        self.patch = patch.multiple(theme, **self.paths)
        self.patch.start()
        self.addCleanup(self.patch.stop)
        shutil.copytree(ROOT / 'dots/.config/matugen', config / 'matugen')
        self.commands = []

        def fake_command(*args, **kwargs):
            self.commands.append(args)
            if args[:2] == ('gsettings', 'get'):
                return "'prefer-dark'" if args[-1] == 'color-scheme' else "'adw-gtk3-dark'"
            if args[0] == 'kreadconfig6':
                return 'OriginalScheme'
            return ''

        self.command_patch = patch.object(theme, 'command', fake_command)
        self.command_patch.start()
        self.addCleanup(self.command_patch.stop)
        colors = ['#15161e', '#f7768e', '#9ece6a', '#e0af68', '#7aa2f7', '#bb9af7', '#7dcfff', '#a9b1d6'] * 2
        for name, bg, fg in [('test-dark', '#1a1b26', '#c0caf5'), ('test-light', '#eff1f5', '#4c4f69')]:
            lines = [f'background {bg}', f'foreground {fg}']
            lines += [f'color{i} {color}' for i, color in enumerate(colors)]
            theme.write(theme.THEMES / name / 'kitty.conf', '\n'.join(lines))
        theme.write(theme.SETTINGS, json.dumps({'background': {'wallpaperPath': '/old-wall.jpg'}}))
        theme.write(theme.GENERATED / 'colors.json', '{"original":true}\n')
        link = config / 'omarchy/current/theme'
        link.parent.mkdir(parents=True)
        link.symlink_to(theme.THEMES / 'test-dark')

    def test_named_palettes_preserve_colors_and_render_all_roles(self):
        for name in ('test-dark', 'test-light'):
            p, files = theme.outputs(name, '/wall.jpg')
            material = json.loads(files[theme.GENERATED / 'colors.json'])
            self.assertEqual(len(material), 49)
            self.assertEqual(material['background'], p['background'])
            self.assertEqual(material['on_background'], p['foreground'])
            self.assertTrue(all('{{' not in text for text in files.values()))
            for role in ('primary', 'secondary', 'tertiary', 'error'):
                self.assertGreaterEqual(theme.contrast(material[role], material['on_' + role]), 4.5)
            kitty = files[theme.GENERATED / 'terminal/kitty-theme.conf']
            self.assertIn('color4 #7aa2f7', kitty)

    def test_multiple_switches_restore_original_and_remove_created_files(self):
        theme.apply('test-dark')
        theme.apply('test-light')
        self.assertEqual(theme.read_json(theme.ACTIVE)['id'], 'test-light')
        self.assertEqual(json.loads((theme.GENERATED / 'colors.json').read_text())['background'], '#eff1f5')
        theme.restore(False)
        self.assertEqual((theme.GENERATED / 'colors.json').read_text(), '{"original":true}\n')
        self.assertFalse((theme.GENERATED / 'terminal/ghostty-named.conf').exists())
        self.assertEqual(list((theme.DATA / 'color-schemes').glob('*.colors')), [])
        self.assertEqual(os.readlink(theme.CONFIG / 'omarchy/current/theme'), str(theme.THEMES / 'test-dark'))
        self.assertEqual(theme.read_json(theme.ACTIVE)['id'], '')
        self.assertIn(('plasma-apply-colorscheme', 'OriginalScheme'), self.commands)

    def test_semantic_toml_theme_without_kitty_config(self):
        name = 'semantic-light'
        source = '''mode = "light"
background = "#fafafa"
foreground = "#212121"
accent = "#3264eb"
muted = "#9e9e9e"
selection = "#d0d0d0"
bright_foreground = "#000000"
red = "#c900c4"
green = "#4a2fd0"
yellow = "#026fde"
blue = "#3264eb"
magenta = "#8a4ad7"
cyan = "#0c67de"
bright_blue = "#5482ff"
'''
        theme.write(theme.THEMES / name / 'colors.toml', source)
        p, files = theme.outputs(name, '')
        self.assertEqual(p['color0'], '#fafafa')
        self.assertEqual(p['color4'], '#3264eb')
        self.assertEqual(p['color12'], '#5482ff')
        self.assertEqual(p['color15'], '#000000')
        self.assertEqual(p['selection_background'], '#d0d0d0')
        entry = next(t for t in theme.catalog()['themes'] if t['id'] == name)
        self.assertFalse(entry['dark'])
        self.assertTrue(all('{{' not in text for text in files.values()))

    def test_write_failure_rolls_back_to_previously_active_theme(self):
        theme.apply('test-dark')
        original = (theme.GENERATED / 'colors.json').read_bytes()
        real_write = theme.write
        failed = False

        def fail_once(path, text):
            nonlocal failed
            if path == theme.CONFIG / 'gtk-3.0/gtk.css' and not failed:
                failed = True
                raise OSError('simulated disk error')
            return real_write(path, text)

        with patch.object(theme, 'write', fail_once), self.assertRaises(OSError):
            theme.apply('test-light')
        self.assertEqual(theme.read_json(theme.ACTIVE)['id'], 'test-dark')
        self.assertEqual((theme.GENERATED / 'colors.json').read_bytes(), original)

    def test_invalid_theme_does_not_mutate_state(self):
        before = (theme.GENERATED / 'colors.json').read_bytes()
        with self.assertRaises(ValueError):
            theme.apply('../test-dark')
        self.assertFalse(theme.ACTIVE.exists())
        self.assertEqual((theme.GENERATED / 'colors.json').read_bytes(), before)

    def test_command_does_not_wait_for_background_output_handles(self):
        code = 'import subprocess,sys; subprocess.Popen([sys.executable,"-c","import time; time.sleep(2)"]); print("finished")'
        started = time.monotonic()
        self.assertEqual(REAL_COMMAND(sys.executable, '-c', code, timeout=1), 'finished')
        self.assertLess(time.monotonic() - started, 1)

    def test_timeout_stops_the_entire_command_group(self):
        marker = self.base / 'child-finished'
        child = f'import time,pathlib; time.sleep(.7); pathlib.Path({str(marker)!r}).touch()'
        parent = f'import subprocess,sys,time; subprocess.Popen([sys.executable,"-c",{child!r}]); time.sleep(10)'
        with self.assertRaises(TimeoutError):
            REAL_COMMAND(sys.executable, '-c', parent, timeout=.2)
        time.sleep(.8)
        self.assertFalse(marker.exists())

    def test_lock_wait_is_bounded(self):
        path = self.base / 'theme.lock'
        with path.open('w') as held, path.open('w') as blocked:
            fcntl.flock(held, fcntl.LOCK_EX)
            with self.assertRaises(TimeoutError):
                theme.acquire_lock(blocked, timeout=.1)

    def test_wallpaper_change_and_mode_toggle_keep_named_palette(self):
        theme.apply('test-dark')
        before = (theme.GENERATED / 'colors.json').read_bytes()
        tools = self.base / 'bin'
        tools.mkdir()
        scripts = {
            'hyprctl': '#!/bin/sh\nif [ "$1" = monitors ]; then echo \'[{"focused":true,"width":1920,"height":1080,"scale":1,"x":0,"y":0}]\'; else echo \'{"x":0,"y":0}\'; fi\n',
            'pkill': '#!/bin/sh\nexit 0\n',
            'matugen': '#!/bin/sh\ntouch "$XDG_STATE_HOME/unwanted-generation"\n',
            'gsettings': '#!/bin/sh\ntouch "$XDG_STATE_HOME/unwanted-generation"\n'
        }
        for name, text in scripts.items():
            (tools / name).write_text(text)
            (tools / name).chmod(0o755)
        (theme.CONFIG / 'hypr/custom/scripts').mkdir(parents=True)
        env = dict(os.environ, XDG_CONFIG_HOME=str(theme.CONFIG), XDG_STATE_HOME=str(theme.STATE),
                   XDG_CACHE_HOME=str(self.base / 'cache'), PATH=str(tools) + os.pathsep + os.environ['PATH'])
        for args in [('--image', '/new-wall.jpg'), ('--mode', 'light', '--noswitch')]:
            proc = subprocess.run(['bash', str(SCRIPT.with_name('switchwall.sh')), *args],
                                  env=env, text=True, capture_output=True, timeout=10)
            self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertEqual(theme.read_json(theme.SETTINGS)['background']['wallpaperPath'], '/new-wall.jpg')
        self.assertEqual((theme.GENERATED / 'colors.json').read_bytes(), before)
        self.assertFalse((theme.STATE / 'unwanted-generation').exists())


if __name__ == '__main__':
    unittest.main()
