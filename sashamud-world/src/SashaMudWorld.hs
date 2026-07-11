module SashaMudWorld
  ( sashaMudWorld
  , defaultDenizen
  , gameState
  , possibilityGraph
  ) where

import           SashaPrelude

import           DSL.Builder
  ( WorldBuilderResult (resultGameState, resultPossibilityGraph)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL
  , declareSceneGID
  , finalizeGameState
  , registerScene
  , sceneDescriptionRich
  , title
  )
import           DSL.Vocabulary (andThen)
import           Model.Core
  ( ActionManagementFunctions (ActionManagementFunctions)
  , Agent (Agent, _agentActionManagement, _agentDescription, _agentKind, _agentShortName, _agentTitle)
  , AgentKind (Denizen)
  , GameState (GameState, _agentLocationMap, _evaluation, _narrationMap, _world)
  , NarrationMap (NarrationMap)
  , PossibilityGraph
  , Scene
  , defaultScene
  , defaultWorld
  )
import           Model.RichText (TextColor (White), colored, plain)

buildLobby :: SashaLambdaDSL Scene
buildLobby =
  defaultScene
    & (title "the lobby" `andThen`
       sceneDescriptionRich (colored White "A spacious lobby with high ceilings."))

sashaMudWorld :: SashaLambdaDSL GameState
sashaMudWorld = do
  lobbyGID <- declareSceneGID "lobby"
  registerScene lobbyGID buildLobby
  finalizeGameState

defaultDenizen :: Text -> Agent
defaultDenizen playerName = Agent
  { _agentShortName        = plain playerName
  , _agentDescription      = colored White "A player."
  , _agentTitle            = mempty
  , _agentActionManagement = ActionManagementFunctions mempty
  , _agentKind             = Denizen
  }

defaultGameState :: GameState
defaultGameState = GameState
  { _world            = defaultWorld
  , _narrationMap     = NarrationMap mempty
  , _evaluation       = mempty
  , _agentLocationMap = mempty
  }

buildResult :: WorldBuilderResult
buildResult = runWorldBuilder (interpretDSL sashaMudWorld) (initialBuilderState defaultGameState)

gameState :: GameState
gameState = resultGameState buildResult

possibilityGraph :: PossibilityGraph
possibilityGraph = resultPossibilityGraph buildResult
