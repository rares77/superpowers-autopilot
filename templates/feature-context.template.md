# Feature Context: {{feature_id}} — {{feature_name}}

## What I'm implementing

{{feature_name}}

## Acceptance criteria

{{#each acceptance_criteria}}
- {{this}}
{{/each}}

## Additional context from PRD

{{feature_body}}

## Project constraints

- Tech stack: {{tech_stack}}
- Existing test runner: {{test_runner}}
- Branch: {{branch}}
- Features already done (don't break these): {{done_features}}

## My task

Generate a TDD implementation plan for this feature.

Each task in the plan must:
1. Start with a failing test
2. Implement the minimum code to make it pass
3. Refactor if needed
4. Reference specific file paths (create them if they don't exist)

The plan will be executed by `superpowers:subagent-driven-development`.
Format it accordingly.
