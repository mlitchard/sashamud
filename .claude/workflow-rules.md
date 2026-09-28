---
name: workflow-rules
description: "User-stated workflow laws — comments, verification, agents, no-vibes, config knobs"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a0284cb4-db5d-45df-b9de-c69048c4cde7
  modified: 2026-09-13T09:17:28.139Z
---

- DOCUMENTATION OVER DEDUCTION (2026-09-01, his order "rely on
  documentation instead of deduction"): when a tool's or library's
  behavior is the question, read its docs, source, or published
  artifact FIRST — never reason from how such things usually work.
  Strikes that earned this: three rounds of module-interop deduction
  when one fetch of the published metadata bundle showed it exports
  nothing and assigns window.RENDERER_METADATA; quoting secrix syntax
  from another script instead of the tool's --help.
- ANNOUNCE BEFORE ACTING (2026-09-01, viewer debugging, his order "tell
  me what you want to do before doing things from now on"): state the
  intended actions in plain language BEFORE the tool calls, every time —
  a short numbered list of what is about to happen, then do exactly
  that. Given after repeated strikes for unexplained tool activity
  during diagnosis.
- SCOPE = HIS ASK, NOTHING MORE (2026-08-29, 0-tutorial-zero VM plan,
  "you are losing focus… stop inventing problems… showing initiative
  wastes my time"): I padded a port-from-main plan with a research spike
  on open-source viewers (problem already solved in main by
  screeps-steamless-client) and an ISO-publish/Hetzner step he didn't
  ask for. Plans contain ONLY the steps his ask requires; a solved
  problem in main stays solved — reuse it, don't reopen it.
- STATED FACTS OVER INFERENCE; GUESS = STOP AND ASK 
- NO UNASKED DESIGN CHOICES 
- NO ASSUMED FOLLOW-UPS 
- FORMATTING IS NOT FILTERING 
- DEFINE SHORTHAND ON FIRST USE 
- No second-guessing additions - when
  told to add something, add it — no speculation riders, no staged
  for/against debates, no hedged alternatives, no "what I deliberately did
  NOT do" riders. ONE verdict, then stop. Same for removals he didn't
  ask for: test PASS lines STAY (he wants a record of passing runs).
- COMMENT-ONLY edits get NO verification run (2026-08-17, corrected twice
  in one session): comments can't change checker output — don't run or
  offer paradox check/tsc after them.
- USE AGENTS BY DEFAULT (2026-08-19: "i should not have to tell you to
  use agents"): heavy research (transcript mining, repo exploration) goes
  to agents, in parallel, without being asked. No busywork in agent
  prompts: [[agent-prompts-no-busywork]].
- NO COMMITS BY ME (2026-09-06, cherry-pick session, "do not do commits,
  leave that to me"): make the ordered edits; he runs git commit himself.
  EXTENDED 2026-09-07: NO `git add` either — staging is his. When a new
  file needs tracking before nix can evaluate it, say so and stop.
  EXTENDED 2026-09-10 ("you dont need to waste tokens and time telling
  me how to use git"): no untracked-file reminders, no git usage notes
  in reports — the ONE exception stays: a file nix must evaluate and
  cannot see. Otherwise never mention git state.
- User often executes fixes/commands HIMSELF mid-session (rejects Bash
  calls, then does the work). Propose + diagnose; expect takeovers. Do
  NOT chain unrequested verification/status checks after his actions
  (corrected 2026-08-15; struck again 2026-08-25 — ran paradox check
  after an ordered spec edit when he'd already proven the edit safe
  himself; do the ordered step, stop).
- File edits go through Edit/Write tools — no printf/echo appends
  (corrected 2026-08-20).
- NO wc, NO size/count narration (2026-08-25, twice; struck AGAIN
  2026-08-27 sizing transcripts): never run wc, and never report line
  counts or file sizes in chat — they're busywork noise. Say what a
  thing IS, never how big it is. READ workflow-rules.md at session
  start — the MEMORY.md pointer alone did not stop this strike.
  STRUCK AGAIN 2026-08-31: ran `git diff --stat` after he had already
  rejected `git show --stat` the same session. The rule covers ANY
  count/size-producing flag (--stat, wc, du, ls -l sizes) — use
  --name-only for file lists; the rule is about count noise, never
  just the wc binary.
  STRUCK AGAIN 2026-09-13: an Explore agent I spawned ran `wc -l` on
  spec files — the ban covers subagents, same as the /nix/store rule;
  every agent prompt must state the ban explicitly.
- NEVER read /nix/store paths directly (corrected twice; STRUCK AGAIN
  2026-09-05: sent an Explore agent after node_modules/@screeps/renderer,
  which resolves into the store — the ban covers subagents and their
  prompts too; ask him for his clone of the upstream repo instead).
- NEVER "model from vibes" (recurring, 4th strike 2026-08-17: claimed "CI
  runs Foundation nix" with zero evidence). Unknown = SAY unknown. Claims
  about HIS infra require docs, source, or his own output first.
- Config knobs: NEVER require env vars before running. Default = flake
  `let` binding; env var is an OPTIONAL override (recurring correction).
- Don't modify the user's personal dotfiles.
- NO GIT COMMANDS (2026-09-27, live-dsl step 5, "stop wasting time with
  git commands you do not need them"): neither I nor any agent runs git
  (log, show, tag, status, diff). Versions come from .cabal files, APIs
  from source reads. Every agent prompt states the ban explicitly.
- SHOW EVERY EDIT (2026-09-27, live-dsl step 7, "dont just say you are
  updating, show me what you are updating as you do it"): before each file
  edit, show the new code in chat (file + the lines being added/replaced),
  then make the edit.
- NO INTERNET FOR DOCS OR SOURCE (2026-09-28, auth step 1, "i have
  instructed you not to go to the internet for documentation of source
  code"): documentation over deduction means local sources only — old
  code, sanctioned checkouts, his stated facts. No WebFetch, no WebSearch,
  no Hackage. Unknown = say unknown and ask him.
- NO SWEEPING HIS OTHER REPOS (2026-09-28, auth steps 1-3, "you keep
  wanting to search mlitchard and mlitchard/gitlab for no reason"): when
  a plan names a library or tool with no pattern in quux, sashamud, or
  the sanctioned checkouts, ask him for the reference. Never grep
  ~/gitlab or ~/github for it, and never send an agent to.
