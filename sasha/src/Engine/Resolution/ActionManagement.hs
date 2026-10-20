module Engine.Resolution.ActionManagement
  ( processActionOutcomeRegistry
  , processSpatialRelationshipEffect
  , processWitnesses
  , processWitnessEffects
  , lookupImplicitStimulus
  , lookupDirectionalStimulus
  , lookupImplicitStimulusTarget
  , lookupDirectionalStimulusTarget
  , lookupWorldOutcomes
  , findAVKey
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
import           Grammar.Parser.GCase (NounKey)
import           Lens.Micro.Platform (at, non, over, use, view, (%=), (.=))
import           Model.Core
  ( AcquisitionF
  , ActionEffectKey
  , ActionManagement (AVSupportManagementKey, AVTargetManagementKey, DSAManagementKey, DSATargetManagementKey, DVManagementKey, DVSurfaceManagementKey, ISAManagementKey, ISATargetManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , ActionManagementOperation (AddAcquisitionVerb, AddDirectionalStimulus, AddDivestmentVerb, AddImplicitStimulus)
  , ActorKey (ActorKey)
  , Agent
  , AgentKey (AgentKey)
  , DirectionalStimulusF
  , DivestmentF
  , DivestmentTargetType (DivestToSurface')
  , Entity (AgentEntity, ObjectEntity, SceneEntity)
  , EntityKey (EntityAgent, EntityObject, EntityScene)
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookAtAgentNarration, LookAtNarration, LookNarration, StaticNarration)
  , Object
  , Scene
  , SpatialRelationship (ContainedIn, Contains, Inventory, SupportedBy, Supports)
  , SpatialRelationshipComputation (Acquisition, Divestiture)
  , TargetKey (TargetKey)
  , WitnessContext (AcquisitionWitnessContext, AgentWitnessContext, DirectedWitnessContext, DivestmentWitnessContext, FailedAgentLookContext, ImplicitWitnessContext)
  , WitnessEffectF (WitnessEffectF)
  , WitnessF (WitnessF)
  , WorldOutcome (NarrationEffect, SpatialRelationshipEffect)
  , actionConsequence
  , actorTargetEntityActionEffects
  , actorTargetWorldOutcomeEffects
  , agentActionManagement
  , agentDescription
  , agentLocationMap
  , agentMap
  , agentShortName
  , agentWitnessMap
  , description
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
  , sharedEntityActionEffects
  , sharedWitnessManagement
  , sharedWorldOutcomeEffects
  , shortName
  , spatialRelationshipMap
  , targetEntityActionEffects
  , targetWorldOutcomeEffects
  , unSpatialRelationshipMap
  , witnessMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored, toPlainText)

-- | Top-level action outcome processing
processActionOutcomeRegistry :: ActorKey -> TargetKey -> ActionEffectKey -> GameComputation Identity ()
processActionOutcomeRegistry actorKey targetKey actionKey = do
  entityActions <- lookupEntityActions actorKey targetKey actionKey
  worldOutcomes <- lookupWorldOutcomes actorKey targetKey actionKey
  processPropActionEffects entityActions
  mapM_ (processWorldOutcome actorKey targetKey) (toList worldOutcomes)

lookupEntityActions :: ActorKey
                    -> TargetKey
                    -> ActionEffectKey
                    -> GameComputation Identity (Map EntityKey (Set ActionManagementOperation))
lookupEntityActions actorKey targetKey@(TargetKey targetEntity) actionKey = do
  actorTarget <- use (possibilityGraph . actorTargetEntityActionEffects)
  target <- use (possibilityGraph . targetEntityActionEffects)
  shared <- use (possibilityGraph . sharedEntityActionEffects)
  let entity = case targetEntity of
        EntityAgent _  -> AgentEntity
        EntityObject _ -> ObjectEntity
        EntityScene _  -> SceneEntity
  pure (fromMaybe mempty
          ((lookup actorKey actorTarget >>= lookup targetKey >>= lookup actionKey)
             <|> (lookup targetKey target >>= lookup actionKey)
             <|> (lookup entity shared >>= lookup actionKey)))

-- | Lookup world outcomes for an action key
lookupWorldOutcomes :: ActorKey
                    -> TargetKey
                    -> ActionEffectKey
                    -> GameComputation Identity (Set WorldOutcome)
lookupWorldOutcomes actorKey targetKey@(TargetKey targetEntity) actionKey = do
  actorTarget <- use (possibilityGraph . actorTargetWorldOutcomeEffects)
  target <- use (possibilityGraph . targetWorldOutcomeEffects)
  shared <- use (possibilityGraph . sharedWorldOutcomeEffects)
  let entity = case targetEntity of
        EntityAgent _  -> AgentEntity
        EntityObject _ -> ObjectEntity
        EntityScene _  -> SceneEntity
  pure (fromMaybe mempty
          ((lookup actorKey actorTarget >>= lookup targetKey >>= lookup actionKey)
             <|> (lookup targetKey target >>= lookup actionKey)
             <|> (lookup entity shared >>= lookup actionKey)))

processPropActionEffects :: Map EntityKey (Set ActionManagementOperation)
                         -> GameComputation Identity ()
processPropActionEffects propActionEffects =
  mapM_ processEffectEntry (Data.Map.Strict.toList propActionEffects)
  where
    processEffectEntry :: (EntityKey, Set ActionManagementOperation) -> GameComputation Identity ()
    processEffectEntry (propKey, operations) =
      mapM_ (processEntityActionEffect propKey) (toList operations)

processEntityActionEffect :: EntityKey
                          -> ActionManagementOperation
                          -> GameComputation Identity ()
processEntityActionEffect (EntityScene sid) effect =
  processSceneActionEffect sid effect
processEntityActionEffect (EntityObject oid) effect =
  processObjectActionEffect oid effect
processEntityActionEffect (EntityAgent aid) effect =
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
processWorldOutcome :: ActorKey -> TargetKey -> WorldOutcome -> GameComputation Identity ()
processWorldOutcome actorKey targetKey (NarrationEffect narrationComp) =
  processNarrationEffect actorKey targetKey narrationComp
processWorldOutcome (ActorKey (EntityAgent actorGid)) _ (SpatialRelationshipEffect spatialComp) =
  processSpatialRelationshipEffect actorGid spatialComp
processWorldOutcome actorKey _ (SpatialRelationshipEffect _) =
  throwError ("Programmer Error: spatial relationship effect for non-agent actor: " <> pack (show actorKey))

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
    EntityScene _    -> pure ()
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
        let existingSupports = mconcat [s | Supports s <- toList relationships]
            withoutOldSupports = Data.Set.filter (\case Supports _ -> False; _ -> True) relationships
        in Data.Set.insert (Supports (Data.Set.insert (EntityObject divestedGID) existingSupports)) withoutOldSupports
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  addObjectToScene sceneGid divestedGID

modifySpatialRelationshipsM :: EntityKey
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

findNounKeysForObject :: GID Object -> GameComputation Identity [NounKey]
findNounKeysForObject oid = do
  globalSemMap <- use (world . globalSemanticMap)
  pure [nk | (nk, oidSet) <- Data.Map.Strict.toList globalSemMap, Data.Set.member oid oidSet]

-- | Process narration effects
processNarrationEffect :: ActorKey -> TargetKey -> NarrationComputation -> GameComputation Identity ()
processNarrationEffect (ActorKey (EntityAgent actorGid)) _ (LookAtNarration objGID) = do
  oMap <- use (world . objectMap . getGIDToDataMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [view description obj]))
  spatialMap <- use (world . spatialRelationshipMap . unSpatialRelationshipMap)
  case lookup (EntityObject objGID) spatialMap of
    Nothing ->
      throwError ("Object not found in spatial relationships: " <> pack (show objGID))
    Just relationships ->
      forM_ (toList relationships) $ \case
        SupportedBy (EntityObject refGID) -> do
          refObj <- throwMaybeM ("Spatial ref not found: " <> pack (show refGID))
                     (lookup refGID oMap)
          modifyAgentNarration (AgentKey actorGid)
            (over actionConsequence (<> [colored White ("It is on the " <> view shortName refObj <> ".")]))
        SupportedBy (EntityAgent refGID) -> do
          aMap <- use (world . agentMap . getAgentMap)
          agent <- throwMaybeM ("Agent not found: " <> pack (show refGID))
                     (lookup refGID aMap)
          modifyAgentNarration (AgentKey actorGid)
            (over actionConsequence (<> [colored White ("It is on " <> toPlainText (view agentShortName agent) <> ".")]))
        ContainedIn (EntityObject containerGID) -> do
          container <- throwMaybeM ("Spatial ref not found: " <> pack (show containerGID))
                         (lookup containerGID oMap)
          modifyAgentNarration (AgentKey actorGid)
            (over actionConsequence (<> [colored White (view shortName obj <> " is inside " <> view shortName container)]))
        ContainedIn (EntityAgent agentGID) -> do
          aMap <- use (world . agentMap . getAgentMap)
          agent <- throwMaybeM ("Agent not found: " <> pack (show agentGID))
                     (lookup agentGID aMap)
          modifyAgentNarration (AgentKey actorGid)
            (over actionConsequence (<> [colored White (view shortName obj <> " is carried by " <> toPlainText (view agentShortName agent))]))
        SupportedBy (EntityScene sid) ->
          throwError ("Programmer Error: object supported by a scene: " <> pack (show sid))
        ContainedIn (EntityScene sid) ->
          throwError ("Programmer Error: object contained in a scene: " <> pack (show sid))
        Inventory agentGID -> do
          aMap <- use (world . agentMap . getAgentMap)
          agent <- throwMaybeM ("Agent not found: " <> pack (show agentGID))
                     (lookup agentGID aMap)
          modifyAgentNarration (AgentKey actorGid)
            (over actionConsequence (<> [colored White (view shortName obj <> " is carried by " <> toPlainText (view agentShortName agent))]))
        Supports eidSet -> do
          let oids = [oid | EntityObject oid <- toList eidSet]
          when (not (null oids)) $ do
            supportedNames <- mapM (\oid -> do
              o <- throwMaybeM ("Object not found: " <> pack (show oid)) (lookup oid oMap)
              pure (view shortName o)) oids
            modifyAgentNarration (AgentKey actorGid)
              (over actionConsequence (<> [colored White ("On it you see: " <> intercalate ", " supportedNames)]))
        Contains eidSet -> do
          let oids = [oid | EntityObject oid <- toList eidSet]
          when (not (null oids)) $ do
            containedNames <- mapM (\oid -> do
              o <- throwMaybeM ("Object not found: " <> pack (show oid)) (lookup oid oMap)
              pure (view shortName o)) oids
            modifyAgentNarration (AgentKey actorGid)
              (over actionConsequence (<> [colored White ("Inside it you see: " <> intercalate ", " containedNames)]))
processNarrationEffect (ActorKey (EntityAgent actorGid)) _ LookNarration = youSeeM actorGid
processNarrationEffect (ActorKey (EntityAgent actorGid)) (TargetKey (EntityAgent targetGid)) LookAtAgentNarration = do
  aMap <- use (world . agentMap . getAgentMap)
  target <- throwMaybeM ("Agent not found: " <> pack (show targetGid))
              (lookup targetGid aMap)
  modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [view agentDescription target]))
