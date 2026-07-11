module DSL.Builder
  ( interpretDSL
  , runWorldBuilder
  , initialBuilderState
  , WorldBuilder
  , WorldBuilderResult (WorldBuilderResult, resultGameState, resultPossibilityGraph)
  ) where

import           SashaPrelude

import           Control.Monad.State (State, get, gets, put, runState)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (insert, lookup)
import qualified Data.Set (insert)
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL (..))
import           Error (throwMaybeM)
import           Lens.Micro.Platform (at, non, over, view, (%~), (?~))
import           Model.Core
  ( ActionManagement (ISAManagementKey, WitnessManagementKey)
  , ActionMaps
  , Agent
  , EntityActionRegistry
  , GameComputation
  , GameState
  , PossibilityGraph (PossibilityGraph, _actionMaps, _entityActionEffects, _newUserF, _worldOutcomeEffects)
  , Scene (_sceneDescription, _title)
  , WorldOutcomeRegistry
  , actionManagementFunctions
  , agentActionManagement
  , agentLocationMap
  , agentMap
  , emptyActionMaps
  , getAgentMap
  , getGIDToDataMap
  , implicitStimulusMap
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , witnessMap
  , world
  )
import           Model.GID (GID (GID))

data BuilderState = BuilderState
  { bsGameState :: GameState
  , bsNextSceneGID :: Int
  , bsNextImplicitStimulusGID :: Int
  , bsNextWitnessGID :: Int
  , bsActionMaps :: ActionMaps
  , bsEntityActionRegistry :: EntityActionRegistry
  , bsWorldOutcomeRegistry :: WorldOutcomeRegistry
  , bsNewUser :: Maybe (GID Agent -> Text -> GameComputation Identity ())
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
  , bsActionMaps              = emptyActionMaps
  , bsEntityActionRegistry    = mempty
  , bsWorldOutcomeRegistry    = mempty
  , bsNewUser                 = Nothing
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
  put st { bsNextImplicitStimulusGID = bsNextImplicitStimulusGID st + 1
         , bsActionMaps = over implicitStimulusMap (insert gid actionF) (bsActionMaps st)
         }
  pure gid

interpretDSL (CreateISAManagement verb gid) = pure (ISAManagementKey verb gid)

interpretDSL (DeclareWitnessGID witnessFn) = do
  st <- get
  let gid = GID (bsNextWitnessGID st)
  put st { bsNextWitnessGID = bsNextWitnessGID st + 1
         , bsActionMaps = over witnessMap (insert gid witnessFn) (bsActionMaps st)
         }
  pure gid

interpretDSL (CreateWitnessManagement gid) = pure (WitnessManagementKey gid)

interpretDSL (SceneBehavior scene actionMgmt) =
  pure (scene & sceneActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (PlayerBehavior mkAgent actionMgmt) =
  pure (\name -> mkAgent name & agentActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (LinkWorldOutcomeEffect actionKey worldOutcome) = do
  st <- get
  put st { bsWorldOutcomeRegistry =
             bsWorldOutcomeRegistry st & at actionKey . non mempty %~ Data.Set.insert worldOutcome }

interpretDSL (NewUser sceneGid mkAgent) = do
  st <- get
  let newUserComputation gid name = do
        gs <- get
        scene <- throwMaybeM ("newUser: start scene not found: " <> pack (show sceneGid))
                   (lookup sceneGid (view (world . sceneMap . getGIDToDataMap) gs))
        let scene' = over sceneAgents (Data.Set.insert gid) scene
        put ( gs
            & world . agentMap . getAgentMap . at gid ?~ mkAgent name
            & world . sceneMap . getGIDToDataMap . at sceneGid ?~ scene'
            & agentLocationMap . at gid ?~ sceneGid )
  put st { bsNewUser = Just newUserComputation }

interpretDSL FinalizeGameState =
  gets bsGameState

runWorldBuilder :: WorldBuilder GameState -> BuilderState -> WorldBuilderResult
runWorldBuilder builder initState =
  let (gs, finalState) = runState builder initState
      possibilityGraph = PossibilityGraph
        { _actionMaps          = bsActionMaps finalState
        , _entityActionEffects = bsEntityActionRegistry finalState
        , _worldOutcomeEffects = bsWorldOutcomeRegistry finalState
        , _newUserF            = fromMaybe
            (error "runWorldBuilder: world declared no newUser generator")
            (bsNewUser finalState)
        }
  in WorldBuilderResult
       { resultGameState        = gs
       , resultPossibilityGraph = possibilityGraph
       }
