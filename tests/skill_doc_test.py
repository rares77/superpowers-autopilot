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
            "Stop after printing the consultant picker and wait for the user's choice.",
            content,
        )


if __name__ == "__main__":
    unittest.main()
