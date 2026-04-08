# PRD: Simple TODO App

> **Demo PRD** — designed to showcase how superpowers-autopilot handles ambiguous
> requirements. Features 1 and 2 contain deliberate ambiguities that the skill's
> design review will catch and resolve via the consultant before planning begins.
> Feature 3 is clear and requires no consultation.

---

## Overview

A lightweight TODO application for managing personal tasks. Users can add tasks,
mark them as complete or delete them, and view their list with basic filtering.

**Tech stack:** Node.js + Express backend, plain HTML/JS frontend, no framework.

---

## Features

### F1: Add TODO Items

Users can add new tasks to their list.

**Requirements:**
- Input field and submit button on the main page
- Tasks should be stored appropriately for the use case
- Validate input before saving — reject inappropriate entries
- The UI should feel fast and responsive
- Show the new task immediately after adding

**Acceptance criteria:**
- A user can type a task and submit it
- Invalid input is rejected with a helpful message
- The task appears in the list without a page reload

> ⚠ **Deliberate ambiguities in F1:**
> - "stored appropriately" — in-memory? SQLite? localStorage? flat file?
> - "reject inappropriate entries" — what counts as invalid? max length? empty only?
> - "fast and responsive" — no concrete metric (ms threshold, animation, etc.)

---

### F2: Complete and Delete Tasks

Users can mark tasks as done or remove them entirely.

**Requirements:**
- Each task should have controls for completion and deletion
- Completing a task should use the best UX approach for this type of app
- Deletion should follow industry standard practices
- Completed tasks should be visually distinct
- The list should update instantly without a reload

**Acceptance criteria:**
- Clicking complete toggles the task's done state
- Clicking delete removes the task from the list
- Done tasks look different from active ones

> ⚠ **Deliberate ambiguities in F2:**
> - "best UX approach for completion" — checkbox? swipe? button? stays in list or moves?
> - "industry standard practices for deletion" — confirmation dialog? undo toast? immediate?
> - No guidance on whether completed tasks should be hidden, greyed out, or struck through

---

### F3: Filter and View Tasks

Users can filter their task list by status.

**Requirements:**
- Three filter tabs: All / Active / Done
- Show a count of remaining active tasks (e.g. "3 tasks left")
- A "Clear completed" button removes all done tasks at once
- Active filter tab is visually highlighted
- Filters apply instantly, no reload

**Acceptance criteria:**
- "All" shows every task
- "Active" shows only incomplete tasks
- "Done" shows only completed tasks
- "Clear completed" removes all done tasks in one action
- Active task count updates whenever tasks are added, completed, or deleted

> ✅ **F3 is intentionally clear** — no ambiguities, no consultant needed.
> The design review should confirm this and proceed directly to planning.
