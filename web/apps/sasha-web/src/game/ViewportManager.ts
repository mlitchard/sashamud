import { GameConnection, WireMessage } from './GameConnection';
import { RichText } from '@sasha/type-gen-output/client';
import { renderRichTextLine, renderPlainLine } from './RichTextRenderer';

type ViewportId = 'scene' | 'system' | 'meta' | 'parser' | 'state' | 'graphics' | 'map';

const ALL_VIEWPORTS: ViewportId[] = ['scene', 'system', 'meta', 'parser', 'state', 'graphics', 'map'];

const VIEWPORT_LABELS: Record<ViewportId, { num: number; label: string }> = {
  scene:    { num: 1, label: 'Scene' },
  system:   { num: 2, label: 'System' },
  meta:     { num: 3, label: 'Meta' },
  parser:   { num: 4, label: 'Parser' },
  state:    { num: 5, label: 'State' },
  graphics: { num: 6, label: 'Graphics' },
  map:      { num: 7, label: 'Map' },
};

const ANALYSIS_KEY_TO_VIEWPORT: Record<string, ViewportId> = {
  parser: 'parser', state: 'state', meta: 'meta', graphics: 'graphics', map: 'map',
};

export class ViewportManager {
  private conn: GameConnection;
  private activeViewports: Set<ViewportId> = new Set(['scene', 'system']);
  private focusedViewport: ViewportId = 'scene';
  private systemMessageCount = 0;
  private panels: Map<ViewportId, HTMLElement> = new Map();
  private sideStackWidth = 360;

  constructor(conn: GameConnection) {
    this.conn = conn;
    conn.onMessage((msg) => this.handleMessage(msg));
    conn.onStatusChange((status) => this.updateStatusDisplay(status));
    for (const vpId of ALL_VIEWPORTS) this.panels.set(vpId, this.createViewportPanel(vpId));
    this.setupKeyboard();
    this.buildToolbar();
    this.rebuildLayout();
  }

  private handleMessage(msg: WireMessage): void {
    switch (msg.tag) {
      case 'GameNarration':
      case 'CommandResponse':
        this.appendRichText('scene', msg.contents as RichText[]);
        break;
      case 'ChatMessage':
        this.appendPlain('scene', msg.contents as string);
        break;
      case 'SystemMessage':
        this.appendSystemMessage(msg.contents as string);
        break;
      case 'AnalysisData':
        for (const [key, lines] of Object.entries(msg.contents as Record<string, RichText[]>)) {
          const vpId = ANALYSIS_KEY_TO_VIEWPORT[key];
          if (vpId) this.replaceRichText(vpId, lines);
        }
        break;
    }
  }

  private appendRichText(vpId: ViewportId, richTexts: RichText[]): void {
    const container = this.getContentEl(vpId);
    if (!container) return;
    for (const rt of richTexts) renderRichTextLine(rt, container);
    this.autoScrollBottom(vpId);
  }

  private appendPlain(vpId: ViewportId, text: string): void {
    const container = this.getContentEl(vpId);
    if (!container) return;
    renderPlainLine(text, container);
    this.autoScrollBottom(vpId);
  }

  private appendSystemMessage(text: string): void {
    const container = this.getContentEl('system');
    if (!container) return;
    const cssClass = this.systemMessageCount % 2 === 0 ? 'heartbeat-red' : 'heartbeat-blue';
    this.systemMessageCount++;
    renderPlainLine(text, container, cssClass);
    this.autoScrollBottom('system');
  }

  private replaceRichText(vpId: ViewportId, richTexts: RichText[]): void {
    const container = this.getContentEl(vpId);
    if (!container) return;
    container.innerHTML = '';
    for (const rt of richTexts) renderRichTextLine(rt, container);
    container.scrollTop = 0;
  }

  private autoScrollBottom(vpId: ViewportId): void {
    const el = document.getElementById(`vp-${vpId}-content`);
    if (el) el.scrollTop = el.scrollHeight;
  }

  private getContentEl(vpId: ViewportId): HTMLElement | null {
    return document.getElementById(`vp-${vpId}-content`);
  }

  private updateStatusDisplay(status: string): void {
    const el = document.getElementById('conn-status');
    if (el) { el.textContent = status; el.className = `status-${status}`; }
  }

