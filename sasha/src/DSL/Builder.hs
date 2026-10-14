module DSL.Builder
  ( interpretDSL
  , runWorldBuilder
  , initialBuilderState
  , WorldBuilder
  , WorldBuilderError (InvalidSceneGID, DuplicateSceneGID, DuplicateObjectGID, UndeclaredSceneLabel, UndeclaredObjectLabel, InvalidObjectGID, MissingNewUserAgent)
  , WorldBuilderResult (WorldBuilderResult, resultCounters, resultGameState)
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Control.Monad.Except
  ( ExceptT
  , MonadError
  , runExceptT
  , throwError
  )
import           Control.Monad.State
  ( MonadState
  , State
  , get
  , gets
  , put
  , runState
  )
import           Data.Map.Strict (insert, lookup, member)
import qualified Data.Set (insert)
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL (..))
import           Lens.Micro.Platform (at, non, view, (%~), (.~))
import           Model.Core
  ( ActionManagement (AVSupportManagementKey, AVTargetManagementKey, DSAManagementKey, DVManagementKey, DVSurfaceManagementKey, ISAManagementKey)
  , Agent
  , EntityActionRegistry
  , GameState
  , Object
  , ObjectLabel
  , PossibilityGraph (PossibilityGraph, _entityActionEffects, _newUserMkAgent, _newUserStartScene, _witnessMap, _worldOutcomeEffects)
  , Scene (_sceneDescription, _title)
  , SceneLabel
  , WitnessMap
  , WorldOutcomeRegistry
  , acquisitionActionMap
  , actionManagementFunctions
  , actionMaps
  , agentActionManagement
  , agentWitnessManagement
  , declaredObjectGIDs
  , declaredSceneGIDs
  , description
  , directionalStimulusMap
  , divestmentActionMap
  , entityActionEffects
  , getGIDToDataMap
  , globalSemanticMap
  , implicitStimulusMap
  , newUserMkAgent
  , newUserStartScene
  , objectActionManagement
  , objectMap
  , objectSemanticMap
  , possibilityGraph
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , sceneObjects
  , shortName
  , spatialRelationshipMap
  , unSpatialRelationshipMap
  , witnessMap
  , world
  , worldOutcomeEffects
  )
import           Model.GID (GID (GID))
import           Server.App
  ( BuilderCounters
  , nextAcquisitionId
  , nextDirectionalStimulusId
  , nextDivestmentId
  , nextImplicitStimulusId
  , nextObjectId
  , nextSceneId
  , nextWitnessId
  , succPInt
  , unPInt
  )

data BuilderState = BuilderState
  { bsGameState            :: GameState
  , bsCounters             :: BuilderCounters
  , bsWitnessMap           :: WitnessMap
  , bsEntityActionRegistry :: EntityActionRegistry
  , bsWorldOutcomeRegistry :: WorldOutcomeRegistry
  , bsNewUserStartScene    :: Maybe (GID Scene)
  , bsNewUserMkAgent       :: Maybe (Text -> Agent)
  }

type WorldBuilderError :: Type
data WorldBuilderError = InvalidSceneGID (GID Scene) String
                       | DuplicateSceneGID (GID Scene) String
                       | DuplicateObjectGID (GID Object) String
                       | UndeclaredSceneLabel SceneLabel
                       | UndeclaredObjectLabel ObjectLabel
                       | InvalidObjectGID (GID Object) String
                       | MissingNewUserAgent
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type WorldBuilder :: Type -> Type
newtype WorldBuilder a = WorldBuilder (ExceptT WorldBuilderError (State BuilderState) a)
  deriving newtype
    ( Applicative
    , Functor
    , Monad
    , MonadError WorldBuilderError
    , MonadState BuilderState
    )

type WorldBuilderResult :: Type
data WorldBuilderResult = WorldBuilderResult
  { resultGameState :: GameState
  , resultCounters  :: BuilderCounters
  }

initialBuilderState :: GameState -> BuilderCounters -> BuilderState
initialBuilderState gs counters = BuilderState
  { bsGameState               = gs
  , bsCounters                = counters
  , bsWitnessMap              = view (possibilityGraph . witnessMap) gs
  , bsEntityActionRegistry    = view (possibilityGraph . entityActionEffects) gs
  , bsWorldOutcomeRegistry    = view (possibilityGraph . worldOutcomeEffects) gs
  , bsNewUserStartScene       = view (possibilityGraph . newUserStartScene) gs
  , bsNewUserMkAgent          = view (possibilityGraph . newUserMkAgent) gs
  }

