module Engine.ActionDiscovery.Instances () where

import           SashaPrelude

import           Control.Monad (filterM)
import           Control.Monad.State (gets)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (Map, lookup)
import           Data.Maybe (listToMaybe)
import qualified Data.Set (member)
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (ActionInput, getActionMap, lookupActionGID, lookupTargetActionGID, mkEffectKey, mkVerbKey, runActionProtocol)
  , fetchAction
  , fetchAgentAction
  , fetchSceneAction
  , fetchTargetAction
  )
import           Engine.Resolution.ActionManagement
  ( findAVKey
  , findAVSupportKey
  , findDVKey
  , findDVSurfaceKey
  , lookupDirectionalStimulus
  , lookupDirectionalStimulusTarget
  , lookupImplicitStimulus
  , lookupImplicitStimulusTarget
  , processSpatialRelationshipEffect
  , processWitnesses
  )
import           Engine.Resolution.Perception (modifyAgentNarration)
import           Error (throwMaybeM)
import           Grammar.Lexer (Lexeme (AGENTNAME))
import           Grammar.Parser.Atomics.Adjectives (Adjective)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulusPlayer (DirectionalStimulusPlayer)
  )
import           Grammar.Parser.Atomics.Semantics.Nouns.Objective (floorOB)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Model
  ( AcquisitionVerbPhrase (SimpleAcquisitionVerbPhrase)
  , DivestmentVerbPhrase (SimpleDivestmentVerbPhrase)
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase, PlayerDirectionalStimulusNounPhrase)
  , NounPhrase (DescriptiveNounPhrase, DescriptiveNounPhraseDet, NounPhrase, SimpleNounPhrase)
  , ObjectPhrase (ObjectPhrase)
  , PlayerName (PlayerName)
  , PlayerNamePhrase (PlayerNamePhrase)
  )
import           Grammar.Parser.GCase
  ( NounKey (DirectionalStimulusKey, DirectionalStimulusPlayerKey, ObjectiveKey)
  , VerbKey (AcquisitionKey, DivestmentKey, ImperativeKey, ImplicitStimulusKey)
  )
