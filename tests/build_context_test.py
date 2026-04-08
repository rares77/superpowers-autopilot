import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BUILD_CONTEXT = REPO_ROOT / "scripts" / "build-context.sh"
PARSE_PRD = REPO_ROOT / "scripts" / "parse-prd.sh"


class BuildContextTest(unittest.TestCase):
    def test_build_context_does_not_require_jq(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            bin_dir = project_dir / "bin"
            bin_dir.mkdir()
            (project_dir / "README.md").write_text("# Demo\n")
            (project_dir / ".claude").mkdir()
            (project_dir / ".claude" / "autopilot-state.json").write_text(
                json.dumps(
                    {
                        "current_feature": "F1",
                        "features": [
                            {
                                "id": "F1",
                                "name": "Feature Without Jq",
                                "status": "queued",
                                "attempts": 1,
                                "spec": "Spec survives without jq.",
                                "acceptance_criteria": ["It still renders context"],
                                "plan_path": None,
                            }
                        ],
                    }
                )
            )

            for name, target in {
                "bash": "/bin/bash",
                "head": "/usr/bin/head",
                "cat": "/bin/cat",
                "python3": "/usr/bin/python3",
            }.items():
                (bin_dir / name).symlink_to(target)

            env = os.environ.copy()
            env["PATH"] = str(bin_dir)

            output = subprocess.check_output(
                ["/bin/bash", str(BUILD_CONTEXT)],
                text=True,
                cwd=project_dir,
                env=env,
            )

        self.assertIn("Name: Feature Without Jq", output)
        self.assertIn("Spec:\nSpec survives without jq.", output)
        self.assertNotIn("jq not available", output)

    def test_build_context_falls_back_to_body_for_legacy_state_files(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            project_dir = Path(tmpdir)
            (project_dir / "README.md").write_text("# Demo\n")
            (project_dir / ".claude").mkdir()
            (project_dir / ".claude" / "autopilot-state.json").write_text(
                json.dumps(
                    {
                        "current_feature": "F1",
                        "features": [
                            {
                                "id": "F1",
                                "name": "Legacy Feature",
                                "status": "queued",
                                "attempts": 0,
                                "body": "Legacy spec text from body.",
                                "acceptance_criteria": ["It works"],
                            }
                        ],
                    }
                )
            )

            output = subprocess.check_output(
                [str(BUILD_CONTEXT)],
                text=True,
                cwd=project_dir,
            )

        self.assertIn("Spec:\nLegacy spec text from body.", output)

    def test_parse_prd_emits_spec_field_for_feature_context(self):
        with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
            handle.write(
                "# Example PRD\n\n## Features\n\n### F1: Example\nFeature details.\n- Acceptance: it works\n"
            )
            prd_path = Path(handle.name)

        try:
            output = subprocess.check_output(
                [str(PARSE_PRD), str(prd_path)],
                text=True,
                cwd=REPO_ROOT,
            )
        finally:
            prd_path.unlink(missing_ok=True)

        features = json.loads(output)

        self.assertEqual(features[0]["spec"], "Feature details.\n- Acceptance: it works")


if __name__ == "__main__":
    unittest.main()
