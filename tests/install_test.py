import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
INSTALL_SCRIPT = REPO_ROOT / "scripts" / "install.sh"


class InstallScriptTest(unittest.TestCase):
    def test_explains_git_init_when_run_outside_repo(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            result = subprocess.run(
                [str(INSTALL_SCRIPT)],
                text=True,
                cwd=tmpdir,
                capture_output=True,
            )

        self.assertEqual(result.returncode, 2)
        self.assertIn("run this from a git project root", result.stderr)
        self.assertIn("run 'git init' first", result.stderr)


if __name__ == "__main__":
    unittest.main()
