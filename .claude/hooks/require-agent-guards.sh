#!/usr/bin/env bash
# PreToolUse hook on Agent. Refuses agent prompts without the rejection-stop line,
# and general-purpose agent prompts without an Old-code reference line.
input=$(cat)
prompt=$(printf '%s' "$input" | jq -r '.tool_input.prompt // ""')
type=$(printf '%s' "$input" | jq -r '.tool_input.subagent_type // ""')
if ! printf '%s' "$prompt" | grep -Fq 'If any edit or proposal is rejected, stop at once'; then
  jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Agent prompts must contain: If any edit or proposal is rejected, stop at once, make no further edits, and report the rejection."}}'
  exit 0
fi
if [ "$type" = "general-purpose" ] || [ -z "$type" ]; then
  if ! printf '%s' "$prompt" | grep -Fq 'Old-code reference:'; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"general-purpose agent prompts must contain an Old-code reference: line (a quoted path and line, or none: user ruling <date>)."}}'
    exit 0
  fi
fi
jq -n '{}'
