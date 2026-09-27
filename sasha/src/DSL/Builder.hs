module DSL.Builder
  ( interpretDSL
  , runWorldBuilder
  , initialBuilderState
  , WorldBuilder
  , WorldBuilderResult (WorldBuilderResult, resultGameState)
  ) where

import           SashaPrelude

import           Control.Monad.State (State, get, gets, put, runState)
import           Data.Map.Strict (insert)
import qualified Data.Set (insert)
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL (..))
import           Lens.Micro.Platform (at, non, (%~), (.~))
import           Model.Core
  ( ActionManagement (DSAManagementKey, ISAManagementKey)
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
  , description
  , directionalStimulusMap
  , getGIDToDataMap
  , globalSemanticMap
  , implicitStimulusMap
  , objectActionManagement
  , objectMap
  , possibilityGraph
  , sceneActionManagement
  , sceneMap
  , shortName
  , spatialRelationshipMap
  , unSpatialRelationshipMap
  , world
  )
import           Model.GID (GID (GID))

data BuilderState = BuilderState
  { bsGameState                  :: GameState
  , bsNextSceneGID               :: Int
  , bsNextObjectGID              :: Int
  , bsNextImplicitStimulusGID    :: Int
  , bsNextDirectionalStimulusGID :: Int
  , bsNextWitnessGID             :: Int
  , bsWitnessMap                 :: WitnessMap
  , bsEntityActionRegistry       :: EntityActionRegistry
  , bsWorldOutcomeRegistry       :: WorldOutcomeRegistry
  , bsNewUserStartScene          :: Maybe (GID Scene)
  , bsNewUserMkAgent             :: Maybe (Text -> Agent)
  }

type WorldBuilder = State BuilderState

type WorldBuilderResult :: Type
data WorldBuilderResult = WorldBuilderResult
  { resultGameState :: GameState
  }

initialBuilderState :: GameState -> BuilderState
initialBuilderState gs = BuilderState
  { bsGameState                    = gs
  , bsNextSceneGID                 = 0
  , bsNextObjectGID                = 0
  , bsNextImplicitStimulusGID      = 0
  , bsNextDirectionalStimulusGID   = 0
  , bsNextWitnessGID               = 0
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

interpretDSL DeclareObjectGID = do
  st <- get
  let gid = GID (bsNextObjectGID st)
  put st { bsNextObjectGID = bsNextObjectGID st + 1 }
  pure gid

interpretDSL (RegisterObject gid objBuilder) = do
  obj <- interpretDSL objBuilder
  st <- get
  let gs' = bsGameState st & world . objectMap . getGIDToDataMap %~ insert gid obj
  put st { bsGameState = gs' }

interpretDSL (ShortName text obj) = pure (obj & shortName .~ text)

interpretDSL (Description rt obj) = pure (obj & description .~ rt)

interpretDSL (ObjectBehavior obj actionMgmt) =
  pure (obj & objectActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (RegisterObjectToScene _sceneGID objGID nounText) = do
  st <- get
  let gs' = bsGameState st & world . globalSemanticMap . at nounText . non mempty %~ Data.Set.insert objGID
  put st { bsGameState = gs' }

interpretDSL (RegisterSpatial entityID spatialRel) = do
  st <- get
  let gs' = bsGameState st & world . spatialRelationshipMap . unSpatialRelationshipMap . at entityID . non mempty %~ Data.Set.insert spatialRel
  put st { bsGameState = gs' }

interpretDSL (DeclareImplicitStimulusGID actionF) = do
  st <- get
  let gid = GID (bsNextImplicitStimulusGID st)
      gs' = bsGameState st & actionMaps . implicitStimulusMap %~ insert gid actionF
  put st { bsNextImplicitStimulusGID = bsNextImplicitStimulusGID st + 1
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateISAManagement verb gid) = pure (ISAManagementKey verb gid)

interpretDSL (DeclareDirectionalStimulusGID actionF) = do
  st <- get
  let gid = GID (bsNextDirectionalStimulusGID st)
      gs' = bsGameState st & actionMaps . directionalStimulusMap %~ insert gid actionF
  put st { bsNextDirectionalStimulusGID = bsNextDirectionalStimulusGID st + 1
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateDSAManagement verb gid) = pure (DSAManagementKey verb gid)

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
      pg = PossibilityGraph
        { _entityActionEffects = bsEntityActionRegistry finalState
        , _worldOutcomeEffects = bsWorldOutcomeRegistry finalState
        , _witnessMap          = bsWitnessMap finalState
        , _newUserStartScene   = bsNewUserStartScene finalState
        , _newUserMkAgent      = bsNewUserMkAgent finalState
        }
  in WorldBuilderResult
       { resultGameState = gs & possibilityGraph .~ pg
       }
