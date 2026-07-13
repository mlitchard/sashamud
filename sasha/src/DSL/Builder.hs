module DSL.Builder
  ( interpretDSL
  , runWorldBuilder
  , initialBuilderState
  , WorldBuilder
  , WorldBuilderResult (WorldBuilderResult, resultGameState, resultPossibilityGraph)
  ) where

import           SashaPrelude

import           Control.Monad.State (State, get, gets, put, runState)
import           Data.Map.Strict (insert)
import qualified Data.Set (insert)
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL (..))
import           Lens.Micro.Platform (at, non, (%~))
import           Model.Core
  ( ActionManagement (ISAManagementKey)
  , Agent
  , EntityActionRegistry
  , GameState
  , PossibilityGraph (PossibilityGraph, _entityActionEffects, _newUserMkAgent, _newUserStartScene, _witnessMap, _worldOutcomeEffects)
  , Scene (_sceneDescription, _title)
  , WitnessMap
  , WorldOutcomeRegistry
  , actionManagementFunctions
  , actionMaps
  , agentActionManagement
  , agentWitnessManagement
  , getGIDToDataMap
  , implicitStimulusMap
  , sceneActionManagement
  , sceneMap
  , world
  )
import           Model.GID (GID (GID))

data BuilderState = BuilderState
  { bsGameState               :: GameState
  , bsNextSceneGID            :: Int
  , bsNextImplicitStimulusGID :: Int
  , bsNextWitnessGID          :: Int
  , bsWitnessMap              :: WitnessMap
  , bsEntityActionRegistry    :: EntityActionRegistry
  , bsWorldOutcomeRegistry    :: WorldOutcomeRegistry
  , bsNewUserStartScene       :: Maybe (GID Scene)
  , bsNewUserMkAgent          :: Maybe (Text -> Agent)
  }

type WorldBuilder = State BuilderState

type WorldBuilderResult :: Type
data WorldBuilderResult = WorldBuilderResult
  { resultGameState        :: GameState
  , resultPossibilityGraph :: PossibilityGraph
  }

initialBuilderState :: GameState -> BuilderState
initialBuilderState gs = BuilderState
  { bsGameState               = gs
  , bsNextSceneGID            = 0
  , bsNextImplicitStimulusGID = 0
  , bsNextWitnessGID          = 0
  , bsWitnessMap              = mempty
  , bsEntityActionRegistry    = mempty
  , bsWorldOutcomeRegistry    = mempty
  , bsNewUserStartScene       = Nothing
  , bsNewUserMkAgent         = Nothing
  }

interpretDSL :: SashaLambdaDSL a -> WorldBuilder a
interpretDSL (Pure a) = pure a
interpretDSL (Bind m f) = interpretDSL m >>= (interpretDSL . f)

interpretDSL (DeclareSceneGID _name) = do
  st <- get
  let gid = GID (bsNextSceneGID st)
  put st { bsNextSceneGID = bsNextSceneGID st + 1 }
  pure gid

interpretDSL (RegisterScene gid sceneBuilder) = do
  scene <- interpretDSL sceneBuilder
  st <- get
  let gs' = bsGameState st & world . sceneMap . getGIDToDataMap %~ insert gid scene
  put st { bsGameState = gs' }

interpretDSL (Title t scene) = pure scene { _title = t }

interpretDSL (SceneDescription rt scene) = pure scene { _sceneDescription = rt }

interpretDSL (DeclareImplicitStimulusGID actionF) = do
  st <- get
  let gid = GID (bsNextImplicitStimulusGID st)
      gs' = bsGameState st & actionMaps . implicitStimulusMap %~ insert gid actionF
  put st { bsNextImplicitStimulusGID = bsNextImplicitStimulusGID st + 1
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateISAManagement verb gid) = pure (ISAManagementKey verb gid)

interpretDSL (DeclareWitnessGID witnessFn) = do
  st <- get
  let gid = GID (bsNextWitnessGID st)
  put st { bsNextWitnessGID = bsNextWitnessGID st + 1
         , bsWitnessMap = insert gid witnessFn (bsWitnessMap st)
         }
  pure gid

interpretDSL (SceneBehavior scene actionMgmt) =
  pure (scene & sceneActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (PlayerBehavior mkAgent actionMgmt) =
  pure (\name -> mkAgent name & agentActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (WitnessBehavior mkAgent verbKey witnessGid) =
  pure (\name -> mkAgent name & agentWitnessManagement %~ insert verbKey witnessGid)

interpretDSL (LinkWorldOutcomeEffect actionKey worldOutcome) = do
  st <- get
  put st { bsWorldOutcomeRegistry =
             bsWorldOutcomeRegistry st & at actionKey . non mempty %~ Data.Set.insert worldOutcome }

interpretDSL (NewUser sceneGid mkAgent) = do
  st <- get
  put st { bsNewUserStartScene = Just sceneGid
         , bsNewUserMkAgent    = Just mkAgent
         }

interpretDSL FinalizeGameState =
  gets bsGameState

runWorldBuilder :: WorldBuilder GameState -> BuilderState -> WorldBuilderResult
runWorldBuilder builder initState =
  let (gs, finalState) = runState builder initState
      possibilityGraph = PossibilityGraph
        { _entityActionEffects = bsEntityActionRegistry finalState
        , _worldOutcomeEffects = bsWorldOutcomeRegistry finalState
        , _witnessMap          = bsWitnessMap finalState
        , _newUserStartScene   = fromMaybe
            (error "runWorldBuilder: world declared no newUser start scene")
            (bsNewUserStartScene finalState)
        , _newUserMkAgent      = fromMaybe
            (error "runWorldBuilder: world declared no newUser agent template")
            (bsNewUserMkAgent finalState)
        }
  in WorldBuilderResult
       { resultGameState        = gs
       , resultPossibilityGraph = possibilityGraph
       }
