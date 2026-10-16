# Enforcement hooks

Goal: every rule a script can check is enforced by a hook, for me and every agent.

## Rulings (user, 2026-10-16)
- All rules weigh the same.
- Rejecting a proposal or an edit stops all work at once: mine and every running agent of every type and model.
- Web lookups are blocked; an exception happens only with his permission.
- Old code is the source to build from; patterns from it are checked against sashamud before use (done in MEMORY.md and settings.local.json).

## Facts (code.claude.com/docs/en/hooks.md)
- An Agent hook receives tool_input.prompt.
- Hooks run inside subagents; the input carries agent_id and agent_type.
- A hook blocks a call with hookSpecificOutput.permissionDecision "deny".
- A PermissionDenied event exists; the docs do not say whether it fires on a user rejection or inside subagents.

## Existing hooks
reload-rules.sh (UserPromptSubmit), refuse-lookups.sh (Bash), refuse-outside-reads.sh (Read), refuse-main-haskell-writes.sh (Edit|Write), the Edit|Write checklist in settings.local.json.

## Steps (Opus writes; each step works on its own)
1. Rejection stop.
   - mark-rejection.sh on PermissionDenied writes .claude/rejected.
   - refuse-after-rejection.sh on PreToolUse Edit|Write|Bash|Agent|Read|Grep|Glob|WebFetch|WebSearch denies every call, main session and subagents, while .claude/rejected exists. Reason: "A proposal or edit was rejected. Stop and discuss with the user." Bash calls are checked only when the input carries agent_type (subagents); main-session Bash passes.
   - reload-rules.sh deletes .claude/rejected, so his next message clears it.
   - The first real rejection shows whether PermissionDenied fires for it.
2. Agent prompt guards. require-agent-guards.sh on PreToolUse Agent denies unless the prompt contains "If any edit or proposal is rejected, stop at once"; for general-purpose agents the prompt must also contain "Old-code reference:".
3. Lookup and read limits.
   - refuse-lookups.sh adds wc and du to its pattern.
   - refuse-outside-reads.sh denies /nix/store/* for subagents too.
4. Web. refuse-web.sh on WebFetch|WebSearch puts each call to him as a permission prompt (permissionDecision "ask"), or denies if "ask" is unavailable.

## Decisions
1. permissionDecision "ask": RESOLVED by docs (2026-10-16). "ask" escalates to a permission prompt; "deny takes priority over defer, which takes priority over ask, which takes priority over allow", so it overrides the WebSearch/WebFetch allows; hooks run in subagents.
2. "!" access: RULED (user, 2026-10-16). His "!" commands keep full access; the hooks exist to hold me and the agents. No new hook blocks a main-session Bash call. git add/commit/tag are not added to refuse-lookups.sh. In step 1, the Bash check applies only to subagent calls (input carries agent_type).
