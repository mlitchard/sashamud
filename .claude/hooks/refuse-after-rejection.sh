#!/usr/bin/env bash
# PreToolUse hook. Refuses every call, main session and subagents, while
# .claude/rejected exists. Main-session Bash passes so "!" access stays.
repo=/home/mlitchard/gitlab/sashamud
input=$(cat)
if [ ! -e "$repo/.claude/rejected" ]; then
  jq -n '{}'
  exit 0
fi
tool=$(printf '%s' "$input" | jq -r '.tool_name')
if [ "$tool" = "Bash" ] && ! printf '%s' "$input" | jq -e '.agent_type' > /dev/null; then
  jq -n '{}'
  exit 0
fi
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"A proposal or edit was rejected. Stop and discuss with the user."}}'
