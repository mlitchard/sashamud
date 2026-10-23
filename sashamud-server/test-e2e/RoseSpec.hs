{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE QuasiQuotes       #-}

module RoseSpec (spec) where

import           Data.String.Interpolate (i)
import           SashaPrelude
import           SeleniumHarness
  ( successToken
  , webDriverTestWithClient
  , withServer
  )
import           Test.Hspec (Spec, around, describe, it)

spec :: Spec
spec = describe "Generated TypeScript client" . around withServer $ do
    it "ROSE" $ \ctx ->
      webDriverTestWithClient ctx [] [i|(sessionId, sock, resolve) => { resolve("#{successToken}"); };|] id
