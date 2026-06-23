import { API, LoginResponse } from '@sasha/type-gen-output/client';
import { createDOM } from './game/createDOM';
import { GameConnection } from './game/GameConnection';
import { ViewportManager } from './game/ViewportManager';

createDOM();
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
  input.maxLength = 10;
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
    button.disabled = true;
    button.textContent = 'Logging in...';
    error.textContent = '';

    API["/api/game/login(PlayerName)"](name)
      .then((sessionId: LoginResponse) => {
        overlay.remove();
        const conn = new GameConnection();
        const _viewports = new ViewportManager(conn);
        conn.connect(sessionId);
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
