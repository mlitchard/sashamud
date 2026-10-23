#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the project memory from Rhine Architecture
# through Remaining for Step 3c on every prompt.
sed -n '/^## Rhine Architecture/,/^## Witness System Design/p' /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md | sed '$d'
