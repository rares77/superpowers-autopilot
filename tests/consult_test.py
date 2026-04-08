import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
CONSULT_SCRIPT = REPO_ROOT / "scripts" / "consult.sh"


class ConsultScriptTest(unittest.TestCase):
    def test_codex_uses_exec_without_overriding_default_codex_home(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            tmp = Path(tmpdir)
            project_dir = tmp / "project"
            project_dir.mkdir()
            (project_dir / "README.md").write_text("# Test Project\n")

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
                "printf '%s\\n' \"${CODEX_HOME:-UNSET}\" > \"$RECORDER_DIR/codex_home.txt\"\n"
                "printf '%s\\n' \"$*\" > \"$RECORDER_DIR/codex_args.txt\"\n"
                "printf '%s\\n' \"$PWD\" > \"$RECORDER_DIR/codex_pwd.txt\"\n"
                "cat > \"$RECORDER_DIR/codex_stdin.txt\"\n"
                "out_file=''\n"
                "prev=''\n"
                "for arg in \"$@\"; do\n"
                "  if [[ \"$prev\" == \"-o\" ]]; then out_file=\"$arg\"; fi\n"
                "  prev=\"$arg\"\n"
                "done\n"
                "printf 'consulted\\n' > \"$out_file\"\n"
            )
            codex.chmod(0o755)

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:/usr/bin:/bin"
            env["AUTOPILOT_CONSULTANT"] = "codex"
            env["RECORDER_DIR"] = str(recorder_dir)

            output = subprocess.check_output(
                [str(CONSULT_SCRIPT), "What is 2+2?", "smoke test"],
                text=True,
                cwd=project_dir,
                env=env,
            )

            codex_home = (recorder_dir / "codex_home.txt").read_text().strip()
            codex_args = (recorder_dir / "codex_args.txt").read_text().strip()
            codex_pwd = (recorder_dir / "codex_pwd.txt").read_text().strip()
            codex_stdin = (recorder_dir / "codex_stdin.txt").read_text()

            self.assertEqual(output.strip(), "consulted")
            self.assertEqual(codex_home, "UNSET")
            self.assertIn("exec -", codex_args)
            self.assertIn("--skip-git-repo-check", codex_args)
            self.assertIn("--ephemeral", codex_args)
            self.assertIn("-o", codex_args)
            self.assertIn("--sandbox read-only", codex_args)
            self.assertNotEqual(codex_pwd, str(project_dir))
            self.assertIn("[QUESTION]", codex_stdin)
            self.assertIn("What is 2+2?", codex_stdin)
            self.assertIn("Do not inspect repository files", codex_stdin)


if __name__ == "__main__":
    unittest.main()
