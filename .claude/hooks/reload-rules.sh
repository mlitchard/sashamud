#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects CLAUDE.md on every prompt so the rules do
# not drift out of context. The project memory follows in the reload-memory
# hooks, split so each stays under the per-hook output cap.
repo=/home/mlitchard/gitlab/sashamud
rm -f "$repo/.claude/rejected"
cat "$repo/CLAUDE.md"
