# Task Manager App — PRD

A simple task manager with two features.

## Features

### F1: Create and List Tasks
Users can create tasks with a title and see all tasks listed.
- POST /tasks creates a task with title (required) and description (optional)
- GET /tasks returns all tasks sorted by creation date
- Acceptance: task persists after server restart (SQLite)
- Acceptance: returns 400 if title is missing

### F2: Mark Tasks Complete
Users can mark a task as done.
- PATCH /tasks/:id/complete marks a task as done
- Completed tasks appear at the bottom of GET /tasks
- Acceptance: returns 404 if task id doesn't exist
- Acceptance: idempotent (marking already-done task is a no-op)
