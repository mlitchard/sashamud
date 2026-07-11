// Defined in API.Types of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type LoginResponse = SessionId;
// Defined in API.Types of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type MessageTo = Ping | GameCommand;
export interface Ping {
  readonly tag: "Ping";
}
export interface GameCommand {
  readonly tag: "GameCommand";
  readonly contents: string;
}
// Defined in Model.Core of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export interface Narration {
  // readonly tag: "Narration";
  readonly _playerAction: Array<RichText>;
  readonly _actionConsequence: Array<RichText>;
  readonly _presenceListing: Array<RichText>;
  readonly _actionEpilogue: Array<RichText>;
}
// Defined in Model.Core of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type SessionId = string;
// Defined in Model.RichText of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export interface StyledSpan {
  // readonly tag: "StyledSpan";
  readonly _ssStyle: TextStyle;
  readonly _ssText: string;
}
// Defined in Model.RichText of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export interface TextStyle {
  // readonly tag: "TextStyle";
  readonly _tsFgColor: TextColor | null;
  readonly _tsBold: boolean;
  readonly _tsItalic: boolean;
}
// Defined in Model.RichText of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type RichText = Array<StyledSpan>;
// Defined in Model.RichText of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type TextColor = "Red" | "Green" | "Blue" | "Yellow" | "Cyan" | "Magenta" | "White" | "BrightWhite" | "BrightRed" | "BrightGreen" | "BrightBlue" | "BrightYellow" | "BrightCyan" | "BrightMagenta";
// Defined in Model.WireProtocol of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type AnalysisViewport = "Parser" | "State" | "Meta" | "Graphics" | "GameMap";
// Defined in Model.WireProtocol of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type MessageFrom = SessionAck | GameNarration | CommandResponse | ChatMessage | SystemMessage | Pong | AnalysisData;
export interface SessionAck {
  readonly tag: "SessionAck";
  readonly contents: SessionId;
}
export interface GameNarration {
  readonly tag: "GameNarration";
  readonly contents: Narration;
}
export interface CommandResponse {
  readonly tag: "CommandResponse";
  readonly contents: Array<RichText>;
}
export interface ChatMessage {
  readonly tag: "ChatMessage";
  readonly contents: string;
}
export interface SystemMessage {
  readonly tag: "SystemMessage";
  readonly contents: string;
}
export interface Pong {
  readonly tag: "Pong";
}
export interface AnalysisData {
  readonly tag: "AnalysisData";
  readonly contents: [AnalysisViewport,Array<RichText>][];
}
// Defined in Server.Validator of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type PlayerNameUNV = string;
// Defined in Server.Validator of sasha-0.1.0.0-Dl0fJS6Owx62ylekHv3J5d
export type PlayerNameVAL = string;
//API
export const API = {
  base: "",
  baseWS: "",
  "/api/game/login(PlayerNameUNV)": (() => {
  const urlBuilder = () => `${API.base}/api/game/login`;
  const f = async (PlayerNameUNV:PlayerNameUNV): Promise<LoginResponse> => {
    const uri = urlBuilder();
    return fetch(uri, {
      method: "POST",
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(PlayerNameUNV),
      redirect: 'manual'
    }).then(res => {
      const location = res.headers.get('Location');
      if (res.status === 401 && location) {
        window.location.replace(location);
        return Promise.reject(res);
      } else {
        return res.status === 200
          ? (res.json() as Promise<LoginResponse>)
          : Promise.reject(res);
      }
    });
  };
  f.urlBuilder = urlBuilder;
  return f; })(),
"/api/game/logout(SessionId)": (() => {
  const urlBuilder = () => `${API.base}/api/game/logout`;
  const f = async (SessionId:SessionId): Promise<null> => {
    const uri = urlBuilder();
    return fetch(uri, {
      method: "DELETE",
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(SessionId),
      redirect: 'manual'
    }).then(res => {
      const location = res.headers.get('Location');
      if (res.status === 401 && location) {
        window.location.replace(location);
        return Promise.reject(res);
      } else {
        return res.status === 204
          ? Promise.resolve(null)
          : Promise.reject(res);
      }
    });
  };
  f.urlBuilder = urlBuilder;
  return f; })(),
"/ws/game{Sec-WebSocket-Protocol}": (Sec_WebSocket_Protocol:string):
    Promise<{ send : (input: MessageTo) => void
            , receive : (cb: (output: MessageFrom) => void) => void
            , raw : WebSocket
    }> => {
      if(!API.baseWS){
        const pr = window.location.protocol === "http:" ? "ws:" : "wss:";
        API.baseWS = `${pr}//${window.location.host}`;
        console.info(`You have not set API.baseWS, so it has been defaulted to ${API.baseWS}.
        Please note, that WebSocket's need to have absolute uri's including protocol.`);
      }
      const ws = new WebSocket(`${API.baseWS}/ws/game`, [Sec_WebSocket_Protocol]);
      return Promise.resolve({
        send: (input: MessageTo) => ws.send(JSON.stringify(input)),
        receive: (cb: ((output: MessageFrom) => void)) =>
          ws.onmessage = (message: MessageEvent<string>) => cb(JSON.parse(message.data) as MessageFrom),
        raw: ws
      });
  }
};