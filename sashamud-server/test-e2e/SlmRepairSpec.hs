{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module SlmRepairSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithPage
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)
import           Test.WebDriver (Selector (ByCSS), asyncJS, findElem, sendKeys)

spec :: Spec
spec = describe "Slm repair" . around withServer . sequential $ do
    it "an unparseable sentence is repaired by the model and runs" $ \ctx ->
        webDriverTestWithPage ctx $ \_ -> do
          connected <- asyncJS [] waitConnected
          case connected of
            Just "connected" -> do
              findElem (ByCSS "#cmd-input") >>= sendKeys "pick up the red ball\n"
              asyncJS [] pollSceneViewport
            Just _ -> pure connected
            Nothing -> pure connected

waitConnected :: Text
waitConnected =
    [i|const done = arguments[0];
const started = Date.now();
const timer = setInterval(() => {
  const el = document.getElementById('bridge-status');
  if (el && el.textContent === "connected") {
    clearInterval(timer);
    done("connected");
  } else if (Date.now() - started > 15000) {
    clearInterval(timer);
    done("timeout: websocket never connected");
  }
}, 200);|]

pollSceneViewport :: Text
pollSceneViewport =
    [i|const done = arguments[0];
const started = Date.now();
const timer = setInterval(() => {
  const el = document.getElementById('vp-scene-content');
  if (el && el.textContent && el.textContent.includes("You pick up the red ball.")) {
    clearInterval(timer);
    done("#{successToken}");
  } else if (Date.now() - started > 300000) {
    clearInterval(timer);
    const sys = document.getElementById('vp-system-content');
    done("timeout: no pickup narration. scene: " + (el ? el.textContent : "") + " | system: " + (sys ? sys.textContent : ""));
  }
}, 200);|]
