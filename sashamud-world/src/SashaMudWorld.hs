module SashaMudWorld
  ( sashaMudWorld
  , defaultPlayerAgent
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
  ( Agent (Agent, _agentActionManagement, _agentCurrentScene, _agentDescription, _agentKind, _agentShortName, _agentTitle)
  , AgentKind (PlayerAgent)
  , GameState
  , PossibilityGraph
  , Scene
  , defaultActionManagement
  , defaultGameState
  , defaultScene
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)

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

defaultPlayerAgent :: Text -> GID Scene -> Agent
defaultPlayerAgent playerName sceneGid = Agent
  { _agentShortName        = playerName
  , _agentDescription      = colored White "A player."
  , _agentTitle            = ""
  , _agentActionManagement = defaultActionManagement
  , _agentCurrentScene     = sceneGid
  , _agentKind             = PlayerAgent
  }

buildResult :: WorldBuilderResult
buildResult = runWorldBuilder (interpretDSL sashaMudWorld) (initialBuilderState defaultGameState)

gameState :: GameState
gameState = resultGameState buildResult

possibilityGraph :: PossibilityGraph
possibilityGraph = resultPossibilityGraph buildResult
