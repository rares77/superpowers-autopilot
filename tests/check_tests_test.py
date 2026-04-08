import subprocess
import tempfile
import unittest
from pathlib import Path
import os


REPO_ROOT = Path(__file__).resolve().parents[1]
CHECK_TESTS = REPO_ROOT / "scripts" / "check-tests.sh"


class CheckTestsScriptTest(unittest.TestCase):
    def test_pytest_branch_uses_python3(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            (project_dir / "pyproject.toml").write_text(
                "[project]\nname = 'demo'\nversion = '0.1.0'\n"
            )
            bin_dir = project_dir / "bin"
            bin_dir.mkdir()

            (bin_dir / "bash").symlink_to("/bin/bash")
            (bin_dir / "tail").symlink_to("/usr/bin/tail")
            python3_stub = bin_dir / "python3"
            python3_stub.write_text(
                "#!/usr/bin/env bash\n"
                "echo \"$@\" > \"$CHECK_TESTS_PYTHON3_LOG\"\n"
                "exit 0\n"
            )
            python3_stub.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = str(bin_dir)
            env["CHECK_TESTS_PYTHON3_LOG"] = str(project_dir / "python3.log")

            output = subprocess.check_output(
                [str(CHECK_TESTS)],
                text=True,
                cwd=project_dir,
                env=env,
            )

            invoked = (project_dir / "python3.log").read_text()

        self.assertIn("All tests passing", output)
        self.assertIn("-m pytest --tb=short -q", invoked)


if __name__ == "__main__":
    unittest.main()
