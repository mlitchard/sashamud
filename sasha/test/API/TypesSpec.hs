module API.TypesSpec (spec) where

import           API.Types
  ( LoginResponse (LoginResponse)
  , SessionId (SessionId)
  )
import           Data.Aeson (decode, encode)
import           SashaPrelude
import           Server.Validator (PlayerNameUNV (PlayerNameUNV))
import           Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "API.Types" $ do
  it "PlayerNameUNV roundtrips" $ do
    let pn = PlayerNameUNV "TestPlayer"
    decode (encode pn) `shouldBe` Just pn

  it "LoginResponse roundtrips" $ do
    let lr = LoginResponse (SessionId "session-123")
    decode (encode lr) `shouldBe` Just lr