processNarrationEffect (ActorKey (EntityAgent _)) targetKey LookAtAgentNarration =
  throwError ("Programmer Error: LookAtAgentNarration target is not an agent: " <> pack (show targetKey))
processNarrationEffect (ActorKey (EntityAgent actorGid)) _ (StaticNarration text) =
  modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White text]))
processNarrationEffect actorKey _ _ =
  throwError ("Programmer Error: narration effect for non-agent actor: " <> pack (show actorKey))

-- | Process witnesses (sashamud witness system)
processWitnesses :: ActorKey -> WitnessContext -> GameComputation Identity ()
processWitnesses actorKey@(ActorKey (EntityAgent actorGid)) witnessCtx = do
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
             (lookup sceneGid sMap)
  witnessEntries <- use agentWitnessMap
  wMap <- use (possibilityGraph . witnessMap)
  shared <- use (world . sharedWitnessManagement)
  let entryWitnesses =
        [ (witnessKey, witnessFGid)
        | (witnessKey, entries) <- Data.Map.Strict.toList witnessEntries
        , Just witnessFGid <- [lookup (EntityAgent actorGid) entries]
        ]
      sceneWitnesses =
        [ (AgentKey gid, witnessFGid)
        | gid <- toList (view sceneAgents scene)
        , gid /= actorGid
        , isNothing (lookup (AgentKey gid) witnessEntries >>= lookup (EntityAgent actorGid))
        , Just witnessFGid <- [lookup AgentEntity shared]
        ]
  forM_ (entryWitnesses <> sceneWitnesses) $ \(witnessKey, witnessFGid) -> do
    witnessFn <- throwMaybeM ("Witness function not found: " <> pack (show witnessFGid))
                   (lookup witnessFGid wMap)
    case witnessFn of
      WitnessF (WitnessEffectF wf) -> wf witnessKey actorKey witnessCtx
