# Authentik, local setup

Authentik runs as a NixOS VM built from this flake. This records the
by-hand steps from `docs/roadmap/auth-plan.md` Step 8, with the field
names taken from authentik's own docs and source
(`/home/mlitchard/github/authentik`).

## 1. Run the VM

From the repo root, in its own terminal:

```
nix run .#authentik-vm
```

The VM forwards host port 9000 to authentik and host port 2222 to
sshd. Its disk image is `authentik-local.qcow2` in the repo root. The
console logs in as root, and so does

```
ssh -p 2222 root@localhost
```

with no password.

Authentik listens only after `authentik-migrate` finishes, which takes
minutes on first boot. Inside the VM:

```
systemctl status authentik
```

From the host, authentik is up when this answers 302:

```
curl -sS -o /dev/null -D - http://127.0.0.1:9000/
```

## 2. Create the admin

On a fresh database authentik redirects `/` to `/setup`. Open

```
http://localhost:9000
```

and complete the setup page. When it lands you on
`http://localhost:9000/if/user/#/library`, the user dashboard, the
admin account exists and you are signed in as it. The Admin interface
is at

```
http://localhost:9000/if/admin/
```

## 3. Register an OAuth App at GitHub

The OAuth App named `sashamud` at GitHub belongs to the live server
and its live callback. Leave it alone. The local VM gets its own
OAuth App.

GitHub: Settings, Developer settings, OAuth Apps, New OAuth App.
Application name `sashamud-local`, homepage `https://localhost:8080`,
authorization callback URL
`http://localhost:9000/source/oauth/callback/github/`. Register, then
Generate a new client secret. Keep the client id and the secret.

## 4. GitHub source in authentik

In the admin UI:

1. In the left menu open Directory, then Federation and Social login.
2. Press Create. A list of source types appears; pick GitHub OAuth
   Source and continue.
3. Fill the form:
    - Name: GitHub
    - Slug: github. This word is part of the callback URL you gave
      GitHub, `.../source/oauth/callback/github/`, so it has to be
      exactly this.
    - Consumer key: paste GitHub's Client ID.
    - Consumer secret: paste GitHub's Client secret.
    - Every other field, including the flow settings: leave as it is.
4. Save.

The flows it leaves at their defaults are what make a first-time
GitHub login create the authentik user by itself.

## 5. Show the GitHub source on the login page

**Flows and Stages** > **Flows** > **default-authentication-flow** >
**Stage Bindings** tab > **Edit Stage** on
**default-authentication-identification** > under **Source settings**,
add `GitHub` to **Selected Sources**. Save.

## 6. Provider and application for sashamud

Authentik 2026.8.3 creates the application and its provider together.
Applications, Applications, **New Application**, **with New
Provider...**. The wizard asks for the application first, then the
provider type, then the provider.

The application step:

- **Application Name**: `sashamud`
- **Slug**: `sashamud`

The provider type: **OAuth2/OIDC**.

The provider step. The form's sections and fields, by their own
labels:

- Top of the form:
    - **Provider Name**: `sashamud`
    - **Authorization Flow**: the default explicit-consent one it
      offers
- **Protocol settings** (open by default):
    - **Client Type**: Confidential
    - **Client ID**, **Client Secret**: leave as generated. These are
      the two values for step 7.
    - **Redirect URIs/Origins (RegEx)**: one entry. It has two selects
      and a URL box. Matching mode **Strict**, type **Authorization**
      (both the defaults), URL `https://localhost:8080/api/auth/callback`.
    - **Signing Key**: leave as it is
- **Advanced protocol settings** (collapsed; click the heading to
  open it):
    - **Scopes**: `scope-openid`, `scope-email`, and `scope-profile`
      are pre-selected. Keep openid and profile; remove email.
    - **Subject Mode**: **Based on the User's UUID**

Finish the wizard. Then Applications, Providers, open `sashamud` and
copy its Client ID and Client Secret from the Overview.

GitHub's form calls it Authorization callback URL. Its value is where
GitHub sends the browser back, which is authentik:
`http://localhost:9000/source/oauth/callback/github/`. Authentik's
provider form calls it Redirect URIs. Its value is where authentik
sends the browser back, which is sashamud:
`https://localhost:8080/api/auth/callback`.

## 7. Point sashamud at it

In the dev shell, the flake exports the base URL and the default client
id and secret. The provider authentik created overrides the last two:

```
export SASHA_OIDC_CLIENT_ID=<Client ID from step 6>
export SASHA_OIDC_CLIENT_SECRET=<Client Secret from step 6>
db-server-start
start-sashamud
```

## 8. Log in and take the token

The browser that did the admin setup is logged into authentik as the
admin. Authentik sees that session, skips its login page, and the
account created is bound to the admin user's UUID. To go through
GitHub, use a private window.

1. Open `https://localhost:8080`.
2. Type a player name in the name field and click Create account, or
   press Log in for an account that exists.
3. You get bounced to `localhost:9000`. On authentik's login page, do
   not type a username or password. Click the GitHub button below the
   form.
4. GitHub asks you to authorize the OAuth App. Approve it.
5. Authentik may show its enrollment step for a first-time GitHub
   user, then sends you back to `localhost:8080/api/auth/callback`.
6. The browser lands on `https://localhost:8080/` with the token in
   the `sashamud_token` cookie, and the game client connects. Press
   **Settings** on the toolbar, then **dsl token**. The token appears
   with a **Copy token** button. Press it.

If there is no GitHub button on authentik's login page, step 5 above
was missed.

To deploy DSL with it:

```
SASHA_TOKEN=<token> nix run .#deploy-dsl -- sashamud-server/test-e2e/study.dsl
```
