import { API, WireMessage } from '@sasha/type-gen-output/client';

export type { WireMessage } from '@sasha/type-gen-output/client';

type ConnectionStatus = 'disconnected' | 'connecting' | 'connected';

export class GameConnection {
  private ws: WebSocket | null = null;
  private sessionId: string | null = null;
  private status: ConnectionStatus = 'disconnected';
  private reconnectAttempts = 0;
  private maxReconnect = 5;
  private reconnectDelay = 1000;

  private messageCallbacks: Array<(msg: WireMessage) => void> = [];
  private statusCallbacks: Array<(status: ConnectionStatus) => void> = [];

  connect(sessionId?: string): void {
    if (sessionId) this.sessionId = sessionId;
    if (!this.sessionId) return;
    this.setStatus('connecting');
    API["/ws/game{Sec-WebSocket-Protocol}"](this.sessionId).then(({ send, receive, raw }) => {
      this.ws = raw;

      raw.onopen = () => {
        this.reconnectAttempts = 0;
        this.setStatus('connected');
      };

      this.updateTestHook('bridge-session', this.sessionId!);

      receive((msg: WireMessage) => {
        for (const cb of this.messageCallbacks) cb(msg);
      });

      raw.onclose = () => {
        this.setStatus('disconnected');
        this.attemptReconnect();
      };

      raw.onerror = () => raw.close();
    });
  }

  sendCommand(text: string): void {
    if (!this.ws) return;
    this.ws.send(JSON.stringify(text));
  }

  onMessage(callback: (msg: WireMessage) => void): void {
    this.messageCallbacks.push(callback);
  }

  onStatusChange(callback: (status: ConnectionStatus) => void): void {
    this.statusCallbacks.push(callback);
  }

  private setStatus(status: ConnectionStatus): void {
    this.status = status;
    this.updateTestHook('bridge-status', status);
    for (const cb of this.statusCallbacks) cb(status);
  }

  private updateTestHook(id: string, value: string): void {
    const el = document.getElementById(id);
    if (el) el.textContent = value;
  }

  private attemptReconnect(): void {
    if (this.reconnectAttempts >= this.maxReconnect) return;
    this.reconnectAttempts++;
    const delay = this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1);
    setTimeout(() => this.connect(), delay);
  }
}
