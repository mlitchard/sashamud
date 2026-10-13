{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module CopyTokenSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithPage
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it, sequential)
import           Test.WebDriver (Selector (ByCSS), asyncJS, click, findElem)

spec :: Spec
spec = describe "Copy token" . around withServer . sequential $ do
    it "copies the dsl token to the clipboard" $ \ctx ->
        webDriverTestWithPage ctx $ \token -> do
          findElem (ByCSS "#settings-btn") >>= click
          findElem (ByCSS "#dsl-token-btn") >>= click
          findElem (ByCSS "#copy-token-btn") >>= click
          copied <- asyncJS [] readClipboard
          pure (Just (if copied == Just (unpack token) then successToken else "clipboard held: " <> show copied))

readClipboard :: Text
readClipboard =
    [i|navigator.clipboard.readText().then(arguments[0], (err) => arguments[0]("clipboard read rejected: " + String(err)));|]
