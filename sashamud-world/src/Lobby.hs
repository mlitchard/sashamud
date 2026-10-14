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

lobbyBuilder :: [String]
lobbyBuilder =
    [ "  buildLobby :: ActionManagement -> ActionManagement -> SashaLambdaDSL Scene"
    , "  buildLobby sceneLookKey sceneLookAtKey ="
    , "    defaultScene"
    , "      & (title \"the lobby\" `andThen`"
    , "         sceneDescriptionRich (colored White \"A spacious lobby with high ceilings.\") `andThen`"
    , "         flip sceneBehavior sceneLookKey `andThen`"
    , "         flip sceneBehavior sceneLookAtKey)"
    ]

floorBuilder :: [String]
floorBuilder =
    [ "  buildFloor :: ActionManagement -> SashaLambdaDSL Object"
    , "  buildFloor lookAtKey ="
    , "    defaultObject"
    , "      & (shortName \"floor\" `andThen`"
    , "         description (colored White \"A plain stone floor.\") `andThen`"
    , "         flip objectBehavior lookAtKey)"
    ]

ballBuilder :: [String]
ballBuilder =
    [ "  buildBall :: ActionManagement -> SashaLambdaDSL Object"
    , "  buildBall lookAtKey ="
    , "    defaultObject"
    , "      & (shortName \"ball\" `andThen`"
    , "         description (colored White \"A small red ball.\") `andThen`"
    , "         flip objectBehavior lookAtKey)"
    ]

denizenBuilder :: [String]
denizenBuilder =
    [ "  defaultDenizen :: Text -> Agent"
    , "  defaultDenizen playerName = Agent"
    , "    { _agentShortName         = plain playerName"
    , "    , _agentDescription       = colored White \"A player.\""
    , "    , _agentTitle             = mempty"
    , "    , _agentActionManagement  = ActionManagementFunctions mempty"
    , "    , _agentWitnessManagement = mempty"
    , "    , _agentKind              = Denizen"
    , "    }"
    ]

lookDeclarations :: [String]
lookDeclarations =
    [ "  declareLook :: SashaLambdaDSL (GID ImplicitStimulusF, ActionManagement)"
    , "  declareLook = do"
    , "    gid <- declareImplicitStimulusGID lookF"
    , "    key <- createISAManagement isaLook gid"
    , "    pure (gid, key)"
    , "  declareLookAt :: SashaLambdaDSL (GID DirectionalStimulusF, ActionManagement)"
    , "  declareLookAt = do"
    , "    gid <- declareDirectionalStimulusGID lookAtF"
    , "    key <- createDSAManagement dsaLook gid"
    , "    pure (gid, key)"
    ]

objectPlacement :: [String]
objectPlacement =
    [ "  placeFloor :: GID Scene -> ActionManagement -> SashaLambdaDSL (GID Object)"
    , "  placeFloor lobbyGID lookAtKey = do"
    , "    floorGID <- declareObjectGID (ObjectLabel \"floor\")"
    , "    registerObject floorGID (buildFloor lookAtKey)"
    , "    registerObjectToScene lobbyGID floorGID \"FLOOR\""
    , "    pure floorGID"
    , "  placeBall :: GID Scene -> GID Object -> ActionManagement -> SashaLambdaDSL (GID Object)"
    , "  placeBall lobbyGID floorGID lookAtKey = do"
    , "    ballGID <- declareObjectGID (ObjectLabel \"ball\")"
    , "    registerObject ballGID (buildBall lookAtKey)"
    , "    registerObjectToScene lobbyGID ballGID \"BALL\""
    , "    registerSpatial (EntityObject ballGID)  (SupportedBy (EntityObject floorGID))"
    , "    registerSpatial (EntityObject floorGID) (Supports (Data.Set.singleton (EntityObject ballGID)))"
    , "    pure ballGID"
    ]

playerTemplate :: [String]
playerTemplate =
    [ "  playerTemplate :: ActionManagement -> ActionManagement -> GID WitnessF -> SashaLambdaDSL (Text -> Agent)"
    , "  playerTemplate lookKey lookAtKey witnessGID = do"
    , "    denizen  <- playerBehavior defaultDenizen lookKey"
    , "    denizen' <- playerBehavior denizen lookAtKey"
    , "    w1       <- witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID"
    , "    witnessBehavior w1 (DirectionalStimulusKey dsaLook) witnessGID"
    ]

worldAssembly :: [String]
worldAssembly =
    [ "in do"
    , "  lobbyGID <- declareSceneGID (SceneLabel \"lobby\")"
    , "  (sceneLookGID, sceneLookKey) <- declareLook"
    , "  (_, playerLookKey)           <- declareLook"
    , "  (_, sceneLookAtKey)          <- declareLookAt"
    , "  (_, playerLookAtKey)         <- declareLookAt"
    , "  (floorLookAtGID, floorLookAtKey) <- declareLookAt"
    , "  (ballLookAtGID, ballLookAtKey)   <- declareLookAt"
    , "  witnessGID <- declareWitnessGID witnessF"
    , "  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)"
    , "  floorGID <- placeFloor lobbyGID floorLookAtKey"
    , "  ballGID  <- placeBall lobbyGID floorGID ballLookAtKey"
    , "  template <- playerTemplate playerLookKey playerLookAtKey witnessGID"
    , "  newUser lobbyGID template"
    , "  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)"
    , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey ballLookAtGID) (NarrationEffect (LookAtNarration ballGID))"
    , "  linkWorldOutcomeEffect (DirectionalStimulusActionKey floorLookAtGID) (NarrationEffect (LookAtNarration floorGID))"
    , "  finalizeGameState"
    ]

worldSource :: String
worldSource = unlines $
     ["let"]
  <> lobbyBuilder
  <> floorBuilder
  <> ballBuilder
  <> denizenBuilder
  <> lookDeclarations
  <> objectPlacement
  <> playerTemplate
  <> worldAssembly

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
