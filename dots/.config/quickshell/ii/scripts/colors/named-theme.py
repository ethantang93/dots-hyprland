#!/usr/bin/env python3
"""Named Omarchy palettes for ii. Only color data is imported from themes."""
import argparse
import base64
import fcntl
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import tempfile
import tomllib

CONFIG = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
STATE = Path(os.environ.get('XDG_STATE_HOME', Path.home() / '.local/state'))
DATA = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
HERE = Path(__file__).resolve().parent
THEMES = CONFIG / 'omarchy/themes'
GENERATED = STATE / 'quickshell/user/generated'
SETTINGS = CONFIG / 'illogical-impulse/config.json'
ACTIVE = CONFIG / 'illogical-impulse/named-theme.json'
SNAPSHOT = STATE / 'ii-named-themes/restore.json'
HEX = re.compile(r'^#[0-9a-fA-F]{6}$')


def read_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else (default or {})


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=path.parent, mode='w', delete=False) as f:
        f.write(text)
        temp = Path(f.name)
    temp.replace(path)


def command(*args, check=False, env=None):
    try:
        return subprocess.run(args, text=True, capture_output=True, timeout=45,
                              check=check, env=env).stdout.strip()
    except FileNotFoundError:
        if check:
            raise
        return ''


def rgb(value):
    return tuple(int(value[i:i + 2], 16) for i in (1, 3, 5))


def mix(a, b, amount):
    return '#' + ''.join(f'{round(x * (1 - amount) + y * amount):02x}'
                         for x, y in zip(rgb(a), rgb(b)))


def luminance(value):
    c = [v / 255 for v in rgb(value)]
    c = [v / 12.92 if v <= .04045 else ((v + .055) / 1.055) ** 2.4 for v in c]
    return sum(x * y for x, y in zip(c, (.2126, .7152, .0722)))


def contrast(a, b):
    lo, hi = sorted((luminance(a), luminance(b)))
    return (hi + .05) / (lo + .05)


def readable(background, *choices):
    return max(choices, key=lambda c: contrast(background, c))


def palette(name):
    if not re.fullmatch(r'[a-zA-Z0-9_-]+', name):
        raise ValueError('Invalid theme name')
    folder = THEMES / name
    colors = {}
    if (folder / 'kitty.conf').exists():
        for line in (folder / 'kitty.conf').read_text().splitlines():
            parts = line.split()
            if len(parts) >= 2 and HEX.fullmatch(parts[1]):
                colors[parts[0]] = parts[1].lower()
    semantic = {}
    if (folder / 'colors.toml').exists():
        raw = tomllib.loads((folder / 'colors.toml').read_text())
        semantic = {k: v.lower() for k, v in raw.items() if isinstance(v, str) and HEX.fullmatch(v)}
        # Omarchy 4 semantic palette, with compatibility for older colorN TOML files.
        for key, alias in [('background', 'bg'), ('foreground', 'fg'), ('bright_foreground', 'bright_fg')]:
            if alias in semantic:
                semantic.setdefault(key, semantic[alias])
        semantic.setdefault('background', semantic.get('color0', colors.get('background')))
        semantic.setdefault('foreground', semantic.get('color7', colors.get('foreground')))
        for key in ('background', 'foreground'):
            if not semantic.get(key):
                raise ValueError(f'{name}: missing {key} in colors.toml')
            colors[key] = semantic[key]
        for i, key in enumerate(('red', 'green', 'yellow', 'blue', 'magenta', 'cyan'), 1):
            value = semantic.get(key, semantic.get(f'color{i}', colors.get(f'color{i}')))
            if not value:
                raise ValueError(f'{name}: missing {key} in colors.toml')
            colors[f'color{i}'] = value
            colors[f'color{i+8}'] = semantic.get('bright_' + key, semantic.get(f'color{i+8}', mix(value, '#ffffff', .2)))
        colors.update(color0=semantic['background'], color7=semantic['foreground'],
                      color8=semantic.get('muted', semantic.get('color8', semantic['foreground'])),
                      color15=semantic.get('bright_foreground', semantic.get('color15', semantic['foreground'])))
        colors.update(cursor=colors['color15'], cursor_text_color=colors['background'],
                      selection_background=semantic.get('selection_background', semantic.get('selection', colors['color8'])),
                      selection_foreground=semantic.get('selection_foreground', colors['color15']))
        colors['active_border_color'] = semantic.get('active_border_color', semantic.get('accent', colors['color4']))
        colors['active_tab_background'] = semantic.get('active_tab_background', semantic.get('accent', colors['color4']))
    for key in ['background', 'foreground'] + [f'color{i}' for i in range(16)]:
        if key not in colors:
            raise ValueError(f'{name}: missing {key} in theme palette')
    # Favor each author's explicit accent, then their terminal blue.
    colors['accent'] = semantic.get('accent', colors.get('active_border_color', colors.get('active_tab_background', colors['color4'])))
    if contrast(colors['accent'], colors['background']) < 2:
        colors['accent'] = readable(colors['background'], colors['color4'], colors['color5'], colors['color6'])
    return colors


