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
  , (&)
  , (.)
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
import           Data.Set (insert, singleton)
import           Data.Text (lines)
import           Engine.Simulation.SignalNetwork
  ( formatState
  , prettyShowSentence
  , resolveCommands
  )
import           Grammar.Gbnf (UnparsedSentence (UnparsedSentence))
import           Grammar.Lexer (lexify, tokens)
import           Grammar.Sentence (parseTokens)
import           Lens.Micro.Platform (set)
import           Model.Core
  ( ActionManagementFunctions (ActionManagementFunctions)
  , Agent (Agent, _agentActionManagement, _agentDescription, _agentKind, _agentShortName, _agentTitle, _agentWitnessManagement)
  , AgentKind (Denizen)
  , SessionId (SessionId)
  , agentLocationMap
  , agentMap
  , defaultGameState
  , defaultObject
  , defaultScene
  , getAgentMap
  , getGIDToDataMap
  , objectMap
  , sceneAgents
  , sceneMap
  , sceneObjects
  , world
  )
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
import           Test.Hspec
  ( Spec
  , describe
  , expectationFailure
  , it
  , shouldContain
  )

spec :: Spec
spec = do
  describe "resolveCommands" $ do
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
  describe "formatState" $ do
    let playerGid = GID 1
        otherGid = GID 2
        objectGid = GID 3
        sceneGid = GID 0
        mkAgent name = Agent
          { _agentShortName         = plain name
          , _agentDescription       = mempty
          , _agentTitle             = mempty
          , _agentActionManagement  = ActionManagementFunctions mempty
          , _agentWitnessManagement = mempty
          , _agentKind              = Denizen
          }
        scene = defaultScene
          & set sceneAgents (insert otherGid (singleton playerGid))
        gs = defaultGameState
          & set (world . agentMap . getAgentMap) (fromList [(playerGid, mkAgent "tester"), (otherGid, mkAgent "other")])
          & set (world . sceneMap . getGIDToDataMap) (fromList [(sceneGid, scene)])
          & set agentLocationMap (fromList [(playerGid, sceneGid)])
    it "shows each agent and the object in the player's scene" $ do
        let stateLines = formatState playerGid
              (gs
                & set (world . objectMap . getGIDToDataMap) (fromList [(objectGid, defaultObject)])
                & set (world . sceneMap . getGIDToDataMap) (fromList [(sceneGid, set sceneObjects (singleton objectGid) scene)]))
        stateLines `shouldContain` [plain "=== Agents ===", plain "  GID 1"]
        stateLines `shouldContain` [plain "  GID 2"]
        stateLines `shouldContain` [plain "=== Objects ===", plain "  GID 3"]
    it "shows (none) under Objects for a scene with no objects" $
        formatState playerGid gs `shouldContain` [plain "=== Objects ===", plain "  (none)"]
