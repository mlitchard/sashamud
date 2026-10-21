module DSL.Builder
  ( interpretDSL
  , runWorldBuilder
  , initialBuilderState
  , WorldBuilder
  , WorldBuilderError (InvalidSceneGID, DuplicateSceneGID, DuplicateObjectGID, UndeclaredSceneLabel, UndeclaredObjectLabel, InvalidObjectGID, DuplicateDescriptive, MissingNewUserAgent)
  , WorldBuilderResult (WorldBuilderResult, resultChanges, resultCounters, resultGameState)
  , WorldChange (SceneCreated, ObjectCreated, SceneModified, ObjectModified, NewUserAgentModified, NewUserRegistered)
  , worldBuilderErrorText
  , worldChangeText
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
import           Data.Map.Strict (Map, insert, lookup, member)
import qualified Data.Set (insert, member)
import           DSL.Model.EDSL.SashaLambdaDSL (SashaLambdaDSL (..))
import           Grammar.Parser.Atomics.Semantics.Prepositions.DirectionalStimulusMarker
  ( atDS
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase)
  )
import           Grammar.Parser.GCase
  ( VerbKey (AcquisitionKey, DivestmentKey, ImperativeKey, ImplicitStimulusKey)
  )
import           Lens.Micro.Platform (at, non, view, (%~), (.~), (?~))
import           Model.Core
  ( ActionManagement (AVSupportManagementKey, AVTargetManagementKey, DSAManagementKey, DSATargetManagementKey, DVManagementKey, DVSurfaceManagementKey, ISAManagementKey, ISATargetManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , ActorKey
  , Agent
  , BuilderCounters
  , Entity
  , EntityActionRegistry
  , GameState
  , Object
  , ObjectLabel
  , PossibilityGraph (PossibilityGraph, _actorTargetEntityActionEffects, _actorTargetWorldOutcomeEffects, _newUserMkAgent, _newUserStartScene, _sharedEntityActionEffects, _sharedWorldOutcomeEffects, _targetEntityActionEffects, _targetWorldOutcomeEffects, _witnessMap)
  , Scene (_sceneDescription, _title)
  , SceneLabel
  , TargetKey
  , WitnessMap
  , WorldOutcomeRegistry
  , acquisitionActionMap
  , actionManagementFunctions
  , actionMaps
  , actorTargetActionManagement
  , actorTargetEntityActionEffects
  , actorTargetWorldOutcomeEffects
  , agentActionManagement
  , declaredObjectGIDs
  , declaredSceneGIDs
  , description
  , descriptives
  , directionalStimulusMap
  , divestmentActionMap
  , getGIDToDataMap
  , globalSemanticMap
  , implicitStimulusMap
  , newUserMkAgent
  , newUserStartScene
  , nextAcquisitionId
  , nextDirectionalStimulusId
  , nextDivestmentId
  , nextImplicitStimulusId
  , nextObjectId
  , nextSceneId
  , nextWitnessId
  , objectActionManagement
  , objectMap
  , objectSemanticMap
  , possibilityGraph
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , sceneObjects
  , sharedActionManagement
  , sharedEntityActionEffects
  , sharedWitnessManagement
  , sharedWorldOutcomeEffects
  , shortName
  , spatialRelationshipMap
  , succPInt
  , targetEntityActionEffects
  , targetWorldOutcomeEffects
  , unObjectLabel
  , unPInt
  , unSceneLabel
  , unSpatialRelationshipMap
  , witnessMap
  , world
  )
import           Model.GID (GID (GID))

data BuilderState = BuilderState
  { bsGameState :: GameState
  , bsCounters :: BuilderCounters
  , bsWitnessMap :: WitnessMap
  , bsActorTargetWorldOutcomeRegistry :: Map ActorKey (Map TargetKey WorldOutcomeRegistry)
  , bsTargetWorldOutcomeRegistry :: Map TargetKey WorldOutcomeRegistry
  , bsSharedWorldOutcomeRegistry :: Map Entity WorldOutcomeRegistry
  , bsActorTargetEntityActionRegistry :: Map ActorKey (Map TargetKey EntityActionRegistry)
  , bsTargetEntityActionRegistry :: Map TargetKey EntityActionRegistry
  , bsSharedEntityActionRegistry :: Map Entity EntityActionRegistry
  , bsNewUserStartScene :: Maybe (GID Scene)
  , bsNewUserMkAgent :: Maybe (Text -> Agent)
  , bsChanges :: [WorldChange]
  }

type WorldChange :: Type
data WorldChange = SceneCreated (GID Scene)
                 | ObjectCreated (GID Object)
                 | SceneModified SceneLabel
                 | ObjectModified ObjectLabel
                 | NewUserAgentModified
                 | NewUserRegistered (GID Scene)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type WorldBuilderError :: Type
data WorldBuilderError = InvalidSceneGID (GID Scene) String
                       | DuplicateSceneGID (GID Scene) String
                       | DuplicateObjectGID (GID Object) String
                       | UndeclaredSceneLabel SceneLabel
                       | UndeclaredObjectLabel ObjectLabel
                       | InvalidObjectGID (GID Object) String
                       | DuplicateDescriptive DirectionalStimulusNounPhrase
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
  , resultChanges   :: [WorldChange]
  }

