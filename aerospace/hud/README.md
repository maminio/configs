# AeroSpace HUD

Native macOS overlay for the AeroSpace workspace grid.

See [../PRODUCT_AND_IMPLEMENTATION.md](../PRODUCT_AND_IMPLEMENTATION.md) for the
full product and implementation notes.

The HUD shows workspace rows and columns through the highest workspace that
currently has apps, plus the focused workspace. It highlights the focused
workspace, displays compact app names per workspace, and supports click-to-jump.
`cmd-3` opens a separate Mission Control-style panel for window moves.

## Starting

- Auto-start: AeroSpace runs `hud/run.sh` on startup (`exec-and-forget` in
  `.aerospace.toml`), which rebuilds-if-stale and launches one instance via
  LaunchServices (`open`). Restarting AeroSpace starts the HUD.
- Manually (no AeroSpace restart): `aerospace/hud/run.sh`.
- After editing the source: re-run `run.sh` (it rebuilds when the source is
  newer, then relaunches the fresh binary) or `build.sh` then `run.sh`.
- Quit it from the menu-bar item (below), or `pkill -f AeroSpaceHud`.

> `run.sh` launches with `open`, not `launchctl submit`: a `launchctl submit`
> process has no window-server connection, so `NSApp.run()` returns immediately
> and the HUD never appears.

## Install into /Applications

- `aerospace/hud/install.sh` builds the bundle and symlinks it to
  `/Applications/AeroSpace HUD.app`, so it shows in Launchpad/Spotlight and can
  be double-clicked. It's a symlink, so rebuilds need no reinstall.
- This is for visibility/manual launch only — AeroSpace still launches the
  binary directly from the repo via `run.sh`.

## Menu bar

- The HUD adds a menu-bar item showing whether the setup is live: a green grid
  icon when AeroSpace and the HUD are both up; an orange warning icon otherwise.
- Click it for per-component status (AeroSpace / HUD) and actions: Open Mission
  Control, Reload Config, Reset HUD Size, Quit.
- Disable with `show_menu_bar = false` in `config.toml`.

## Features

- Floating translucent grid overlay
- Dynamic height and width based on active workspace rows/columns
- Auto-hide after workspace/grid updates
- Draggable position
- Saved position between launches
- Current workspace highlight
- Compact app names in each HUD tile
- Separate 70%-screen Mission Control panel with active rows and columns
- Native macOS 26 Clear Liquid Glass with restrained dark tint
- Adaptive semantic tile, project-lane, window-row, and tooltip colors
- Plain vertical project-lane names and visible workspace identifiers
- Continuous rounded clipping with no rectangular panel shadow
- Live Reduce Transparency, Increase Contrast, and Reduce Motion support
- Empty cells inside active row/column intersections are translucent drop targets
- Click tile to jump to that workspace
- `w`/`a`/`s`/`d` or arrow-key navigation between visible Mission Control tiles
- `Enter`/`Space` focuses the selected workspace; `Esc` closes Mission Control
- Fast highlight updates through `/tmp/aerospace-hud-focused-workspace`

Mission Control uses one Clear `NSGlassEffectView` rather than layered blur cards.
Its tiles and controls are content-layer fills inside the glass, avoiding
glass-on-glass while preserving native lensing and accessibility. A dark neutral
selection color marks focus, drop targets, drag previews, and the edge `+` action.

## Quick actions

Mission Control has an independent **Quick actions** row above `base`. Its spaces
are named `q0`, `q1`, and so on, without the project grid's ten-column limit.

- Each quick space shows only one centered application icon, even with multiple windows.
- The always-visible `+` creates an empty space without switching workspaces.
- Drag a window onto the **Quick actions header** to create a new space and move
  that window into it. The header highlights while a drop is eligible. If the move
  fails, the reserved slot is rolled back. Dragging keeps the existing per-window semantics.
- Drag a window into an empty space. Additional windows from the same application
  are allowed; moves from a different application into an occupied space are rejected.
- Drag a populated Quick actions tile horizontally to reorder it. The lifted app
  follows the pointer, an insertion marker previews its destination, and the
  intervening items shift as one atomic operation. Every window represented by
  the app icon travels with it, and an active Quick actions workspace follows
  its item.
- Press `option-left` / `option-right` while a Quick actions workspace is
  selected to move that item one slot without leaving the keyboard.
- Scroll horizontally when the row overflows. Keyboard navigation reveals the
  selected quick space automatically.
