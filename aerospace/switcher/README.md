# AeroSpace Switcher

Snappy `cmd-tab` replacement for the AeroSpace workspace grid. A vertical,
Contexts-style overlay that lists windows and lets you pick one by holding `cmd`
and tabbing through scopes, or release `cmd` to drop into a searchable launcher.

It is a sibling of [`../hud`](../hud): a single Swift file compiled into an
`LSUIElement` app, launched from `.aerospace.toml`. It never takes a screenshot
and needs no Screen Recording permission.

## Interaction

Hold `cmd` and press `tab` to reveal the overlay. While `cmd` stays down:

- `tab` again cycles the scope: **This Workspace → This Row → All Windows →**
  back to This Workspace.
- `cmd-1` moves the selection up, `cmd-2` moves it down (wraps at the ends).
- Release `cmd` to focus the highlighted window and dismiss.

The exception: a **bare** `cmd-tab` with no navigation — press `cmd-tab`, then
let go of `cmd` immediately — persists the overlay and drops into **search
mode** across all open windows.

In search mode (`cmd` is up, panel is key):

- Type to fuzzy-filter every open window by app name and title.
- `↑`/`↓`, `ctrl-p`/`ctrl-n`, or `cmd-1`/`cmd-2` move the selection.
- `tab` still cycles the scope filter.
- `Enter` focuses the selection; `Esc` or a click outside dismisses.
- Click any row to focus it.

"Row" means the grid row of the focused workspace — e.g. focused on `w23`, the
row scope spans `w20..w29`. See
[../PRODUCT_AND_IMPLEMENTATION.md](../PRODUCT_AND_IMPLEMENTATION.md) for the grid
model.

## How it works

- A `CGEventTap` (session level) captures `cmd-tab` and, while the overlay is
  up, `cmd-1`/`cmd-2`, swallowing them so the macOS switcher and AeroSpace grid
  bindings never see them. This requires Accessibility permission.
- `cmd` release is detected via `flagsChanged` on the same tap.
- Search mode hands the keyboard to the key panel via a local key monitor; the
  tap goes transparent so typing flows through.
- Window inventory comes from `aerospace list-windows --all`, polled every 1.5s
  into a cache and refreshed on each trigger, so the overlay opens instantly.
- The focused workspace is read from `/tmp/aerospace-hud-focused-workspace`
  (written by the HUD/nav scripts) for zero-latency scoping.
- Picking a window writes that workspace to the same state file, then calls
  `aerospace focus --window-id <id>`.

## Files

- `AeroSpaceSwitcher.swift`: switcher application source
- `config.toml`: appearance + layout config
- `build.sh`: compiles the macOS app bundle (ad-hoc codesigned)
- `run.sh`: starts one instance through `launchctl`
- `.gitignore`: ignores the generated app bundle/binary

Generated / runtime files:

- `AeroSpaceSwitcher.app`: compiled app bundle
- `/tmp/aerospace-switcher.pid`: active PID
- `/tmp/aerospace-switcher.log`: stdout/stderr

## Run

Build and start:

```bash
/Users/aminmoradi/workspace/configs/aerospace/switcher/run.sh
```

Restart after a Swift change:

```bash
pkill -f /Users/aminmoradi/workspace/configs/aerospace/switcher/AeroSpaceSwitcher.app/Contents/MacOS/AeroSpaceSwitcher
rm -f /tmp/aerospace-switcher.pid
/Users/aminmoradi/workspace/configs/aerospace/switcher/run.sh
```

Check status:

```bash
cat /tmp/aerospace-switcher.pid
tail -n 80 /tmp/aerospace-switcher.log
```

## Permission

The event tap needs Accessibility. On first launch macOS prompts; approve
**AeroSpace Switcher** in System Settings → Privacy & Security → Accessibility,
then restart AeroSpace. If `cmd-tab` still shows the macOS switcher, the
permission is missing or stale:

```bash
tccutil reset Accessibility dev.aminmoradi.aerospace-switcher
/Users/aminmoradi/workspace/configs/aerospace/switcher/run.sh
```

## Config

Loaded in order: `AEROSPACE_SWITCHER_CONFIG`, source-adjacent
`switcher/config.toml`, bundled `Resources/config.toml`, then
`~/.config/aerospace-switcher/config.toml`. Keys live under `[switcher]`; colors
accept `#RGB`, `#RGBA`, `#RRGGBB`, or `#RRGGBBAA`. Edit and rerun `run.sh` (it
rebuilds when the source or config is newer).

## Validation

```bash
./aerospace/switcher/build.sh
bash -n aerospace/switcher/run.sh
python3 -c 'import tomllib; tomllib.load(open("aerospace/switcher/config.toml", "rb")); print("switcher config ok")'
python3 -c 'import tomllib; tomllib.load(open("aerospace/.aerospace.toml", "rb")); print("toml ok")'
```
