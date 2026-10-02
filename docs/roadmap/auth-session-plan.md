# Login Sessions: Execution Plan

`tokens` is the set of live logins, one row per user, as quux keeps it.
This plan makes the row's expiry visible to SQL and adds quux's
`user_logs` table as the history of logins and logouts.

Pattern source: quux (`/home/mlitchard/gitlab/quux/server`):

- `migrations/build/00-Init.sql:32-37`: `tokens (token, hash, user_id,
  created)`.
- `migrations/build/07-user-logs.sql:1-5`: `user_logs (user_id, path,
  timet)`; `migrations/rollback/92-user-logs.sql` drops it.
- `Context.hs:92-98`: `logRequest` inserts `(user_id, path, now())` into
  `user_logs` from inside the auth handler.
- `Handlers/Logout.hs:37-38`: `logoutSelf` deletes the caller's row by
  token.
- `Model/Jwt.hs:81-93`: `tryAddHashAndJwt` inserts the row and trims the
  user's old rows in one statement.

Migration library (`/home/mlitchard/github/postgresql-migration`,
`Readme.markdown:27-40`, `Migration.hs:163-187,253-266`): every applied
script's MD5 is recorded in `schema_migrations`, and a changed script
answers `MigrationError`. Applied scripts are never edited. Changes go in
new scripts.

Rulings (2026-10-02):

- `00-auth.sql` and `02-tokens.sql` stay as they are. The second
  definition of `tokens` is history, as the migration library records
  it.
- `tokens.expires_at` is the claim's `expirationDate`, stored beside the
  token. The auth query filters on it; the claim check after decoding
  stays, as quux has it.
- `tryAddHashAndJwt` reads the expiry back from the token it stores with
  `getJwtData`, so its signature and quux's shape stay.
- A login deletes every expired row, of every user, in the same
  statement that inserts the new one. That is the cleanup the column is
  for.
- `user_logs` is quux's table unchanged: `user_id`, `path`, `timet`, no
  foreign key, no index. quux's `get_user_logs_by_user` function is
  omitted; nothing reads the table yet.
- One row per login, written by the callback with path
  `/api/auth/callback`, and one per logout, written by the logout handler
  with path `/api/game/logout`. Those handlers hold no `Request`, so the
  path is the route's own text. A socket close is a disconnect and
  writes nothing.
- Current state is `tokens`. History is `user_logs`.

Every step builds. Each step names its test.

---

## Step 1: Schema

**Change:**

- `migrations/build/03-sessions.sql`:
  ```sql
  ALTER TABLE tokens ADD COLUMN expires_at timestamp with time zone;
  UPDATE tokens SET expires_at = created + interval '1 day';
  ALTER TABLE tokens ALTER COLUMN expires_at SET NOT NULL;

  CREATE TABLE user_logs
    ( user_id integer NOT NULL
    , path text  NOT NULL
    , timet timestamp with time zone NOT NULL
    );
  ```
  The update gives existing rows the expiry their claims carry, since
  `makeJwt` mints one day out.
- `migrations/rollback/96-sessions.sql`:
  ```sql
  DROP TABLE IF EXISTS user_logs CASCADE;
  ALTER TABLE tokens DROP COLUMN IF EXISTS expires_at;
  ```
- `Model.Jwt.tryAddHashAndJwt`: decode the token with `getJwtData jwt
  hash`; a `Left` answers 500 with the error text, as the insert failure
  does. The statement becomes
  ```sql
  DELETE FROM tokens WHERE user_id = ? OR expires_at < now();
  INSERT INTO tokens (token, hash, user_id, created, expires_at) VALUES (?, ?, ?, now(), ?);
  ```
- `Server.Authentication.authHandler`, `userQuery`: add
  `AND tokens.expires_at > now()`.
- `LoginLogoutSpec.insertExpired`: insert `expires_at` as
  `now() - interval '1 hour'`.

**Test:** `MigrationSpec` builds and rolls back to only
`schema_migrations`. `LoginLogoutSpec` green, including "an expired token
is rejected" and "a second login replaces the first".

## Step 2: History

**Change:**

- `Server.Authentication.authCallback`: after `tryAddHashAndJwt`,
  ```haskell
  execute conn "INSERT INTO user_logs VALUES (?, ?, now())" (userId, "/api/auth/callback" :: Text)
  ```
  through `withResource (acDbPool ctx)`, as quux's `logRequest` writes.
- `Server.Server.logoutHandler`: the `AuthenticatedUser` carries the
  user id. After the token delete,
  ```haskell
  execute conn "INSERT INTO user_logs VALUES (?, ?, now())" (userId, "/api/game/logout" :: Text)
  ```

**Test:** `LoginLogoutSpec`, two new cases. "login writes a user_logs
row": after `loginAs`, `SELECT path FROM user_logs WHERE user_id = ?`
answers `["/api/auth/callback"]`. "logout writes a user_logs row": after
logout, the same query answers `["/api/auth/callback",
"/api/game/logout"]` ordered by `timet`.

## Step 3: Browser logout, by hand

**Change:** none. `main.ts` already calls the logout route, clears
`sashamud_token` with `Max-Age=0` and the same attributes the server set,
disconnects, and shows the login overlay. The button now sits on the
command row.

**Test:** by hand, with the server running. Press Logout. The login
overlay appears. A reload stays on the overlay. In psql, `SELECT count(*)
FROM tokens` for the user answers 0, and `user_logs` holds the logout
row. If any of these fails, the browser console and the server output
are the next prompt.
