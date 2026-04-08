# PRD Format Support

`parse-prd.sh` auto-detects the format. This file documents what each format looks like and how it's parsed.

---

## Format A: Markdown Headers (default)

Detected by: `### F1:` or `### Feature 1:` or `### 1.` headers inside a `## Features` section.

```markdown
## Features

### F1: User Authentication
- OAuth2 with Google/GitHub
- JWT token management
- Acceptance: login flow completes in <2s

### F2: Dashboard
- Real-time data display
- Acceptance: updates within 500ms
```

**Parser behavior:**
- Each `###` header becomes a feature
- Bullet points under the header → `acceptance_criteria[]`
- Lines containing "Acceptance", "AC:", or "criteria" get priority as AC
- Body text (up to 500 chars) preserved for context injection

---

## Format B: YAML Frontmatter

Detected by: file starts with `---` and contains a `features:` key.

```yaml
---
features:
  - id: F1
    name: User Authentication
    priority: high
    acceptance_criteria:
      - OAuth2 login works
      - JWT tokens refresh automatically
  - id: F2
    name: Dashboard
    priority: medium
    acceptance_criteria:
      - Real-time updates within 500ms
---

# Product Overview
...rest of PRD...
```

**Parser behavior:**
- Each item in `features[]` becomes a feature
- `id` and `name` required; `priority` optional
- `acceptance_criteria[]` mapped directly

---

## Format C: Superpowers Brainstorm Output

Detected by: `## What We're Building` or `## Features` section with `###`/`####` subsections.

```markdown
## What We're Building

### User Authentication
Enable users to sign in with Google or GitHub using OAuth2.
- JWT token management
- Session persistence

### Dashboard
Real-time data visualization with live updates.
- Updates within 500ms via WebSocket
```

**Parser behavior:**
- Finds the "What We're Building" section
- Each `###` or `####` subsection → one feature
- Bullet points → `acceptance_criteria[]`
- IDs auto-assigned as F1, F2, F3...

---

## Tips for Best Results

1. **Be explicit with acceptance criteria** — the parser looks for bullet points. The more specific they are, the better the plan validator can check them.

2. **Use numbered IDs when possible** — `### F1:` gives stable IDs across re-parses. Auto-assigned IDs (F1, F2...) may shift if you add features.

3. **Order matters** — features are queued in document order. Put foundational features (auth, DB schema) before dependent ones (dashboard, reports).

4. **Use one of the supported formats** — if your PRD uses a custom structure, rewrite the feature list into one of the documented formats before running autopilot.
