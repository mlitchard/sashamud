#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the first part of the workflow rules on
# every prompt. The workflow rules are split across two hooks so each stays
# under the per-hook output cap.
sed '/^- NO GIT COMMANDS/,$d' /home/mlitchard/gitlab/sashamud/.claude-memory/workflow-rules.md
