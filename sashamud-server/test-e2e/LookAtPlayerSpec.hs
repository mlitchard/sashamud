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
        webDriverTestWithClient ctx lookAtPlayerTest id

    it "target player sees witness narration for look at player" $ \ctx ->
        webDriverTestWithClient ctx lookAtPlayerWitnessTest id

lookAtPlayerTest :: String
lookAtPlayerTest =
    [i|(sessionId, sock, resolve) => {
  const messages: any[] = [];

  const sid2: string = await API["/api/game/login(PlayerNameUNV)"]("Sasha");
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

lookAtPlayerWitnessTest :: String
lookAtPlayerWitnessTest =
    [i|(sessionId, sock, resolve) => {
  let gotWitness = false;

  const sid2: string = await API["/api/game/login(PlayerNameUNV)"]("Sasha");
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {});
  await new Promise(r => setTimeout(r, 2000));

  sock2.receive((msg) => {
    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("looks at")) {
          gotWitness = true;
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
    if (!gotWitness) {
      sock2.raw.close();
      sock.raw.close();
      resolve("timeout: no witness narration within 10s");
    }
  }, 10000);
};|]
