module Engine.Resolution.ActionManagement
  ( processActionOutcomeRegistry
  , processSpatialRelationshipEffect
  , processWitnesses
  , processWitnessEffects
  , lookupImplicitStimulus
  , lookupDirectionalStimulus
  , lookupWorldOutcomes
  , findAVKey
  , findAVTargetKey
  , findAVSupportKey
  , findDVKey
  , findDVSurfaceKey
  ) where

import           SashaPrelude

import           Control.Monad.Except (throwError)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, adjust, insertWith, lookup)
import qualified Data.Map.Strict (toList)
import           Data.Maybe (listToMaybe)
import           Data.Set (Set)
import qualified Data.Set (delete, filter, insert, map, member, singleton)
import           Data.Text (intercalate)
import           Engine.Resolution.Perception (modifyAgentNarration, youSeeM)
import           Error (throwMaybeM)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.GCase (VerbKey)
import           Lens.Micro.Platform (at, non, over, use, view, (%=), (.=))
import           Model.Core
  ( AcquisitionF
  , ActionEffectKey
  , ActionManagement (AVSupportManagementKey, AVTargetManagementKey, DSAManagementKey, DVManagementKey, DVSurfaceManagementKey, ISAManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , ActionManagementOperation (AddAcquisitionVerb, AddDirectionalStimulus, AddDivestmentVerb, AddImplicitStimulus)
  , Agent
  , DirectionalStimulusF
  , DivestmentF
  , DivestmentTargetType (DivestToSurface')
  , EntityID (EntityAgent, EntityObject)
  , EntityKey (ActingAgentKey, AgentKey', ObjectKey', SceneKey')
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookAtNarration, LookNarration, StaticNarration)
  , Object
  , Scene
  , SpatialRelationship (ContainedIn, Contains, Inventory, SupportedBy, Supports)
  , SpatialRelationshipComputation (Acquisition, Divestiture)
  , WitnessContext (AcquisitionWitnessContext, AgentWitnessContext, DirectedWitnessContext, DivestmentWitnessContext, FailedAgentLookContext, ImplicitWitnessContext)
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WorldOutcome (NarrationEffect, SpatialRelationshipEffect)
  , actionConsequence
  , agentActionManagement
  , agentLocationMap
  , agentMap
  , agentShortName
  , agentWitnessManagement
  , description
  , entityActionEffects
  , getAgentMap
  , getGIDToDataMap
  , globalSemanticMap
  , objectActionManagement
  , objectMap
  , objectSemanticMap
  , possibilityGraph
  , sceneActionManagement
  , sceneAgents
  , sceneMap
  , sceneObjects
  , sharedWitnessManagement
  , shortName
  , spatialRelationshipMap
  , unSpatialRelationshipMap
  , witnessMap
  , world
  , worldOutcomeEffects
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored, toPlainText)

-- | Top-level action outcome processing
processActionOutcomeRegistry :: GID Agent -> ActionEffectKey -> GameComputation Identity ()
processActionOutcomeRegistry actorGid actionKey = do
  entityActions <- lookupEntityActions actionKey
  worldOutcomes <- lookupWorldOutcomes actionKey
  processPropActionEffects actorGid entityActions
  mapM_ (processWorldOutcome actorGid) (toList worldOutcomes)

lookupEntityActions :: ActionEffectKey
                    -> GameComputation Identity (Map EntityKey (Set ActionManagementOperation))
lookupEntityActions actionKey =
  fromMaybe mempty . lookup actionKey <$> use (possibilityGraph . entityActionEffects)

-- | Lookup world outcomes for an action key
lookupWorldOutcomes :: ActionEffectKey -> GameComputation Identity (Set WorldOutcome)
lookupWorldOutcomes actionKey =
  fromMaybe mempty . lookup actionKey <$> use (possibilityGraph . worldOutcomeEffects)

processPropActionEffects :: GID Agent
                         -> Map EntityKey (Set ActionManagementOperation)
                         -> GameComputation Identity ()
processPropActionEffects actorGid propActionEffects =
  mapM_ processEffectEntry (Data.Map.Strict.toList propActionEffects)
  where
    processEffectEntry :: (EntityKey, Set ActionManagementOperation) -> GameComputation Identity ()
    processEffectEntry (propKey, operations) =
      mapM_ (processEntityActionEffect actorGid propKey) (toList operations)

processEntityActionEffect :: GID Agent
                          -> EntityKey
                          -> ActionManagementOperation
                          -> GameComputation Identity ()
processEntityActionEffect _ (SceneKey' sid) effect =
  processSceneActionEffect sid effect
processEntityActionEffect _ (ObjectKey' oid) effect =
  processObjectActionEffect oid effect
processEntityActionEffect actorGid ActingAgentKey effect =
  processAgentActionEffect actorGid effect
processEntityActionEffect _ (AgentKey' aid) effect =
  processAgentActionEffect aid effect

applyActionManagementOp :: ActionManagementOperation -> ActionManagementFunctions -> ActionManagementFunctions
applyActionManagementOp op (ActionManagementFunctions actionSet) =
  ActionManagementFunctions (Data.Set.insert newEntry (Data.Set.filter (not . matchesVerb) actionSet))
  where
    (newEntry, matchesVerb) = case op of
      AddImplicitStimulus verb gid ->
        (ISAManagementKey verb gid, \case ISAManagementKey v _ -> v == verb; _ -> False)
      AddDirectionalStimulus verb gid ->
        (DSAManagementKey verb gid, \case DSAManagementKey v _ -> v == verb; _ -> False)
      AddAcquisitionVerb verb gid ->
        (AVTargetManagementKey verb gid, \case AVTargetManagementKey v _ -> v == verb; _ -> False)
      AddDivestmentVerb verb gid ->
        (DVManagementKey verb gid, \case DVManagementKey v _ -> v == verb; _ -> False)

processSceneActionEffect :: GID Scene -> ActionManagementOperation -> GameComputation Identity ()
processSceneActionEffect sid op =
  modifySceneM sid (over sceneActionManagement (applyActionManagementOp op))

processObjectActionEffect :: GID Object -> ActionManagementOperation -> GameComputation Identity ()
processObjectActionEffect oid op =
  modifyObjectM oid (over objectActionManagement (applyActionManagementOp op))

processAgentActionEffect :: GID Agent -> ActionManagementOperation -> GameComputation Identity ()
processAgentActionEffect aid op =
  modifyAgentM aid (over agentActionManagement (applyActionManagementOp op))

modifySceneM :: GID Scene -> (Scene -> Scene) -> GameComputation Identity ()
modifySceneM sid sceneF = do
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sid)) (lookup sid sMap)
  world . sceneMap . getGIDToDataMap . at sid .= Just (sceneF scene)

modifyObjectM :: GID Object -> (Object -> Object) -> GameComputation Identity ()
modifyObjectM oid objectF = do
  oMap <- use (world . objectMap . getGIDToDataMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show oid)) (lookup oid oMap)
  world . objectMap . getGIDToDataMap . at oid .= Just (objectF obj)

modifyAgentM :: GID Agent -> (Agent -> Agent) -> GameComputation Identity ()
modifyAgentM aid agentF = do
  aMap <- use (world . agentMap . getAgentMap)
  agent <- throwMaybeM ("Agent not found: " <> pack (show aid)) (lookup aid aMap)
  world . agentMap . getAgentMap . at aid .= Just (agentF agent)

-- | Dispatch on WorldOutcome constructors
processWorldOutcome :: GID Agent -> WorldOutcome -> GameComputation Identity ()
processWorldOutcome actorGid (NarrationEffect narrationComp) =
  processNarrationEffect actorGid narrationComp
processWorldOutcome actorGid (SpatialRelationshipEffect spatialComp) =
  processSpatialRelationshipEffect actorGid spatialComp

processSpatialRelationshipEffect :: GID Agent -> SpatialRelationshipComputation -> GameComputation Identity ()
processSpatialRelationshipEffect actorGid (Acquisition acquireableGID supportGID) = do
  modifySpatialRelationshipsM acquireableGID $ \relationships ->
    Data.Set.filter (\case
      SupportedBy eid -> eid /= supportGID
      ContainedIn eid -> eid /= supportGID
      _ -> True
    ) relationships
  modifySpatialRelationshipsM supportGID $ \relationships ->
    Data.Set.map (\case
      Supports eidSet -> Supports (Data.Set.delete acquireableGID eidSet)
      Contains eidSet -> Contains (Data.Set.delete acquireableGID eidSet)
      other -> other
    ) relationships
  modifySpatialRelationshipsM acquireableGID (Data.Set.insert (Inventory actorGid))
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  case acquireableGID of
    EntityObject oid -> removeObjectFromScene sceneGid oid
    EntityAgent _    -> pure ()
processSpatialRelationshipEffect actorGid (Divestiture divestedGID targetGID targetRole) = do
  modifySpatialRelationshipsForObjectM divestedGID $ \relationships ->
    Data.Set.filter (\case
      Inventory _ -> False
      _ -> True
    ) relationships
  case targetRole of
    DivestToSurface' -> do
      modifySpatialRelationshipsForObjectM divestedGID (Data.Set.insert (SupportedBy (EntityObject targetGID)))
      modifySpatialRelationshipsForObjectM targetGID $ \relationships ->
        let existingSupports = foldl' (\acc r -> case r of Supports s -> s; _ -> acc)
                                      mempty
                                      (toList relationships)
            withoutOldSupports = Data.Set.filter (\case Supports _ -> False; _ -> True) relationships
        in Data.Set.insert (Supports (Data.Set.insert (EntityObject divestedGID) existingSupports)) withoutOldSupports
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  addObjectToScene sceneGid divestedGID

modifySpatialRelationshipsM :: EntityID
                            -> (Set SpatialRelationship -> Set SpatialRelationship)
                            -> GameComputation Identity ()
modifySpatialRelationshipsM eid relationshipSetF =
  world . spatialRelationshipMap . unSpatialRelationshipMap . at eid . non mempty %= relationshipSetF

modifySpatialRelationshipsForObjectM :: GID Object
                                     -> (Set SpatialRelationship -> Set SpatialRelationship)
                                     -> GameComputation Identity ()
modifySpatialRelationshipsForObjectM oid = modifySpatialRelationshipsM (EntityObject oid)

addObjectToScene :: GID Scene -> GID Object -> GameComputation Identity ()
addObjectToScene sid oid = do
  modifySceneM sid (over sceneObjects (Data.Set.insert oid))
  nounKeys <- findNounKeysForObject oid
  modifySceneM sid $ \scene ->
    foldr (\nk sc -> over objectSemanticMap (insertWith (<>) nk (Data.Set.singleton oid)) sc) scene nounKeys

removeObjectFromScene :: GID Scene -> GID Object -> GameComputation Identity ()
removeObjectFromScene sid oid = do
  modifySceneM sid (over sceneObjects (Data.Set.delete oid))
  nounKeys <- findNounKeysForObject oid
  modifySceneM sid $ \scene ->
    foldr (over objectSemanticMap . adjust (Data.Set.delete oid)) scene nounKeys

findNounKeysForObject :: GID Object -> GameComputation Identity [Text]
findNounKeysForObject oid = do
  globalSemMap <- use (world . globalSemanticMap)
  pure [nk | (nk, oidSet) <- Data.Map.Strict.toList globalSemMap, Data.Set.member oid oidSet]

-- | Process narration effects
processNarrationEffect :: GID Agent -> NarrationComputation -> GameComputation Identity ()
processNarrationEffect actorGid (LookAtNarration objGID) = do
  oMap <- use (world . objectMap . getGIDToDataMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration actorGid (over actionConsequence (<> [view description obj]))
  spatialMap <- use (world . spatialRelationshipMap . unSpatialRelationshipMap)
  case lookup (EntityObject objGID) spatialMap of
    Nothing ->
      throwError ("Object not found in spatial relationships: " <> pack (show objGID))
    Just relationships ->
      forM_ (toList relationships) $ \case
        SupportedBy (EntityObject refGID) -> do
          refObj <- throwMaybeM ("Spatial ref not found: " <> pack (show refGID))
                     (lookup refGID oMap)
          modifyAgentNarration actorGid
            (over actionConsequence (<> [colored White ("It is on the " <> view shortName refObj <> ".")]))
        SupportedBy (EntityAgent refGID) -> do
          aMap <- use (world . agentMap . getAgentMap)
          agent <- throwMaybeM ("Agent not found: " <> pack (show refGID))
                     (lookup refGID aMap)
          modifyAgentNarration actorGid
            (over actionConsequence (<> [colored White ("It is on " <> toPlainText (view agentShortName agent) <> ".")]))
        ContainedIn (EntityObject containerGID) -> do
          container <- throwMaybeM ("Spatial ref not found: " <> pack (show containerGID))
                         (lookup containerGID oMap)
          modifyAgentNarration actorGid
            (over actionConsequence (<> [colored White (view shortName obj <> " is inside " <> view shortName container)]))
        ContainedIn (EntityAgent agentGID) -> do
          aMap <- use (world . agentMap . getAgentMap)
          agent <- throwMaybeM ("Agent not found: " <> pack (show agentGID))
                     (lookup agentGID aMap)
          modifyAgentNarration actorGid
            (over actionConsequence (<> [colored White (view shortName obj <> " is carried by " <> toPlainText (view agentShortName agent))]))
        Inventory agentGID -> do
          aMap <- use (world . agentMap . getAgentMap)
          agent <- throwMaybeM ("Agent not found: " <> pack (show agentGID))
                     (lookup agentGID aMap)
          modifyAgentNarration actorGid
            (over actionConsequence (<> [colored White (view shortName obj <> " is carried by " <> toPlainText (view agentShortName agent))]))
        Supports eidSet -> do
          let oids = [oid | EntityObject oid <- toList eidSet]
          when (not (null oids)) $ do
            supportedNames <- mapM (\oid -> do
              o <- throwMaybeM ("Object not found: " <> pack (show oid)) (lookup oid oMap)
              pure (view shortName o)) oids
            modifyAgentNarration actorGid
              (over actionConsequence (<> [colored White ("On it you see: " <> intercalate ", " supportedNames)]))
        Contains eidSet -> do
          let oids = [oid | EntityObject oid <- toList eidSet]
          when (not (null oids)) $ do
            containedNames <- mapM (\oid -> do
              o <- throwMaybeM ("Object not found: " <> pack (show oid)) (lookup oid oMap)
              pure (view shortName o)) oids
            modifyAgentNarration actorGid
              (over actionConsequence (<> [colored White ("Inside it you see: " <> intercalate ", " containedNames)]))
processNarrationEffect actorGid LookNarration = youSeeM actorGid
processNarrationEffect actorGid (StaticNarration text) =
  modifyAgentNarration actorGid (over actionConsequence (<> [colored White text]))

-- | Process witnesses (sashamud witness system)
processWitnesses :: GID Agent -> VerbKey -> WitnessContext -> GameComputation Identity ()
processWitnesses actorGid verbKey witnessCtx = do
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
             (lookup sceneGid sMap)
  aMap <- use (world . agentMap . getAgentMap)
  wMap <- use (possibilityGraph . witnessMap)
  shared <- use (world . sharedWitnessManagement)
  let witnesses =
        [ (gid, agent)
        | gid <- toList (view sceneAgents scene)
        , gid /= actorGid
        , Just agent <- [lookup gid aMap]
        ]
  forM_ witnesses $ \(witnessGid, witnessAgent) ->
    case lookup verbKey (view agentWitnessManagement witnessAgent) <|> lookup verbKey shared of
      Nothing -> pure ()
      Just witnessFGid -> do
        witnessFn <- throwMaybeM ("Witness function not found: " <> pack (show witnessFGid))
                       (lookup witnessFGid wMap)
        case witnessFn of
          WitnessF wf -> wf witnessGid actorGid witnessCtx

processWitnessEffects :: WitnessEffectF
processWitnessEffects witnessGid actorGid ImplicitWitnessContext = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  modifyAgentNarration witnessGid
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks around.")]))
processWitnessEffects witnessGid actorGid (DirectedWitnessContext objGID) = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration witnessGid
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks at the " <> view shortName obj <> ".")]))
processWitnessEffects witnessGid actorGid (AgentWitnessContext targetGid) = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  target <- throwMaybeM ("Agent not found: " <> pack (show targetGid))
              (lookup targetGid aMap)
  modifyAgentNarration witnessGid
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks at " <> toPlainText (view agentShortName target) <> ".")]))
processWitnessEffects witnessGid actorGid FailedAgentLookContext = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  modifyAgentNarration witnessGid
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks around for someone not here.")]))
processWitnessEffects witnessGid actorGid (AcquisitionWitnessContext objGID) = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration witnessGid
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " picks up the " <> view shortName obj <> ".")]))
processWitnessEffects witnessGid actorGid (DivestmentWitnessContext objGID) = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration witnessGid
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " drops the " <> view shortName obj <> ".")]))

