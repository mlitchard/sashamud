module Engine.Resolution.ActionManagement
  ( processActionOutcomeRegistry
  , processWitnesses
  , processWitnessEffects
  , lookupImplicitStimulus
  , lookupDirectionalStimulus
  , lookupWorldOutcomes
  ) where

import           SashaPrelude

import           Control.Monad.Except (throwError)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (lookup)
import           Data.Maybe (listToMaybe)
import           Data.Set (Set)
import           Data.Text (intercalate)
import           Engine.Resolution.Perception (modifyAgentNarration, youSeeM)
import           Error (throwMaybeM)
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.GCase (VerbKey)
import           Lens.Micro.Platform (over, use, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement (DSAManagementKey, ISAManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent
  , DirectionalStimulusF
  , EntityID (EntityAgent, EntityObject)
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookAtNarration, LookNarration, StaticNarration)
  , SpatialRelationship (ContainedIn, Contains, SupportedBy, Supports)
  , WitnessContext (AgentWitnessContext, DirectedWitnessContext, FailedAgentLookContext, ImplicitWitnessContext)
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WorldOutcome (NarrationEffect)
  , actionConsequence
  , agentLocationMap
  , agentMap
  , agentShortName
  , agentWitnessManagement
  , description
  , getAgentMap
  , getGIDToDataMap
  , objectMap
  , possibilityGraph
  , sceneAgents
  , sceneMap
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
  worldOutcomes <- lookupWorldOutcomes actionKey
  mapM_ (processWorldOutcome actorGid) (toList worldOutcomes)

-- | Lookup world outcomes for an action key
lookupWorldOutcomes :: ActionEffectKey -> GameComputation Identity (Set WorldOutcome)
lookupWorldOutcomes actionKey =
  fromMaybe mempty . lookup actionKey <$> use (possibilityGraph . worldOutcomeEffects)

-- | Dispatch on WorldOutcome constructors
processWorldOutcome :: GID Agent -> WorldOutcome -> GameComputation Identity ()
processWorldOutcome actorGid (NarrationEffect narrationComp) =
  processNarrationEffect actorGid narrationComp

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
  let witnesses =
        [ (gid, agent)
        | gid <- toList (view sceneAgents scene)
        , gid /= actorGid
        , Just agent <- [lookup gid aMap]
        ]
  forM_ witnesses $ \(witnessGid, witnessAgent) ->
    case lookup verbKey (view agentWitnessManagement witnessAgent) of
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
