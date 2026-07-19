{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module LookAtBallSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithClient
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)

spec :: Spec
spec = describe "Look At Ball" . around withServer . sequential $ do
    it "look at ball returns ball description" $ \ctx ->
        webDriverTestWithClient ctx lookAtBallTest id

    it "second player sees witness narration for look at ball" $ \ctx ->
        webDriverTestWithClient ctx lookAtBallWitnessTest id

lookAtBallTest :: String
lookAtBallTest =
    [i|(sessionId, sock, resolve) => {
  const messages: any[] = [];

  sock.receive((msg) => {
    messages.push(msg);

    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("A small red ball.")) {
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  sock.send({tag: "GameCommand", contents: "look at ball"});

  setTimeout(() => {
    sock.raw.close();
    resolve("timeout: no look-at narration within 10s. Got: " + JSON.stringify(messages));
  }, 10000);
};|]

lookAtBallWitnessTest :: String
lookAtBallWitnessTest =
    [i|(sessionId, sock, resolve) => {
  let gotWitness = false;

  sock.receive((msg) => {
    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      const conseq = narr._actionConsequence || [];
      for (const richText of conseq) {
        const text = richText.map(s => s._ssText).join("");
        if (text.includes("looks at the ball")) {
          gotWitness = true;
          sock.raw.close();
          resolve("#{successToken}");
          return;
        }
      }
    }
  });

  const player2Name = "looker" + Math.random().toString(36).replace(/[^a-z]/g, "").substring(0, 6);
  const sid2: string = await API["/api/game/login(PlayerNameUNV)"](player2Name);
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {});
  await new Promise(r => setTimeout(r, 2000));
  sock2.send({tag: "GameCommand", contents: "look at ball"});

  setTimeout(() => {
    if (!gotWitness) {
      sock.raw.close();
      resolve("timeout: no witness narration within 10s");
    }
  }, 10000);
};|]
