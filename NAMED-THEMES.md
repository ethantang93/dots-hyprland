# Named themes for end4

Press **Ctrl+Super+Shift+T**, run `ii-theme-picker`, or launch **Themes**.

The native Quickshell gallery provides searchable wallpaper cards, dark/light filters,
palette and terminal previews, keyboard navigation, and an explicit Apply button.
It opens as a fixed overlay, consistent with end4’s other desktop pickers.
Select a card, then apply with Enter or the button. Arrow keys browse when search is
empty; up/down also work while searching. Escape or the shortcut closes the gallery.
Selecting a card only changes the preview. Double-clicking applies it.
Escape and the close button remain available during application: they hide the overlay
while the change finishes, then the picker exits. Theme commands and lock waits are
bounded so a stalled helper cannot hold the overlay indefinitely.

**Use matching wallpaper** is optional and off by default. **Wallpaper colors** restores
the pre-theme files and settings, then runs end4's wallpaper color generation again.
While a named theme is active, wallpaper changes preserve its palette. Choose a light
theme from the gallery to switch to light mode; the ordinary light/dark generator
buttons do not replace an active named palette.

## Supported components

- Quickshell bar, sidebars and lock: full 49-role Material palette adapted from the
  theme's original background, foreground and accents. Shell layouts stay as configured.
- Kitty: original ANSI and other supported hex colors, plus end4's extended prompt colors.
- Ghostty: original ANSI palette, foreground/background, selection and cursor, with live reload.
  Font, opacity and other preferences stay in the user's configuration.
- GTK 3/4, Hyprland borders, Hyprlock and Fuzzel: the user's installed Matugen templates.
- KDE/Qt: generated KDE color scheme, when end4's Qt theming option is enabled.
  Apps that do not follow KDE/GTK may need their own theme setting or a restart.
- btop and Neovim: existing Omarchy theme symlinks follow the chosen theme. btop reloads;
  Neovim picks up the theme on startup or through the user's existing reload integration.

No Omarchy services or desktop theme scripts are launched. Browser extensions, VS Code
themes and Obsidian themes are not managed by this add-on. Ghostty returns to its
previous configuration when leaving named mode; its original end4 setup did not
generate a persistent Ghostty theme.

## Theme discovery

Themes are discovered in `~/.config/omarchy/themes/`. Both legacy `kitty.conf` palettes
and Omarchy 4 semantic `colors.toml` palettes are supported. A legacy palette needs hex
`background`, `foreground`, and `color0` through `color15`. Optional wallpaper previews
come from its `backgrounds/` folder. Shell Material roles are adaptations, while terminal
ANSI colors are copied exactly. Light themes remain light.

On September 11, 2026, eight missing official themes were imported from Omarchy **v4.0.3**:
Last Horizon, Lumon, Lupine, Miasma, Retro 82, Solitude, Vantablack and White. Together with
the existing collection there are **24 themes**. Downloaded files were checked against
upstream Git blob hashes. Each added theme includes `SOURCE.json` and the upstream license.
Missing Kitty, btop and Neovim files were rendered from the official release templates.
Neovim may install the theme's declared plugin on its next startup through Lazy.

Check or import future official themes without replacing existing themes:

```sh
python tools/import-omarchy-themes.py --list
python tools/import-omarchy-themes.py
# Or reproduce the release used here:
python tools/import-omarchy-themes.py --release v4.0.3
```

Theme assets stay in the local Omarchy theme directory, outside the end4 deployment paths.

## Persistence and updates

These files belong on the repository's `custom` branch. After rebasing and deploying
end4, run this additive installer from the repository:

```sh
python tools/install-named-themes.py
hyprctl reload
```

It installs the gallery, backend, launcher and desktop entry; adds the wallpaper
generation guard and shortcut; and connects Ghostty through an optional include.
It preserves unrelated config and backs up changed files. Both the installed Hyprland
`.conf` format and the repository's newer Lua format are supported. It refuses to
patch an unrecognized upstream wallpaper script instead of overwriting it.
The main desktop shell does not need restarting because the picker is a separate
Quickshell entry point that loads only while open.

State lives in `~/.config/illogical-impulse/named-theme.json`.
Before the first named theme in each session of named mode, the backend snapshots the
generated files, original Omarchy theme symlink, GNOME settings, and KDE scheme to
`~/.local/state/ii-named-themes/restore.json`. Switching among named themes preserves
that original snapshot. Install backups are in the same state directory.

To restore exactly the saved appearance without regenerating colors:

```sh
python ~/.config/quickshell/ii/scripts/colors/named-theme.py restore
```

The restore command does not change wallpaper. Avoid editing generated theme files
while named mode is active; the snapshot is restored when leaving this mode.

Other commands:

```sh
python ~/.config/quickshell/ii/scripts/colors/named-theme.py list
python ~/.config/quickshell/ii/scripts/colors/named-theme.py apply tokyo-night
python ~/.config/quickshell/ii/scripts/colors/named-theme.py apply nord --wallpaper
python ~/.config/quickshell/ii/scripts/colors/named-theme.py wallpaper
python -m unittest discover -s tests -p test_named_themes.py -v
```

Tests use temporary config/state and fake desktop commands. They check palette fidelity,
readability, complete template rendering, multi-theme restoration, failure rollback,
invalid inputs, preserving named colors across wallpaper and mode changes, background
process output handles, process-group timeouts, and bounded lock waits.
