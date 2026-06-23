// Defined in API.Types of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export type GameCommand = string;
// Defined in API.Types of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export type LoginResponse = SessionId;
// Defined in API.Types of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export type PlayerName = string;
// Defined in Model.RichText of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export interface StyledSpan {
  // readonly tag: "StyledSpan";
  readonly ssStyle: TextStyle;
  readonly ssText: string;
}
// Defined in Model.RichText of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export interface TextStyle {
  // readonly tag: "TextStyle";
  readonly tsFgColor: TextColor | null;
  readonly tsBold: boolean;
  readonly tsItalic: boolean;
}
// Defined in Model.RichText of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export type RichText = Array<StyledSpan>;
// Defined in Model.RichText of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export type TextColor = "Red" | "Green" | "Blue" | "Yellow" | "Cyan" | "Magenta" | "White" | "BrightWhite" | "BrightRed" | "BrightGreen" | "BrightBlue" | "BrightYellow" | "BrightCyan" | "BrightMagenta";
// Defined in Model.WireProtocol of sasha-0.1.0.0-E52Uz84tstZFiBbuO6Etf7
export type WireMessage = SessionAck | GameNarration | CommandResponse | ChatMessage | SystemMessage | AnalysisData;
export interface SessionAck {
  readonly tag: "SessionAck";
  readonly contents: SessionId;
}
export interface GameNarration {
  readonly tag: "GameNarration";
  readonly contents: Array<RichText>;
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
export interface AnalysisData {
  readonly tag: "AnalysisData";
  readonly contents: { [key: string]: Array<RichText> };
}
//API
export const API = {
  base: "",
  baseWS: "",
  "/api/game/login(PlayerName)": (() => {
  const urlBuilder = () => `${API.base}/api/game/login`;
  const f = async (PlayerName:PlayerName): Promise<LoginResponse> => {
    const uri = urlBuilder();
    return fetch(uri, {
      method: "POST",
      headers: {
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(PlayerName),
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
"/ws/game{Sec-WebSocket-Protocol}": (Sec_WebSocket_Protocol:string):
    Promise<{ send : (input: string) => void
            , receive : (cb: (output: WireMessage) => void) => void
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
        send: (input: string) => ws.send(JSON.stringify(input)),
        receive: (cb: ((output: WireMessage) => void)) =>
          ws.onmessage = (message: MessageEvent<string>) => cb(JSON.parse(message.data) as WireMessage),
        raw: ws
      });
  }
};