-- | Lookup functions
lookupImplicitStimulus :: ImplicitStimulusVerb
                       -> ActionManagementFunctions
                       -> Maybe (GID ImplicitStimulusF)
lookupImplicitStimulus verb (ActionManagementFunctions actions) =
  listToMaybe [gid | ISAManagementKey v gid <- toList actions, v == verb]

lookupDirectionalStimulus :: DirectionalStimulusVerb
                          -> ActionManagementFunctions
                          -> Maybe (GID DirectionalStimulusF)
lookupDirectionalStimulus verb (ActionManagementFunctions actions) =
  listToMaybe [gid | DSAManagementKey v gid <- toList actions, v == verb]

findAVKey :: AcquisitionVerb
          -> ActionManagementFunctions
          -> Maybe (GID AcquisitionF)
findAVKey verb (ActionManagementFunctions actionSet) =
  listToMaybe [gid | AVTargetManagementKey v gid <- toList actionSet, v == verb]

findAVTargetKey :: AcquisitionVerb
                -> ActionManagementFunctions
                -> Maybe (GID AcquisitionF)
findAVTargetKey verb (ActionManagementFunctions actionSet) =
  listToMaybe [gid | AVTargetManagementKey v gid <- toList actionSet, v == verb]

findAVSupportKey :: AcquisitionVerb
                 -> ActionManagementFunctions
                 -> Maybe (GID AcquisitionF)
findAVSupportKey verb (ActionManagementFunctions actionSet) =
  listToMaybe [gid | AVSupportManagementKey v gid <- toList actionSet, v == verb]

findDVKey :: DivestmentVerb
          -> ActionManagementFunctions
          -> Maybe (GID DivestmentF)
findDVKey verb (ActionManagementFunctions actionSet) =
  listToMaybe [gid | DVManagementKey v gid <- toList actionSet, v == verb]

findDVSurfaceKey :: DivestmentVerb
                 -> ActionManagementFunctions
                 -> Maybe (GID DivestmentF)
findDVSurfaceKey verb (ActionManagementFunctions actionSet) =
  listToMaybe [gid | DVSurfaceManagementKey v gid <- toList actionSet, v == verb]
