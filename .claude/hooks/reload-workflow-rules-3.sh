#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the third part of the workflow rules on
# every prompt, from the FABLE PLANS entry to the end.
sed -n '/^- FABLE PLANS, OPUS EXECUTES/,$p' /home/mlitchard/gitlab/sashamud/.claude-memory/workflow-rules.md
