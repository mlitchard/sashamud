module Model.WireProtocolSpec (spec) where

import           API.Types (SessionId (SessionId))
import           Data.Aeson (decode, encode)
import           Data.Map.Strict (singleton)
import           Data.UUID (toText)
import           Data.UUID.V4 (nextRandom)
import           Model.RichText (TextColor (White), colored)
import           Model.WireProtocol
  ( WireMessage (AnalysisData, ChatMessage, CommandResponse, GameNarration, SessionAck, SystemMessage)
  )
import           SashaPrelude
import           Test.Hspec (Spec, describe, it, shouldBe)

spec :: Spec
spec = describe "Model.WireProtocol" $ do
  it "SessionAck roundtrips" $ do
    sessionId <- SessionId . toText <$> nextRandom
    let msg = SessionAck sessionId
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
