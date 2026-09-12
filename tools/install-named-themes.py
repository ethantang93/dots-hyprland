#!/usr/bin/env python3
"""Install the named-theme add-on without replacing other desktop customizations."""
from datetime import datetime
import os
import re
from pathlib import Path
import shutil

ROOT = Path(__file__).resolve().parents[1]
CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
BACKUP = STATE / 'ii-named-themes' / ('install-backup-' + datetime.now().strftime('%Y%m%d-%H%M%S'))


def install(path, content, executable=False):
    if path.exists() and path.read_text() == content:
        return
    if path.exists():
        backup = BACKUP / path.relative_to(Path.home())
        backup.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, backup)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if executable:
        path.chmod(0o755)
    print(path)


def append_once(path, marker, line):
    text = path.read_text() if path.exists() else ''
    if marker not in text:
        install(path, text.rstrip() + '\n\n' + line + '\n')


switch_path = CONFIG / 'quickshell/ii/scripts/colors/switchwall.sh'
live = switch_path.read_text()
reference = (ROOT / 'dots/.config/quickshell/ii/scripts/colors/switchwall.sh').read_text()
if '# Serialize theme and wallpaper changes;' not in live:
    # Prepare every edit before writing. Refuse an unknown upstream script layout.
    start = reference.index('# Serialize theme and wallpaper changes;')
    end = reference.index('\nhandle_kde_material_you_colors()', start)
    assert '\nhandle_kde_material_you_colors()' in live, 'Upstream switchwall changed; review hooks before installing'
    live = live.replace('\nhandle_kde_material_you_colors()', '\n' + reference[start:end] + '\nhandle_kde_material_you_colors()', 1)
    anchor = '        check_and_prompt_upscale "$imgpath" &'
    assert anchor in live, 'Upstream wallpaper handling changed; review hooks before installing'
    live = live.replace(anchor, '        if [[ -z "$named_theme" && "$noswitch_flag" != "1" ]]; then\n' + anchor + '\n        fi', 1)
    for marker, anchor in [('# Named palettes stay selected', '# Determine mode if not set'),
                           ('# Wallpaper selection remains available', "# If type_flag is 'auto', detect scheme type from image (after imgpath is set)")]:
        start = reference.index('    ' + marker)
        end = reference.index('    ' + anchor, start)
        assert '    ' + anchor in live, 'Upstream color generation changed; review hooks before installing'
        live = live.replace('    ' + anchor, reference[start:end] + '    ' + anchor, 1)

# Upgrade an existing installation of the add-on too.
live = live.replace('if [[ -z "$named_theme" ]]; then\n            check_and_prompt_upscale',
                    'if [[ -z "$named_theme" && "$noswitch_flag" != "1" ]]; then\n            check_and_prompt_upscale', 1)
if 'if [[ "${II_THEME_SYNC:-}" == "1" ]]; then' not in live:
    old = '    handle_kde_material_you_colors &\n    "$SCRIPT_DIR/code/material-code-set-color.sh" &'
    assert old in live, 'Upstream post-processing changed; review before installing'
    live = live.replace(old, '''    if [[ "${II_THEME_SYNC:-}" == "1" ]]; then
        handle_kde_material_you_colors
        "$SCRIPT_DIR/code/material-code-set-color.sh"
    else
        handle_kde_material_you_colors &
        "$SCRIPT_DIR/code/material-code-set-color.sh" &
    fi''', 1)
apply_path = CONFIG / 'quickshell/ii/scripts/colors/applycolor.sh'
apply_text = apply_path.read_text()
if 'II_THEME_SYNC' not in apply_text:
    apply_text, count = re.subn(r'(?m)^( +)apply_term &$',
                               r'\1if [[ "${II_THEME_SYNC:-}" == "1" ]]; then apply_term; else apply_term & fi', apply_text)
    assert count == 2, 'Upstream terminal application changed; review before installing'

for name in ['themes.qml', 'modules/ii/themePicker/ThemePickerContent.qml', 'scripts/colors/named-theme.py']:
    install(CONFIG / 'quickshell/ii' / name, (ROOT / 'dots/.config/quickshell/ii' / name).read_text(), name.endswith('.py'))
install(switch_path, live, True)
install(apply_path, apply_text, True)
install(Path.home() / '.local/bin/ii-theme-picker', (ROOT / 'dots/.local/bin/ii-theme-picker').read_text(), True)
install(DATA / 'applications/ii-theme-picker.desktop', (ROOT / 'dots/.local/share/applications/ii-theme-picker.desktop').read_text())

if (CONFIG / 'hypr/hyprland.lua').exists():
    append_once(CONFIG / 'hypr/custom/keybinds.lua', 'ii-theme-picker',
                'hl.bind("CTRL + SUPER + SHIFT + T", hl.dsp.exec_cmd("~/.local/bin/ii-theme-picker"), { description = "Choose named theme" })')
else:
    append_once(CONFIG / 'hypr/custom/keybinds.conf', 'ii-theme-picker',
                'bindd = Ctrl+Super+Shift, T, Choose named theme, exec, ~/.local/bin/ii-theme-picker')
if (CONFIG / 'ghostty/config').exists():
    append_once(CONFIG / 'ghostty/config', 'ghostty-named.conf',
                '# Named themes in end4. Optional when wallpaper colors are active.\n'
                + f'config-file = ?{STATE}/quickshell/user/generated/terminal/ghostty-named.conf')
print('Installed. Run hyprctl reload, then press Ctrl+Super+Shift+T.')