import           Lens.Micro.Platform (over, use, view)
import           Model.Core
  ( AcquisitionF (AcquisitionCannotF, AcquisitionF)
  , ActionEffectKey (AcquisitionalActionKey, DirectionalStimulusActionKey, DivestmentActionKey, ImplicitStimulusActionKey)
  , ActionEffectKeyF (ActionEffectKeyF)
  , ActorKey (ActorKey)
  , Agent
  , AgentKey (AgentKey)
  , DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , DivestmentF (DivestmentCannotF, DivestmentF)
  , DivestmentTargetType (DivestToSurface')
  , EntityKey (EntityAgent, EntityObject, EntityScene)
  , GameComputation
  , ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , Object
  , SpatialRelationship (ContainedIn, Inventory, SupportedBy)
  , SpatialRelationshipComputation (Acquisition, Divestiture)
  , TargetKey (TargetKey)
  , WitnessContext (AcquisitionWitnessContext, AgentWitnessContext, DirectedWitnessContext, DivestmentWitnessContext, FailedAgentLookContext, ImplicitWitnessContext)
  , acquisitionActionMap
  , actionConsequence
  , actionMaps
  , agentLocationMap
  , agentSemanticMap
  , descriptives
  , directionalStimulusMap
  , divestmentActionMap
  , getGIDToDataMap
  , globalSemanticMap
  , implicitStimulusMap
  , objectActionManagement
  , objectMap
  , objectSemanticMap
  , sceneMap
  , spatialRelationshipMap
  , unSpatialRelationshipMap
  , world
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)

-- | Instance for ImplicitStimulusF (actor + scene veto for bare "look")
instance ActionProtocol ImplicitStimulusF where
  type ActionInput ImplicitStimulusF = ImplicitStimulusVerb

  getActionMap = view implicitStimulusMap

  mkEffectKey = ImplicitStimulusActionKey

  mkVerbKey = ImplicitStimulusKey

  lookupActionGID = lookupImplicitStimulus

  lookupTargetActionGID = lookupImplicitStimulusTarget

  runActionProtocol actorGid verb = do
    actionMap <- gets (getActionMap @ImplicitStimulusF . view actionMaps)
    locMap <- use agentLocationMap
    sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                  (lookup actorGid locMap)
    let actorKey = ActorKey (EntityAgent actorGid)
        targetKey = TargetKey (EntityScene sceneGid)
    (playerGID, playerAction) <- fetchAgentAction @ImplicitStimulusF verb actionMap actorGid
    (sceneGID, sceneAction) <- fetchTargetAction @ImplicitStimulusF verb actionMap actorKey targetKey

    let playerKey = mkEffectKey @ImplicitStimulusF playerGID
        sceneKey = mkEffectKey @ImplicitStimulusF sceneGID

    case (playerAction, sceneAction) of
      (ImplicitNoStimulusF (ActionEffectKeyF pf), _) ->
        pf actorKey targetKey playerKey
      (_, ImplicitNoStimulusF (ActionEffectKeyF lf)) ->
        lf actorKey targetKey sceneKey
      (ImplicitStimulusF (ActionEffectKeyF ps), ImplicitStimulusF (ActionEffectKeyF ls)) ->
        ps actorKey targetKey playerKey
          >> ls actorKey targetKey sceneKey
          >> processWitnesses actorKey ImplicitWitnessContext

-- | Instance for DirectionalStimulusF (actor + object + scene veto for "look at X")
instance ActionProtocol DirectionalStimulusF where
  type ActionInput DirectionalStimulusF = (DirectionalStimulusVerb, DirectionalStimulusNounPhrase)

  getActionMap = view directionalStimulusMap

  mkEffectKey = DirectionalStimulusActionKey

  mkVerbKey (verb, _) = ImperativeKey verb

  lookupActionGID (verb, _) = lookupDirectionalStimulus verb

  lookupTargetActionGID (verb, _) = lookupDirectionalStimulusTarget verb

  runActionProtocol actorGid (verb, nounPhrase@(DirectionalStimulusNounPhrase _ np)) = do
    let nounKey = extractDirectionalNoun nounPhrase
    locMap <- use agentLocationMap
    sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                  (lookup actorGid locMap)
    sMap <- use (world . sceneMap . getGIDToDataMap)
    scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
               (lookup sceneGid sMap)
    objGIDMaybe <- case lookup nounKey (view objectSemanticMap scene) of
                     Nothing -> pure Nothing
                     Just objGIDSet -> case np of
                       DescriptiveNounPhrase adj _      ->
                         findMatchingObject adj (toList objGIDSet)
                       DescriptiveNounPhraseDet _ adj _ ->
                         findMatchingObject adj (toList objGIDSet)
                       SimpleNounPhrase _               -> case toList objGIDSet of
                         []        -> pure Nothing
                         (gid : _) -> pure (Just gid)
                       NounPhrase _ _                   -> case toList objGIDSet of
                         []        -> pure Nothing
                         (gid : _) -> pure (Just gid)

    case objGIDMaybe of
      Nothing -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "That's not here. Try something else."]))
      Just objGID -> do
        let actorKey = ActorKey (EntityAgent actorGid)
            targetKey = TargetKey (EntityObject objGID)
        actionMap <- gets (getActionMap @DirectionalStimulusF . view actionMaps)
        (playerGID, playerAction) <- fetchAgentAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid
        (sceneGID, sceneAction) <- fetchSceneAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid
        (objectActionGID, objectAction) <- fetchTargetAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorKey targetKey

        let playerKey = mkEffectKey @DirectionalStimulusF playerGID
            sceneKey  = mkEffectKey @DirectionalStimulusF sceneGID
            objectKey = mkEffectKey @DirectionalStimulusF objectActionGID

        case (playerAction, sceneAction, objectAction) of
          (DirectionalNoStimulusF (ActionEffectKeyF pf), _, _) ->
            pf actorKey targetKey playerKey
          (_, DirectionalNoStimulusF (ActionEffectKeyF lf), _) ->
            lf actorKey targetKey sceneKey
          (_, _, DirectionalNoStimulusF (ActionEffectKeyF of')) ->
            of' actorKey targetKey objectKey
          (DirectionalStimulusF (ActionEffectKeyF ps), DirectionalStimulusF (ActionEffectKeyF ls), DirectionalStimulusF (ActionEffectKeyF os)) ->
            ps actorKey targetKey playerKey
              >> ls actorKey targetKey sceneKey
              >> os actorKey targetKey objectKey
              >> processWitnesses actorKey (DirectedWitnessContext objGID)

  runActionProtocol actorGid (verb, nounPhrase@(PlayerDirectionalStimulusNounPhrase _ _)) = do
    let nounKey = extractDirectionalNoun nounPhrase
        actorKey = ActorKey (EntityAgent actorGid)
    locMap <- use agentLocationMap
    sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                  (lookup actorGid locMap)
    sMap <- use (world . sceneMap . getGIDToDataMap)
    scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
               (lookup sceneGid sMap)
    case toList (fromMaybe mempty (lookup nounKey (view agentSemanticMap scene))) of
      [] -> do
        modifyAgentNarration (AgentKey actorGid)
          (over actionConsequence (<> [colored White "That's not here. Try something else."]))
        processWitnesses actorKey FailedAgentLookContext
      (targetGid : _) -> do
        let targetKey = TargetKey (EntityAgent targetGid)
        actionMap <- gets (getActionMap @DirectionalStimulusF . view actionMaps)
        (playerGID, playerAction) <- fetchAgentAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid
        (sceneGID, sceneAction) <- fetchSceneAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid
        (targetActionGID, targetAction) <- fetchTargetAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorKey targetKey

        let playerKey       = mkEffectKey @DirectionalStimulusF playerGID
            sceneKey        = mkEffectKey @DirectionalStimulusF sceneGID
            targetEffectKey = mkEffectKey @DirectionalStimulusF targetActionGID

        case (playerAction, sceneAction, targetAction) of
          (DirectionalNoStimulusF (ActionEffectKeyF pf), _, _) ->
            pf actorKey targetKey playerKey
          (_, DirectionalNoStimulusF (ActionEffectKeyF lf), _) ->
            lf actorKey targetKey sceneKey
          (_, _, DirectionalNoStimulusF (ActionEffectKeyF tf)) ->
            tf actorKey targetKey targetEffectKey
          (DirectionalStimulusF (ActionEffectKeyF ps), DirectionalStimulusF (ActionEffectKeyF ls), DirectionalStimulusF (ActionEffectKeyF ts)) -> do
            ps actorKey targetKey playerKey
            ls actorKey targetKey sceneKey
            ts actorKey targetKey targetEffectKey
            processWitnesses actorKey (AgentWitnessContext targetGid)

-- | Extract noun text from DirectionalStimulusNounPhrase for globalSemanticMap lookup
extractDirectionalNoun :: DirectionalStimulusNounPhrase -> NounKey
extractDirectionalNoun (DirectionalStimulusNounPhrase _ np) = case np of
  SimpleNounPhrase ds             -> DirectionalStimulusKey ds
  NounPhrase _ ds                 -> DirectionalStimulusKey ds
  DescriptiveNounPhrase _ ds      -> DirectionalStimulusKey ds
  DescriptiveNounPhraseDet _ _ ds -> DirectionalStimulusKey ds
extractDirectionalNoun (PlayerDirectionalStimulusNounPhrase _ (PlayerNamePhrase np)) = case np of
  SimpleNounPhrase (PlayerName name)             -> DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME name))
  NounPhrase _ (PlayerName name)                 -> DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME name))
  DescriptiveNounPhrase _ (PlayerName name)      -> DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME name))
  DescriptiveNounPhraseDet _ _ (PlayerName name) -> DirectionalStimulusPlayerKey (DirectionalStimulusPlayer (AGENTNAME name))

