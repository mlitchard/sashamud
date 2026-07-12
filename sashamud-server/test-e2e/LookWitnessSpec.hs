{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module LookWitnessSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithClient
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)

spec :: Spec
spec = describe "Look and Witness" . around withServer . sequential $ do
    it "look returns lobby description in narration" $ \ctx ->
        webDriverTestWithClient ctx lookTest id

    it "second player joining triggers witness narration for first player" $ \ctx ->
        webDriverTestWithClient ctx witnessTest id

lookTest :: String
lookTest =
    [i|(sessionId, sock, resolve) => {
  const messages: any[] = [];

  sock.receive((msg) => {
    messages.push(msg);

    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      if (narr._actionConsequence.length > 0) {
        sock.raw.close();
        resolve("#{successToken}");
        return;
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look"});

  setTimeout(() => {
    sock.raw.close();
    resolve("timeout: no look narration within 10s. Got: " + JSON.stringify(messages));
  }, 10000);
};|]

witnessTest :: String
witnessTest =
    [i|(sessionId, sock, resolve) => {
  let gotWitness = false;

  // Player 1 (from harness) listens for witness narration
  sock.receive((msg) => {
    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("looks around")) {
          gotWitness = true;
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  // Login player 2 via the API, connect WS, send "look"
  const player2Name = "witness" + Math.random().toString(36).replace(/[^a-z]/g, "").substring(0, 6);
  const sid2: string = await API["/api/game/login(PlayerNameUNV)"](player2Name);
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {});
  await new Promise(r => setTimeout(r, 2000));
  sock2.send({tag: "GameCommand", contents: "look"});

  setTimeout(() => {
    if (!gotWitness) {
      sock.raw.close();
      resolve("timeout: no witness narration within 10s");
    }
  }, 10000);
};|]
