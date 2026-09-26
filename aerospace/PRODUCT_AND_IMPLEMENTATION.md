# AeroSpace Grid Product And Implementation

## Product Goal

This setup replaces linear macOS space navigation with a project/grid model on
top of AeroSpace. The user keeps a lightweight workspace HUD for quick context
and gets a separate Mission Control-style panel for larger workspace management.

The product has three visual surfaces:

- Compact HUD: small top-right overlay showing current grid extent, focused
  workspace, and compact app names.
- Mission Control: large centered overlay opened by `cmd-3`, about 70% of the
  current screen, showing active workspace rows/columns and draggable window chips.
- App Switcher: centered vertical `cmd-tab` overlay listing windows by scope
  (workspace, row, all) with a release-to-search launcher mode. See
  `switcher/README.md`.

The compact HUD is intentionally not the drag workspace manager. It stays small,
fast, and sufficient for normal navigation. Mission Control is the explicit
window-management mode.

## Workspace Model

Quick-action workspaces form an independent row above `base`: `q0`, `q1`, and so
on. Each accepts one application at a time, including multiple windows from that
application. Mission Control's persistent `+` adds empty slots without changing
focus; the row scrolls independently and is not limited to ten columns. Empty
slots persist in `hud/.quick-spaces-count` (environment override:
`AEROSPACE_QUICK_SPACES_FILE`). The row uses the existing directional shortcuts:
up from `base` enters Quick actions, down returns to `base`, and column indices
clamp to the destination row's bounds. The compact HUD recognizes quick spaces,
and the app switcher treats them as a separate row.

HUD and shortcut moves into quick spaces recheck application identity against
fresh window inventory under a shared native PID lock. This rejects mixed-app
moves made through these surfaces; direct AeroSpace commands and third-party
moves are outside that guard. No automatic launch or permanent app binding is
implied by a slot.

Populated Quick-action slots can be reordered by dragging their app icons
horizontally. The dragged application and all of its windows move together,
intervening slots shift, and focus follows the active item. The transaction is
serialized under the same native PID lock as guarded window moves and rolls
back completed moves if AeroSpace rejects any step. `option-left` and
`option-right` provide the keyboard-equivalent reorder action.

Project workspaces use fixed grid names:

- Rows/projects: `1..9`
- Columns: `0..9`
- Workspace names: `w10..w19`, `w20..w29`, ..., `w90..w99`

Examples:

- `w10`: row 1, column 0
- `w23`: row 2, column 3
- `w90`: row 9, column 0

Rows are intended to act like project lanes. Columns act like positions inside a
project. Navigation scripts clamp at the grid edges rather than wrapping.

## User Experience

### Compact HUD

The compact HUD appears when workspace focus changes or when visible grid size
changes. It auto-hides after the configured delay.

It supports:

- Click workspace tile: switch to that workspace.
- Drag HUD background/tile: reposition compact HUD and save that position.
- Right-click: open HUD menu.
- Right-click -> `Reload Config`: reload visual config.

It does not support drag-to-move windows. That is reserved for Mission Control.

### Mission Control

`cmd-3` toggles the large Mission Control panel.

It supports:

- Click workspace tile: switch to that workspace and close Mission Control.
- Right-click a workspace tile, then choose `Add Workspace Before` or
  `Add Workspace After`: insert an empty slot in that project lane and shift
  populated workspaces to its right one column.
- Drag app/window chip to any tile, including empty translucent cells: move
  that AeroSpace window to the target workspace.
- Drag a populated Quick actions tile horizontally to reorder its application;
  all represented windows move together and an insertion marker previews the
  destination.
- Press `option-left` / `option-right` on a selected Quick actions workspace to
  reorder it by one slot.
- Press `w`/`a`/`s`/`d` or an arrow key: switch to the adjacent visible
  workspace while keeping Mission Control open.
- Press `Enter` or `Space`: switch to the highlighted workspace and close
  Mission Control.
- Press `Esc`: close Mission Control without switching workspaces.
- Hover an edge for the `+` button, then click it to add one empty row or column
  without switching workspaces.
- Press `cmd-3` again: close Mission Control.

