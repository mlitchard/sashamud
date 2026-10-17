module SignalNetworkSpec (spec) where

import           SashaPrelude
  ( Either (Left, Right)
  , Eq ((==))
  , Maybe (Just)
  , Monoid (mconcat, mempty)
  , const
  , fmap
  , pure
  , unpack
  , ($)
  , (<>)
  , (>>=)
  )

import           API.Types
  ( MessageTo (GameCommand, RepairedCommand)
  , ParseFailure (ParseFailure)
  , Routed (Routed)
  , SlmName (SlmName)
  )
import           Data.Map.Strict (fromList, lookup)
import           Data.Text (lines)
import           Engine.Simulation.SignalNetwork (prettyShowSentence, resolveCommands)
import           Grammar.Gbnf (UnparsedSentence (UnparsedSentence))
import           Grammar.Lexer (lexify, tokens)
import           Grammar.Sentence (parseTokens)
import           Model.Core (SessionId (SessionId))
import           Model.GID (GID (GID))
import           Model.RichText (plain)
import           Model.WireProtocol
  ( AnalysisViewport (Parser)
  , MessageFrom (AnalysisData)
  )
import           Server.App
  ( PendingRepair (PendingRepair)
  , SessionPhase (SessionPhase)
  , SessionState (InGame)
  )
import           Server.Validator (PlayerNameVAL (PlayerNameVAL))
import           Test.Hspec (Spec, describe, expectationFailure, it, shouldContain)

spec :: Spec
spec = describe "resolveCommands" $ do
    let sid = SessionId "session-1"
        sessions = fromList [(sid, SessionPhase (PlayerNameVAL "tester") (GID 0) (InGame (const (pure ()))))]
    it "shows the sentence for a GameCommand that parses" $
        case lexify tokens "look" >>= parseTokens of
            Left err -> expectationFailure (unpack err)
            Right sentence -> do
                let (_, replies, _, _, _, _) = resolveCommands sessions mempty [] [Routed sid (GameCommand "look")]
                    parserLines = mconcat [viewLines | Routed target (AnalysisData viewports) <- replies, target == sid, Just viewLines <- [lookup Parser viewports]]
                parserLines `shouldContain` ([plain "=== Sentence ==="] <> fmap plain (lines (prettyShowSentence sentence)))
    it "shows the parse error and the repair request for a GameCommand that fails to parse" $
        case lexify tokens "look look" >>= parseTokens of
            Right _ -> expectationFailure "expected a parse failure"
            Left err -> do
                let (_, replies, _, _, _, _) = resolveCommands sessions mempty [] [Routed sid (GameCommand "look look")]
                    parserLines = mconcat [viewLines | Routed target (AnalysisData viewports) <- replies, target == sid, Just viewLines <- [lookup Parser viewports]]
                parserLines `shouldContain` ([plain "=== Sentence ==="] <> fmap plain (lines err))
                parserLines `shouldContain` [plain "=== Repair ===", plain "  repair requested"]
    it "shows the parsed outcome for a RepairedCommand whose rewrite parses" $
        case lexify tokens "look" >>= parseTokens of
            Left err -> expectationFailure (unpack err)
            Right sentence -> do
                let unparsed = UnparsedSentence "luk"
                    pending = fromList [(sid, PendingRepair unparsed (ParseFailure "Nonsense in parsed tokens PLAYERNAME \"LUK\"") [])]
                    (_, replies, _, _, _, _) = resolveCommands sessions pending [] [Routed sid (RepairedCommand unparsed "look" (SlmName "qwen-Qwen3-1.7B-Q8_0"))]
                    parserLines = mconcat [viewLines | Routed target (AnalysisData viewports) <- replies, target == sid, Just viewLines <- [lookup Parser viewports]]
                parserLines `shouldContain` ([plain "=== Outcome ===", plain "  parsed, the sentence runs"] <> fmap plain (lines (prettyShowSentence sentence)))
