module Engine.ActionDiscovery.Instances () where

import           SashaPrelude

import           Control.Monad (filterM)
import           Control.Monad.Except (throwError)
import           Control.Monad.State (gets)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (lookup)
import           Data.Maybe (listToMaybe)
import qualified Data.Set (member)
import           Engine.ActionDiscovery.Protocol
  ( ActionProtocol (ActionInput, getActionMap, lookupActionGID, mkEffectKey, runActionProtocol)
  , fetchAction
  , fetchAgentAction
  , fetchSceneAction
  )
import           Engine.Resolution.ActionManagement
  ( findAVKey
  , findAVSupportKey
  , findAVTargetKey
  , findDVKey
  , findDVSurfaceKey
  , lookupDirectionalStimulus
  , lookupImplicitStimulus
  , processSpatialRelationshipEffect
  , processWitnesses
  )
import           Error (throwMaybeM)
import           Grammar.Lexer (HasLexeme (toLexeme))
import           Grammar.Parser.Atomics.Adjectives (Adjective)
import           Grammar.Parser.Atomics.Semantics.Nouns.Objective (floorOB)
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Model
  ( AcquisitionVerbPhrase (SimpleAcquisitionVerbPhrase)
  , DivestmentVerbPhrase (SimpleDivestmentVerbPhrase)
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase)
  , NounPhrase (DescriptiveNounPhrase, DescriptiveNounPhraseDet, NounPhrase, SimpleNounPhrase)
  , ObjectPhrase (ObjectPhrase)
  )
import           Grammar.Parser.GCase
  ( VerbKey (AcquisitionKey, DirectionalStimulusKey, DivestmentKey, ImplicitStimulusKey)
  )
