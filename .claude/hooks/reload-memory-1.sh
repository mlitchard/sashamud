#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the first part of the project memory on
# every prompt, the CRITICAL RULES block.
sed '/^## Rhine Architecture/,$d' /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md
