{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module LookAtPlayerSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithClient
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)

spec :: Spec
spec = describe "Look At Player" . around withServer . sequential $ do
    it "look at player returns player description" $ \ctx ->
        webDriverTestWithClient ctx ["sasha"] lookAtPlayerTest id

    it "target player sees witness narration for look at player" $ \ctx ->
        webDriverTestWithClient ctx ["sasha"] lookAtPlayerWitnessTest id

    it "look at nonexistent player returns nobody-here narration" $ \ctx ->
        webDriverTestWithClient ctx ["sasha"] lookAtNobodyTest id

    it "witness sees failed agent look narration" $ \ctx ->
        webDriverTestWithClient ctx ["sasha"] lookAtNobodyWitnessTest id

    it "player can look at self" $ \ctx ->
        webDriverTestWithClient ctx ["sasha"] lookAtSelfTest id

lookAtPlayerTest :: String
lookAtPlayerTest =
    [i|(sessionId, sock, resolve) => {
  const messages: any[] = [];

  const sid2: string = tokens["sasha"];
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {});
  await new Promise(r => setTimeout(r, 2000));

  sock.receive((msg) => {
    messages.push(msg);

    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("A player.")) {
          sock2.raw.close();
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look at sasha"});

  setTimeout(() => {
    sock2.raw.close();
    sock.raw.close();
    resolve("timeout: no look-at-player narration within 10s. Got: " + JSON.stringify(messages));
  }, 10000);
};|]

lookAtNobodyTest :: String
lookAtNobodyTest =
    [i|(sessionId, sock, resolve) => {
  const messages: any[] = [];

  sock.receive((msg) => {
    messages.push(msg);

    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("That's not here. Try something else.")) {
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look at bootstrap"});

  setTimeout(() => {
    sock.raw.close();
    resolve("timeout: no nobody-here narration within 10s. Got: " + JSON.stringify(messages));
  }, 10000);
};|]

lookAtPlayerWitnessTest :: String
lookAtPlayerWitnessTest =
    [i|(sessionId, sock, resolve) => {
  let settled = false;

  const sid2: string = tokens["sasha"];
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {});
  await new Promise(r => setTimeout(r, 2000));

  sock2.receive((msg) => {
    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const fields = [narr._playerAction, narr._actionConsequence, narr._presenceListing, narr._actionEpilogue];
      const texts = fields.flatMap(field => (field || []).map(richText => richText.map(s => s._ssText).join("")));
      if (texts.some(text => text.includes("A player."))) {
        settled = true;
        sock2.raw.close();
        sock.raw.close();
        resolve("target received the looked-at description: " + JSON.stringify(texts));
        return;
      }
      if (texts.some(text => text.includes("looks at"))) {
        settled = true;
        sock2.raw.close();
        sock.raw.close();
        resolve("#{successToken}");
        return;
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look at sasha"});

  setTimeout(() => {
    if (!settled) {
      sock2.raw.close();
      sock.raw.close();
      resolve("timeout: no witness narration within 10s");
    }
  }, 10000);
};|]

lookAtNobodyWitnessTest :: String
lookAtNobodyWitnessTest =
    [i|(sessionId, sock, resolve) => {
  let gotWitness = false;

  const sid2: string = tokens["sasha"];
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {});
  await new Promise(r => setTimeout(r, 2000));

  sock2.receive((msg) => {
    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("looks around for someone not here")) {
          gotWitness = true;
          sock2.raw.close();
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look at bootstrap"});

  setTimeout(() => {
    if (!gotWitness) {
      sock2.raw.close();
      sock.raw.close();
      resolve("timeout: no failed-look witness narration within 10s");
    }
  }, 10000);
};|]

lookAtSelfTest :: String
lookAtSelfTest =
    [i|(sessionId, sock, resolve) => {
  const messages: any[] = [];

  sock.receive((msg) => {
    messages.push(msg);

    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("A player.")) {
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look at raj"});

  setTimeout(() => {
    sock.raw.close();
    resolve("timeout: no look-at-self narration within 10s. Got: " + JSON.stringify(messages));
  }, 10000);
};|]