def material(p):
    bg, fg = p['background'], p['foreground']
    dark = luminance(bg) < luminance(fg)
    result = dict(background=bg, on_background=fg, surface=bg, on_surface=fg,
                  surface_tint=p['accent'], shadow='#000000', scrim='#000000',
                  inverse_surface=fg, inverse_on_surface=bg, inverse_primary=p['accent'],
                  on_surface_variant=mix(fg, bg, .16), outline=mix(bg, fg, .55),
                  outline_variant=mix(bg, fg, .24), surface_variant=mix(bg, fg, .12),
                  surface_dim=mix(bg, '#000000', .12) if dark else mix(bg, fg, .09),
                  surface_bright=mix(bg, fg, .14) if dark else bg,
                  surface_container_lowest=mix(bg, '#000000' if dark else '#ffffff', .18))
    for level, amount in [('low', .025), ('', .05), ('high', .08), ('highest', .12)]:
        result['surface_container' + ('_' + level if level else '')] = mix(bg, fg, amount)
    for role, accent in [('primary', p['accent']), ('secondary', p['color6']),
                         ('tertiary', p['color5']), ('error', p['color1'])]:
        container = mix(bg, accent, .24)
        result.update({role: accent, 'on_' + role: readable(accent, bg, fg, '#000000', '#ffffff'),
                       role + '_container': container, 'on_' + role + '_container': readable(container, fg, bg)})
        if role != 'error':
            fixed = mix(accent, '#ffffff', .25)
            result.update({role + '_fixed': fixed, role + '_fixed_dim': accent,
                           'on_' + role + '_fixed': readable(fixed, bg, fg, '#000000', '#ffffff'),
                           'on_' + role + '_fixed_variant': readable(accent, bg, fg, '#000000', '#ffffff')})
    return result


def wallpapers(name):
    return [str(p.resolve()) for p in sorted((THEMES / name / 'backgrounds').glob('*'))
            if p.suffix.lower() in ('.jpg', '.jpeg', '.png', '.webp')]


def catalog():
    result = []
    for folder in sorted(THEMES.iterdir()):
        try:
            p = palette(folder.name)
            walls = wallpapers(folder.name)
            result.append(dict(id=folder.name, name=folder.name.replace('-', ' ').title(),
                               background=p['background'], foreground=p['foreground'], accent=p['accent'],
                               dark=luminance(p['background']) < luminance(p['foreground']),
                               swatches=[p[f'color{i}'] for i in (1, 2, 3, 4, 5, 6)],
                               wallpaper=Path(walls[0]).as_uri() if walls else '',
                               wallpaperPath=walls[0] if walls else ''))
        except (OSError, ValueError) as e:
            print(e, file=sys.stderr)
    return dict(themes=result, active=read_json(ACTIVE).get('id', ''))


def render_template(source, colors, wallpaper):
    def replace(match):
        expr = match[1].strip()
        if expr == 'image':
            return wallpaper
        fields = expr.split('.')
        if len(fields) != 4 or fields[0] != 'colors' or fields[2] not in ('default', 'dark', 'light'):
            raise ValueError(f'Unsupported template expression: {expr}')
        value = colors[fields[1]]
        formats = dict(hex=value, hex_stripped=value[1:], **dict(zip(('red', 'green', 'blue'), map(str, rgb(value)))))
        return formats[fields[3]]
    return re.sub(r'{{(.*?)}}', replace, source)


