#!/usr/bin/env bash
# PreToolUse hook on Bash. Refuses lookup commands in the main session so that
# lookups go to the quote-source agent on Haiku instead.
cmd=$(jq -r '.tool_input.command')
if printf '%s' "$cmd" | grep -Eq '/home/mlitchard/gitlab/sasha([^m]|$)' && ! printf '%s' "$cmd" | grep -q '/nix/store'; then
  jq -n '{}'
elif printf '%s' "$cmd" | grep -Eq '(^|[;&|][[:space:]]*)(grep|rg|find|ls|cat|head|tail|sed -n|wc|du|git (log|status|show|diff))([[:space:]]|$)'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Lookup commands are refused in the main session. Send the lookup to the quote-source agent on Haiku, or skip it when the answer is already in context."}}'
else
  jq -n '{}'
fi