Mission Control uses the same workspace grid model as the compact HUD, but shows
only active rows and active columns. A row or column is active when at least one
workspace in it has an app. Empty intersections inside that active grid remain
visible as translucent drop targets.

Mission Control follows Apple's Liquid Glass hierarchy on macOS 26:

- One native `NSGlassEffectView` with Clear style forms the lensing navigation
  plane. A restrained dark native tint improves separation without covering the
  content behind it.
- Workspace tiles, project-lane labels, window rows, and tooltips use semantic
  fills and vibrancy as content inside that plane. Glass is never stacked on glass.
- Project-lane names remain plain and vertical, with no row number, pill, or
  placeholder chrome. Workspace identifiers are plain text.
- Current focus, drop targets, drag previews, and the edge `+` action use one dark
  neutral emphasis instead of the system accent color.
- Native panel shadow is disabled and glass content is clipped with continuous
  corners so no sharp rectangular backing appears behind the rounded material.
- Semantic colors adapt to light/dark context. Custom drawing listens for macOS
  accessibility display changes and honors Reduce Transparency, Increase Contrast,
  and Reduce Motion.

Mission Control grid contract:

- Quick actions is a separate persistent, horizontally scrollable row above the project grid.
- Initial project rows always include `base`, plus rows that contain windows.
- Initial columns: sorted column numbers that contain at least one window.
- If no windows exist yet, fall back to the focused workspace's row and column.
- The visible grid is the cross-product of those active rows and columns.
- Empty cells inside that cross-product are drawn with lower opacity and remain
  valid click/drop targets.
- Edge `+` expansion adds one adjacent empty row or column to the visible grid.
- Context-menu insertion affects only the clicked project lane. It moves the
  populated suffix rightmost-first, preserves focus on shifted content, and is
  disabled when column 9 leaves no capacity.
- Clicking the `+` consumes that mouse interaction; it must not switch to the
  newly added workspace.
- Closing and reopening Mission Control recomputes the active grid from the
  current window inventory, so unused `+` expansions are transient.

### App Switcher

`cmd-tab` replaces the macOS application switcher with a centered vertical
overlay of windows, styled after the Contexts switcher (number, right-aligned
app name, icon, window title).

Hold `cmd`:

- `tab` reveals the overlay scoped to the focused workspace; pressing `tab`
  again cycles the scope: This Workspace → This Row → All Windows → back to This
  Workspace.
- `cmd-1` / `cmd-2` move the selection up / down (wrapping).
- Release `cmd` focuses the highlighted window and dismisses.

A bare `cmd-tab` (press, then release `cmd` with no navigation) persists the
overlay and enters search mode across all open windows: type to fuzzy-filter,
arrows / `ctrl-p` / `ctrl-n` / `cmd-1` / `cmd-2` move, `tab` cycles scope,
`Enter` focuses, `Esc` or an outside click dismisses, click a row to focus it.

"Row" is the grid row of the focused workspace (e.g. focused on `w23`, the row
scope spans `w20..w29`). The switcher captures these keys with a
session-level `CGEventTap` (Accessibility permission required) and goes
transparent in search mode so typing reaches its key panel.

## Key Bindings

Primary grid controls:

- `cmd-tab`: open the App Switcher (event tap; not an AeroSpace binding).
- `cmd-1`: move left in current row (or move switcher selection up while the
  switcher is open).
- `cmd-2`: move right in current row (or move switcher selection down while the
  switcher is open).
- `cmd-3`: toggle Mission Control.
- `cmd-ctrl-1`: move up one row.
- `cmd-ctrl-2`: move down one row.
- `cmd-shift-1`: move up one row.
- `cmd-shift-2`: move down one row.
- `alt-1..alt-9`: jump to row starts `w10..w90`.
- While Mission Control is open: `w`/`a`/`s`/`d` or arrow keys navigate visible
  tiles and keep the panel open; `Enter`/`Space` selects, and `Esc` closes.

Move focused window:

- Hold a focused window with the left mouse button, then press `cmd-1`,
  `cmd-2`, `cmd-shift-1`, or `cmd-shift-2`.
- In Mission Control, drag a window chip between tiles.

## Architecture

### AeroSpace Config

File: `.aerospace.toml`

This file binds keyboard shortcuts to helper scripts and starts companion
processes:

