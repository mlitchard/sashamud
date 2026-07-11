module JSONSpec (spec) where

import           Data.Aeson (FromJSON, ToJSON, decode, encode)
import           Data.Kind (Type)
import           SashaPrelude (Eq, Maybe (Just), Show, ($), (==))

import           API.Types (LoginResponse, MessageTo)
import           Model.Core (SessionId)
import           Model.RichText (RichText, StyledSpan, TextColor, TextStyle)
import           Model.WireProtocol (MessageFrom)
import           Server.Validator (PlayerNameUNV)
import           Test.Hspec (Spec, describe)
import           Test.Hspec.QuickCheck (prop)
import           Test.QuickCheck (Arbitrary, Property, property)

checkJSON ::
    forall (a :: Type).
    ( Arbitrary a
    , Show a
    , Eq a
    , FromJSON a
    , ToJSON a
    ) =>
    Property
checkJSON = property $ \(a :: a) -> Just a == decode (encode a)

spec :: Spec
spec = describe "JSON round trip" $ do
    prop "SessionId" $ checkJSON @SessionId
    prop "TextColor" $ checkJSON @TextColor
    prop "TextStyle" $ checkJSON @TextStyle
    prop "StyledSpan" $ checkJSON @StyledSpan
    prop "RichText" $ checkJSON @RichText
    prop "MessageFrom" $ checkJSON @MessageFrom
    prop "MessageTo" $ checkJSON @MessageTo
    prop "LoginResponse" $ checkJSON @LoginResponse
    prop "PlayerNameUNV" $ checkJSON @PlayerNameUNV
