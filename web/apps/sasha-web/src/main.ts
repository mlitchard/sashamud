import { API, LoginResponse } from '@sasha/type-gen-output/client';
import { createDOM } from './game/createDOM';
import { GameConnection } from './game/GameConnection';
import { ViewportManager } from './game/ViewportManager';

showLogin();

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
  subtitle.textContent = 'Make a character and come on in.';

  const input = document.createElement('input');
  input.id = 'login-name';
  input.type = 'text';
  input.maxLength = 20;
  input.placeholder = 'Character name';
  input.autocomplete = 'off';
  input.autofocus = true;

  const error = document.createElement('div');
  error.id = 'login-error';

  const button = document.createElement('button');
  button.id = 'login-btn';
  button.textContent = 'Login';

  box.appendChild(title);
  box.appendChild(subtitle);
  box.appendChild(input);
  box.appendChild(error);
  box.appendChild(button);
  overlay.appendChild(box);
  document.body.appendChild(overlay);

  const doLogin = (): void => {
    const name = input.value.trim();
    if (name.length === 0) {
      error.textContent = 'Enter a name.';
      return;
    }
    if (!/^[A-Za-z0-9]+$/.test(name)) {
      error.textContent = 'Letters and numbers only.';
      return;
    }
    button.disabled = true;
    button.textContent = 'Logging in...';
    error.textContent = '';

    API["/api/game/login(PlayerNameUNV)"](name)
      .then((sessionId: LoginResponse) => {
        overlay.remove();
        createDOM();
        const conn = new GameConnection();
        const viewports = new ViewportManager(conn);
        conn.connect(sessionId);
        addLogoutButton(conn, viewports);
      })
      .catch((err: unknown) => {
        button.disabled = false;
        button.textContent = 'Login';
        error.textContent = 'Login failed: ' + String(err);
      });
  };

  button.addEventListener('click', doLogin);
  input.addEventListener('keydown', (e: KeyboardEvent) => {
    if (e.key === 'Enter') doLogin();
  });
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
