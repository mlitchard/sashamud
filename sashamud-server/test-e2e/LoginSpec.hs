{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module LoginSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithClient
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)

spec :: Spec
spec = describe "Login" . around withServer . sequential $ do
    it "login and receive heartbeat" $ \ctx ->
        webDriverTestWithClient ctx loginHeartbeatTest id

loginHeartbeatTest :: String
loginHeartbeatTest =
    [i|(sessionId, sock, resolve) => {
  sock.receive((msg) => {
    if (msg.tag === "SystemMessage" && msg.contents === "*** heartbeat") {
      sock.raw.close();
      resolve("#{successToken}");
    }
  });

  setTimeout(() => {
    sock.raw.close();
    resolve("timeout: no heartbeat received within 15s");
  }, 15000);
};|]
