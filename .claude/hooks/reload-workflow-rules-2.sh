#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the second part of the workflow rules on
# every prompt, from the NO GIT COMMANDS entry up to the FABLE PLANS entry.
sed -n '/^- NO GIT COMMANDS/,/^- FABLE PLANS, OPUS EXECUTES/p' /home/mlitchard/gitlab/sashamud/.claude-memory/workflow-rules.md | sed '$d'
