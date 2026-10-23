#!/usr/bin/env bash
# PreToolUse hook on Edit and Write. Refuses Haskell writes in the main session
# so the writing goes to an Opus agent from a spec. Subagent calls carry
# agent_type and pass through.
input=$(cat)
if printf '%s' "$input" | jq -e '.agent_type' > /dev/null; then
  jq -n '{}'
  exit 0
fi
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path')
case "$f" in
  *.hs)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Haskell writes are refused in the main session. Write the spec and hand the edit to a general-purpose agent with model opus."}}'
    ;;
  *)
    jq -n '{}'
    ;;
esac
