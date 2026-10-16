#!/usr/bin/env bash
# PermissionDenied hook. Marks a rejection by creating .claude/rejected so that
# refuse-after-rejection.sh stops all further work until the next user prompt.
repo=/home/mlitchard/gitlab/sashamud
touch "$repo/.claude/rejected"
jq -n '{}'
