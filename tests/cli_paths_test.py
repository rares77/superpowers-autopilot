import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CLI_PATHS = REPO_ROOT / "scripts" / "lib" / "cli-paths.sh"


class CliPathsTest(unittest.TestCase):
    def test_run_with_timeout_has_python_fallback(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            sleeper = tmp / "sleepy.sh"
            sleeper.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "sleep 5\n"
            )
            sleeper.chmod(0o755)

            cmd = (
                f"source {CLI_PATHS} && "
                f"PATH=/usr/bin:/bin run_with_timeout 1 {sleeper}"
            )
            result = subprocess.run(
                ["/bin/bash", "-lc", cmd],
                text=True,
                capture_output=True,
            )

        self.assertEqual(result.returncode, 124)


if __name__ == "__main__":
    unittest.main()
