module Lobby
  ( worldSource
  , buildResult
  , WorldLoadFailure (WorldReifyFailed, WorldBuildFailed)
  , worldLoadFailureText
  ) where

import           SashaPrelude

import           Control.Monad.Except (ExceptT, throwError)
import           Data.List (unlines)
import           DSL.Builder
  ( WorldBuilderError
  , WorldBuilderResult
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           DSL.Reify (reifyDSL)
import           Language.Haskell.Interpreter (InterpreterError)
import           Model.Core
  ( GameState (GameState, _actionMaps, _agentLocationMap, _evaluation, _narrationMap, _possibilityGraph, _world)
  , NarrationMap (NarrationMap)
  , PossibilityGraph (PossibilityGraph, _entityActionEffects, _newUserMkAgent, _newUserStartScene, _witnessMap, _worldOutcomeEffects)
  , defaultWorld
  , emptyActionMaps
  )
import           Server.App (initialCounters)

type WorldLoadFailure :: Type
data WorldLoadFailure = WorldReifyFailed InterpreterError
                      | WorldBuildFailed WorldBuilderError
  deriving stock (Generic, Show)

worldSource :: String
worldSource = unlines
    [ "let"
    , "  buildLobby :: ActionManagement -> ActionManagement -> SashaLambdaDSL Scene"
    , "  buildLobby sceneLookKey sceneLookAtKey ="
    , "    defaultScene"
    , "      & (title \"the lobby\" `andThen`"
    , "         sceneDescriptionRich (colored White \"A spacious lobby with high ceilings.\") `andThen`"
    , "         flip sceneBehavior sceneLookKey `andThen`"
    , "         flip sceneBehavior sceneLookAtKey)"
    , ""
    , "  buildFloor :: ActionManagement -> SashaLambdaDSL Object"
    , "  buildFloor lookAtKey ="
    , "    defaultObject"
    , "      & (shortName \"floor\" `andThen`"
    , "         description (colored White \"A plain stone floor.\") `andThen`"
    , "         flip objectBehavior lookAtKey)"
    , ""
    , "  buildBall :: ActionManagement -> SashaLambdaDSL Object"
    , "  buildBall lookAtKey ="
    , "    defaultObject"
    , "      & (shortName \"ball\" `andThen`"
    , "         description (colored White \"A small red ball.\") `andThen`"
    , "         flip objectBehavior lookAtKey)"
    , ""
    , "  defaultDenizen :: Text -> Agent"
    , "  defaultDenizen playerName = Agent"
    , "    { _agentShortName         = plain playerName"
    , "    , _agentDescription       = colored White \"A player.\""
    , "    , _agentTitle             = mempty"
    , "    , _agentActionManagement  = ActionManagementFunctions mempty"
    , "    , _agentWitnessManagement = mempty"
    , "    , _agentKind              = Denizen"
    , "    }"
    , "in do"
    , "  lobbyGID      <- declareSceneGID \"lobby\""
    , ""
    , "  sceneLookGID  <- declareImplicitStimulusGID lookF"
    , "  playerLookGID <- declareImplicitStimulusGID lookF"
    , "  sceneLookKey  <- createISAManagement isaLook sceneLookGID"
    , "  playerLookKey <- createISAManagement isaLook playerLookGID"
    , ""
    , "  sceneLookAtGID  <- declareDirectionalStimulusGID lookAtF"
    , "  playerLookAtGID <- declareDirectionalStimulusGID lookAtF"
    , "  floorLookAtGID  <- declareDirectionalStimulusGID lookAtF"
    , "  ballLookAtGID   <- declareDirectionalStimulusGID lookAtF"
    , "  sceneLookAtKey  <- createDSAManagement dsaLook sceneLookAtGID"
    , "  playerLookAtKey <- createDSAManagement dsaLook playerLookAtGID"
    , "  floorLookAtKey  <- createDSAManagement dsaLook floorLookAtGID"
    , "  ballLookAtKey   <- createDSAManagement dsaLook ballLookAtGID"
    , ""
    , "  witnessGID <- declareWitnessGID witnessF"
    , ""
    , "  floorGID <- declareObjectGID"
    , "  ballGID  <- declareObjectGID"
    , ""
    , "  registerObject floorGID (buildFloor floorLookAtKey)"
    , "  registerObject ballGID  (buildBall ballLookAtKey)"
    , ""
    , "  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)"
    , ""
    , "  registerObjectToScene lobbyGID floorGID \"FLOOR\""
    , "  registerObjectToScene lobbyGID ballGID  \"BALL\""
    , ""
    , "  registerSpatial (EntityObject ballGID)  (SupportedBy (EntityObject floorGID))"
    , "  registerSpatial (EntityObject floorGID) (Supports (Data.Set.singleton (EntityObject ballGID)))"
    , ""
    , "  denizen       <- playerBehavior defaultDenizen playerLookKey"
    , "  denizen'      <- playerBehavior denizen playerLookAtKey"
    , "  w1            <- witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID"
    , "  w2            <- witnessBehavior w1 (DirectionalStimulusKey dsaLook) witnessGID"
    , "  newUser lobbyGID w2"
    , ""
    , "  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)"
    , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey ballLookAtGID) (NarrationEffect (LookAtNarration ballGID))"
    , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey floorLookAtGID) (NarrationEffect (LookAtNarration floorGID))"
    , "  finalizeGameState"
    ]

defaultGameState :: GameState
defaultGameState = GameState
  { _world            = defaultWorld
  , _narrationMap     = NarrationMap mempty
  , _evaluation       = mempty
  , _agentLocationMap = mempty
  , _actionMaps      = emptyActionMaps
  , _possibilityGraph = PossibilityGraph
      { _entityActionEffects = mempty
      , _worldOutcomeEffects = mempty
      , _witnessMap          = mempty
      , _newUserStartScene   = Nothing
      , _newUserMkAgent      = Nothing
      }
  }

buildResult :: ExceptT WorldLoadFailure IO WorldBuilderResult
buildResult = do
  reified <- liftIO (reifyDSL worldSource)
  case reified of
    Left err  -> throwError (WorldReifyFailed err)
    Right dsl -> case runWorldBuilder (interpretDSL dsl) (initialBuilderState defaultGameState initialCounters) of
      Left err     -> throwError (WorldBuildFailed err)
      Right result -> pure result

worldLoadFailureText :: WorldLoadFailure -> String
worldLoadFailureText (WorldReifyFailed err) = "Failed to reify world source: " <> show err
worldLoadFailureText (WorldBuildFailed err) = "Failed to build game state: " <> show err
