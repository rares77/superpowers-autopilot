import json
import subprocess
import tempfile
import textwrap
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
PARSE_PRD = REPO_ROOT / "scripts" / "parse-prd.sh"


def parse_prd(content: str):
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as handle:
        handle.write(content)
        tmp_path = Path(handle.name)

    try:
        output = subprocess.check_output(
            [str(PARSE_PRD), str(tmp_path)],
            text=True,
            cwd=REPO_ROOT,
        )
    finally:
        tmp_path.unlink(missing_ok=True)

    return json.loads(output)


class ParsePrdTest(unittest.TestCase):
    def test_prefers_explicit_acceptance_lines_over_general_bullets(self):
        prd = textwrap.dedent(
            """
            # Example PRD

            ## Features

            ### F1: Project Setup and Foundation
            Initialize a monorepo structure with Next.js frontend and Express backend.
            - Create root package.json with workspace configuration
            - Set up frontend/ directory with Next.js 14
            - Set up backend/ directory with Express
            - Configure TypeScript for both projects
            - Add .gitignore and environment variable templates
            - Acceptance: `npm install` succeeds in root, frontend/, and backend/
            """
        ).strip()

        features = parse_prd(prd)

        self.assertEqual(
            features[0]["acceptance_criteria"],
            ["`npm install` succeeds in root, frontend/, and backend/"],
        )

    def test_extracts_acceptance_criteria_section_when_present(self):
        prd = textwrap.dedent(
            """
            # PRD: Simple TODO App

            ## Features

            ### F1: Add TODO Items

            Users can add new tasks to their list.

            **Requirements:**
            - Input field and submit button on the main page
            - Tasks should be stored appropriately for the use case

            **Acceptance criteria:**
            - A user can type a task and submit it
            - Invalid input is rejected with a helpful message
            - The task appears in the list without a page reload
            """
        ).strip()

        features = parse_prd(prd)

        self.assertEqual(
            features[0]["acceptance_criteria"],
            [
                "A user can type a task and submit it",
                "Invalid input is rejected with a helpful message",
                "The task appears in the list without a page reload",
            ],
        )


if __name__ == "__main__":
    unittest.main()