- starts at `w10`
- runs legacy workspace repair
- starts the HUD app
- starts the App Switcher app
- maps `cmd-3` to `scripts/show-hud.sh`

### Helper Scripts

Navigation scripts:

- `scripts/grid-workspace.sh`: moves focus within the grid.
- `scripts/grid-workspace-or-mouse-move.sh`: navigates or moves focused window
  when left mouse button is held.
- `scripts/grid-jump.sh`: direct row-start jumps.

Startup and repair:

- `scripts/repair-legacy-workspaces.sh`: moves restored legacy numeric
  workspaces `1..9` to grid row starts `w10..w90`.

Mission Control:

- `scripts/show-hud.sh`: starts or refreshes the HUD app, writes the focused
  workspace state, then writes `/tmp/aerospace-mission-control-toggle`.

Mouse helpers:

- `scripts/mouse-button-down.sh`: builds/runs left mouse button state helper.

### Native HUD App

Files:

- `hud/AeroSpaceHud.swift`
- `hud/config.toml`
- `hud/build.sh`
- `hud/run.sh`

`AeroSpaceHud.swift` contains these core types:

- `WorkspaceWindow`: in-memory representation of an AeroSpace window.
- `AeroSpaceClient`: runs AeroSpace CLI commands and parses output.
- `HudView`: compact auto-hiding HUD.
- `MissionControlView`: large draggable workspace manager.
- `AppDelegate`: owns panels, timers, state sync, and command handling.

The app creates two panels:

- compact HUD panel, positioned and saved by user
- Mission Control panel, centered and sized to about 70% of the screen

Both panels share window inventory and focused workspace state.
Mission Control's panel content is a native macOS 26 `NSGlassEffectView` using
Clear style and restrained dark tint; the compact HUD keeps its independent
configurable appearance.

Mission Control glass tokens live under `[mission_control]` in
`aerospace/hud/config.toml`. Native glass exposes style, corner radius, background
tint, and tint opacity. Content-layer tokens expose panel opacity, tile colors,
tile border/shape, hover, accent fill/border/text, primary/secondary text, and row
text. Exact background color is a separate content layer inside native glass,
because AppKit tint adapts rather than guaranteeing literal color output. A 350ms
file watcher applies saves automatically; Reload Config remains available. Reload
keeps the rectangular `NSPanel` shadow disabled.
`MissionControlView` is a sibling overlay above `NSGlassEffectView`, not its
`contentView`, so TOML colors remain literal while glass still provides lensing.

### Native App Switcher

Files:

- `switcher/AeroSpaceSwitcher.swift`
- `switcher/config.toml`
- `switcher/build.sh`
- `switcher/run.sh`

A standalone `LSUIElement` app, sibling to the HUD. It installs a session-level
`CGEventTap` to capture `cmd-tab` (and `cmd-1`/`cmd-2` while open), swallowing
them before the macOS switcher and AeroSpace grid bindings see them. `cmd`
release is detected via `flagsChanged` on the same tap. Search mode hands the
keyboard to a key `NSPanel` through a local key monitor, with the tap
transparent so typing flows through.

It reuses the data model: `aerospace list-windows --all` polled every 1.5s into
a cache (refreshed on each trigger for an instant overlay), and the focused
workspace read from `/tmp/aerospace-hud-focused-workspace`. Picking a window
writes that workspace to the same state file, then runs
`aerospace focus --window-id <id>`. The switcher requires Accessibility
permission for its event tap; it takes no screenshots and needs no Screen
Recording permission.

## Data Flow

### Focused Workspace

Navigation scripts write:

```text
/tmp/aerospace-hud-focused-workspace
```

The HUD app reads this file every 50ms for fast highlight updates. AeroSpace is
also polled every 600ms as a fallback.

### Mission Control Toggle

`scripts/show-hud.sh` writes:

```text
/tmp/aerospace-mission-control-toggle
```

The HUD app reads this file every 50ms. Each new signal toggles the large Mission
Control panel. The signal includes the focused workspace and a timestamp/process
suffix so repeated `cmd-3` presses are distinct.

### Window Inventory

The HUD app polls AeroSpace every 3 seconds:

```bash
aerospace list-windows --all --format '%{workspace}\t%{window-id}\t%{app-name}'
```

