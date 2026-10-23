{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module ParseFailureSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithClient
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)

spec :: Spec
spec = describe "Parse Failure" . around withServer . sequential $ do
    it "parse failure reaches the sender while the other player's narration arrives" $ \ctx ->
        webDriverTestWithClient ctx ["witness"] parseFailureTest id

parseFailureTest :: String
parseFailureTest =
    [i|(sessionId, sock, resolve) => {
  let gotFailure = false;
  let gotNarration = false;
  let done = false;

  const finish = () => {
    if (gotFailure && gotNarration && !done) {
      done = true;
      sock.raw.close();
      resolve("#{successToken}");
    }
  };

  sock.receive((msg) => {
    if (msg.tag === "RepairRequest") {
      gotFailure = true;
      finish();
    }
  });

  sock.send({tag: "GameCommand", contents: "pick up the red ball"});

  const sid2: string = tokens["witness"];
  const sock2 = await API["/ws/game{Sec-WebSocket-Protocol}"](sid2);
  sock2.receive((msg: MessageFrom) => {
    if (msg.tag === "GameNarration") {
      const narr = msg.contents;
      if (narr._actionConsequence.length > 0) {
        gotNarration = true;
        finish();
      }
    }
  });
  await new Promise(r => setTimeout(r, 2000));
  sock2.send({tag: "GameCommand", contents: "look"});

  setTimeout(() => {
    if (!done) {
      done = true;
      sock.raw.close();
      const missing: string[] = [];
      if (!gotFailure) { missing.push("no RepairRequest for the sender"); }
      if (!gotNarration) { missing.push("no GameNarration with _actionConsequence for the witness"); }
      resolve("timeout within 10s: " + missing.join("; "));
    }
  }, 10000);
};|]
