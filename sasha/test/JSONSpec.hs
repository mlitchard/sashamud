module JSONSpec (spec) where

import           Data.Aeson (FromJSON, ToJSON, decode, encode)
import           Data.Kind (Type)
import           SashaPrelude (Eq, Maybe (Just), Show, ($), (==))

import           API.Types (MessageTo)
import           Model.Account (AccountStatus, AuthentikUserId, UserPermissions)
import           Model.Authorization (AllowedAction)
import           Model.Core (Narration, SessionId)
import           Model.GID (GID)
import           Model.Mid (Mid)
import           Model.RichText (RichText, StyledSpan, TextColor, TextStyle)
import           Model.WireProtocol (AnalysisViewport, MessageFrom)
import           Server.Validator (PlayerNameUNV, PlayerNameVAL)
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
    prop "PlayerNameUNV" $ checkJSON @PlayerNameUNV
    prop "PlayerNameVAL" $ checkJSON @PlayerNameVAL
    prop "Narration" $ checkJSON @Narration
    prop "GID" $ checkJSON @(GID ())
    prop "AnalysisViewport" $ checkJSON @AnalysisViewport
    prop "Mid" $ checkJSON @(Mid ())
    prop "AllowedAction" $ checkJSON @AllowedAction
    prop "AccountStatus" $ checkJSON @AccountStatus
    prop "AuthentikUserId" $ checkJSON @AuthentikUserId
    prop "UserPermissions" $ checkJSON @UserPermissions
