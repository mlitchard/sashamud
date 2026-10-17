{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module ParserViewSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
  ( Maybe (Just, Nothing)
  , Text
  , pure
  , ($)
  , (.)
  , (>>=)
  )
import           SeleniumHarness
  ( successToken
  , webDriverTestWithPage
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)
import           Test.WebDriver (Selector (ByCSS), asyncJS, findElem, sendKeys)

spec :: Spec
spec = describe "Parser view" . around withServer . sequential $ do
    it "a typed sentence shows its parse in the Parser tab" $ \ctx ->
        webDriverTestWithPage ctx $ \_ -> do
          connected <- asyncJS [] waitConnected
          case connected of
            Just "connected" -> do
              opened <- asyncJS [] openParserTab
              case opened of
                Just "opened" -> do
                  findElem (ByCSS "#cmd-input") >>= sendKeys "look\n"
                  asyncJS [] pollParserViewport
                Just _ -> pure opened
                Nothing -> pure opened
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

openParserTab :: Text
openParserTab =
    [i|const done = arguments[0];
document.dispatchEvent(new KeyboardEvent('keydown', { code: 'Digit4', shiftKey: true }));
done("opened");|]

pollParserViewport :: Text
pollParserViewport =
    [i|const done = arguments[0];
const started = Date.now();
const timer = setInterval(() => {
  const el = document.getElementById('vp-parser-content');
  if (el && el.textContent && el.textContent.includes("=== Sentence ===")) {
    clearInterval(timer);
    done("#{successToken}");
  } else if (Date.now() - started > 15000) {
    clearInterval(timer);
    const sys = document.getElementById('vp-system-content');
    done("timeout: no sentence parse. parser: " + (el ? el.textContent : "") + " | system: " + (sys ? sys.textContent : ""));
  }
}, 200);|]