The compact HUD deduplicates window records into app names per workspace.
Mission Control keeps individual window records so each chip has a `window-id`.

### Window Move

Mission Control drag-to-move calls:

```bash
aerospace move-node-to-workspace --window-id <window-id> <workspace>
```

The app updates its in-memory inventory optimistically, then refreshes from
AeroSpace. If AeroSpace rejects the move, the previous inventory is restored.

## Privacy And Permissions

The HUD app does not:

- capture screenshots
- store thumbnails
- request Screen Recording permission
- inspect window-under-pointer metadata

Data used:

- app names
- workspace names
- AeroSpace window ids

The left-mouse-held window move reads only the left button state through a
CoreGraphics query. Mission Control drag-and-drop itself does not require Screen
Recording permission.

## Performance Model

Fast paths:

- 50ms state-file poll for focused workspace highlight
- 50ms signal-file poll for Mission Control toggle

Slower paths:

- 600ms fallback focused-workspace poll from AeroSpace
- 3s window inventory poll from AeroSpace

`list-windows --all` stays off the 50ms hot path because it is the expensive
operation and can be eventually consistent.

## Generated Files

Generated and ignored files:

- `hud/AeroSpaceHud.app/`
- `hud/aerospace-hud`
- `switcher/AeroSpaceSwitcher.app/`
- `scripts/.build/`
- `/tmp/aerospace-hud.pid`
- `/tmp/aerospace-hud.log`
- `/tmp/aerospace-hud-focused-workspace`
- `/tmp/aerospace-mission-control-toggle`
- `/tmp/aerospace-switcher.pid`
- `/tmp/aerospace-switcher.log`

## Operational Commands

Build HUD:

```bash
./aerospace/hud/build.sh
```

Start or refresh HUD:

```bash
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

Restart HUD:

```bash
pkill -f /Users/aminmoradi/workspace/configs/aerospace/hud/AeroSpaceHud.app/Contents/MacOS/AeroSpaceHud
rm -f /tmp/aerospace-hud.pid
/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh
```

Reload AeroSpace config:

```bash
aerospace reload-config --no-gui
```

Trigger Mission Control directly:

```bash
/Users/aminmoradi/workspace/configs/aerospace/scripts/show-hud.sh
```

Build / restart App Switcher:

```bash
./aerospace/switcher/build.sh
pkill -f /Users/aminmoradi/workspace/configs/aerospace/switcher/AeroSpaceSwitcher.app/Contents/MacOS/AeroSpaceSwitcher
rm -f /tmp/aerospace-switcher.pid
/Users/aminmoradi/workspace/configs/aerospace/switcher/run.sh
```

## Validation

Run after changes:

```bash
./aerospace/hud/build.sh
python3 aerospace/hud/tests/test_mission_control_grid.py
./aerospace/switcher/build.sh
bash -n aerospace/hud/run.sh
bash -n aerospace/switcher/run.sh
bash -n aerospace/scripts/grid-workspace.sh
bash -n aerospace/scripts/grid-workspace-or-mouse-move.sh
bash -n aerospace/scripts/show-hud.sh
bash -n aerospace/scripts/mouse-button-down.sh
bash -n aerospace/scripts/repair-legacy-workspaces.sh
bash -n aerospace/scripts/grid-jump.sh
python3 -c 'import tomllib; tomllib.load(open("aerospace/.aerospace.toml", "rb")); tomllib.load(open("aerospace/hud/config.toml", "rb")); tomllib.load(open("aerospace/switcher/config.toml", "rb")); print("toml ok")'
```

## Known Tradeoffs

- Compact HUD is intentionally small and cannot show every window when many apps
  occupy one workspace.
- Mission Control shows app names, not screenshots, to avoid Screen Recording
  permission and thumbnail storage.
- Window inventory can lag by up to 3 seconds after external moves.
- Mission Control hides inactive rows and columns by default; use the edge `+`
  affordance to expose one adjacent empty row or column for new placements.
- Dragging a chip moves a specific AeroSpace window id. Multiple windows from
  the same app can appear as separate chips in Mission Control.
- AeroSpace CLI can print warning text before real output in this environment;
  parsers filter for valid workspace names before using focused-workspace
  output.