def kde_scheme(p, m):
    def triplet(c):
        return ','.join(map(str, rgb(c)))
    lines = ['[General]', 'Name=ii Named Theme', 'ColorScheme=iiNamedTheme', '']
    for group, bg, fg in [('Window', m['background'], m['on_background']),
                          ('View', m['surface_container_lowest'], m['on_surface']),
                          ('Button', m['surface_container'], m['on_surface']),
                          ('Selection', m['primary'], m['on_primary']),
                          ('Tooltip', m['surface_container_high'], m['on_surface']),
                          ('Complementary', m['surface_container_high'], m['on_surface']),
                          ('Header', m['surface_container'], m['on_surface'])]:
        lines += [f'[Colors:{group}]', f'BackgroundNormal={triplet(bg)}',
                  f'BackgroundAlternate={triplet(m["surface_container"])}',
                  f'ForegroundNormal={triplet(fg)}', f'ForegroundInactive={triplet(m["on_surface_variant"])}',
                  f'ForegroundLink={triplet(m["primary"])}', f'ForegroundVisited={triplet(m["tertiary"])}',
                  f'ForegroundNegative={triplet(p["color1"])}', f'ForegroundNeutral={triplet(p["color3"])}',
                  f'ForegroundPositive={triplet(p["color2"])}', f'DecorationFocus={triplet(m["primary"])}',
                  f'DecorationHover={triplet(m["secondary"])}', '']
    return '\n'.join(lines)


def outputs(name, wallpaper):
    p = palette(name)
    m = material(p)
    files = {GENERATED / 'colors.json': json.dumps(m, indent=2) + '\n'}
    # Reuse the installed templates so existing layout/style customizations survive.
    # Read destinations from Matugen: newer end4 versions use Hyprland Lua.
    templates = tomllib.loads((CONFIG / 'matugen/config.toml').read_text())['templates']

    def config_path(value):
        if value.startswith('~/.config/'):
            return CONFIG / value[len('~/.config/'):]
        path = Path(value).expanduser()
        return path if path.is_absolute() else CONFIG / 'matugen' / path

    for key in ('hyprland', 'hyprlock', 'gtk3', 'gtk4', 'fuzzel'):
        template = templates[key]
        source, dest = config_path(template['input_path']), config_path(template['output_path'])
        files[dest] = render_template(source.read_text(), m, wallpaper)
    kitty = {k: v for k, v in p.items() if k != 'accent'}
    kitty.setdefault('cursor', p['foreground'])
    kitty.setdefault('cursor_text_color', p['background'])
    kitty.setdefault('selection_background', m['primary_container'])
    kitty.setdefault('selection_foreground', m['on_primary_container'])
    # Keep end4's extended prompt colors while preserving the author's ANSI palette.
    roles = ['primary', 'primary_container', 'secondary', 'secondary_container',
             'tertiary', 'tertiary_container', 'error', 'error_container']
    for i, role in enumerate(roles):
        kitty[f'color{255-i}'] = m[role]
        kitty[f'color{232+i}'] = m['on_' + role]
    kitty.update(color240=m['on_primary'], color243=m['primary'], color244=m['error'], color245=m['outline_variant'])
    files[GENERATED / 'terminal/kitty-theme.conf'] = '\n'.join(f'{k} {v}' for k, v in kitty.items()) + '\n'
    ghostty = [f'{k} = {p[k]}' for k in ('background', 'foreground')]
    ghostty += [f'palette = {i}={p[f"color{i}"]}' for i in range(16)]
    ghostty += [f'cursor-color = {kitty["cursor"]}', f'cursor-text = {kitty["cursor_text_color"]}',
                f'selection-background = {kitty["selection_background"]}', f'selection-foreground = {kitty["selection_foreground"]}']
    files[GENERATED / 'terminal/ghostty-named.conf'] = '\n'.join(ghostty) + '\n'
    files[DATA / f'color-schemes/iiNamedTheme-{name}.colors'] = kde_scheme(p, m).replace('ColorScheme=iiNamedTheme', f'ColorScheme=iiNamedTheme-{name}')
    return p, files


def snapshot_data(paths):
    snapshot = {'files': {}, 'settings': {}, 'omarchy': None}
    for path in paths:
        snapshot['files'][str(path)] = base64.b64encode(path.read_bytes()).decode() if path.exists() else None
    link = CONFIG / 'omarchy/current/theme'
    if link.is_symlink():
        snapshot['omarchy'] = os.readlink(link)
    for key in ('color-scheme', 'gtk-theme'):
        snapshot['settings'][key] = command('gsettings', 'get', 'org.gnome.desktop.interface', key)
    snapshot['kde'] = command('kreadconfig6', '--file', 'kdeglobals', '--group', 'General', '--key', 'ColorScheme')
    return snapshot


def restore_data(saved):
    for filename, content in saved['files'].items():
        path = Path(filename)
        if content is None:
            path.unlink(missing_ok=True)
        else:
            write(path, base64.b64decode(content).decode())
    link = CONFIG / 'omarchy/current/theme'
    if saved.get('omarchy') and link.is_symlink():
        temp = link.with_name('theme.ii-new')
        temp.unlink(missing_ok=True)
        temp.symlink_to(saved['omarchy'])
        temp.replace(link)
    for key, value in saved['settings'].items():
        if value:
            command('gsettings', 'set', 'org.gnome.desktop.interface', key, value)
    if saved.get('kde'):
        command('plasma-apply-colorscheme', saved['kde'])


