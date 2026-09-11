#!/usr/bin/env python3
"""Import missing official Omarchy themes; leave existing themes untouched."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import re
import shutil
import tempfile
import tomllib
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('named_theme', ROOT / 'dots/.config/quickshell/ii/scripts/colors/named-theme.py')
theme = importlib.util.module_from_spec(spec)
spec.loader.exec_module(theme)
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--release', help='Pinned official release tag; default: latest stable')
parser.add_argument('--list', action='store_true', help='Only report missing themes')
args = parser.parse_args()


def get(url):
    return urllib.request.urlopen(url, timeout=45).read()


release = args.release or json.loads(get('https://api.github.com/repos/omacom/omarchy/releases/latest'))['tag_name']
if not re.fullmatch(r'v[0-9]+\.[0-9]+\.[0-9]+', release):
    raise ValueError('Use a stable vMAJOR.MINOR.PATCH release tag')
tree = json.loads(get(f'https://api.github.com/repos/omacom/omarchy/git/trees/{release}?recursive=1'))
if tree.get('truncated'):
    raise RuntimeError('Incomplete upstream tree; refusing a partial import')
available = {f['path'].split('/')[1] for f in tree['tree'] if f['path'].startswith('themes/')}
local = {p.name for p in theme.THEMES.iterdir()} if theme.THEMES.exists() else set()
missing = sorted(available - local)
print(f'{release}: missing themes: {", ".join(missing) or "none"}')
if args.list or not missing:
    raise SystemExit(0)
files = [f for f in tree['tree'] if f['type'] == 'blob' and
         ((f['path'].startswith('themes/') and f['path'].split('/')[1] in missing)
          or f['path'] in ('LICENSE', 'default/themed/kitty.conf.tpl',
                          'default/themed/btop.theme.tpl', 'default/themed/neovim.lua.tpl'))]


def download(item):
    content = get(f'https://raw.githubusercontent.com/omacom/omarchy/{release}/{item["path"]}')
    digest = hashlib.sha1(b'blob ' + str(len(content)).encode() + b'\0' + content).hexdigest()
    if digest != item['sha']:
        raise ValueError('Hash mismatch: ' + item['path'])
    return item['path'], content


theme.THEMES.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory(dir=theme.THEMES.parent, prefix='.ii-import-') as directory:
    stage = Path(directory)
    with ThreadPoolExecutor(max_workers=6) as pool:
        for path, content in pool.map(download, files):
            dest = stage / path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(content)
    original_themes = theme.THEMES
    theme.THEMES = stage / 'themes'
    for name in missing:
        folder = theme.THEMES / name
        c = tomllib.loads((folder / 'colors.toml').read_text())
        theme.palette(name)  # Validate the new format before making it visible.
        c.setdefault('orange', c['yellow'])
        c.setdefault('brown', theme.mix(c['orange'], '#000000', .5))
        c.setdefault('selection_foreground', c['bright_foreground'])
        c.setdefault('selection_background', c['selection'])
        derived = []
        for filename in ('kitty.conf', 'btop.theme', 'neovim.lua'):
            dest = folder / filename
            if not dest.exists():
                template = (stage / 'default/themed' / (filename + '.tpl')).read_text()
                text = re.sub(r'{{\s*(\w+)\s*}}', lambda m: c[m[1]], template)
                if '{{' in text:
                    raise ValueError('Unsupported upstream template: ' + filename)
                dest.write_text(text)
                derived.append(filename)
        shutil.copy2(stage / 'LICENSE', folder / 'OMARCHY-LICENSE')
        (folder / 'SOURCE.json').write_text(json.dumps(dict(
            repository='https://github.com/omacom/omarchy', release=release, tree=tree['sha'],
            path='themes/' + name, generated_from_official_templates=derived), indent=2) + '\n')
    theme.THEMES = original_themes
    for name in missing:
        dest = theme.THEMES / name
        if os.path.lexists(dest):
            raise FileExistsError('Theme appeared during import; refusing to replace: ' + name)
        (stage / 'themes' / name).rename(dest)
        print('Imported ' + name)
print('Reopen Themes to see the new collection.')
