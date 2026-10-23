module JSONSpec (spec) where

import           Data.Aeson (FromJSON, ToJSON, decode, encode)
import           Data.Kind (Type)
import           SashaPrelude (Eq, Maybe (Just), Show, ($), (==))

import           API.Types (MessageTo, ParseFailure, RepairAttempt, SlmName)
import           ArbitraryOrphans ()
import           Grammar.Gbnf (Gbnf, UnparsedSentence)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Adjectives (Adjective)
import           Grammar.Parser.Atomics.Misc (Determiner)
import           Grammar.Parser.Atomics.Nouns (DirectionalStimulus)
import           Grammar.Parser.Atomics.Prepositions (DirectionalStimulusMarker)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase
  , NounPhrase
  )
import           Grammar.Parser.GCase (VerbKey)
import           Model.Account (AccountStatus, AuthentikUserId, UserPermissions)
import           Model.Authorization (AllowedAction)
import           Model.Core
  ( ActionManagement
  , ActionManagementFunctions
  , Agent
  , AgentKind
  , Narration
  , Object
  , SessionId
  )
import           Model.GID (GID)
import           Model.Jwt (Credentials, SashaClaims)
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
    prop "ParseFailure" $ checkJSON @ParseFailure
    prop "SlmName" $ checkJSON @SlmName
    prop "RepairAttempt" $ checkJSON @RepairAttempt
    prop "UnparsedSentence" $ checkJSON @UnparsedSentence
    prop "Gbnf" $ checkJSON @Gbnf
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
    prop "Credentials" $ checkJSON @Credentials
    prop "SashaClaims" $ checkJSON @SashaClaims
    prop "Lexeme" $ checkJSON @Lexeme
    prop "DirectionalStimulusMarker" $ checkJSON @DirectionalStimulusMarker
    prop "DirectionalStimulus" $ checkJSON @DirectionalStimulus
    prop "Determiner" $ checkJSON @Determiner
    prop "Adjective" $ checkJSON @Adjective
    prop "NounPhrase" $ checkJSON @(NounPhrase DirectionalStimulus)
    prop "DirectionalStimulusNounPhrase" $ checkJSON @DirectionalStimulusNounPhrase
    prop "DirectionalStimulusVerb" $ checkJSON @DirectionalStimulusVerb
    prop "ImplicitStimulusVerb" $ checkJSON @ImplicitStimulusVerb
    prop "AcquisitionVerb" $ checkJSON @AcquisitionVerb
    prop "DivestmentVerb" $ checkJSON @DivestmentVerb
    prop "VerbKey" $ checkJSON @VerbKey
    prop "ActionManagement" $ checkJSON @ActionManagement
    prop "ActionManagementFunctions" $ checkJSON @ActionManagementFunctions
    prop "AgentKind" $ checkJSON @AgentKind
    prop "Object" $ checkJSON @Object
    prop "Agent" $ checkJSON @Agent