- `cmd-1` / `cmd-2` move left/right. The existing row shortcuts move up from `base`
  into Quick actions and down into `base`, clamping to the nearest valid column.
- Mission Control's arrows and WASD support the same row transition.
- Empty spaces persist in `.quick-spaces-count` beside the HUD source. The default
  is one empty space. `AEROSPACE_QUICK_SPACES_FILE` overrides this path for testing.
- The HUD and shortcut scripts share a native PID lock (`.quick-spaces-count.lock`)
  so concurrent guarded moves cannot assign different apps to the same empty space.

These are workspace slots, not application launchers or permanent app assignments.
An empty slot can receive a different application. Moves performed directly through
AeroSpace or unrelated tools bypass the HUD/shortcut one-app guard.

Run shortcut regression tests without changing live workspaces:

```bash
python3 aerospace/hud/tests/test_quick_navigation.py
```

## Files

- `AeroSpaceHud.swift`: HUD application source
- `config.toml`: HUD appearance and timing config
- `build.sh`: compiles the macOS app bundle
- `run.sh`: rebuilds-if-stale and starts one HUD instance through LaunchServices (`open`)
- `install.sh`: builds and symlinks the bundle into `/Applications`
- `../scripts/grid-workspace-or-mouse-move.sh`: keeps grid navigation, but moves the focused window when the left mouse button is held
- `../scripts/show-hud.sh`: writes the Mission Control toggle signal used by `cmd-3`
- `../scripts/mouse-button-down.sh`: compiles/runs the left mouse button state helper
- `.gitignore`: ignores generated app bundle/binaries

Generated files:

- `AeroSpaceHud.app`: compiled app bundle
- `AeroSpaceHud.app/Contents/Resources/config.toml`: bundled fallback copy
- `../scripts/.build/mouse-button-down`: compiled mouse button helper
- `../scripts/.build/module-cache/`: Swift module cache for helper builds
- `/tmp/aerospace-hud.pid`: active HUD PID
- `/tmp/aerospace-hud.log`: HUD stdout/stderr
- `/tmp/aerospace-hud-focused-workspace`: fast workspace state
- `/tmp/aerospace-mission-control-toggle`: Mission Control toggle signal written by `cmd-3`

## Run

Build and start:

```bash
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

Restart:

```bash
pkill -f /Users/aminmoradi/workspace/configs/aerospace/hud/AeroSpaceHud.app/Contents/MacOS/AeroSpaceHud
rm -f /tmp/aerospace-hud.pid
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

Check status:

```bash
cat /tmp/aerospace-hud.pid
tail -n 80 /tmp/aerospace-hud.log
```

## Config

Primary config path:

```bash
/Users/aminmoradi/workspace/configs/aerospace/hud/config.toml
```

The app loads config in this order:

- `AEROSPACE_HUD_CONFIG`
- source-adjacent `aerospace/hud/config.toml`
- bundled `AeroSpaceHud.app/Contents/Resources/config.toml`
- `~/.config/aerospace-hud/config.toml`

Reload config after config edits:

- Right-click the HUD
- Choose `Reload Config`

Full restart:

