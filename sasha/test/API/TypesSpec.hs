module API.TypesSpec (spec) where

import SashaPrelude
import Data.Aeson (decode, encode)
import API.Types (LoginResponse (LoginResponse), PlayerName (PlayerName))
import Test.Hspec

spec :: Spec
spec = describe "API.Types" $ do
  it "PlayerName roundtrips" $ do
    let pn = PlayerName "TestPlayer"
    decode (encode pn) `shouldBe` Just pn

  it "LoginResponse roundtrips" $ do
    let lr = LoginResponse "session-123"
    decode (encode lr) `shouldBe` Just lr