  private toggleViewport(vpId: ViewportId): void {
    if (this.activeViewports.has(vpId)) {
      this.activeViewports.delete(vpId);
      if (this.focusedViewport === vpId)
        this.focusedViewport = this.activeViewports.values().next().value ?? 'scene';
    } else {
      this.activeViewports.add(vpId);
    }
    this.rebuildLayout();
    this.updateToolbar();
  }

  private setFocus(vpId: ViewportId): void {
    this.focusedViewport = vpId;
    for (const vp of ALL_VIEWPORTS) {
      const el = document.getElementById(`vp-${vp}`);
      if (el) el.classList.toggle('focused', vp === vpId);
    }
  }

  private setupKeyboard(): void {
    const digitCodes: Record<string, number> = {
      Digit1: 1, Digit2: 2, Digit3: 3, Digit4: 4, Digit5: 5, Digit6: 6, Digit7: 7,
    };
    document.addEventListener('keydown', (e) => {
      const cmdInput = document.getElementById('cmd-input') as HTMLInputElement | null;
      if (e.shiftKey && digitCodes[e.code]) {
        const vpId = ALL_VIEWPORTS[digitCodes[e.code] - 1];
        if (vpId) { e.preventDefault(); this.toggleViewport(vpId); }
        return;
      }
      if (e.key === 'Enter' && cmdInput && document.activeElement === cmdInput) {
        const text = cmdInput.value.trim();
        if (text) { this.conn.sendCommand(text); cmdInput.value = ''; }
        return;
      }
      if (cmdInput && document.activeElement !== cmdInput
          && e.key.length === 1 && !e.ctrlKey && !e.altKey && !e.metaKey && !e.shiftKey) {
        cmdInput.focus();
      }
    });
  }

  private buildToolbar(): void {
    const toolbar = document.getElementById('toolbar');
    if (!toolbar) return;
    toolbar.innerHTML = '';
    for (const vpId of ALL_VIEWPORTS) {
      const info = VIEWPORT_LABELS[vpId];
      const btn = document.createElement('button');
      btn.id = `btn-${vpId}`;
      btn.textContent = `${info.label} (!${info.num})`;
      btn.className = this.activeViewports.has(vpId) ? 'vp-btn active' : 'vp-btn inactive';
      btn.addEventListener('click', () => this.toggleViewport(vpId));
      toolbar.appendChild(btn);
    }
  }

  private updateToolbar(): void {
    for (const vpId of ALL_VIEWPORTS) {
      const btn = document.getElementById(`btn-${vpId}`);
      if (btn) btn.className = this.activeViewports.has(vpId) ? 'vp-btn active' : 'vp-btn inactive';
    }
  }

  private rebuildLayout(): void {
    const viewports = document.getElementById('viewports');
    if (!viewports) return;
    viewports.innerHTML = '';
    const active = ALL_VIEWPORTS.filter((vp) => this.activeViewports.has(vp));
    if (active.length === 0) {
      viewports.innerHTML = '<div class="no-viewports">No viewports active</div>';
      return;
    }
    const mainPanel = this.panels.get(active[0])!;
    mainPanel.className = 'viewport viewport-main';
    viewports.appendChild(mainPanel);
    if (active.length > 1) {
      const sideStack = document.createElement('div');
      sideStack.className = 'viewport-stack';
      sideStack.style.width = `${this.sideStackWidth}px`;
      for (const vp of active.slice(1)) {
        const panel = this.panels.get(vp)!;
        panel.className = 'viewport viewport-side';
        panel.style.flex = '1';
        sideStack.appendChild(panel);
      }
      viewports.appendChild(sideStack);
    }
    this.setFocus(this.focusedViewport);
  }

  private createViewportPanel(vpId: ViewportId): HTMLElement {
    const panel = document.createElement('div');
    panel.id = `vp-${vpId}`;
    panel.className = 'viewport';
    panel.addEventListener('click', () => this.setFocus(vpId));
    const titleEl = document.createElement('div');
    titleEl.className = 'viewport-title';
    titleEl.textContent = VIEWPORT_LABELS[vpId].label;
    panel.appendChild(titleEl);
    const content = document.createElement('div');
    content.id = `vp-${vpId}-content`;
    content.className = 'viewport-content';
    panel.appendChild(content);
    return panel;
  }
}