```bash
pkill -f /Users/aminmoradi/workspace/configs/aerospace/hud/AeroSpaceHud.app/Contents/MacOS/AeroSpaceHud
rm -f /tmp/aerospace-hud.pid
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

Supported keys under `[hud]`:

- `opacity`: panel opacity, `0.1..1`
- `header_text`: text template; supports `{workspace}`, `{row}`, `{col}`
- `tile_width`, `tile_height`, `minimum_width`
- `margin`, `gap`, `header_height`, `screen_padding`
- `auto_hide_delay`
- `background_corner_radius`, `tile_corner_radius`, `label_corner_radius`
- `selected_border_width`, `occupied_border_width`, `shadow`
- `show_menu_bar`: show the menu-bar status item (default `true`)
- `header_font_size`, `workspace_font_size`, `app_font_size`, `tile_label_max_apps`
- `background_color`, `background_border_color`, `tile_color`
- `selected_color`, `occupied_border_color`
- `label_background_color`, `empty_label_background_color`
- `header_text_color`, `workspace_text_color`, `app_text_color`

Colors accept `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA`.

Mission Control Liquid Glass uses a separate section:

```toml
[mission_control]
glass_style = "clear"             # "clear" or "regular"
corner_radius = 30
panel_opacity = 1.0
glass_tint_color = "#050505"
glass_tint_opacity = 0.08
background_color = "#ff0000"      # exact color inside native glass
background_opacity = 0.22
tile_color = "#0c0d0e24"
empty_tile_color = "#0c0d0e12"
tile_border_color = "#0505058f"
tile_border_width = 1.0
tile_corner_radius = 15
hover_color = "#ffffff14"
accent_color = "#0a0a0ac7"
accent_border_color = "#050505ff"
accent_text_color = "#f5f5f5ff"
primary_text_color = "#111111ff"
secondary_text_color = "#11111199"
row_text_color = "#111111cc"
```

- `glass_tint_color` and `glass_tint_opacity` map to native
  `NSGlassEffectView.tintColor`.
- `background_color` and `background_opacity` draw an exact configurable color
  layer inside native glass. Lower opacity preserves more lensing; high opacity
  intentionally dominates underlying content.
- AppKit's public native glass properties are style, corner radius, and tint.
  Remaining keys configure content drawn inside that single glass plane.
- `tile_*` and `hover_color` control workspace surfaces and pointer feedback.
- `accent_color` controls focused workspace, drop targets, drag previews, and
  edge `+` action; `accent_border_color` controls their outline.
- `accent_text_color` keeps labels readable over custom accents.
- `primary_text_color`, `secondary_text_color`, and `row_text_color` control
  unselected window, metadata, and vertical project-lane labels.
- Mission Control content renders as a sibling overlay above `NSGlassEffectView`,
  so configured RGB values stay literal; native glass remains the background.
- Saving `config.toml` automatically reapplies all values to open Mission
  Control within about 350ms. Right-click -> `Reload Config` remains available.

## Controls

- Click tile: jump to workspace
- `cmd-3`: toggle the large Mission Control panel from AeroSpace
- In Mission Control, use `w`/`a`/`s`/`d` or arrow keys to navigate, `Enter` or
  `Space` to focus the selected workspace and close, and `Esc` to close without
  switching
- In Mission Control, drag app/window chip to any tile, including empty translucent cells: move that window to the target workspace
- In Mission Control, hover an edge for the `+` button, then click it to add one empty row or column without switching workspaces
- In Mission Control, right-click a tile and choose `Add Workspace Before` or `Add Workspace After` to insert an empty slot in that project lane
- Right-click: open HUD menu
- Right-click -> `Reload Config`: reload `config.toml`
- Drag HUD background/tile: move HUD
- Move workspace with keyboard: HUD highlight updates from state file
- Hover HUD: pause auto-hide
- Mission Control stays open for drag moves until `cmd-3` or `Esc` is pressed.

Position:

- Dragging the HUD saves the normal home position.
- Keyboard navigation shows the HUD at the saved home position.
- After auto-hide, the HUD remains at the saved home position while hidden.

Visible grid:

- Mini HUD: row 1 through the highest row with apps or current focus
- Mini HUD: column 0 through the highest column with apps or current focus
- Mission Control initial rows: sorted row numbers that contain at least one app
- Mission Control initial columns: sorted column numbers that contain at least one app
- Mission Control fallback when no apps exist: focused workspace row and column
- Mission Control visible cells: cross-product of active rows and active columns
- Mission Control empty intersections: lower opacity, still valid click/drop targets
- Edge `+`: adds one adjacent empty row or column without switching workspaces
- Tile context menu: inserts before/after in one project lane, shifts populated workspaces right, and disables insertion when column 9 would overflow
- Unused `+` expansions are transient; closing and reopening recomputes from current apps
- Example: apps in `w10` and `w23` make Mission Control show rows 1 and 2, columns 0 and 3, including empty `w13` and `w20` targets

Click-to-jump calls:

```bash
aerospace workspace <workspace>
```

Drag-to-move calls:

```bash
aerospace move-node-to-workspace --window-id <window-id> <workspace>
```

The HUD updates its highlight before the AeroSpace call completes, so the UI
feels immediate.

Auto-hide:

- Shows on workspace focus change
- Shows when visible grid size changes
- Hides after `1.6s` of idle time
- Disable for debugging with `AEROSPACE_HUD_AUTO_HIDE=0`

## Performance Model

The HUD has four update paths:

- `50ms`: read `/tmp/aerospace-hud-focused-workspace` for instant highlight
- `50ms`: read `/tmp/aerospace-mission-control-toggle` for Mission Control toggles
- `600ms`: fallback focused-workspace poll from AeroSpace
- `3s`: window inventory via `aerospace list-windows --all`

The expensive command is:

```bash
aerospace list-windows --all --format '%{workspace}\t%{window-id}\t%{app-name}'
```

Keep it off the hot path. Navigation scripts write the state file before
switching workspaces, which makes highlight updates cheap.

The `window-id` is used only for Mission Control chip moves; no screenshot or
window-under-pointer lookup is needed.

HUD size changes when window inventory finds apps in a higher row or column. The
top-right corner stays anchored where possible, so the HUD grows downward and
leftward from its current position.

The `50ms` state-file poll does not keep the HUD visible by itself. Only real
state changes reset the auto-hide timer.

## Privacy Model

- HUD does not capture screenshots.
- HUD does not store thumbnails.
- HUD app bundle does not include `NSScreenCaptureUsageDescription`.
- HUD does not need Screen Recording permission.
- HUD app names and Mission Control chips come from AeroSpace's `list-windows --all` output.
- Dragging a Mission Control chip moves that AeroSpace window by `window-id`.
- Mouse-held window moves use left mouse button state only; target window is AeroSpace's focused window.
- Window-under-pointer detection was removed because it required window metadata reads.

## Troubleshooting

HUD not visible:

```bash
defaults delete dev.aminmoradi.aerospace-hud AeroSpaceHudFrame
pkill -f /Users/aminmoradi/workspace/configs/aerospace/hud/AeroSpaceHud.app/Contents/MacOS/AeroSpaceHud
rm -f /tmp/aerospace-hud.pid
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

