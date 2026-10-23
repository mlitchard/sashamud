#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the fourth part of the project memory on
# every prompt, Code Rules through Key Files.
sed -n '/^## Code Rules/,/^## Live DSL/p' /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md | sed '$d'
