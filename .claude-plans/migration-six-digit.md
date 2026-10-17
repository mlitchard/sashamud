# Migration six-digit prefixes

## Goal
Every migration file name starts with a six-digit number.

## His rulings
- RULED (user, 2026-10-17): six digits in all files, e.g. 000000-auth.sql and 999999-auth.sql.
- RULED (user, 2026-10-17): sashamud-d0 plans; sashamud-1c executes.

## What exists today
migrations/build/: 00-auth.sql, 01-dsl-submission.sql, 02-tokens.sql, 03-sessions.sql, 04-repair.sql
migrations/rollback/: 95-repair.sql, 96-sessions.sql, 97-tokens.sql, 98-dsl-submission.sql, 99-auth.sql
No code or config names a migration file. Every reader takes the directory:
- sasha/src/Server/Server.hs:154
- sasha/test/MigrationSpec.hs:62
- sashamud-server/test/Integration/LoginLogoutSpec.hs:232
- sashamud-server/test-e2e/SeleniumHarness.hs:135
- flake.nix:159 (migrationsDir = ./migrations)

## Decisions
1. Rename map. RULED (user, 2026-10-17). Build files pad with zeros: 00 → 000000 through 04 → 000004.
   Rollback files pad with nines: 95 → 999995 through 99 → 999999.
   Run order in each folder stays the same.
2. Existing databases. RULED (user, 2026-10-17): no lookup. He resets the
   database; this is a complete rebuild and no database data needs keeping.

## Steps
Step rule: every step builds and is green on its own; any fix a step needs lands in that step.

Step 1 (sashamud-1c): rename the ten files per decision 1 with mv. No other edits.
He builds and runs the migration test.