initialBuilderState :: GameState -> BuilderCounters -> BuilderState
initialBuilderState gs counters = BuilderState
  { bsGameState               = gs
  , bsCounters                = counters
  , bsWitnessMap              = view (possibilityGraph . witnessMap) gs
  , bsActorTargetWorldOutcomeRegistry = view (possibilityGraph . actorTargetWorldOutcomeEffects) gs
  , bsTargetWorldOutcomeRegistry = view (possibilityGraph . targetWorldOutcomeEffects) gs
  , bsSharedWorldOutcomeRegistry = view (possibilityGraph . sharedWorldOutcomeEffects) gs
  , bsActorTargetEntityActionRegistry = view (possibilityGraph . actorTargetEntityActionEffects) gs
  , bsTargetEntityActionRegistry = view (possibilityGraph . targetEntityActionEffects) gs
  , bsSharedEntityActionRegistry = view (possibilityGraph . sharedEntityActionEffects) gs
  , bsNewUserStartScene       = view (possibilityGraph . newUserStartScene) gs
  , bsNewUserMkAgent          = view (possibilityGraph . newUserMkAgent) gs
  , bsChanges                 = []
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
  put st { bsGameState = gs'
         , bsChanges   = bsChanges st <> [SceneCreated gid]
         }

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
  put st { bsGameState = gs'
         , bsChanges   = bsChanges st <> [ObjectCreated gid]
         }

interpretDSL (ShortName text obj) = pure (obj & shortName .~ text)

interpretDSL (Description rt obj) = pure (obj & description .~ rt)

interpretDSL (Descriptive descs obj) = do
  st <- get
  let phrase = DirectionalStimulusNounPhrase atDS descs
      obj' = obj & descriptives %~ Data.Set.insert phrase
  case Data.Set.member phrase (view descriptives obj) of
    True -> pure obj'
    False -> do
      when (any (Data.Set.member phrase . view descriptives) (view (world . objectMap . getGIDToDataMap) (bsGameState st))) $
        throwError (DuplicateDescriptive phrase)
      pure obj'

interpretDSL (ObjectBehavior obj actionMgmt) =
  pure (obj & objectActionManagement . actionManagementFunctions %~ Data.Set.insert actionMgmt)

interpretDSL (RegisterObjectToScene sceneGID objGID nounKey) = do
  st <- get
  case lookup sceneGID (view (world . sceneMap . getGIDToDataMap) (bsGameState st)) of
    Nothing -> throwError (InvalidSceneGID sceneGID "Scene not registered")
    Just scene -> do
      let updatedScene = scene
            & objectSemanticMap . at nounKey . non mempty %~ Data.Set.insert objGID
            & sceneObjects %~ Data.Set.insert objGID
          gs' = bsGameState st
            & world . sceneMap . getGIDToDataMap %~ insert sceneGID updatedScene
            & world . globalSemanticMap . at nounKey . non mempty %~ Data.Set.insert objGID
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

interpretDSL (CreateISATargetManagement verb gid) = pure (ISATargetManagementKey verb gid)

interpretDSL (DeclareDirectionalStimulusGID actionF) = do
  st <- get
  let gid = GID (unPInt (view nextDirectionalStimulusId (bsCounters st)))
      gs' = bsGameState st & actionMaps . directionalStimulusMap %~ insert gid actionF
  put st { bsCounters = bsCounters st & nextDirectionalStimulusId %~ succPInt
         , bsGameState = gs'
         }
  pure gid

interpretDSL (CreateDSAManagement verb gid) = pure (DSAManagementKey verb gid)

interpretDSL (CreateDSATargetManagement verb gid) = pure (DSATargetManagementKey verb gid)

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

interpretDSL (SharedBehavior entity actionMgmt) = do
  st <- get
  let verbKey = case actionMgmt of
        DSAManagementKey verb _       -> ImperativeKey verb
        ISAManagementKey verb _       -> ImplicitStimulusKey verb
        DSATargetManagementKey verb _ -> ImperativeKey verb
        ISATargetManagementKey verb _ -> ImplicitStimulusKey verb
        AVTargetManagementKey verb _  -> AcquisitionKey verb
        AVSupportManagementKey verb _ -> AcquisitionKey verb
        DVManagementKey verb _        -> DivestmentKey verb
        DVSurfaceManagementKey verb _ -> DivestmentKey verb
      gs' = bsGameState st & world . sharedActionManagement . at verbKey . non mempty . at entity . non (ActionManagementFunctions mempty) . actionManagementFunctions %~ Data.Set.insert actionMgmt
  put st { bsGameState = gs' }

interpretDSL (ActorTargetBehavior actorKey targetKey actionMgmt) = do
  st <- get
  let gs' = bsGameState st & world . actorTargetActionManagement . at actorKey . non mempty . at targetKey . non (ActionManagementFunctions mempty) . actionManagementFunctions %~ Data.Set.insert actionMgmt
  put st { bsGameState = gs' }

interpretDSL (SharedWitnessBehavior entity witnessGid) = do
  st <- get
  let gs' = bsGameState st & world . sharedWitnessManagement . at entity ?~ witnessGid
  put st { bsGameState = gs' }

interpretDSL (LinkWorldOutcomeEffect entity actionKey worldOutcome) = do
  st <- get
  put st { bsSharedWorldOutcomeRegistry =
             bsSharedWorldOutcomeRegistry st & at entity . non mempty . at actionKey . non mempty %~ Data.Set.insert worldOutcome }

interpretDSL (LinkTargetWorldOutcomeEffect targetKey actionKey worldOutcome) = do
  st <- get
  put st { bsTargetWorldOutcomeRegistry =
             bsTargetWorldOutcomeRegistry st & at targetKey . non mempty . at actionKey . non mempty %~ Data.Set.insert worldOutcome }

interpretDSL (LinkActorTargetWorldOutcomeEffect actorKey targetKey actionKey worldOutcome) = do
  st <- get
  put st { bsActorTargetWorldOutcomeRegistry =
             bsActorTargetWorldOutcomeRegistry st & at actorKey . non mempty . at targetKey . non mempty . at actionKey . non mempty %~ Data.Set.insert worldOutcome }

interpretDSL (LinkEntityActionEffect entity actionKey eid op) = do
  st <- get
  put st { bsSharedEntityActionRegistry =
             bsSharedEntityActionRegistry st & at entity . non mempty . at actionKey . non mempty . at eid . non mempty %~ Data.Set.insert op }

interpretDSL (LinkTargetEntityActionEffect targetKey actionKey eid op) = do
  st <- get
  put st { bsTargetEntityActionRegistry =
             bsTargetEntityActionRegistry st & at targetKey . non mempty . at actionKey . non mempty . at eid . non mempty %~ Data.Set.insert op }

interpretDSL (LinkActorTargetEntityActionEffect actorKey targetKey actionKey eid op) = do
  st <- get
  put st { bsActorTargetEntityActionRegistry =
             bsActorTargetEntityActionRegistry st & at actorKey . non mempty . at targetKey . non mempty . at actionKey . non mempty . at eid . non mempty %~ Data.Set.insert op }

interpretDSL (NewUser sceneGid mkAgent) = do
  st <- get
  put st { bsNewUserStartScene = Just sceneGid
         , bsNewUserMkAgent    = Just mkAgent
         , bsChanges           = bsChanges st <> [NewUserRegistered sceneGid]
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
        put st' { bsGameState = bsGameState st' & world . sceneMap . getGIDToDataMap %~ insert gid kept
                , bsChanges   = bsChanges st' <> [SceneModified label]
                }

interpretDSL (ModifyObject label f) = do
  st <- get
  case lookup label (view (world . declaredObjectGIDs) (bsGameState st)) of
    Nothing -> throwError (UndeclaredObjectLabel label)
    Just gid -> case lookup gid (view (world . objectMap . getGIDToDataMap) (bsGameState st)) of
      Nothing -> throwError (InvalidObjectGID gid "Object not registered")
      Just stored -> do
        obj <- interpretDSL (f stored)
        st' <- get
        put st' { bsGameState = bsGameState st' & world . objectMap . getGIDToDataMap %~ insert gid obj
                , bsChanges   = bsChanges st' <> [ObjectModified label]
                }

interpretDSL (ModifyNewUserAgent f) = do
  st <- get
  case bsNewUserMkAgent st of
    Nothing -> throwError MissingNewUserAgent
    Just mkAgent -> do
      mkAgent' <- interpretDSL (f mkAgent)
      st' <- get
      put st' { bsNewUserMkAgent = Just mkAgent'
              , bsChanges        = bsChanges st' <> [NewUserAgentModified]
              }

interpretDSL FinalizeGameState =
  gets bsGameState

runWorldBuilder :: WorldBuilder GameState -> BuilderState -> Either WorldBuilderError WorldBuilderResult
runWorldBuilder (WorldBuilder builder) initState =
  case runState (runExceptT builder) initState of
    (Left err, _) -> Left err
    (Right gs, finalState) ->
      let pg = PossibilityGraph
            { _actorTargetWorldOutcomeEffects = bsActorTargetWorldOutcomeRegistry finalState
            , _targetWorldOutcomeEffects      = bsTargetWorldOutcomeRegistry finalState
            , _sharedWorldOutcomeEffects      = bsSharedWorldOutcomeRegistry finalState
            , _actorTargetEntityActionEffects = bsActorTargetEntityActionRegistry finalState
            , _targetEntityActionEffects      = bsTargetEntityActionRegistry finalState
            , _sharedEntityActionEffects      = bsSharedEntityActionRegistry finalState
            , _witnessMap          = bsWitnessMap finalState
            , _newUserStartScene   = bsNewUserStartScene finalState
            , _newUserMkAgent      = bsNewUserMkAgent finalState
            }
      in Right WorldBuilderResult
           { resultGameState = gs & possibilityGraph .~ pg
           , resultCounters  = bsCounters finalState
           , resultChanges   = bsChanges finalState
           }

worldChangeText :: WorldChange -> Text
worldChangeText (SceneCreated gid)      = "Scene created: " <> pack (show gid)
worldChangeText (ObjectCreated gid)     = "Object created: " <> pack (show gid)
worldChangeText (SceneModified label)   = "Scene modified: " <> unSceneLabel label
worldChangeText (ObjectModified label)  = "Object modified: " <> unObjectLabel label
worldChangeText NewUserAgentModified    = "New user agent modified"
worldChangeText (NewUserRegistered gid) = "New user registered in " <> pack (show gid)

worldBuilderErrorText :: WorldBuilderError -> Text
worldBuilderErrorText (InvalidSceneGID gid reason)    = "Invalid scene " <> pack (show gid) <> ": " <> pack reason
worldBuilderErrorText (DuplicateSceneGID gid reason)  = "Duplicate scene " <> pack (show gid) <> ": " <> pack reason
worldBuilderErrorText (DuplicateObjectGID gid reason) = "Duplicate object " <> pack (show gid) <> ": " <> pack reason
worldBuilderErrorText (UndeclaredSceneLabel label)    = "Undeclared scene label: " <> unSceneLabel label
worldBuilderErrorText (UndeclaredObjectLabel label)   = "Undeclared object label: " <> unObjectLabel label
worldBuilderErrorText (InvalidObjectGID gid reason)   = "Invalid object " <> pack (show gid) <> ": " <> pack reason
worldBuilderErrorText (DuplicateDescriptive phrase)   = "Duplicate descriptive: " <> pack (show phrase)
worldBuilderErrorText MissingNewUserAgent             = "No new user agent to modify"
