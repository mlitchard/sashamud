#!/usr/bin/env bash
# PreToolUse hook on Read. Refuses reads outside the repo, the scratchpad and
# the Claude state directory in the main session, so old-code reads go to the
# quote-source agent. Subagent calls carry agent_type and pass through.
input=$(cat)
if printf '%s' "$input" | jq -e '.agent_type' > /dev/null; then
  jq -n '{}'
  exit 0
fi
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path')
case "$f" in
  /home/mlitchard/gitlab/sashamud/*|/tmp/*|/home/mlitchard/.claude/*)
    jq -n '{}'
    ;;
  *)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Reads outside the repo are refused in the main session. Send the lookup to the quote-source agent on Haiku."}}'
    ;;
esac