import           Lens.Micro.Platform (use, view)
import           Model.Core
  ( AcquisitionF (AcquisitionCannotF, AcquisitionF)
  , ActionEffectKey (AcquisitionalActionKey, DirectionalStimulusActionKey, DivestmentActionKey, ImplicitStimulusActionKey)
  , DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , DivestmentF (DivestmentCannotF, DivestmentF)
  , DivestmentTargetType (DivestToSurface')
  , EntityID (EntityObject)
  , GameComputation
  , ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , Object
  , SpatialRelationship (ContainedIn, Inventory, SupportedBy)
  , SpatialRelationshipComputation (Acquisition, Divestiture)
  , WitnessContext (AcquisitionWitnessContext, DirectedWitnessContext, DivestmentWitnessContext, ImplicitWitnessContext)
  , acquisitionActionMap
  , actionMaps
  , agentLocationMap
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

-- | Instance for ImplicitStimulusF (actor + scene veto for bare "look")
instance ActionProtocol ImplicitStimulusF where
  type ActionInput ImplicitStimulusF = ImplicitStimulusVerb

  getActionMap = view implicitStimulusMap

  mkEffectKey = ImplicitStimulusActionKey

  lookupActionGID = lookupImplicitStimulus

  runActionProtocol actorGid verb = do
    actionMap <- gets (getActionMap @ImplicitStimulusF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @ImplicitStimulusF verb actionMap actorGid
    (sceneGID, sceneAction) <- fetchSceneAction @ImplicitStimulusF verb actionMap actorGid

    let playerKey = mkEffectKey @ImplicitStimulusF playerGID
        sceneKey = mkEffectKey @ImplicitStimulusF sceneGID

    case (playerAction, sceneAction) of
      (ImplicitNoStimulusF pf, _) ->
        pf actorGid playerKey
      (_, ImplicitNoStimulusF lf) ->
        lf actorGid sceneKey
      (ImplicitStimulusF ps, ImplicitStimulusF ls) ->
        ps actorGid playerKey
          >> ls actorGid sceneKey
          >> processWitnesses actorGid (ImplicitStimulusKey verb) ImplicitWitnessContext

-- | Instance for DirectionalStimulusF (actor + object + scene veto for "look at X")
instance ActionProtocol DirectionalStimulusF where
  type ActionInput DirectionalStimulusF = (DirectionalStimulusVerb, DirectionalStimulusNounPhrase)

  getActionMap = view directionalStimulusMap

  mkEffectKey = DirectionalStimulusActionKey

  lookupActionGID (verb, _) = lookupDirectionalStimulus verb

  runActionProtocol actorGid (verb, nounPhrase) = do
    -- Resolve object from noun phrase via globalSemanticMap
    let nounText = extractDirectionalNoun nounPhrase
    semMap <- use (world . globalSemanticMap)
    objGIDSet <- throwMaybeM ("Nothing called \"" <> nounText <> "\" here.")
                   (lookup nounText semMap)
    objGID <- case toList objGIDSet of
                [gid] -> pure gid
                []    -> throwError ("Nothing called \"" <> nounText <> "\" here.")
                _     -> throwError ("Which " <> nounText <> "?")

    -- Fetch actions from player, object, scene
    actionMap <- gets (getActionMap @DirectionalStimulusF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid

    oMap <- use (world . objectMap . getGIDToDataMap)
    obj <- throwMaybeM ("Object not found: " <> pack (show objGID))
             (lookup objGID oMap)
    objectActionGID <- throwMaybeM "Object has no look-at action"
                         (lookupDirectionalStimulus verb (view objectActionManagement obj))
    objectAction <- fetchAction @DirectionalStimulusF actionMap objectActionGID

    (sceneGID, sceneAction) <- fetchSceneAction @DirectionalStimulusF (verb, nounPhrase) actionMap actorGid

    let playerKey = mkEffectKey @DirectionalStimulusF playerGID
        objectKey = mkEffectKey @DirectionalStimulusF objectActionGID
        sceneKey  = mkEffectKey @DirectionalStimulusF sceneGID

    case (playerAction, objectAction, sceneAction) of
      (DirectionalNoStimulusF pf, _, _) ->
        pf actorGid playerKey
      (_, DirectionalNoStimulusF of', _) ->
        of' actorGid objectKey
      (_, _, DirectionalNoStimulusF lf) ->
        lf actorGid sceneKey
      (DirectionalStimulusF ps, DirectionalStimulusF os, DirectionalStimulusF ls) ->
        ps actorGid playerKey
          >> os actorGid objectKey
          >> ls actorGid sceneKey
          >> processWitnesses actorGid (DirectionalStimulusKey verb) (DirectedWitnessContext objGID)

-- | Extract noun text from DirectionalStimulusNounPhrase for globalSemanticMap lookup
extractDirectionalNoun :: DirectionalStimulusNounPhrase -> Text
extractDirectionalNoun (DirectionalStimulusNounPhrase _ np) = case np of
  SimpleNounPhrase ds             -> pack (show (toLexeme ds))
  NounPhrase _ ds                 -> pack (show (toLexeme ds))
  DescriptiveNounPhrase _ ds      -> pack (show (toLexeme ds))
  DescriptiveNounPhraseDet _ _ ds -> pack (show (toLexeme ds))

-- | Instance for AcquisitionF (player + scene + support + object veto chain for "get X")
instance ActionProtocol AcquisitionF where
  type ActionInput AcquisitionF = AcquisitionVerbPhrase

  getActionMap = view acquisitionActionMap

  mkEffectKey = AcquisitionalActionKey

  lookupActionGID (SimpleAcquisitionVerbPhrase verb _) = findAVKey verb

  runActionProtocol actorGid avp@(SimpleAcquisitionVerbPhrase verb objectPhrase) = do
    actionMap <- gets (getActionMap @AcquisitionF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @AcquisitionF avp actionMap actorGid
    let playerKey = mkEffectKey @AcquisitionF playerGID

    case playerAction of
      AcquisitionCannotF pf -> pf actorGid playerKey
      AcquisitionF ps -> do
        -- Resolve object in the actor's scene
        let nounText = parseObjectPhrase objectPhrase
        locMap <- use agentLocationMap
        sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                      (lookup actorGid locMap)
        sMap <- use (world . sceneMap . getGIDToDataMap)
        scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
                   (lookup sceneGid sMap)
        objGIDSet <- throwMaybeM "You don't see that here."
                       (lookup nounText (view objectSemanticMap scene))
        objectGID <- case objectPhrase of
                       ObjectPhrase np -> case np of
                         DescriptiveNounPhrase adj _      ->
                           findMatchingObject adj (toList objGIDSet) >>= throwMaybeM "You don't see that here."
                         DescriptiveNounPhraseDet _ adj _ ->
                           findMatchingObject adj (toList objGIDSet) >>= throwMaybeM "You don't see that here."
                         SimpleNounPhrase _               -> case toList objGIDSet of
                           [gid] -> pure gid
                           []    -> throwError "You don't see that here."
                           _     -> throwError ("Which " <> nounText <> "?")
                         NounPhrase _ _                   -> case toList objGIDSet of
                           [gid] -> pure gid
                           []    -> throwError "You don't see that here."
                           _     -> throwError ("Which " <> nounText <> "?")

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
                             (findAVTargetKey verb (view objectActionManagement obj))
        objectAction <- fetchAction @AcquisitionF actionMap objectActionGID

        let sceneKey   = mkEffectKey @AcquisitionF sceneActionGID
            supportKey = mkEffectKey @AcquisitionF supportActionGID
            objectKey  = mkEffectKey @AcquisitionF objectActionGID

        case (sceneAction, supportAction, objectAction) of
          (AcquisitionCannotF lf, _, _) ->
            lf actorGid sceneKey
          (_, AcquisitionCannotF cf, _) ->
            cf actorGid supportKey
          (_, _, AcquisitionCannotF of') ->
            of' actorGid objectKey
          (AcquisitionF ls, AcquisitionF cs, AcquisitionF os) -> do
            ps actorGid playerKey
            ls actorGid sceneKey
            cs actorGid supportKey
            os actorGid objectKey
            processSpatialRelationshipEffect actorGid (Acquisition (EntityObject objectGID) (EntityObject supportGID))
            processWitnesses actorGid (AcquisitionKey verb) (AcquisitionWitnessContext objectGID)

-- | Instance for DivestmentF (player + object + scene + target veto chain for "drop X")
instance ActionProtocol DivestmentF where
  type ActionInput DivestmentF = DivestmentVerbPhrase

  getActionMap = view divestmentActionMap

  mkEffectKey = DivestmentActionKey

  lookupActionGID (SimpleDivestmentVerbPhrase verb _) = findDVKey verb

  runActionProtocol actorGid dvp@(SimpleDivestmentVerbPhrase verb objectPhrase) = do
    actionMap <- gets (getActionMap @DivestmentF . view actionMaps)
    (playerGID, playerAction) <- fetchAgentAction @DivestmentF dvp actionMap actorGid
    let playerKey = mkEffectKey @DivestmentF playerGID

    case playerAction of
      DivestmentCannotF pf -> pf actorGid playerKey
      DivestmentF ps -> do
        -- Resolve object in the actor's inventory
        let nounText = parseObjectPhrase objectPhrase
        semMap <- use (world . globalSemanticMap)
        spatialMap <- use (world . spatialRelationshipMap . unSpatialRelationshipMap)
        let candidates = fromMaybe mempty (lookup nounText semMap)
            inventoryObjs =
              [ oid
              | oid <- toList candidates
              , let rels = fromMaybe mempty (lookup (EntityObject oid) spatialMap)
              , Data.Set.member (Inventory actorGid) rels
              ]
        objectGID <- case objectPhrase of
                       ObjectPhrase np -> case np of
                         DescriptiveNounPhrase adj _      ->
                           findMatchingObject adj inventoryObjs >>= throwMaybeM "You don't have that."
                         DescriptiveNounPhraseDet _ adj _ ->
                           findMatchingObject adj inventoryObjs >>= throwMaybeM "You don't have that."
                         SimpleNounPhrase _               -> case inventoryObjs of
                           [oid] -> pure oid
                           []    -> throwError "You don't have that."
                           _     -> throwError ("Which " <> nounText <> "?")
                         NounPhrase _ _                   -> case inventoryObjs of
                           [oid] -> pure oid
                           []    -> throwError "You don't have that."
                           _     -> throwError ("Which " <> nounText <> "?")

        -- Target is the floor of the actor's scene
        locMap <- use agentLocationMap
        sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                      (lookup actorGid locMap)
        sMap <- use (world . sceneMap . getGIDToDataMap)
        scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
                   (lookup sceneGid sMap)
        floorSet <- throwMaybeM "There's nowhere to drop that here."
                      (lookup (pack (show (toLexeme floorOB))) (view objectSemanticMap scene))
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
          (DivestmentCannotF of', _, _) ->
            of' actorGid objectKey
          (_, DivestmentCannotF lf, _) ->
            lf actorGid sceneKey
          (_, _, DivestmentCannotF tf) ->
            tf actorGid targetKey
          (DivestmentF os, DivestmentF ls, DivestmentF ts) -> do
            ps actorGid playerKey
            os actorGid objectKey
            ls actorGid sceneKey
            ts actorGid targetKey
            processSpatialRelationshipEffect actorGid (Divestiture objectGID floorGID DivestToSurface')
            processWitnesses actorGid (DivestmentKey verb) (DivestmentWitnessContext objectGID)

-- | Extract noun text from ObjectPhrase for semantic map lookup
parseObjectPhrase :: ObjectPhrase -> Text
parseObjectPhrase (ObjectPhrase np) = case np of
  SimpleNounPhrase obj             -> pack (show (toLexeme obj))
  NounPhrase _ obj                 -> pack (show (toLexeme obj))
  DescriptiveNounPhrase _ obj      -> pack (show (toLexeme obj))
  DescriptiveNounPhraseDet _ _ obj -> pack (show (toLexeme obj))

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

findMatchingObject :: Adjective -> [GID Object] -> GameComputation Identity (Maybe (GID Object))
findMatchingObject adj objectGIDs = do
  matchingObjects <- filterM (objectMatchesAdjective adj) objectGIDs
  case matchingObjects of
    (firstMatch:_) -> pure (Just firstMatch)
    []             -> pure Nothing
