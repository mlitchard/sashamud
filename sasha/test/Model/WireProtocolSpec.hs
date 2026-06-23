module Model.WireProtocolSpec (spec) where

import SashaPrelude
import Data.Aeson (decode, encode)
import Data.Map.Strict (singleton)
import Model.RichText (TextColor (White), colored)
import Model.WireProtocol (WireMessage (AnalysisData, ChatMessage, CommandResponse, GameNarration, SessionId, SystemMessage))
import Test.Hspec

spec :: Spec
spec = describe "Model.WireProtocol" $ do
  it "SessionId roundtrips" $ do
    let msg = SessionId "abc-123"
    decode (encode msg) `shouldBe` Just msg

  it "SystemMessage roundtrips" $ do
    let msg = SystemMessage "*** heartbeat"
    decode (encode msg) `shouldBe` Just msg

  it "GameNarration roundtrips" $ do
    let msg = GameNarration [colored White "You look around."]
    decode (encode msg) `shouldBe` Just msg

  it "CommandResponse roundtrips" $ do
    let msg = CommandResponse [colored White "OK"]
    decode (encode msg) `shouldBe` Just msg

  it "ChatMessage roundtrips" $ do
    let msg = ChatMessage "hello"
    decode (encode msg) `shouldBe` Just msg

  it "AnalysisData roundtrips" $ do
    let msg = AnalysisData (singleton "parser" [colored White "parse tree"])
    decode (encode msg) `shouldBe` Just msg
