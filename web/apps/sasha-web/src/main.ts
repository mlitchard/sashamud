import { API } from '@sasha/type-gen-output/client';
import { createDOM } from './game/createDOM';
import { GameConnection } from './game/GameConnection';
import { ViewportManager } from './game/ViewportManager';

const token = tokenFromFragment();
if (token) {
  enterGame(token);
} else {
  showLogin();
}

function tokenFromFragment(): string | null {
  const match = /^#token=(.+)$/.exec(location.hash);
  if (!match) return null;
  history.replaceState(null, '', location.pathname + location.search);
  return match[1] ?? null;
}

function showLogin(): void {
  const overlay = document.createElement('div');
  overlay.id = 'login-overlay';

  const box = document.createElement('div');
  box.id = 'login-box';

  const title = document.createElement('h1');
  title.id = 'login-title';
  title.textContent = 'Welcome to SashaMUD';

  const subtitle = document.createElement('p');
  subtitle.id = 'login-subtitle';
  subtitle.textContent = 'Sign in and come on in.';

  const button = document.createElement('button');
  button.id = 'login-btn';
  button.textContent = 'Log in';

  box.appendChild(title);
  box.appendChild(subtitle);
  box.appendChild(button);
  overlay.appendChild(box);
  document.body.appendChild(overlay);

  button.addEventListener('click', () => {
    button.disabled = true;
    button.textContent = 'Redirecting...';
    location.href = '/api/auth/start';
  });
}

function enterGame(sessionId: string): void {
  createDOM();
  const conn = new GameConnection();
  const viewports = new ViewportManager(conn);
  conn.connect(sessionId);
  addLogoutButton(conn, viewports);
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
    API["/api/game/logout(SessionId)"](sessionId)
      .then(() => {
        conn.disconnect();
        viewports.destroy();
        showLogin();
      })
      .catch(() => {
        conn.disconnect();
        viewports.destroy();
        showLogin();
      });
  });
}
