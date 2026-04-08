import subprocess
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


if __name__ == "__main__":
    unittest.main()
