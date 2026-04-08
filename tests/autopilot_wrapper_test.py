import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
WRAPPER = REPO_ROOT / "scripts" / "autopilot.sh"


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


if __name__ == "__main__":
    unittest.main()
