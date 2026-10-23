#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the second part of the project memory on
# every prompt, Witness System Design and NarrationMap Design.
sed -n '/^## Witness System Design/,/^## Design Decisions/p' /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md | sed '$d'
