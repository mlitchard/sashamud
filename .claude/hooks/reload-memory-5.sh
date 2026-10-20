#!/usr/bin/env bash
# UserPromptSubmit hook. Re-injects the fifth part of the project memory on
# every prompt, Live DSL / Lobby and LLM sentence repair to the end.
sed -n '/^## Live DSL/,$p' /home/mlitchard/gitlab/sashamud/.claude-memory/MEMORY.md
