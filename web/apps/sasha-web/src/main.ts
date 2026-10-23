import { API } from '@sasha/type-gen-output/client';
import { createDOM } from './game/createDOM';
import { GameConnection } from './game/GameConnection';
import { ViewportManager } from './game/ViewportManager';

const TOKEN_KEY = 'sashamud_token';

const fragment = readFragment();
if (fragment.token) sessionStorage.setItem(TOKEN_KEY, fragment.token);
const token = sessionStorage.getItem(TOKEN_KEY);
if (token) {
  enterGame(token);
} else {
  showLogin(fragment.message);
}

function readFragment(): { token: string | null; message: string | null } {
  const hash = location.hash;
  history.replaceState(null, '', location.pathname + location.search);
  const token = /^#token=(.+)$/.exec(hash);
  if (token) return { token: token[1] ?? null, message: null };
  const taken = /^#taken=(.+)$/.exec(hash);
  if (taken) return { token: null, message: decodeURIComponent(taken[1] ?? '') + ' is taken. Choose another name.' };
  const unknown = /^#unknown=(.+)$/.exec(hash);
  if (unknown) return { token: null, message: 'No character named ' + decodeURIComponent(unknown[1] ?? '') + ' on your account.' };
  if (hash === '#new') return { token: null, message: 'Choose a name to create your account.' };
  return { token: null, message: null };
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
    const name = input.value.trim();
    if (name.length === 0) {
      error.textContent = 'Enter a name.';
      return;
    }
    loginButton.disabled = true;
    loginButton.textContent = 'Redirecting...';
    location.href = `/api/auth/start?name=${encodeURIComponent(name)}&mode=login`;
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
          location.href = `/api/auth/start?name=${encodeURIComponent(name)}&mode=create`;
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

const CLOSE_ICON = '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 640 640"><!--!Font Awesome Free 7.3.1 by @fontawesome - https://fontawesome.com License - https://fontawesome.com/license/free Copyright 2026 Fonticons, Inc.--><path d="M128 128C92.7 128 64 156.7 64 192L64 448C64 483.3 92.7 512 128 512L512 512C547.3 512 576 483.3 576 448L576 192C576 156.7 547.3 128 512 128L128 128zM231 231C240.4 221.6 255.6 221.6 264.9 231L319.9 286L374.9 231C384.3 221.6 399.5 221.6 408.8 231C418.1 240.4 418.2 255.6 408.8 264.9L353.8 319.9L408.8 374.9C418.2 384.3 418.2 399.5 408.8 408.8C399.4 418.1 384.2 418.2 374.9 408.8L319.9 353.8L264.9 408.8C255.5 418.2 240.3 418.2 231 408.8C221.7 399.4 221.6 384.2 231 374.9L286 319.9L231 264.9C221.6 255.5 221.6 240.3 231 231z"/></svg>';
function addTokenControl(sessionId: string): void {
  const toolbar = document.getElementById('toolbar');
  if (!toolbar) return;

  const settings = document.createElement('button');
  settings.id = 'settings-btn';
  settings.textContent = 'Settings';
  settings.addEventListener('click', () => showSettings(sessionId));
  toolbar.appendChild(settings);
}

function showSettings(sessionId: string): void {
  const overlay = document.createElement('div');
  overlay.id = 'settings-overlay';

  const box = document.createElement('div');
  box.id = 'settings-box';

  const closeIcon = document.createElement('button');
  closeIcon.id = 'settings-close-icon';
  closeIcon.innerHTML = CLOSE_ICON;

  const tokenButton = document.createElement('button');
  tokenButton.id = 'dsl-token-btn';
  tokenButton.textContent = 'dsl token';

  const closeButton = document.createElement('button');
  closeButton.id = 'settings-close-btn';
  closeButton.textContent = 'Close';

  box.appendChild(closeIcon);
  box.appendChild(tokenButton);
  box.appendChild(closeButton);
  overlay.appendChild(box);
  document.body.appendChild(overlay);

  const close = (): void => { overlay.remove(); };
  closeIcon.addEventListener('click', close);
  closeButton.addEventListener('click', close);

  tokenButton.addEventListener('click', () => {
    tokenButton.disabled = true;

    const field = document.createElement('div');
    field.id = 'dsl-token-field';

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

    field.appendChild(token);
    field.appendChild(copy);
    box.insertBefore(field, closeButton);
  });
}

function addLogoutButton(conn: GameConnection, viewports: ViewportManager): void {
  const commandBar = document.getElementById('command-bar');
  if (!commandBar) return;

  const btn = document.createElement('button');
  btn.id = 'logout-btn';
  btn.textContent = 'Logout';
  commandBar.appendChild(btn);

  btn.addEventListener('click', () => {
    const sessionId = conn.getSessionId();
    if (!sessionId) return;

    btn.disabled = true;
    API["/api/game/logout{BEARER}"](sessionId)
      .then(() => {
        sessionStorage.removeItem(TOKEN_KEY);
        conn.disconnect();
        viewports.destroy();
        showLogin(null);
      })
      .catch(() => {
        sessionStorage.removeItem(TOKEN_KEY);
        conn.disconnect();
        viewports.destroy();
        showLogin(null);
      });
  });
}
