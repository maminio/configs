#!/usr/bin/env python3
"""Source-level regression tests for Mission Control grid behavior."""

from pathlib import Path
import re
import sys

SOURCE = Path(__file__).resolve().parents[1] / "AeroSpaceHud.swift"
swift = SOURCE.read_text()
config_text = (SOURCE.parent / "config.toml").read_text()


def function_body(name: str) -> str:
    markers = [f"private func {name}", f"override func {name}", f"func {name}"]
    start = -1
    marker = markers[0]
    for candidate in markers:
        start = swift.find(candidate)
        if start != -1:
            marker = candidate
            break
    if start == -1:
        raise AssertionError(f"Missing function {name}")
    brace = swift.find("{", start)
    if brace == -1:
        raise AssertionError(f"Missing body for {name}")
    depth = 0
    for index in range(brace, len(swift)):
        char = swift[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return swift[brace + 1:index]
    raise AssertionError(f"Unclosed body for {name}")


def alpha(name: str) -> float:
    match = re.search(
        rf"static let {name} = NSColor\.white\.withAlphaComponent\((0\.\d+)\)",
        swift,
    )
    if not match:
        raise AssertionError(f"Missing alpha style for {name}")
    return float(match.group(1))


def test_mission_control_uses_active_rows_and_columns() -> None:
    body = function_body("missionControlGrid")
    assert "rowSet.insert(row)" in body, "Rows should become active from occupied workspaces"
    assert "colSet.insert(col)" in body, "Columns should become active from occupied workspaces"
    assert "windows.isEmpty" in body, "Empty workspaces should not activate rows or columns"
    assert "rowSet.min()!...rowSet.max()!" in body, "Active rows should span a contiguous range so interior empties keep their slot"
    assert "colSet.min()!...colSet.max()!" in body, "Active columns should span a contiguous range so interior empties keep their slot"
    assert "workspaceRows, workspaceCols" not in body, "Mission Control should not force the whole 9×10 grid"


def test_sparse_active_grid_maps_rows_and_columns() -> None:
    assert "let row = visibleRowValues[rowIndex]" in swift, "Drawing should use sparse active row values"
    assert "let col = visibleColValues[colIndex]" in swift, "Drawing should use sparse active column values"
    assert "visibleRowValues.firstIndex(of: row)" in swift, "Tile lookup should map row value to sparse index"
    assert "visibleColValues.firstIndex(of: col)" in swift, "Tile lookup should map column value to sparse index"
    assert "return visibleRowValues[rowIndex]" in swift, "Rail hit-testing should map sparse index back to row value"


def test_edge_plus_expands_sparse_active_grid() -> None:
    can_expand = function_body("canExpand")
    expand = function_body("expand")

    assert "visibleColValues.max()" in can_expand, "Right edge should expand from the active column set"
    assert "visibleColValues.min()" in can_expand, "Left edge should expand from the active column set"
    assert "visibleRowValues.max()" in can_expand, "Bottom edge should expand from the active row set"
    assert "visibleRowValues.min()" in can_expand, "Top edge should expand from the active row set"
    assert can_expand.strip() != "false", "Edge expansion should remain available for adding rows/columns"

    assert "visibleColValues.append" in expand, "Right expansion should add the next sparse column"
    assert "visibleColValues.insert" in expand, "Left expansion should add the previous sparse column"
    assert "visibleRowValues.append" in expand, "Bottom expansion should add the next sparse row"
    assert "visibleRowValues.insert" in expand, "Top expansion should add the previous sparse row"


def test_plus_click_does_not_fall_through_to_workspace_click() -> None:
    assert "suppressWorkspaceClickOnMouseUp" in swift, "Plus-click should carry consumed state into mouseUp"
    assert "suppressWorkspaceClickOnMouseUp = true" in swift, "Clicking + should mark mouseUp as consumed"
    assert "if suppressWorkspaceClickOnMouseUp { return }" in swift, "Consumed plus-click mouseUp should not jump workspace"


def test_right_click_can_add_workspace_before_or_after() -> None:
    mission_source = swift[swift.index("private final class MissionControlView"):]
    can_insert = function_body("canInsertWorkspace")

    assert 'title: "Add Workspace Before"' in mission_source, "Tile menu should offer insertion before its workspace"
    assert 'title: "Add Workspace After"' in mission_source, "Tile menu should offer insertion after its workspace"
    assert "beforeItem.representedObject = workspace" in mission_source, "Before action should retain the clicked workspace"
    assert "afterItem.representedObject = workspace" in mission_source, "After action should retain the clicked workspace"
    assert "canInsertWorkspace(around: workspace, position: .before)" in mission_source, "Before action should enforce grid capacity"
    assert "canInsertWorkspace(around: workspace, position: .after)" in mission_source, "After action should enforce grid capacity"
    assert "if let workspace = workspace(at: point)" in mission_source, "Insertion actions should appear only for a workspace tile"
    assert "(occupiedColumns.max() ?? insertionColumn) < workspaceCols - 1" in can_insert, (
        "Insertion should disable when shifting would overflow column 9"
    )


def test_workspace_insertion_shifts_only_same_lane_suffix() -> None:
    body = function_body("insertWorkspaceGap")

    assert "workspaceRow(workspace) == row" in body, "Insertion should leave other project lanes untouched"
    assert "column >= insertionColumn" in body, "Insertion should shift only workspaces at and after the new slot"
    assert "workspaceName(row: row, col: column + 1)" in body, "Affected workspaces should move one column right"
    assert "lastOccupiedColumn < workspaceCols - 1" in body, "Insertion must prevent workspace overflow"
    assert "moves.sort" in body and "leftColumn > rightColumn" in body, "Rightmost workspaces should move first"
    assert "completed.reversed()" in body, "Partial failures should roll completed moves back"
    assert "revealWorkspaceColumn(insertionColumn)" in body, "New empty slot should remain visible after remapping"
    assert "shiftedFocusedWorkspace" in body, "Focus should follow a populated workspace that shifts"


def test_empty_cells_are_visible_drop_targets() -> None:
    body = function_body("isCellVisible")
    assert body.strip() == "true", "Every active-row/active-column cell should be drawn and hit-testable"


def test_empty_tiles_are_subtle_but_visible() -> None:
    assert "empty ? config.missionEmptyTileColor : config.missionTileColor" in swift, "Tile fills should come from Mission Control config"
    assert "empty ? 0.58 : 0.82" in swift, "Reduced Transparency should retain stronger tile separation"


def test_mission_control_uses_native_liquid_glass() -> None:
    panel_body = function_body("createMissionPanel")
    glass_body = function_body("configureMissionGlass")
    reload_start = swift.index("private func reloadConfig(showMiniHud: Bool = true)")
    reload_end = swift.index("private func updateVisibleGrid", reload_start)
    reload_body = swift[reload_start:reload_end]

    assert "NSGlassEffectView" in panel_body, "Mission Control should use native AppKit Liquid Glass"
    assert 'config.missionGlassStyle == "regular" ? .regular : .clear' in glass_body, "Glass style should come from config"
    assert "config.missionGlassTintColor.withAlphaComponent(config.missionGlassTintOpacity)" in glass_body, "Native glass tint and opacity should come from config"
    assert "glass.cornerRadius = config.missionGlassCornerRadius" in glass_body, "Glass radius should come from config"
    assert "container.addSubview(glass)" in panel_body, "Native glass should form the background layer"
    assert "container.addSubview(missionView)" in panel_body, "Configured content should render above glass without color remapping"
    assert "glass.contentView = missionView" not in panel_body, "Custom colors must not be embedded in adaptive glass content"
    assert "panel.hasShadow = false" in panel_body, "Rectangular NSWindow shadow must not leak behind rounded glass"
    assert "glass.clipsToBounds = true" in glass_body, "Glass content should clip to rounded material bounds"
    assert "glass.wantsLayer" not in glass_body, "Custom layer backing must not flatten native glass rendering"
    assert "configureMissionGlass(missionGlassView)" in reload_body, "Reload Config should update live glass attributes"
    assert "missionPanel.hasShadow = false" in reload_body, "Reload Config must preserve rounded glass edges"
    assert "NSVisualEffectView" not in panel_body, "Legacy vibrancy blur should not back Mission Control"
    assert "vibrantDark" not in panel_body, "Liquid Glass should adapt instead of forcing dark appearance"


def test_mission_control_glass_tokens_are_configurable() -> None:
    assert "[mission_control]" in config_text, "Config should expose a Mission Control section"
    assert 'glass_style = "clear"' in config_text, "Config should expose Clear or Regular glass style"
    assert "corner_radius = 30" in config_text, "Config should expose glass corner radius"
    assert "glass_tint_color =" in config_text, "Config should expose native glass tint"
    assert "glass_tint_opacity =" in config_text, "Config should expose native glass tint strength"
    assert "background_color =" in config_text, "Config should expose deterministic background color inside glass"
    assert "background_opacity =" in config_text, "Config should expose deterministic background strength"
    assert "panel_opacity =" in config_text, "Config should expose whole-panel opacity"
    assert "tile_color =" in config_text, "Config should expose occupied tile fill"
    assert "empty_tile_color =" in config_text, "Config should expose empty tile fill"
    assert "tile_border_color =" in config_text, "Config should expose tile border color"
    assert "tile_border_width =" in config_text, "Config should expose tile border width"
    assert "tile_corner_radius =" in config_text, "Config should expose tile corner radius"
    assert "hover_color =" in config_text, "Config should expose window hover feedback"
    assert "accent_color =" in config_text, "Config should expose Mission Control accent"
    assert "accent_border_color =" in config_text, "Config should expose accent outline"
    assert "accent_text_color =" in config_text, "Config should expose accent text contrast"
    assert "primary_text_color =" in config_text, "Config should expose primary text"
    assert "secondary_text_color =" in config_text, "Config should expose secondary text"
    assert "row_text_color =" in config_text, "Config should expose vertical row text"
    assert 'values["mission_control.\\(key)"] = value' in swift, "Parser should load Mission Control section values"
    assert 'values.color("mission_control.accent_color")' in swift, "HUD config should parse Mission Control accent"
    assert "config.missionBackgroundColor" in swift and ".withAlphaComponent(config.missionBackgroundOpacity)" in swift, (
        "Mission Control should draw configured background inside native glass"
    )
    assert "HudConfig.modificationDate()" in swift, "HUD should monitor active config file"
    assert "reloadConfig(showMiniHud: false)" in swift, "Saving config should update Mission Control automatically"


def test_liquid_glass_content_hierarchy_and_accessibility() -> None:
    row_body = function_body("drawRowName")
    tooltip_animation = function_body("startTooltipAnimation")

    assert "NSColor.labelColor" in swift, "Mission content should use adaptive semantic colors"
    assert "NSColor.secondaryLabelColor" in swift, "Secondary labels should adapt with system appearance"
    assert "override var allowsVibrancy: Bool { false }" in swift, "Configured colors should not be remapped by glass vibrancy"
    assert "drawWorkspaceIdentifier(workspace, focused: isFocused" in swift, "Each tile should expose its workspace identity"
    assert "context.rotate(by: -.pi / 2)" in row_body, "Project-lane labels should remain vertical"
    assert "roundedRect" not in row_body, "Project-lane labels should not sit inside pills"
    assert 'let number = "\\(row)"' not in row_body, "Project-lane labels should not show row numbers"
    assert ".foregroundColor: config.missionRowTextColor" in row_body, "Row text should preserve configured color and alpha exactly"
    assert "calibratedWhite: 0.04, alpha: 0.78" in swift, "Selection should use clear dark neutral emphasis"
    assert "hoveredWindowID" in swift, "Window rows should expose pointer feedback"
    assert "accessibilityDisplayShouldIncreaseContrast" in swift, "Custom drawing should honor Increase Contrast"
    assert "accessibilityDisplayShouldReduceTransparency" in swift, "Custom drawing should honor Reduce Transparency"
    assert "accessibilityDisplayShouldReduceMotion" in swift, "Custom motion should honor Reduce Motion"
    assert "accessibilityDisplayOptionsDidChangeNotification" in swift, "Accessibility changes should redraw live"
    assert "if reduceMotion" in tooltip_animation, "Tooltip motion should stop when Reduce Motion is enabled"


def test_mission_control_keyboard_controls() -> None:
    key_body = function_body("keyDown")
    adjacent_body = function_body("adjacentWorkspace")
    toggle_body = function_body("toggleMissionControl")
    jump_body = function_body("jump")

    assert "acceptsFirstResponder" in swift, "Mission Control should be able to receive key events"
    assert "keyboardNavigationDirection(for: event)" in key_body, "keyDown should route WASD navigation"
    assert 'case "w": return .up' in swift, "W should move to the previous visible row"
    assert 'case "a": return .left' in swift, "A should move to the previous visible column"
    assert 'case "s": return .down' in swift, "S should move to the next visible row"
    assert 'case "d": return .right' in swift, "D should move to the next visible column"
    assert "case 123: return .left" in swift, "Left Arrow should move to the previous visible column"
    assert "case 124: return .right" in swift, "Right Arrow should move to the next visible column"
    assert "case 125: return .down" in swift, "Down Arrow should move to the next visible row"
    assert "case 126: return .up" in swift, "Up Arrow should move to the previous visible row"
    assert "visibleRowValues.firstIndex(of: row)" in adjacent_body, "Navigation should use visible Mission Control rows"
    assert "visibleColValues.firstIndex(of: col)" in adjacent_body, "Navigation should use visible Mission Control columns"
    assert "onKeyboardWorkspaceNavigate?(workspace)" in key_body, "WASD and arrows should switch to the computed workspace"
    assert "jump(to: workspace, showMiniHud: false, refocusMissionControl: true)" in swift, "Navigation should keep Mission Control open"
    assert "case 36, 49, 76:" in key_body, "Return, Space, and keypad Enter should activate the highlighted workspace"
    assert "onWorkspaceClick?(focusedWorkspace)" in key_body, "Activation keys should reuse click-to-focus behavior"
    assert "event.keyCode == 53" in key_body, "Escape should be handled explicitly"
    assert "onKeyboardDismiss?()" in key_body, "Escape should request Mission Control dismissal"
    assert "missionView.onKeyboardDismiss" in swift, "App delegate should wire keyboard dismissal"
    assert "self?.hideMissionControl()" in swift, "Keyboard dismissal should close Mission Control"
    assert "missionPanel.orderFrontRegardless()" in toggle_body, "Opening Mission Control should order the hidden panel onscreen"
    assert "refocusMissionControlKeyboard()" in toggle_body, "Opening Mission Control should focus the key handler"
    assert "missionPanel.makeFirstResponder(missionView)" in swift, "Focus helper should target the Mission Control key handler"
    assert "refocusMissionControl: true" in swift, "Keyboard navigation should request focus restoration after AeroSpace switches apps"
    assert "refocusMissionControlKeyboard(after: 0.15)" in jump_body, "Keyboard navigation should re-key Mission Control after app focus settles"


def test_mission_control_dismisses_before_focusing_window() -> None:
    launch_body = function_body("applicationDidFinishLaunching")
    start = launch_body.index("missionView.onWindowClick")
    end = launch_body.index("missionView.onWindowMove", start)
    click_handler = launch_body[start:end]

    assert click_handler.index("hideMissionControl()") < click_handler.index("focus(window: window)"), (
        "Mission Control must dismiss before AeroSpace focuses a clicked window, "
        "or panel teardown can restore the previously active app"
    )


if __name__ == "__main__":
    failures = []
    for test in (
        test_mission_control_uses_active_rows_and_columns,
        test_sparse_active_grid_maps_rows_and_columns,
        test_edge_plus_expands_sparse_active_grid,
        test_plus_click_does_not_fall_through_to_workspace_click,
        test_right_click_can_add_workspace_before_or_after,
        test_workspace_insertion_shifts_only_same_lane_suffix,
        test_empty_cells_are_visible_drop_targets,
        test_empty_tiles_are_subtle_but_visible,
        test_mission_control_uses_native_liquid_glass,
        test_mission_control_glass_tokens_are_configurable,
        test_liquid_glass_content_hierarchy_and_accessibility,
        test_mission_control_keyboard_controls,
        test_mission_control_dismisses_before_focusing_window,
    ):
        try:
            test()
        except AssertionError as exc:
            failures.append(f"{test.__name__}: {exc}")

    if failures:
        print("FAIL")
        print("\n".join(failures))
        sys.exit(1)

    print("PASS")