HUD or Mission Control running but app names stale:

Wait up to 3 seconds. Window inventory is intentionally slower for performance.

Screen Recording prompt appears:

- Rebuild HUD with `./aerospace/hud/build.sh`.
- Restart HUD with `./aerospace/hud/run.sh`.
- Reset old permission entry if macOS still shows stale state:

```bash
tccutil reset ScreenCapture dev.aminmoradi.aerospace-hud
```

AeroSpace socket error from shell:

```text
Can't connect to AeroSpace server. Is AeroSpace.app running?
```

Reload from AeroSpace itself or restart AeroSpace. The config may still be valid
even when shell access cannot reach the AeroSpace socket.

## Do

- Keep current-workspace updates file-based and cheap.
- Keep `list-windows --all` on a slow timer.
- Restart HUD after Swift source changes.
- Reload AeroSpace after binding or script-path changes.
- Use `grid-jump.sh` for direct workspace jumps so HUD state stays in sync.
- Keep generated `AeroSpaceHud.app` out of git.
- Keep mouse-held moves focused-window based unless privacy tradeoff changes.
- Keep visual constants in `config.toml`; change Swift only for behavior.

## Don't

- Do not put `list-windows --all` in the 50ms hot loop.
- Do not rely only on polling AeroSpace for highlight updates.
- Do not make HUD navigation call shell scripts when Swift can call AeroSpace directly.
- Do not store workspace state in the repo; use `/tmp`.
- Do not make launch use raw `nohup` for the app. Use `launchctl` through `run.sh`.
- Do not reset user-chosen HUD position unless it is off-screen or broken.
- Do not add screenshot thumbnails back without also accepting Screen Recording permission.
- Do not reintroduce window-under-pointer detection unless focused-window moves stop being enough.
- Do not hardcode new colors, opacity, tile sizes, or header text in Swift.

## Best Practices

- Treat workspace highlight as real-time UI state.
- Treat window inventory as eventually consistent metadata.
- Prefer explicit state writes from navigation scripts.
- Keep restart commands idempotent.
- Keep AeroSpace keybindings mapped to helper scripts when those scripts maintain HUD state.
- Keep auto-hide driven by real changes, not every poll tick.
- Validate with:

```bash
./aerospace/hud/build.sh
python3 aerospace/hud/tests/test_mission_control_grid.py
python3 -c 'import tomllib; tomllib.load(open("aerospace/hud/config.toml", "rb")); print("hud config ok")'
bash -n aerospace/hud/run.sh
bash -n aerospace/scripts/grid-workspace.sh
bash -n aerospace/scripts/grid-workspace-or-mouse-move.sh
bash -n aerospace/scripts/show-hud.sh
bash -n aerospace/scripts/mouse-button-down.sh
bash -n aerospace/scripts/repair-legacy-workspaces.sh
bash -n aerospace/scripts/grid-jump.sh
python3 -c 'import tomllib; tomllib.load(open("aerospace/.aerospace.toml", "rb")); print("toml ok")'
```