processWitnesses actorKey _ =
  throwError ("Programmer Error: witness for non-agent actor: " <> pack (show actorKey))

processWitnessEffects :: AgentKey -> ActorKey -> WitnessContext -> GameComputation Identity ()
processWitnessEffects witnessKey (ActorKey (EntityAgent actorGid))ImplicitWitnessContext = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  modifyAgentNarration witnessKey
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks around.")]))
processWitnessEffects witnessKey (ActorKey (EntityAgent actorGid))(DirectedWitnessContext objGID) = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration witnessKey
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks at the " <> view shortName obj <> ".")]))
processWitnessEffects witnessKey (ActorKey (EntityAgent actorGid))(AgentWitnessContext targetGid) = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  target <- throwMaybeM ("Agent not found: " <> pack (show targetGid))
              (lookup targetGid aMap)
  modifyAgentNarration witnessKey
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks at " <> toPlainText (view agentShortName target) <> ".")]))
processWitnessEffects witnessKey (ActorKey (EntityAgent actorGid))FailedAgentLookContext = do
  aMap <- use (world . agentMap . getAgentMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  modifyAgentNarration witnessKey
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " looks around for someone not here.")]))
processWitnessEffects witnessKey (ActorKey (EntityAgent actorGid))(AcquisitionWitnessContext objGID) = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration witnessKey
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " picks up the " <> view shortName obj <> ".")]))
processWitnessEffects witnessKey (ActorKey (EntityAgent actorGid))(DivestmentWitnessContext objGID) = do
  aMap <- use (world . agentMap . getAgentMap)
  oMap <- use (world . objectMap . getGIDToDataMap)
  actor <- throwMaybeM ("Actor not found: " <> pack (show actorGid))
             (lookup actorGid aMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
           (lookup objGID oMap)
  modifyAgentNarration witnessKey
    (over actionConsequence (<> [colored White (toPlainText (view agentShortName actor) <> " drops the " <> view shortName obj <> ".")]))
processWitnessEffects _ actorKey _ =
  throwError ("Programmer Error: witness effect for non-agent actor: " <> pack (show actorKey))

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

lookupImplicitStimulusTarget :: ImplicitStimulusVerb
                             -> ActionManagementFunctions
                             -> Maybe (GID ImplicitStimulusF)
lookupImplicitStimulusTarget verb (ActionManagementFunctions actions) =
  listToMaybe [gid | ISATargetManagementKey v gid <- toList actions, v == verb]

lookupDirectionalStimulusTarget :: DirectionalStimulusVerb
                                -> ActionManagementFunctions
                                -> Maybe (GID DirectionalStimulusF)
lookupDirectionalStimulusTarget verb (ActionManagementFunctions actions) =
  listToMaybe [gid | DSATargetManagementKey v gid <- toList actions, v == verb]

findAVKey :: AcquisitionVerb
          -> ActionManagementFunctions
          -> Maybe (GID AcquisitionF)
findAVKey verb (ActionManagementFunctions actionSet) =
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
