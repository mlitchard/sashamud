module SashaMudWorld
  ( buildResult
  , sashaMudWorld
  , defaultDenizen
  , gameState
  ) where

import           SashaPrelude

import           ConstraintRefinement.Actions (lookAtF, lookF, witnessF)
import qualified Data.Set (singleton)
import           DSL.Builder
  ( WorldBuilderResult (resultGameState)
  , initialBuilderState
  , interpretDSL
  , runWorldBuilder
  )
import           DSL.Model.EDSL.SashaLambdaDSL
  ( SashaLambdaDSL
  , createDSAManagement
  , createISAManagement
  , declareDirectionalStimulusGID
  , declareImplicitStimulusGID
  , declareObjectGID
  , declareSceneGID
  , declareWitnessGID
  , description
  , finalizeGameState
  , linkWorldOutcomeEffect
  , newUser
  , objectBehavior
  , playerBehavior
  , registerObject
  , registerObjectToScene
  , registerScene
  , registerSpatial
  , sceneBehavior
  , sceneDescriptionRich
  , shortName
  , title
  , witnessBehavior
  )
import           DSL.Vocabulary (andThen)
import           Grammar.Parser.Atomics.Semantics.Verbs.DirectionalStimulus
  ( dsaLook
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( isaLook
  )
import           Grammar.Parser.GCase
  ( VerbKey (DirectionalStimulusKey, ImplicitStimulusKey)
  )
import           Model.Core
  ( ActionEffectKey (DirectionalStimulusActionKey, ImplicitStimulusActionKey)
  , ActionManagement
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent (Agent, _agentActionManagement, _agentDescription, _agentKind, _agentShortName, _agentTitle, _agentWitnessManagement)
  , AgentKind (Denizen)
  , EntityID (EntityObject)
  , GameState (GameState, _actionMaps, _agentLocationMap, _evaluation, _narrationMap, _possibilityGraph, _world)
  , NarrationComputation (LookAtNarration, LookNarration)
  , NarrationMap (NarrationMap)
  , Object
  , PossibilityGraph (PossibilityGraph, _entityActionEffects, _newUserMkAgent, _newUserStartScene, _witnessMap, _worldOutcomeEffects)
  , Scene
  , SpatialRelationship (SupportedBy, Supports)
  , WorldOutcome (NarrationEffect)
  , defaultObject
  , defaultScene
  , defaultWorld
  , emptyActionMaps
  )
import           Model.RichText (TextColor (White), colored, plain)
import           Server.App (initialCounters)

buildLobby :: ActionManagement -> ActionManagement -> SashaLambdaDSL Scene
buildLobby sceneLookKey sceneLookAtKey =
  defaultScene
    & (title "the lobby" `andThen`
       sceneDescriptionRich (colored White "A spacious lobby with high ceilings.") `andThen`
       flip sceneBehavior sceneLookKey `andThen`
       flip sceneBehavior sceneLookAtKey)

buildFloor :: ActionManagement -> SashaLambdaDSL Object
buildFloor lookAtKey =
  defaultObject
    & (shortName "floor" `andThen`
       description (colored White "A plain stone floor.") `andThen`
       flip objectBehavior lookAtKey)

buildBall :: ActionManagement -> SashaLambdaDSL Object
buildBall lookAtKey =
  defaultObject
    & (shortName "ball" `andThen`
       description (colored White "A small red ball.") `andThen`
       flip objectBehavior lookAtKey)

sashaMudWorld :: SashaLambdaDSL GameState
sashaMudWorld = do
  lobbyGID      <- declareSceneGID "lobby"

  -- Implicit look
  sceneLookGID  <- declareImplicitStimulusGID lookF
  playerLookGID <- declareImplicitStimulusGID lookF
  sceneLookKey  <- createISAManagement isaLook sceneLookGID
  playerLookKey <- createISAManagement isaLook playerLookGID

  -- Directional look
  sceneLookAtGID  <- declareDirectionalStimulusGID lookAtF
  playerLookAtGID <- declareDirectionalStimulusGID lookAtF
  floorLookAtGID  <- declareDirectionalStimulusGID lookAtF
  ballLookAtGID   <- declareDirectionalStimulusGID lookAtF
  sceneLookAtKey  <- createDSAManagement dsaLook sceneLookAtGID
  playerLookAtKey <- createDSAManagement dsaLook playerLookAtGID
  floorLookAtKey  <- createDSAManagement dsaLook floorLookAtGID
  ballLookAtKey   <- createDSAManagement dsaLook ballLookAtGID

  -- Witness
  witnessGID <- declareWitnessGID witnessF

  -- Objects
  floorGID <- declareObjectGID
  ballGID  <- declareObjectGID

  registerObject floorGID (buildFloor floorLookAtKey)
  registerObject ballGID  (buildBall ballLookAtKey)

  registerObjectToScene lobbyGID floorGID "FLOOR"
  registerObjectToScene lobbyGID ballGID  "BALL"

  -- Spatial: ball is on the floor
  registerSpatial (EntityObject ballGID)  (SupportedBy (EntityObject floorGID))
  registerSpatial (EntityObject floorGID) (Supports (Data.Set.singleton (EntityObject ballGID)))

  -- Scene
  registerScene lobbyGID (buildLobby sceneLookKey sceneLookAtKey)

  -- Player template
  denizen       <- playerBehavior defaultDenizen playerLookKey
  denizen'      <- playerBehavior denizen playerLookAtKey
  w1            <- witnessBehavior denizen' (ImplicitStimulusKey isaLook) witnessGID
  w2            <- witnessBehavior w1 (DirectionalStimulusKey dsaLook) witnessGID
  newUser lobbyGID w2

  -- World outcome effects
  linkWorldOutcomeEffect (ImplicitStimulusActionKey sceneLookGID) (NarrationEffect LookNarration)
  linkWorldOutcomeEffect (DirectionalStimulusActionKey ballLookAtGID) (NarrationEffect (LookAtNarration ballGID))
  linkWorldOutcomeEffect (DirectionalStimulusActionKey floorLookAtGID) (NarrationEffect (LookAtNarration floorGID))
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
  , _possibilityGraph = PossibilityGraph
      { _entityActionEffects = mempty
      , _worldOutcomeEffects = mempty
      , _witnessMap          = mempty
      , _newUserStartScene   = Nothing
      , _newUserMkAgent      = Nothing
      }
  }

buildResult :: WorldBuilderResult
buildResult = runWorldBuilder (interpretDSL sashaMudWorld) (initialBuilderState defaultGameState initialCounters)

gameState :: GameState
gameState = resultGameState buildResult
