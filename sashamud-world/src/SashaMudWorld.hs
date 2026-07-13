module SashaMudWorld
  ( sashaMudWorld
  , defaultDenizen
  , gameState
  , possibilityGraph
  ) where

import           SashaPrelude

import           ConstraintRefinement.Actions (lookF, witnessF)
import           DSL.Builder
  ( WorldBuilderResult (resultGameState, resultPossibilityGraph)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL
  , createISAManagement
  , declareImplicitStimulusGID
  , declareSceneGID
  , declareWitnessGID
  , finalizeGameState
  , linkWorldOutcomeEffect
  , newUser
  , playerBehavior
  , registerScene
  , sceneBehavior
  , sceneDescriptionRich
  , title
  , witnessBehavior
  )
import           DSL.Vocabulary (andThen)
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( isaLook
  )
import           Grammar.Parser.GCase (VerbKey (ImplicitStimulusKey))
import           Model.Core
  ( ActionEffectKey (ImplicitStimulusActionKey)
  , ActionManagement
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent (Agent, _agentActionManagement, _agentDescription, _agentKind, _agentShortName, _agentTitle, _agentWitnessManagement)
  , AgentKind (Denizen)
  , GameState (GameState, _actionMaps, _agentLocationMap, _evaluation, _narrationMap, _world)
  , NarrationComputation (LookNarration)
  , NarrationMap (NarrationMap)
  , PossibilityGraph
  , Scene
  , WorldOutcome (NarrationEffect)
  , defaultScene
  , defaultWorld
  , emptyActionMaps
  )
import           Model.RichText (TextColor (White), colored, plain)

buildLobby :: ActionManagement -> SashaLambdaDSL Scene
buildLobby sceneLookKey =
  defaultScene
    & (title "the lobby" `andThen`
       sceneDescriptionRich (colored White "A spacious lobby with high ceilings.") `andThen`
       flip sceneBehavior sceneLookKey)

sashaMudWorld :: SashaLambdaDSL GameState
sashaMudWorld = do
  lobbyGID      <- declareSceneGID "lobby"
  sceneLookGID  <- declareImplicitStimulusGID lookF
  playerLookGID <- declareImplicitStimulusGID lookF
  sceneLookKey  <- createISAManagement isaLook sceneLookGID
  playerLookKey <- createISAManagement isaLook playerLookGID
  witnessGID    <- declareWitnessGID witnessF
  registerScene lobbyGID (buildLobby sceneLookKey)
  denizen       <- playerBehavior defaultDenizen playerLookKey
  lookWitness   <- witnessBehavior denizen (ImplicitStimulusKey isaLook) witnessGID
  newUser lobbyGID lookWitness
  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)
  finalizeGameState

defaultDenizen :: Text -> Agent
defaultDenizen playerName = Agent
  { _agentShortName         = plain playerName
  , _agentDescription       = colored White "A player."
  , _agentTitle             = mempty
  , _agentActionManagement  = ActionManagementFunctions mempty
  , _agentWitnessManagement = mempty
  , _agentKind              = Denizen
  }

defaultGameState :: GameState
defaultGameState = GameState
  { _world            = defaultWorld
  , _narrationMap     = NarrationMap mempty
  , _evaluation       = mempty
  , _agentLocationMap = mempty
  , _actionMaps      = emptyActionMaps
  }

buildResult :: WorldBuilderResult
buildResult = runWorldBuilder (interpretDSL sashaMudWorld) (initialBuilderState defaultGameState)

gameState :: GameState
gameState = resultGameState buildResult

possibilityGraph :: PossibilityGraph
possibilityGraph = resultPossibilityGraph buildResult
