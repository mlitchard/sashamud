---
description: Review Haskell architecture or code using the haskell-nix-engineer agent
argument-hint: File or description to review
---

# Haskell Engineering Review

Review target: $ARGUMENTS

Launch a haskell-nix-engineer agent to assess the target. The agent definition is in .claude/agents/haskell-nix-engineer.md — read it first, then follow its review approach.

**Actions:**
1. Read .claude/agents/haskell-nix-engineer.md to load the agent's expertise and review checklist
2. Read the target file(s) specified in $ARGUMENTS
3. Read reference codebases as needed to verify patterns
4. Apply the agent's review approach — check every type against Hackage, every library against the reference codebase, flag redundancy, check Nix packaging
5. Report findings: list each issue with the specific library/function/type that should be used instead
