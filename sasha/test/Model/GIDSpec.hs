module Model.GIDSpec (spec) where

import SashaPrelude
import Data.Aeson (decode, encode)
import Model.GID (GID (..))
import Model.Core (Agent, Scene)
import Test.Hspec

spec :: Spec
spec = describe "Model.GID" $ do
  it "JSON roundtrip for GID Agent" $ do
    let gid = GID 42 :: GID Agent
    decode (encode gid) `shouldBe` Just gid

  it "JSON roundtrip for GID Scene" $ do
    let gid = GID 0 :: GID Scene
    decode (encode gid) `shouldBe` Just gid

  it "GIDs with same Int are equal regardless of phantom" $ do
    let a = GID 1 :: GID Agent
        b = GID 1 :: GID Scene
    unGID a `shouldBe` unGID b
