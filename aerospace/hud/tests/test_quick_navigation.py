#!/usr/bin/env python3
"""Behavioral tests for grid shortcuts, with no live workspace changes."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[2]
SCRIPTS = ROOT / "scripts"
MOCK = '''#!/usr/bin/env python3
import json, os, sys, time
from pathlib import Path
args = sys.argv[1:]
data = json.loads(Path(os.environ["MOCK_DATA"]).read_text())
with open(os.environ["MOCK_LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
if args[0] in data.get("fail", []):
    sys.exit(1)
if args[0] == "list-workspaces":
    print(data.get("focused", "w10"))
elif args[0] == "list-windows":
    if "--focused" in args:
        print(os.environ.get("MOCK_WINDOW_ID", data.get("window_id", "1")))
    else:
        print(data.get("inventory", ""))
elif args[0] == "workspace":
    time.sleep(data.get("delay", 0))
    data["focused"] = args[-1]
    Path(os.environ["MOCK_DATA"]).write_text(json.dumps(data))
elif args[0] == "move-node-to-workspace" and data.get("update_inventory"):
    time.sleep(data.get("delay", 0))
    window_id = args[args.index("--window-id") + 1]
    lines = []
    for line in data["inventory"].splitlines():
        parts = line.split("\\t")
        if parts[1] == window_id:
            parts[0] = args[-1]
        lines.append("\\t".join(parts))
    data["inventory"] = "\\n".join(lines)
    Path(os.environ["MOCK_DATA"]).write_text(json.dumps(data))
'''


class QuickNavigationTests(unittest.TestCase):
    def setUp(self):
        artifacts = SCRIPTS / ".build"
        artifacts.mkdir(exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(prefix="quick-tests-", dir=artifacts)
        self.addCleanup(self.temp.cleanup)
        self.directory = Path(self.temp.name)
        self.state = self.directory / "focused"
        self.count = self.directory / "count"
        self.data = self.directory / "data.json"
        self.log = self.directory / "commands.jsonl"
        executable = self.directory / "aerospace"
        executable.write_text(MOCK)
        executable.chmod(0o755)
        self.env = dict(os.environ, AEROSPACE_BIN=str(executable),
                        AEROSPACE_FOCUSED_STATE_FILE=str(self.state),
                        AEROSPACE_QUICK_SPACES_FILE=str(self.count),
                        MOCK_DATA=str(self.data), MOCK_LOG=str(self.log))
        self.configure()

    def configure(self, current="w10", count="3", **data):
        self.state.write_text(current + "\n")
        self.count.write_text(count + "\n")
        self.data.write_text(json.dumps(data))
        self.log.write_text("")

    def commands(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def navigate(self, axis, direction, success=True):
        result = subprocess.run([str(SCRIPTS / "grid-workspace.sh"), axis, direction],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return self.state.read_text().strip()

    def move(self, target, success=True):
        result = subprocess.run(["bash", "-c", 'set -euo pipefail; source "$1"; grid_move_focused_window "$2"',
                                 "test", str(SCRIPTS / "grid-common.sh"), target],
                                env=self.env, text=True, capture_output=True)
        self.assertEqual(result.returncode == 0, success, result.stderr)
        return result

    def test_base_up_and_quick_down(self):
        self.configure(current="w17", count="3")
        self.assertEqual(self.navigate("row", "prev"), "q2")
        self.assertEqual(self.navigate("row", "next"), "w12")

    def test_quick_row_has_more_than_ten_spaces(self):
        self.configure(current="q10", count="24")
        self.assertEqual(self.navigate("col", "next"), "q11")
        self.assertEqual(self.navigate("col", "prev"), "q10")
        self.assertEqual(self.navigate("row", "next"), "w19")

    def test_quick_edges_clamp(self):
        self.configure(current="q0")
        self.assertEqual(self.navigate("col", "prev"), "q0")
        self.assertEqual(self.navigate("row", "prev"), "q0")
        self.configure(current="q2")
        self.assertEqual(self.navigate("col", "next"), "q2")

    def test_default_and_corrupt_counts(self):
        for count in ("", "bad", "0", "-1", "999999999999999999999999999"):
            with self.subTest(count=count):
                self.configure(current="w19", count=count)
                self.assertEqual(self.navigate("row", "prev"), "q0")
        self.count.unlink()
        self.assertEqual(self.navigate("col", "next"), "q0")

    def test_current_quick_space_is_never_lost(self):
        self.configure(current="q27", count="1")
        self.assertEqual(self.navigate("col", "next"), "q27")
        self.assertEqual(self.navigate("col", "prev"), "q26")

    def test_regular_grid_unchanged(self):
        for current, axis, direction, target in (
            ("w10", "col", "prev", "w10"), ("w19", "col", "next", "w19"),
            ("w99", "row", "next", "w99"), ("w23", "row", "prev", "w13"),
            ("w13", "row", "next", "w23"), ("p2", "col", "next", "w21"),
            ("p23", "row", "prev", "w13"),
        ):
            with self.subTest(current=current):
                self.configure(current=current)
                self.assertEqual(self.navigate(axis, direction), target)

    def test_focus_parser_skips_cli_warning(self):
        self.configure(current="invalid", focused="Warning: restored workspace\nq12")
        self.assertEqual(self.navigate("row", "next"), "w19")

    def test_failure_does_not_change_focus_hint(self):
        self.configure(current="w10", fail=["workspace"])
        self.assertEqual(self.navigate("row", "prev", success=False), "w10")

    def test_empty_quick_space_accepts_app(self):
        self.configure(inventory="w10\t1\tSpotify\tcom.spotify.client")
        self.move("q0")
        self.assertEqual(self.state.read_text().strip(), "q0")
        self.assertIn(["move-node-to-workspace", "--window-id", "1", "--focus-follows-window", "q0"], self.commands())

    def test_same_bundle_allows_multiple_windows(self):
        self.configure(inventory="w10\t1\tSlack\tcom.slack\nq0\t2\tSlack Helper\tcom.slack\nq0\t3\tSlack\tcom.slack")
        self.move("q0")

    def test_different_application_is_rejected(self):
        self.configure(inventory="w10\t1\tSpotify\tcom.spotify\nq0\t2\tSlack\tcom.slack")
        result = self.move("q0", success=False)
        self.assertIn("one application", result.stderr)
        self.assertFalse(any(c[0] == "move-node-to-workspace" for c in self.commands()))
        self.assertEqual(self.state.read_text().strip(), "w10")

    def test_same_name_different_bundle_is_rejected(self):
        self.configure(inventory="w10\t1\tApp\tcom.first\nq0\t2\tApp\tcom.second")
        self.move("q0", success=False)

    def test_missing_bundle_falls_back_to_app_name(self):
        self.configure(inventory="w10\t1\tSlack\t\nq0\t2\tSlack\tcom.slack")
        self.move("q0")
        self.configure(inventory="w10\t1\tSpotify\t\nq0\t2\tSlack\t")
        self.move("q0", success=False)

    def test_no_focused_window_or_failed_inventory_fails_closed(self):
        for data in ({"inventory": ""}, {"window_id": ""}, {"fail": ["list-windows"]},
                     {"inventory": "w10\t1\tSlack\tcom.slack\nq0\t2\tSlack"}):
            with self.subTest(data=data):
                self.configure(**data)
                self.move("q0", success=False)
                self.assertFalse(any(c[0] == "move-node-to-workspace" for c in self.commands()))

    def test_failed_move_preserves_focus(self):
        self.configure(inventory="w10\t1\tSlack\tcom.slack", fail=["move-node-to-workspace"])
        self.move("q0", success=False)
        self.assertEqual(self.state.read_text().strip(), "w10")

    def test_focused_window_parser_skips_warning(self):
        self.configure(window_id="Warning: restored window\n1", inventory="w10\t1\tSlack\tcom.slack")
        self.move("q0")

    def test_overlapping_navigation_preserves_each_step(self):
        self.configure(current="q0", delay=0.15)
        args = [str(SCRIPTS / "grid-workspace.sh"), "col", "next"]
        first = subprocess.Popen(args, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        second = subprocess.Popen(args, env=self.env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        for process in (first, second):
            _, error = process.communicate(timeout=10)
            self.assertEqual(process.returncode, 0, error)
        self.assertEqual(self.state.read_text().strip(), "q2")
        self.assertEqual([c for c in self.commands() if c[0] == "workspace"], [["workspace", "q1"], ["workspace", "q2"]])

    def test_concurrent_different_apps_cannot_claim_same_empty_space(self):
        self.configure(inventory="w10\t1\tSlack\tcom.slack\nw11\t2\tSpotify\tcom.spotify",
                       update_inventory=True, delay=0.15)
        args = ["bash", "-c", 'set -euo pipefail; source "$1"; grid_move_focused_window q0',
                "test", str(SCRIPTS / "grid-common.sh")]
        processes = [subprocess.Popen(args, env=dict(self.env, MOCK_WINDOW_ID=window_id),
                                      stdout=subprocess.PIPE, stderr=subprocess.PIPE) for window_id in ("1", "2")]
        for process in processes:
            process.communicate(timeout=10)
        self.assertEqual(sorted(p.returncode for p in processes), [0, 1])
        self.assertEqual(len([c for c in self.commands() if c[0] == "move-node-to-workspace"]), 1)

    def test_stale_lock_is_recovered(self):
        # A reaped child PID is no longer the owner of a live lock.
        child = subprocess.Popen(["true"])
        child.wait()
        Path(str(self.count) + ".lock").write_text(str(child.pid) + "\n")
        self.assertEqual(self.navigate("row", "prev"), "q0")
        self.assertFalse(Path(str(self.count) + ".lock").exists())

    def test_show_hud_reads_focus_after_slow_launch(self):
        self.configure(current="q0", focused="q0")
        started = self.directory / "started"
        resume = self.directory / "resume"
        launcher = self.directory / "launch.sh"
        launcher.write_text('#!/usr/bin/env bash\n: > "$MOCK_STARTED"\nwhile [[ ! -f "$MOCK_RESUME" ]]; do sleep 0.01; done\n')
        launcher.chmod(0o755)
        script = (SCRIPTS / "show-hud.sh").read_text()
        script = script.replace('/Users/aminmoradi/workspace/configs/aerospace/hud/run.sh', str(launcher))
        script = script.replace('/tmp/aerospace-mission-control-toggle', str(self.directory / "toggle"))
        (self.directory / "grid-common.sh").write_text((SCRIPTS / "grid-common.sh").read_text())
        show = self.directory / "show-hud.sh"
        show.write_text(script)
        process = subprocess.Popen(["bash", str(show)],
                                   env=dict(self.env, MOCK_STARTED=str(started), MOCK_RESUME=str(resume)),
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            deadline = time.monotonic() + 5
            while not started.exists() and time.monotonic() < deadline:
                time.sleep(0.01)
            self.assertTrue(started.exists(), "Mock launcher did not start")
            self.assertEqual(self.navigate("col", "next"), "q1")
        finally:
            resume.touch()
            _, error = process.communicate(timeout=10)
        self.assertEqual(process.returncode, 0, error)
        self.assertEqual(self.state.read_text().strip(), "q1")
        self.assertTrue((self.directory / "toggle").read_text().startswith("q1 "))
        self.assertEqual(self.navigate("col", "next"), "q2")

    def test_mouse_wrapper_navigates_or_moves(self):
        # Copy the real entry point beside a deterministic mouse-button helper.
        wrapper = self.directory / "grid-workspace-or-mouse-move.sh"
        wrapper.write_text((SCRIPTS / wrapper.name).read_text())
        (self.directory / "grid-common.sh").write_text((SCRIPTS / "grid-common.sh").read_text())
        mouse = self.directory / "mouse-button-down.sh"
        mouse.write_text('#!/usr/bin/env bash\nexit "${MOCK_MOUSE_EXIT:-1}"\n')
        mouse.chmod(0o755)
        for mouse_exit, command in (("1", "workspace"), ("0", "move-node-to-workspace")):
            with self.subTest(mouse_exit=mouse_exit):
                self.configure(inventory="w10\t1\tSlack\tcom.slack")
                result = subprocess.run(["bash", str(wrapper), "row", "prev"],
                                        env=dict(self.env, MOCK_MOUSE_EXIT=mouse_exit),
                                        text=True, capture_output=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(self.commands()[-1][0], command)
                self.assertEqual(self.state.read_text().strip(), "q0")
        self.configure(inventory="w10\t1\tSlack\tcom.slack\nq0\t2\tSpotify\tcom.spotify")
        result = subprocess.run(["bash", str(wrapper), "row", "prev"],
                                env=dict(self.env, MOCK_MOUSE_EXIT="0"), capture_output=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text().strip(), "w10")

    def test_direct_jump_accepts_quick_spaces(self):
        result = subprocess.run([str(SCRIPTS / "grid-jump.sh"), "q21"], env=self.env, capture_output=True)
        self.assertEqual(result.returncode, 0)
        self.assertEqual(self.state.read_text().strip(), "q21")
        result = subprocess.run([str(SCRIPTS / "grid-jump.sh"), "q01"], env=self.env, capture_output=True)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
