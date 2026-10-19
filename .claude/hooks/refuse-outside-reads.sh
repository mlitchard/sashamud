#!/usr/bin/env bash
# PreToolUse hook on Read. Refuses reads outside the repo, the scratchpad and
# the Claude state directory in the main session, so old-code reads go to the
# quote-source agent. Subagent calls carry agent_type and pass through.
input=$(cat)
f=$(printf '%s' "$input" | jq -r '.tool_input.file_path')
case "$f" in
  /nix/store/*)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Reads under /nix/store are refused. Ask the user for a checkout of the upstream source."}}'
    exit 0
    ;;
esac
if printf '%s' "$input" | jq -e '.agent_type' > /dev/null; then
  jq -n '{}'
  exit 0
fi
case "$f" in
  /home/mlitchard/gitlab/sashamud/*|/home/mlitchard/gitlab/sasha/*|/tmp/*|/home/mlitchard/.claude/*)
    jq -n '{}'
    ;;
  *)
    jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:"Reads outside the repo are refused in the main session. Send the lookup to the quote-source agent on Haiku."}}'
    ;;
esac
