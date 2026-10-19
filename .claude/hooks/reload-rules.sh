#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects CLAUDE.md, the CRITICAL RULES block and the
# Code Rules block of the project memory on every prompt so the rules do not
# drift out of context.
repo=/home/mlitchard/gitlab/sashamud
rm -f "$repo/.claude/rejected"
cat "$repo/CLAUDE.md"
printf '\n'
sed -n '/^## CRITICAL RULES/,/^## Rhine Architecture/p' "$repo/.claude-memory/MEMORY.md" | sed '$d'
printf '\n'
sed -n '/^## Code Rules/,/^## Dead Files/p' "$repo/.claude-memory/MEMORY.md" | sed '$d'
