#!/usr/bin/env bash
# PreToolUse hook on Agent. Refuses agent prompts without the rejection-stop line,
# general-purpose agent prompts without an Old-code reference line, and lookup agent
# prompts (quote-source, Explore, claude-code-guide) without a Decision this changes: line.
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
if [ "$type" = "quote-source" ] || [ "$type" = "Explore" ] || [ "$type" = "claude-code-guide" ]; then
  if ! printf '%s' "$prompt" | grep -Fq 'Decision this changes:'; then
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Lookup prompts must name the open decision the lookup would change: Decision this changes: <decision>. If the user'"'"'s message already settled it, skip the lookup."}}'
    exit 0
  fi
fi
jq -n '{}'
