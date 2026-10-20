#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the third part of the project memory on
# every prompt, Design Decisions.
sed -n '/^## Design Decisions/,/^## Code Rules/p' /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md | sed '$d'
