import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
DETECT_SCRIPT = REPO_ROOT / "scripts" / "detect-consultants.sh"


class ConsultantDetectionTest(unittest.TestCase):
    def test_detects_clis_from_common_non_path_locations(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            home = tmp / "home"
            home.mkdir()

            local_bin = home / ".local" / "bin"
            local_bin.mkdir(parents=True)
            claude = local_bin / "claude"
            claude.write_text("#!/usr/bin/env bash\nif [[ \"$1\" == \"--version\" ]]; then exit 0; fi\n")
            claude.chmod(0o755)

            nvm_bin = home / ".nvm" / "versions" / "node" / "v22.17.1" / "bin"
            nvm_bin.mkdir(parents=True)
            for name in ("codex", "gemini"):
                exe = nvm_bin / name
                exe.write_text("#!/usr/bin/env bash\nif [[ \"$1\" == \"--version\" ]]; then exit 0; fi\n")
                exe.chmod(0o755)

            env = os.environ.copy()
            env["HOME"] = str(home)
            env["PATH"] = "/usr/bin:/bin"

            output = subprocess.check_output(
                [str(DETECT_SCRIPT)],
                text=True,
                cwd=REPO_ROOT,
                env=env,
            )

        data = json.loads(output)
        self.assertIn("claude:opus", data["available"])
        self.assertIn("claude:sonnet", data["available"])
        self.assertIn("codex", data["available"])
        self.assertIn("gemini", data["available"])


if __name__ == "__main__":
    unittest.main()
