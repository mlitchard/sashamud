export function createDOM(): void {
  const app = document.createElement('div');
  app.id = 'app';
  app.setAttribute('role', 'application');
  app.setAttribute('aria-label', 'SashaMUD web interface');

  const toolbar = document.createElement('div');
  toolbar.id = 'toolbar';
  app.appendChild(toolbar);

  const viewports = document.createElement('div');
  viewports.id = 'viewports';
  app.appendChild(viewports);

  const commandBar = document.createElement('div');
  commandBar.id = 'command-bar';
  const prompt = document.createElement('span');
  prompt.className = 'prompt';
  prompt.textContent = '>';
  commandBar.appendChild(prompt);
  const cmdInput = document.createElement('input');
  cmdInput.id = 'cmd-input';
  cmdInput.type = 'text';
  cmdInput.placeholder = 'Enter command...';
  cmdInput.autocomplete = 'off';
  cmdInput.autofocus = true;
  commandBar.appendChild(cmdInput);
  app.appendChild(commandBar);

  const statusBar = document.createElement('div');
  statusBar.id = 'status-bar';
  statusBar.textContent = 'Status: ';
  const connStatus = document.createElement('span');
  connStatus.id = 'conn-status';
  connStatus.className = 'status-disconnected';
  connStatus.textContent = 'disconnected';
  statusBar.appendChild(connStatus);
  app.appendChild(statusBar);

  document.body.appendChild(app);

  // Hidden test hooks for Selenium
  for (const hookId of ['bridge-status', 'bridge-session', 'bridge-scene']) {
    const hook = document.createElement('div');
    hook.id = hookId;
    hook.style.display = 'none';
    hook.textContent = 'disconnected';
    document.body.appendChild(hook);
  }
}
