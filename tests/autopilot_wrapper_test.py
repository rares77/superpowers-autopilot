import json
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WRAPPER = REPO_ROOT / "scripts" / "autopilot.sh"
INSTALL_SCRIPT = REPO_ROOT / "scripts" / "install.sh"


class AutopilotWrapperTest(unittest.TestCase):
    def test_prints_usage_for_unknown_command(self):
        result = subprocess.run(
            [str(WRAPPER), "nope"],
            text=True,
            cwd=REPO_ROOT,
            capture_output=True,
        )

        self.assertEqual(result.returncode, 1)
        self.assertIn("Usage:", result.stderr)

    def test_guard_status_reports_inactive_and_active(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            inactive = subprocess.check_output(
                [str(WRAPPER), "guard-status"],
                text=True,
                cwd=project_dir,
            )

            (project_dir / ".claude").mkdir()
            (project_dir / ".claude" / "autopilot-active").touch()

            active = subprocess.check_output(
                [str(WRAPPER), "guard-status"],
                text=True,
                cwd=project_dir,
            )

        self.assertIn("INACTIVE", inactive)
        self.assertIn("ACTIVE", active)

    def test_runtime_state_reports_not_initialized_without_state_file(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            output = subprocess.check_output(
                [str(WRAPPER), "runtime-state"],
                text=True,
                cwd=tmpdir,
            )

        self.assertIn("not initialized", output)

    def test_resume_check_migrates_legacy_state_and_returns_pending_count(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            legacy_state = project_dir / "autopilot-state.json"
            legacy_state.write_text(
                '{"features":[{"id":"F1","status":"queued"},{"id":"F2","status":"done"}]}'
            )

            output = subprocess.check_output(
                [str(WRAPPER), "resume-check"],
                text=True,
                cwd=project_dir,
            )

            migrated = project_dir / ".claude" / "autopilot-state.json"

            self.assertEqual(output.strip(), "1")
            self.assertFalse(legacy_state.exists())
            self.assertTrue(migrated.exists())

    def test_startup_status_reports_fresh_project_in_one_command(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            subprocess.check_call(["git", "init"], cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.check_call([str(INSTALL_SCRIPT)], cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            output = subprocess.check_output(
                [str(WRAPPER), "startup-status"],
                text=True,
                cwd=project_dir,
            )

            data = json.loads(output)

            self.assertEqual(data["mode"], "fresh")
            self.assertEqual(data["pending_count"], 0)
            self.assertEqual(data["install_status"], "already-installed")
            self.assertFalse(data["restart_required"])
            self.assertIn("consultants", data)

    def test_start_run_initializes_state_branch_and_guard_in_one_command(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            subprocess.check_call(["git", "init"], cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.check_call([str(INSTALL_SCRIPT)], cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (project_dir / "PRD.md").write_text(
                "## Features\n\n### F1: Add item\n- Acceptance: Can add items\n"
            )

            output = subprocess.check_output(
                [str(WRAPPER), "start-run", "PRD.md", "self"],
                text=True,
                cwd=project_dir,
            )

            data = json.loads(output)
            state_file = project_dir / ".claude" / "autopilot-state.json"
            active_file = project_dir / ".claude" / "autopilot-active"
            branch = subprocess.check_output(
                ["git", "branch", "--show-current"],
                text=True,
                cwd=project_dir,
            ).strip()

            self.assertEqual(data["consultant"], "self")
            self.assertEqual(branch, data["branch"])
            self.assertTrue(branch.startswith("autopilot/"))
            self.assertTrue(state_file.exists())
            self.assertTrue(active_file.exists())
            self.assertEqual(len(data["queued_features"]), 1)

    def test_consult_uses_consultant_from_state_when_env_is_missing(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            project_dir = tmp / "project"
            project_dir.mkdir()
            subprocess.check_call(["git", "init"], cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.check_call([str(INSTALL_SCRIPT)], cwd=project_dir, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            (project_dir / "README.md").write_text("# Test Project\n")
            (project_dir / ".claude" / "autopilot-state.json").write_text(
                '{"consultant":"codex","features":[{"id":"F1","name":"Feature 1","status":"queued"}]}'
            )

            recorder_dir = tmp / "recordings"
            recorder_dir.mkdir()
            bin_dir = tmp / "bin"
            bin_dir.mkdir()
            codex = bin_dir / "codex"
            codex.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "if [[ \"${1:-}\" == \"--version\" ]]; then\n"
                "  echo \"codex test\"\n"
                "  exit 0\n"
                "fi\n"
                "printf '%s\\n' \"$*\" > \"$RECORDER_DIR/codex_args.txt\"\n"
                "cat > \"$RECORDER_DIR/codex_stdin.txt\"\n"
                "echo \"consulted\"\n"
            )
            codex.chmod(0o755)

            env = {
                "PATH": f"{bin_dir}:/usr/bin:/bin",
                "RECORDER_DIR": str(recorder_dir),
            }

            output = subprocess.check_output(
                [str(WRAPPER), "consult", "What should we do?", "smoke test"],
                text=True,
                cwd=project_dir,
                env=env,
            )

            codex_args = (recorder_dir / "codex_args.txt").read_text().strip()
            codex_stdin = (recorder_dir / "codex_stdin.txt").read_text()

            self.assertEqual(output.strip(), "consulted")
            self.assertEqual(codex_args, "exec - --full-auto")
            self.assertIn("What should we do?", codex_stdin)


if __name__ == "__main__":
    unittest.main()
