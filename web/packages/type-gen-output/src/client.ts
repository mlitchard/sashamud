// Defined in API.Types of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type DSLSource = string;
// Defined in API.Types of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type MessageTo = Ping | GameCommand | RepairedCommand;
export interface Ping {
  readonly tag: "Ping";
}
export interface GameCommand {
  readonly tag: "GameCommand";
  readonly contents: string;
}
export interface RepairedCommand {
  readonly tag: "RepairedCommand";
  readonly contents: [UnparsedSentence, string, SlmName];
}
// Defined in API.Types of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type ParseFailure = string;
// Defined in API.Types of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type RepairAttempt = [string, ParseFailure];
// Defined in API.Types of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type SlmName = string;
// Defined in Grammar.Gbnf of sasha-grammar-0.1.0.0-8WzKeWZQEwnLr5T52YhIVo
export type Gbnf = string;
// Defined in Grammar.Gbnf of sasha-grammar-0.1.0.0-8WzKeWZQEwnLr5T52YhIVo
export type UnparsedSentence = string;
// Defined in Model.Core of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export interface Narration {
  // readonly tag: "Narration";
  readonly _playerAction: Array<RichText>;
  readonly _actionConsequence: Array<RichText>;
  readonly _presenceListing: Array<RichText>;
  readonly _actionEpilogue: Array<RichText>;
}
// Defined in Model.Core of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type SessionId = string;
// Defined in Model.RichText of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export interface StyledSpan {
  // readonly tag: "StyledSpan";
  readonly _ssStyle: TextStyle;
  readonly _ssText: string;
}
// Defined in Model.RichText of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export interface TextStyle {
  // readonly tag: "TextStyle";
  readonly _tsFgColor: TextColor | null;
  readonly _tsBold: boolean;
  readonly _tsItalic: boolean;
}
// Defined in Model.RichText of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type RichText = Array<StyledSpan>;
// Defined in Model.RichText of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type TextColor = "Red" | "Green" | "Blue" | "Yellow" | "Cyan" | "Magenta" | "White" | "BrightWhite" | "BrightRed" | "BrightGreen" | "BrightBlue" | "BrightYellow" | "BrightCyan" | "BrightMagenta";
// Defined in Model.WireProtocol of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type AnalysisViewport = "Parser" | "State" | "Meta" | "Graphics" | "GameMap";
// Defined in Model.WireProtocol of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type MessageFrom = SessionAck | GameNarration | CommandResponse | ChatMessage | SystemMessage | Pong | AnalysisData | RepairRequest;
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
  readonly contents: Array<[AnalysisViewport,Array<RichText>]>;
}
export interface RepairRequest {
  readonly tag: "RepairRequest";
  readonly contents: [UnparsedSentence, ParseFailure, Gbnf, Array<RepairAttempt>];
}
// Defined in Server.Validator of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type PlayerNameUNV = string;
// Defined in Server.Validator of sasha-0.1.0.0-6R1wvb4bQPjF6HGiPcb4p3
export type PlayerNameVAL = string;
//API
export const API = {
  base: "",
  baseWS: "",
  "/api/game/logout{BEARER}": (() => {
  const urlBuilder = () => `${API.base}/api/game/logout`;
  const f = async (BEARER:string): Promise<null> => {
    const uri = urlBuilder();
    return fetch(uri, {
      method: "DELETE",
      headers: {
        "BEARER": BEARER
      },
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
  },
"/api/game/dsl(DSLSource){BEARER}": (() => {
  const urlBuilder = () => `${API.base}/api/game/dsl`;
  const f = async (BEARER:string,DSLSource:DSLSource): Promise<null> => {
    const uri = urlBuilder();
    return fetch(uri, {
      method: "POST",
      headers: {
        "BEARER": BEARER,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify(DSLSource),
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
  return f; })()
};