# Local customizations of end-4's dots

This is a fork (`origin` = ethantang93/dots-hyprland, `upstream` = end-4/dots-hyprland).
Customizations live as commits on the `custom` branch, rebased onto `main` (which tracks
`upstream/main`). The installer copies `dots/` over `~/.config/`, so anything not
committed here is lost on the next update.

## Saving a live change ("save it to our repo")

The live config (`~/.config/...`) has drifted from `dots/` in many unrelated files, so
never copy a whole live file over its `dots/` counterpart.

1. Clean up the change, then run `/code-review` on it and fix what it finds.
2. `git checkout custom`, then port into the matching `dots/.config/...` path:
   - new files: copy as-is (keep the executable bit on scripts)
   - edited files: apply only your hunks, e.g. `diff -u original live > x.patch`,
     then `patch dots/.config/.../file < x.patch`
3. One focused commit: short subject, body explaining why. No attribution lines.
4. `git push origin custom`.

Don't commit files end-4 already preserves: `~/.config/hypr/custom/`, `monitors.conf`,
`hypr*/colors.conf`.

When backporting, check each changed hunk against upstream history: a hunk that matches
an older upstream version is a stale snapshot that would revert a later upstream fix,
not a customization.

## Updating from upstream

```sh
git checkout main && git pull --ff-only
git checkout custom && git rebase main      # resolve conflicts
git push --force-with-lease origin custom
# then run the end-4 installer
```

## Testing Quickshell changes

- The shell (`qs -c ii`) normally reloads on save; if not, run
  `pkill -x qs; hyprctl dispatch exec "qs -c ii"`. Logs: `qs log -c ii`.
- Drive the UI with `hyprctl dispatch movecursor X Y` and `ydotool click 0xC0`, and
  screenshot with `grim -g "X,Y WxH"` (logical coords; screen scale is 1.6667).
