#!/usr/bin/env bash
# PreToolUse hook on WebFetch and WebSearch. Puts every web lookup to the user
# as a permission prompt, for the main session and subagents alike.
jq -n '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:"Web lookups need the user'"'"'s permission. Name what the lookup is for and why no local source will do."}}'
