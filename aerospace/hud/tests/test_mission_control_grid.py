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
    assert "Array(rowSet).sorted()" in body, "Active rows should be sorted for stable layout"
    assert "Array(colSet).sorted()" in body, "Active columns should be sorted for stable layout"
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


if __name__ == "__main__":
    failures = []
    for test in (
        test_mission_control_uses_active_rows_and_columns,
        test_sparse_active_grid_maps_rows_and_columns,
        test_edge_plus_expands_sparse_active_grid,
        test_plus_click_does_not_fall_through_to_workspace_click,
        test_empty_cells_are_visible_drop_targets,
        test_empty_tiles_are_subtle_but_visible,
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
