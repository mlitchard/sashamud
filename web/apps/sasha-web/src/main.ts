import { API } from '@sasha/type-gen-output/client';
import { createDOM } from './game/createDOM';
import { GameConnection } from './game/GameConnection';
import { ViewportManager } from './game/ViewportManager';

const TOKEN_COOKIE = 'sashamud_token';

const fragment = readFragment();
const token = readCookie(TOKEN_COOKIE);
if (token) {
  enterGame(token);
} else {
  showLogin(fragment.message);
}

function readFragment(): { message: string | null } {
  const hash = location.hash;
  history.replaceState(null, '', location.pathname + location.search);
  const taken = /^#taken=(.+)$/.exec(hash);
  if (taken) return { message: decodeURIComponent(taken[1] ?? '') + ' is taken. Choose another name.' };
  if (hash === '#new') return { message: 'Choose a name to create your account.' };
  return { message: null };
}

function readCookie(name: string): string | null {
  for (const part of document.cookie.split('; ')) {
    const eq = part.indexOf('=');
    if (eq > 0 && part.slice(0, eq) === name) return part.slice(eq + 1);
  }
  return null;
}

function clearCookie(name: string): void {
  document.cookie = `${name}=; Path=/; Max-Age=0; Secure; SameSite=Strict`;
}

function showLogin(message: string | null): void {
  const overlay = document.createElement('div');
  overlay.id = 'login-overlay';

  const box = document.createElement('div');
  box.id = 'login-box';

  const title = document.createElement('h1');
  title.id = 'login-title';
  title.textContent = 'Welcome to SashaMUD';

  const subtitle = document.createElement('p');
  subtitle.id = 'login-subtitle';
  subtitle.textContent = 'Returning player? Log in.';

  const loginButton = document.createElement('button');
  loginButton.id = 'login-btn';
  loginButton.textContent = 'Log in';

  const newPlayer = document.createElement('p');
  newPlayer.id = 'login-new';
  newPlayer.textContent = 'New player? Choose a name, then sign in.';

  const input = document.createElement('input');
  input.id = 'login-name';
  input.type = 'text';
  input.maxLength = 20;
  input.placeholder = 'Character name';
  input.autocomplete = 'off';

  const error = document.createElement('div');
  error.id = 'login-error';
  error.textContent = message ?? '';

  const createButton = document.createElement('button');
  createButton.id = 'create-btn';
  createButton.textContent = 'Create account';

  box.appendChild(title);
  box.appendChild(subtitle);
  box.appendChild(loginButton);
  box.appendChild(newPlayer);
  box.appendChild(input);
  box.appendChild(error);
  box.appendChild(createButton);
  overlay.appendChild(box);
  document.body.appendChild(overlay);

  loginButton.addEventListener('click', () => {
    loginButton.disabled = true;
    loginButton.textContent = 'Redirecting...';
    location.href = '/api/auth/start';
  });

  const createAccount = (): void => {
    const name = input.value.trim();
    if (name.length === 0) {
      error.textContent = 'Enter a name.';
      return;
    }
    createButton.disabled = true;
    error.textContent = '';
    fetch(`${API.base}/api/auth/available?name=${encodeURIComponent(name)}`)
      .then(async (resp: Response) => {
        if (resp.status === 204) {
          location.href = `/api/auth/start?name=${encodeURIComponent(name)}`;
          return;
        }
        const text = await resp.text();
        error.textContent = text.length > 0 ? text : `Name rejected (${resp.status}).`;
        createButton.disabled = false;
        input.focus();
      })
      .catch((err: unknown) => {
        error.textContent = 'Could not check the name: ' + String(err);
        createButton.disabled = false;
      });
  };

  createButton.addEventListener('click', createAccount);
  input.addEventListener('keydown', (e: KeyboardEvent) => {
    if (e.key === 'Enter') createAccount();
  });
  if (message) input.focus();
}

function enterGame(sessionId: string): void {
  createDOM();
  const conn = new GameConnection();
  const viewports = new ViewportManager(conn);
  conn.connect(sessionId);
  addTokenControl(sessionId);
  addLogoutButton(conn, viewports);
}

function addTokenControl(sessionId: string): void {
  const toolbar = document.getElementById('toolbar');
  if (!toolbar) return;

  const label = document.createElement('span');
  label.id = 'session-token-label';
  label.textContent = 'Token: ';

  const token = document.createElement('code');
  token.id = 'session-token';
  token.textContent = sessionId;

  const copy = document.createElement('button');
  copy.id = 'copy-token-btn';
  copy.textContent = 'Copy token';
  copy.addEventListener('click', () => {
    navigator.clipboard.writeText(sessionId)
      .then(() => { copy.textContent = 'Copied'; })
      .catch(() => { copy.textContent = 'Copy failed'; });
  });

  toolbar.appendChild(label);
  toolbar.appendChild(token);
  toolbar.appendChild(copy);
}

function addLogoutButton(conn: GameConnection, viewports: ViewportManager): void {
  const toolbar = document.getElementById('toolbar');
  if (!toolbar) return;

  const btn = document.createElement('button');
  btn.id = 'logout-btn';
  btn.textContent = 'Logout';
  toolbar.appendChild(btn);

  btn.addEventListener('click', () => {
    const sessionId = conn.getSessionId();
    if (!sessionId) return;

    btn.disabled = true;
    API["/api/game/logout{BEARER}"](sessionId)
      .then(() => {
        clearCookie(TOKEN_COOKIE);
        conn.disconnect();
        viewports.destroy();
        showLogin(null);
      })
      .catch(() => {
        clearCookie(TOKEN_COOKIE);
        conn.disconnect();
        viewports.destroy();
        showLogin(null);
      });
  });
}
