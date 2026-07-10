#!/usr/bin/env python3
"""Source-level regression tests for Mission Control grid behavior."""

from pathlib import Path
import re
import sys

SOURCE = Path(__file__).resolve().parents[1] / "AeroSpaceHud.swift"
swift = SOURCE.read_text()


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


def test_empty_cells_are_visible_drop_targets() -> None:
    body = function_body("isCellVisible")
    assert body.strip() == "true", "Every active-row/active-column cell should be drawn and hit-testable"


def test_empty_tiles_are_subtle_but_visible() -> None:
    occupied = alpha("tileFill")
    empty = alpha("tileFillEmpty")
    assert 0 < empty < occupied, "Empty tiles should be more transparent than occupied tiles"
    assert empty >= occupied * 0.55, "Empty tiles should remain visible enough to target"


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
        test_empty_cells_are_visible_drop_targets,
        test_empty_tiles_are_subtle_but_visible,
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
