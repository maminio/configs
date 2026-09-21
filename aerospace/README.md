# AeroSpace Configuration

This directory contains the AeroSpace window-manager setup and the companion
HUD used to visualize the workspace grid.

See [PRODUCT_AND_IMPLEMENTATION.md](PRODUCT_AND_IMPLEMENTATION.md) for product
goals, UX details, architecture, data flow, privacy model, and validation.

## Workspace Model

Workspaces use a project/grid naming scheme:

- Rows/projects: `1..9`
- Columns: `0..9`
- Workspace names: `w10..w19`, `w20..w29`, ..., `w90..w99`

Examples:

- `w10`: row 1, column 0
- `w23`: row 2, column 3
- `w90`: row 9, column 0

## Key Bindings

Navigation:

- `cmd-1`: move left in current row
- `cmd-2`: move right in current row
- `cmd-1`/`cmd-2` while holding a focused window with the left mouse button: move that window left/right instead
- `cmd-3`: toggle the large AeroSpace Mission Control panel
- `cmd-ctrl-1`: move up one row
- `cmd-ctrl-2`: move down one row
- `cmd-shift-1`: move up one row
- `cmd-shift-2`: move down one row
- `cmd-shift-1`/`cmd-shift-2` while holding a focused window with the left mouse button: move that window up/down instead
- `alt-1..alt-9`: jump to row start, `w10..w90`

Startup repair:

- AeroSpace may put restored windows into legacy numeric workspaces like `1` during app restart.
- `repair-legacy-workspaces.sh` runs on startup and moves legacy `1..9` to grid row starts `w10..w90`.

Move a held window:

- Hold a focused window with the left mouse button, then press `cmd-1`, `cmd-2`, `cmd-shift-1`, or `cmd-shift-2`.
- The helper checks only left mouse button state, then moves AeroSpace's focused window.
- No window-under-pointer scan is used. The window must already be focused.

## Files

- `.aerospace.toml`: AeroSpace config
- `scripts/grid-workspace.sh`: relative workspace navigation
- `scripts/grid-workspace-or-mouse-move.sh`: navigation wrapper that moves the focused window while left mouse is held
- `scripts/show-hud.sh`: toggle the large Mission Control panel from `cmd-3`
- `scripts/mouse-button-down.sh`: left mouse button state helper
- `scripts/mouse-button-down.swift`: tiny CoreGraphics button-state binary source
- `scripts/repair-legacy-workspaces.sh`: startup repair for restored windows in legacy numeric workspaces
- `scripts/grid-jump.sh`: direct jump helper used by `alt-1..9`
- `hud/`: native macOS HUD overlay
- `hud/config.toml`: HUD appearance and timing config

## Privacy

- HUD does not take screenshots.
- HUD does not request Screen Recording permission.
- HUD tiles show workspace labels and compact app names from `aerospace list-windows --all`.
- The separate Mission Control panel shows draggable app/window chips and moves windows by `window-id`.
- Mouse-held move checks only left mouse button state through CoreGraphics, then asks AeroSpace to move the focused window.
- Pointer-window detection was removed to avoid screen/window metadata reads.

## HUD

The HUD starts from AeroSpace:

```toml
after-startup-command = [
    'workspace w10',
    'exec-and-forget /Users/aminmoradi/workspace/configs/aerospace/scripts/repair-legacy-workspaces.sh',
    'exec-and-forget /Users/aminmoradi/workspace/configs/aerospace/hud/run.sh',
]
```

The compact HUD shows rows and columns up to the highest workspace with apps,
while always including the currently focused workspace.

`cmd-3` opens a separate 70%-screen Mission Control panel. It starts with only
active rows and active columns: a row or column is active when at least one app
exists anywhere in it. Empty intersections inside that active grid remain visible
as translucent drop targets. Drag an app/window chip from one tile to another to
move that window without switching focus. Hover an edge for the `+` button, then
click it to add one empty row or column without jumping to that workspace. Use
the context menu on a tile to add a workspace before or after it; populated
workspaces to its right shift one column within that project lane. Use
`w`/`a`/`s`/`d` or arrow keys to navigate, `Enter`/`Space` to focus the selected
workspace and close Mission Control, and `Esc` to close it without switching.
On macOS 26 it uses native Clear Liquid Glass with subtle dark tint as one lensing
navigation plane. Workspace tiles and window rows remain content fills; project
names stay plain and vertical. Rounded glass clips the complete panel with no
rectangular window shadow behind it.

See [hud/README.md](hud/README.md) for controls, troubleshooting, and best
practices.

HUD appearance is configured in:

```bash
aerospace/hud/config.toml
```

`[mission_control]` controls native glass style, corner radius, glass background
tint, accent, and accent text color. HUD menu -> `Reload Config` applies changes
live without rebuilding. Saving the file also reloads it automatically.

Edit that file, then right-click the HUD and choose `Reload Config`.

Full restart command:

```bash
pkill -f /Users/aminmoradi/workspace/configs/aerospace/hud/AeroSpaceHud.app/Contents/MacOS/AeroSpaceHud
rm -f /tmp/aerospace-hud.pid
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

## Reload

After config edits:

```bash
aerospace reload-config --no-gui
```

If shell access cannot reach the AeroSpace socket, reload from AeroSpace itself
or restart AeroSpace.

## Validate

```bash
./aerospace/hud/build.sh
python3 aerospace/hud/tests/test_mission_control_grid.py
bash -n aerospace/hud/run.sh
bash -n aerospace/scripts/grid-workspace.sh
bash -n aerospace/scripts/grid-workspace-or-mouse-move.sh
bash -n aerospace/scripts/show-hud.sh
bash -n aerospace/scripts/mouse-button-down.sh
bash -n aerospace/scripts/repair-legacy-workspaces.sh
bash -n aerospace/scripts/grid-jump.sh
python3 -c 'import tomllib; tomllib.load(open("aerospace/.aerospace.toml", "rb")); print("toml ok")'
```