interpretDSL :: SashaLambdaDSL a -> WorldBuilder a
interpretDSL (Pure a) = pure a
interpretDSL (Bind m f) = interpretDSL m >>= (interpretDSL . f)

interpretDSL (DeclareSceneGID label) = do
  st <- get
  case lookup label (view (world . declaredSceneGIDs) (bsGameState st)) of
    Just gid -> pure gid
    Nothing -> do
      let gid = GID (unPInt (view nextSceneId (bsCounters st)))
          gs' = bsGameState st & world . declaredSceneGIDs %~ insert label gid
      put st { bsCounters  = bsCounters st & nextSceneId %~ succPInt
             , bsGameState = gs'
             }
      pure gid

interpretDSL (RegisterScene gid sceneBuilder) = do
  scene <- interpretDSL sceneBuilder
  st <- get
  when (member gid (view (world . sceneMap . getGIDToDataMap) (bsGameState st))) $
    throwError (DuplicateSceneGID gid "Scene already registered")
  let gs' = bsGameState st & world . sceneMap . getGIDToDataMap %~ insert gid scene
  put st { bsGameState = gs' }

interpretDSL (Title t scene) = pure scene { _title = t }

interpretDSL (SceneDescription rt scene) = pure scene { _sceneDescription = rt }

interpretDSL (DeclareObjectGID label) = do
  st <- get
  case lookup label (view (world . declaredObjectGIDs) (bsGameState st)) of
    Just gid -> pure gid
    Nothing -> do
      let gid = GID (unPInt (view nextObjectId (bsCounters st)))
          gs' = bsGameState st & world . declaredObjectGIDs %~ insert label gid
      put st { bsCounters  = bsCounters st & nextObjectId %~ succPInt
             , bsGameState = gs'
             }
      pure gid

interpretDSL (RegisterObject gid objBuilder) = do
  obj <- interpretDSL objBuilder
  st <- get
  when (member gid (view (world . objectMap . getGIDToDataMap) (bsGameState st))) $
    throwError (DuplicateObjectGID gid "Object already registered")
  let gs' = bsGameState st & world . objectMap . getGIDToDataMap %~ insert gid obj
  put st { bsGameState = gs' }

interpretDSL (ShortName text obj) = pure (obj & shortName .~ text)

interpretDSL (Description rt obj) = pure (obj & description .~ rt)

interpretDSL (ObjectBehavior obj actionMgmt) =
  pure (obj & objectActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (RegisterObjectToScene sceneGID objGID nounText) = do
  st <- get
  case lookup sceneGID (view (world . sceneMap . getGIDToDataMap) (bsGameState st)) of
    Nothing -> throwError (InvalidSceneGID sceneGID "Scene not registered")
    Just scene -> do
      let updatedScene = scene
            & objectSemanticMap . at nounText . non mempty %~ Data.Set.insert objGID
            & sceneObjects %~ Data.Set.insert objGID
          gs' = bsGameState st
            & world . sceneMap . getGIDToDataMap %~ insert sceneGID updatedScene
            & world . globalSemanticMap . at nounText . non mempty %~ Data.Set.insert objGID
      put st { bsGameState = gs' }

interpretDSL (RegisterSpatial entityID spatialRel) = do
  st <- get
  let gs' = bsGameState st & world . spatialRelationshipMap . unSpatialRelationshipMap . at entityID . non mempty %~ Data.Set.insert spatialRel
  put st { bsGameState = gs' }

interpretDSL (DeclareImplicitStimulusGID actionF) = do
  st <- get
  let gid = GID (unPInt (view nextImplicitStimulusId (bsCounters st)))
      gs' = bsGameState st & actionMaps . implicitStimulusMap %~ insert gid actionF
  put st { bsCounters = bsCounters st & nextImplicitStimulusId %~ succPInt
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateISAManagement verb gid) = pure (ISAManagementKey verb gid)

interpretDSL (DeclareDirectionalStimulusGID actionF) = do
  st <- get
  let gid = GID (unPInt (view nextDirectionalStimulusId (bsCounters st)))
      gs' = bsGameState st & actionMaps . directionalStimulusMap %~ insert gid actionF
  put st { bsCounters = bsCounters st & nextDirectionalStimulusId %~ succPInt
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateDSAManagement verb gid) = pure (DSAManagementKey verb gid)

interpretDSL (DeclareAcquisitionActionGID actionF) = do
  st <- get
  let gid = GID (unPInt (view nextAcquisitionId (bsCounters st)))
      gs' = bsGameState st & actionMaps . acquisitionActionMap %~ insert gid actionF
  put st { bsCounters = bsCounters st & nextAcquisitionId %~ succPInt
         , bsGameState = gs'
         }
  pure gid

interpretDSL (DeclareDivestmentActionGID actionF) = do
  st <- get
  let gid = GID (unPInt (view nextDivestmentId (bsCounters st)))
      gs' = bsGameState st & actionMaps . divestmentActionMap %~ insert gid actionF
  put st { bsCounters = bsCounters st & nextDivestmentId %~ succPInt
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateAVTargetManagement verb gid) = pure (AVTargetManagementKey verb gid)

interpretDSL (CreateAVSupportManagement verb gid) = pure (AVSupportManagementKey verb gid)

interpretDSL (CreateDVManagement verb gid) = pure (DVManagementKey verb gid)

interpretDSL (CreateDVSurfaceManagement verb gid) = pure (DVSurfaceManagementKey verb gid)

interpretDSL (DeclareWitnessGID witnessFn) = do
  st <- get
  let gid = GID (unPInt (view nextWitnessId (bsCounters st)))
  put st { bsCounters = bsCounters st & nextWitnessId %~ succPInt
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

interpretDSL (LinkEntityActionEffect actionKey eid op) = do
  st <- get
  put st { bsEntityActionRegistry =
             bsEntityActionRegistry st & at actionKey . non mempty . at eid . non mempty %~ Data.Set.insert op }

interpretDSL (NewUser sceneGid mkAgent) = do
  st <- get
  put st { bsNewUserStartScene = Just sceneGid
         , bsNewUserMkAgent    = Just mkAgent
         }

interpretDSL (ModifyScene label f) = do
  st <- get
  case lookup label (view (world . declaredSceneGIDs) (bsGameState st)) of
    Nothing -> throwError (UndeclaredSceneLabel label)
    Just gid -> case lookup gid (view (world . sceneMap . getGIDToDataMap) (bsGameState st)) of
      Nothing -> throwError (InvalidSceneGID gid "Scene not registered")
      Just stored -> do
        scene <- interpretDSL (f stored)
        let kept = scene & sceneAgents .~ view sceneAgents stored
        st' <- get
        put st' { bsGameState = bsGameState st' & world . sceneMap . getGIDToDataMap %~ insert gid kept }

interpretDSL (ModifyObject label f) = do
  st <- get
  case lookup label (view (world . declaredObjectGIDs) (bsGameState st)) of
    Nothing -> throwError (UndeclaredObjectLabel label)
    Just gid -> case lookup gid (view (world . objectMap . getGIDToDataMap) (bsGameState st)) of
      Nothing -> throwError (InvalidObjectGID gid "Object not registered")
      Just stored -> do
        obj <- interpretDSL (f stored)
        st' <- get
        put st' { bsGameState = bsGameState st' & world . objectMap . getGIDToDataMap %~ insert gid obj }

interpretDSL (ModifyNewUserAgent f) = do
  st <- get
  case bsNewUserMkAgent st of
    Nothing -> throwError MissingNewUserAgent
    Just mkAgent -> do
      mkAgent' <- interpretDSL (f mkAgent)
      st' <- get
      put st' { bsNewUserMkAgent = Just mkAgent' }

interpretDSL FinalizeGameState =
  gets bsGameState

runWorldBuilder :: WorldBuilder GameState -> BuilderState -> Either WorldBuilderError WorldBuilderResult
runWorldBuilder (WorldBuilder builder) initState =
  case runState (runExceptT builder) initState of
    (Left err, _) -> Left err
    (Right gs, finalState) ->
      let pg = PossibilityGraph
            { _entityActionEffects = bsEntityActionRegistry finalState
            , _worldOutcomeEffects = bsWorldOutcomeRegistry finalState
            , _witnessMap          = bsWitnessMap finalState
            , _newUserStartScene   = bsNewUserStartScene finalState
            , _newUserMkAgent      = bsNewUserMkAgent finalState
            }
      in Right WorldBuilderResult
           { resultGameState = gs & possibilityGraph .~ pg
           , resultCounters  = bsCounters finalState
           }
