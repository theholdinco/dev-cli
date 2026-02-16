# Task: When doing a task, the AI should only mark as complete after it has created and submitted the PR. Also, the PR should have a custom title and description, not the prompt that we give as the title, but an actual title and description that tell what it did, etc.

## Project
cli

## Branch
task-create-pr

## Instructions

Please implement the following task:

When doing a task, the AI should only mark as complete after it has created and submitted the PR. Also, the PR should have a custom title and description, not the prompt that we give as the title, but an actual title and description that tell what it did, etc.

## When done

1. Make sure all changes are committed
2. Run any relevant tests to verify your changes work
3. Create a file called `.task-done` in the project root: `touch .task-done`

This signals the task runner that you've completed the work.