-- | Instance for AcquisitionF (player + scene + support + object veto chain for "get X")
instance ActionProtocol AcquisitionF where
  type ActionInput AcquisitionF = AcquisitionVerbPhrase

  getActionMap = view acquisitionActionMap

  mkEffectKey = AcquisitionalActionKey

  mkVerbKey (SimpleAcquisitionVerbPhrase verb _) = AcquisitionKey verb

  lookupActionGID (SimpleAcquisitionVerbPhrase verb _) = findAVKey verb

  lookupTargetActionGID (SimpleAcquisitionVerbPhrase verb _) = findAVKey verb

  runActionProtocol actorGid avp@(SimpleAcquisitionVerbPhrase verb objectPhrase) = do
    actionMap <- gets (getActionMap @AcquisitionF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @AcquisitionF avp actionMap actorGid
    let playerKey = mkEffectKey @AcquisitionF playerGID

    -- Resolve object in the actor's scene
    let nounKey = parseObjectPhrase objectPhrase
    locMap <- use agentLocationMap
    sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                  (lookup actorGid locMap)
    sMap <- use (world . sceneMap . getGIDToDataMap)
    scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
               (lookup sceneGid sMap)
    case lookup nounKey (view objectSemanticMap scene) of
      Nothing -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't see that here."]))
      Just objGIDSet -> case objectPhrase of
        ObjectPhrase np -> case np of
          DescriptiveNounPhrase adj _      ->
            findMatchingObject adj (toList objGIDSet) >>= \case
              Nothing  -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't see that here."]))
              Just gid -> handleAcquisition actorGid avp playerAction playerKey verb actionMap gid
          DescriptiveNounPhraseDet _ adj _ ->
            findMatchingObject adj (toList objGIDSet) >>= \case
              Nothing  -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't see that here."]))
              Just gid -> handleAcquisition actorGid avp playerAction playerKey verb actionMap gid
          SimpleNounPhrase _               -> case toList objGIDSet of
            []        -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't see that here."]))
            (gid : _) -> handleAcquisition actorGid avp playerAction playerKey verb actionMap gid
          NounPhrase _ _                   -> case toList objGIDSet of
            []        -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't see that here."]))
            (gid : _) -> handleAcquisition actorGid avp playerAction playerKey verb actionMap gid

handleAcquisition :: GID Agent
                  -> AcquisitionVerbPhrase
                  -> AcquisitionF
                  -> ActionEffectKey
                  -> AcquisitionVerb
                  -> Map (GID AcquisitionF) AcquisitionF
                  -> GID Object
                  -> GameComputation Identity ()
handleAcquisition actorGid _ (AcquisitionCannotF (ActionEffectKeyF pf)) playerKey _ _ objectGID =
  pf (ActorKey (EntityAgent actorGid)) (TargetKey (EntityObject objectGID)) playerKey
handleAcquisition actorGid avp (AcquisitionF (ActionEffectKeyF ps)) playerKey verb actionMap objectGID = do
  let actorKey = ActorKey (EntityAgent actorGid)
      targetKey = TargetKey (EntityObject objectGID)
  -- Support the object rests on
  spatialMap <- use (world . spatialRelationshipMap . unSpatialRelationshipMap)
  rels <- throwMaybeM ("Object not found in spatial relationships: " <> pack (show objectGID))
            (lookup (EntityObject objectGID) spatialMap)
  supportGID <- throwMaybeM ("Object has no support: " <> pack (show objectGID))
                  (listToMaybe ([oid | ContainedIn (EntityObject oid) <- toList rels]
                                <> [oid | SupportedBy (EntityObject oid) <- toList rels]))

  -- Fetch actions from scene, support, object
  oMap <- use (world . objectMap . getGIDToDataMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show objectGID))
           (lookup objectGID oMap)
  support <- throwMaybeM ("Support not found: " <> pack (show supportGID))
               (lookup supportGID oMap)
  (sceneActionGID, sceneAction) <- fetchSceneAction @AcquisitionF avp actionMap actorGid
  supportActionGID <- throwMaybeM "Support has no acquisition action"
                        (findAVSupportKey verb (view objectActionManagement support))
  supportAction <- fetchAction @AcquisitionF actionMap supportActionGID
  objectActionGID <- throwMaybeM "Object has no acquisition action"
                       (findAVKey verb (view objectActionManagement obj))
  objectAction <- fetchAction @AcquisitionF actionMap objectActionGID

  let sceneKey   = mkEffectKey @AcquisitionF sceneActionGID
      supportKey = mkEffectKey @AcquisitionF supportActionGID
      objectKey  = mkEffectKey @AcquisitionF objectActionGID

  case (sceneAction, supportAction, objectAction) of
    (AcquisitionCannotF (ActionEffectKeyF lf), _, _) ->
      lf actorKey targetKey sceneKey
    (_, AcquisitionCannotF (ActionEffectKeyF cf), _) ->
      cf actorKey targetKey supportKey
    (_, _, AcquisitionCannotF (ActionEffectKeyF of')) ->
      of' actorKey targetKey objectKey
    (AcquisitionF (ActionEffectKeyF ls), AcquisitionF (ActionEffectKeyF cs), AcquisitionF (ActionEffectKeyF os)) -> do
      ps actorKey targetKey playerKey
      ls actorKey targetKey sceneKey
      cs actorKey targetKey supportKey
      os actorKey targetKey objectKey
      processSpatialRelationshipEffect actorGid (Acquisition (EntityObject objectGID) (EntityObject supportGID))
      processWitnesses actorKey (AcquisitionWitnessContext objectGID)

-- | Instance for DivestmentF (player + object + scene + target veto chain for "drop X")
instance ActionProtocol DivestmentF where
  type ActionInput DivestmentF = DivestmentVerbPhrase

  getActionMap = view divestmentActionMap

  mkEffectKey = DivestmentActionKey

  mkVerbKey (SimpleDivestmentVerbPhrase verb _) = DivestmentKey verb

  lookupActionGID (SimpleDivestmentVerbPhrase verb _) = findDVKey verb

  lookupTargetActionGID (SimpleDivestmentVerbPhrase verb _) = findDVKey verb

  runActionProtocol actorGid dvp@(SimpleDivestmentVerbPhrase verb objectPhrase) = do
    actionMap <- gets (getActionMap @DivestmentF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @DivestmentF dvp actionMap actorGid
    let playerKey = mkEffectKey @DivestmentF playerGID

    -- Resolve object in the actor's inventory
    let nounKey = parseObjectPhrase objectPhrase
    semMap <- use (world . globalSemanticMap)
    spatialMap <- use (world . spatialRelationshipMap . unSpatialRelationshipMap)
    let candidates = fromMaybe mempty (lookup nounKey semMap)
        inventoryObjs =
          [ oid
          | oid <- toList candidates
          , let rels = fromMaybe mempty (lookup (EntityObject oid) spatialMap)
          , Data.Set.member (Inventory actorGid) rels
          ]
    objectGIDMaybe <- case objectPhrase of
                        ObjectPhrase np -> case np of
                          DescriptiveNounPhrase adj _      ->
                            findMatchingObject adj inventoryObjs
                          DescriptiveNounPhraseDet _ adj _ ->
                            findMatchingObject adj inventoryObjs
                          SimpleNounPhrase _               -> case inventoryObjs of
                            []        -> pure Nothing
                            (oid : _) -> pure (Just oid)
                          NounPhrase _ _                   -> case inventoryObjs of
                            []        -> pure Nothing
                            (oid : _) -> pure (Just oid)

    case objectGIDMaybe of
      Nothing -> modifyAgentNarration (AgentKey actorGid) (over actionConsequence (<> [colored White "You don't have that."]))
      Just objectGID -> do
        let actorKey = ActorKey (EntityAgent actorGid)
            objectTargetKey = TargetKey (EntityObject objectGID)
        case playerAction of
          DivestmentCannotF (ActionEffectKeyF pf) -> pf actorKey objectTargetKey playerKey
          DivestmentF (ActionEffectKeyF ps) -> do
            -- Target is the floor of the actor's scene
            locMap <- use agentLocationMap
            sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                          (lookup actorGid locMap)
            sMap <- use (world . sceneMap . getGIDToDataMap)
            scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
                       (lookup sceneGid sMap)
            floorSet <- throwMaybeM "There's nowhere to drop that here."
                          (lookup (ObjectiveKey floorOB) (view objectSemanticMap scene))
            floorGID <- throwMaybeM "There's nowhere to drop that here."
                          (listToMaybe (toList floorSet))

            -- Fetch actions from object, scene, target
            oMap <- use (world . objectMap . getGIDToDataMap)
            obj <- throwMaybeM ("Object not found: " <> pack (show objectGID))
                     (lookup objectGID oMap)
            target <- throwMaybeM ("Target not found: " <> pack (show floorGID))
                        (lookup floorGID oMap)
            let objectActions = view objectActionManagement obj
                targetActions = view objectActionManagement target
            objectActionGID <- throwMaybeM "Object has no divestment action"
                                 (findDVSurfaceKey verb objectActions <|> findDVKey verb objectActions)
            objectAction <- fetchAction @DivestmentF actionMap objectActionGID
            (sceneActionGID, sceneAction) <- fetchSceneAction @DivestmentF dvp actionMap actorGid
            targetActionGID <- throwMaybeM "Target has no divestment action"
                                 (findDVSurfaceKey verb targetActions <|> findDVKey verb targetActions)
            targetAction <- fetchAction @DivestmentF actionMap targetActionGID

            let objectKey = mkEffectKey @DivestmentF objectActionGID
                sceneKey  = mkEffectKey @DivestmentF sceneActionGID
                targetKey = mkEffectKey @DivestmentF targetActionGID

            case (objectAction, sceneAction, targetAction) of
              (DivestmentCannotF (ActionEffectKeyF of'), _, _) ->
                of' actorKey objectTargetKey objectKey
              (_, DivestmentCannotF (ActionEffectKeyF lf), _) ->
                lf actorKey objectTargetKey sceneKey
              (_, _, DivestmentCannotF (ActionEffectKeyF tf)) ->
                tf actorKey objectTargetKey targetKey
              (DivestmentF (ActionEffectKeyF os), DivestmentF (ActionEffectKeyF ls), DivestmentF (ActionEffectKeyF ts)) -> do
                ps actorKey objectTargetKey playerKey
                os actorKey objectTargetKey objectKey
                ls actorKey objectTargetKey sceneKey
                ts actorKey objectTargetKey targetKey
                processSpatialRelationshipEffect actorGid (Divestiture objectGID floorGID DivestToSurface')
                processWitnesses actorKey (DivestmentWitnessContext objectGID)

-- | Extract noun text from ObjectPhrase for semantic map lookup
parseObjectPhrase :: ObjectPhrase -> NounKey
parseObjectPhrase (ObjectPhrase np) = case np of
  SimpleNounPhrase obj             -> ObjectiveKey obj
  NounPhrase _ obj                 -> ObjectiveKey obj
  DescriptiveNounPhrase _ obj      -> ObjectiveKey obj
  DescriptiveNounPhraseDet _ _ obj -> ObjectiveKey obj

objectMatchesAdjective :: Adjective -> GID Object -> GameComputation Identity Bool
objectMatchesAdjective adj oid = do
  oMap <- use (world . objectMap . getGIDToDataMap)
  obj <- throwMaybeM ("Object not found: " <> pack (show oid))
           (lookup oid oMap)
  let objDescriptives = view descriptives obj
  pure $ any matchesAdjective (toList objDescriptives)
  where
    matchesAdjective :: DirectionalStimulusNounPhrase -> Bool
    matchesAdjective (DirectionalStimulusNounPhrase _ np) = case np of
      SimpleNounPhrase _             -> False
      NounPhrase _ _                 -> False
      DescriptiveNounPhrase a _      -> a == adj
      DescriptiveNounPhraseDet _ a _ -> a == adj
    matchesAdjective (PlayerDirectionalStimulusNounPhrase _ (PlayerNamePhrase np)) = case np of
      SimpleNounPhrase _             -> False
      NounPhrase _ _                 -> False
      DescriptiveNounPhrase a _      -> a == adj
      DescriptiveNounPhraseDet _ a _ -> a == adj

findMatchingObject :: Adjective -> [GID Object] -> GameComputation Identity (Maybe (GID Object))
findMatchingObject adj objectGIDs = do
  matchingObjects <- filterM (objectMatchesAdjective adj) objectGIDs
  case matchingObjects of
    (firstMatch:_) -> pure (Just firstMatch)
    []             -> pure Nothing
