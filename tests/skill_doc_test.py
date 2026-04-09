import re
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
SKILL_DOC = REPO_ROOT / "SKILL.md"


class SkillDocTest(unittest.TestCase):
    def test_runtime_context_has_no_bash_commands(self):
        content = SKILL_DOC.read_text()
        match = re.search(r"## Runtime Context\n(.*?)\n## Overview", content, re.S)
        self.assertIsNotNone(match)
        runtime_section = match.group(1)
        self.assertNotIn("!`", runtime_section)

    def test_consultant_selection_requires_waiting_for_user_choice(self):
        content = SKILL_DOC.read_text()
        self.assertIn(
            "Stop after asking the consultant question and wait for the user's choice.",
            content,
        )
        self.assertIn(
            "Do not try to emulate a custom picker, menu, or pseudo-UI in the prompt itself.",
            content,
        )

    def test_skill_uses_single_startup_commands_without_shell_decorations(self):
        content = SKILL_DOC.read_text()
        self.assertIn("./.claude/autopilot.sh startup-status", content)
        self.assertIn("./.claude/autopilot.sh start-run <PRD_PATH> <chosen-consultant>", content)
        bash_blocks = re.findall(r"```bash\n(.*?)```", content, re.S)
        bash_content = "\n".join(bash_blocks)
        self.assertNotIn("2>&1", bash_content)
        self.assertNotIn("EXIT:$?", bash_content)
        self.assertNotIn("&&", bash_content)
        self.assertNotIn("||", bash_content)

    def test_writing_plans_is_constrained_for_autopilot(self):
        content = SKILL_DOC.read_text()
        self.assertIn("Treat `.claude/` and cloned skill files as tooling noise", content)
        self.assertIn("use the required `file_path` parameter", content)
        self.assertIn("avoid raw risky DOM sink examples such as `innerHTML`", content)
        self.assertIn("Do not start changing implementation files during planning.", content)
        self.assertIn("Autopilot always chooses subagent-driven execution.", content)

    def test_feature_begin_and_consultant_constraints_are_documented(self):
        content = SKILL_DOC.read_text()
        self.assertIn("./.claude/autopilot.sh begin-feature <feature-id>", content)
        self.assertIn("This sets both `current_feature` and `status = \"in_progress\"`", content)
        self.assertIn("do not inspect repository files", content)
        self.assertIn("do not invoke skills", content)
        self.assertIn("do not propose workflows or planning rituals", content)


if __name__ == "__main__":
    unittest.main()