def reload_apps():
    command('hyprctl', 'reload')
    for name, sig in [('kitty', signal.SIGUSR1), ('btop', signal.SIGUSR2)]:
        for pid in command('pgrep', '-u', str(os.getuid()), '-x', name).split():
            try:
                os.kill(int(pid), sig)
            except ProcessLookupError:
                pass
    command('gdbus', 'call', '--session', '--dest', 'com.mitchellh.ghostty',
            '--object-path', '/com/mitchellh/ghostty', '--method', 'org.gtk.Actions.Activate', 'reload-config', '[]', '{}')


def apply(name, use_wallpaper=False):
    settings = read_json(SETTINGS)
    wallpaper = settings.get('background', {}).get('wallpaperPath', '')
    walls = wallpapers(name)
    if use_wallpaper and walls:
        wallpaper = walls[0]
    p, files = outputs(name, wallpaper)  # Validate every template before any mutation.
    previous = snapshot_data([*files, ACTIVE])
    if not read_json(ACTIVE).get('id'):
        write(SNAPSHOT, json.dumps(snapshot_data(files), indent=2))
    else:
        saved = read_json(SNAPSHOT)
        for path in files:
            if str(path) not in saved['files']:
                saved['files'][str(path)] = base64.b64encode(path.read_bytes()).decode() if path.exists() else None
        write(SNAPSHOT, json.dumps(saved, indent=2))
    try:
        for path, content in files.items():
            write(path, content)
        link = CONFIG / 'omarchy/current/theme'
        if link.is_symlink():
            temp = link.with_name('theme.ii-new')
            temp.unlink(missing_ok=True)
            temp.symlink_to(THEMES / name)
            temp.replace(link)
        write(ACTIVE, json.dumps({'id': name}, indent=2) + '\n')
        dark = luminance(p['background']) < luminance(p['foreground'])
        command('gsettings', 'set', 'org.gnome.desktop.interface', 'color-scheme', 'prefer-dark' if dark else 'prefer-light')
        command('gsettings', 'set', 'org.gnome.desktop.interface', 'gtk-theme', 'adw-gtk3-dark' if dark else 'adw-gtk3')
        if settings.get('appearance', {}).get('wallpaperTheming', {}).get('enableQtApps', True):
            command('plasma-apply-colorscheme', f'iiNamedTheme-{name}')
        if use_wallpaper and walls:
            env = dict(os.environ, II_THEME_LOCK_HELD='1')
            command('bash', str(HERE / 'switchwall.sh'), '--image', wallpaper, env=env, check=True)
    except Exception:
        restore_data(previous)
        reload_apps()
        raise
    reload_apps()
    return {'active': name}


def restore(regenerate):
    if read_json(ACTIVE).get('id') and not SNAPSHOT.exists():
        raise ValueError('Restore snapshot is missing; current theme was left active')
    if SNAPSHOT.exists() and read_json(ACTIVE).get('id'):
        restore_data(read_json(SNAPSHOT))
    write(ACTIVE, '{"id": ""}\n')
    if regenerate:
        command('bash', str(HERE / 'switchwall.sh'), '--color', 'clear', '--noswitch',
                env=dict(os.environ, II_THEME_LOCK_HELD='1'), check=True)
    reload_apps()
    return {'active': ''}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['list', 'apply', 'wallpaper', 'restore', 'render'])
    parser.add_argument('name', nargs='?')
    parser.add_argument('--wallpaper', action='store_true', help='Also use the theme’s first wallpaper')
    parser.add_argument('--output', type=Path, help='Render all files here without applying')
    args = parser.parse_args()
    if args.action == 'list':
        print(json.dumps(catalog()))
        return
    if args.action == 'render':
        if not args.name or not args.output:
            parser.error('render requires a theme name and --output')
        _, files = outputs(args.name, '')
        for path, content in files.items():
            write(args.output / path.relative_to(Path.home()), content)
        print(json.dumps({'rendered': len(files)}))
        return
    lock = STATE / 'ii-named-themes/theme.lock'
    lock.parent.mkdir(parents=True, exist_ok=True)
    with lock.open('w') as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        if args.action == 'apply':
            if not args.name:
                parser.error('apply requires a theme name')
            result = apply(args.name, args.wallpaper)
        else:
            result = restore(args.action == 'wallpaper')
        print(json.dumps(result))


if __name__ == '__main__':
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as e:
        print(str(e), file=sys.stderr)
        sys.exit(1)
