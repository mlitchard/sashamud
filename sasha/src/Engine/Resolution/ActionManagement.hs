module Engine.Resolution.ActionManagement
  ( processActionEffects
  , processWitnessEffects
  , lookupImplicitStimulus
  , lookupWitness
  ) where

import           SashaPrelude

import           Control.Monad.Reader (asks)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (lookup)
import           Data.Maybe (listToMaybe)
import           Engine.Resolution.Perception
  ( modifyAgentNarration
  , witnessLookM
  , youSeeM
  )
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Lens.Micro.Platform (over, use, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement (ISAManagementKey, WitnessManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent
  , AgentKind (Denizen)
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookNarration, StaticNarration)
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WorldOutcome (NarrationEffect, WitnessEffect)
  , actionConsequence
  , agentActionManagement
  , agentKind
  , agentLocationMap
  , agentMap
  , ctxPossibilityGraph
  , getAgentMap
  , getGIDToDataMap
  , sceneAgents
  , sceneMap
  , witnessMap
  , world
  , worldOutcomeEffects
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)

processActionEffects :: GID Agent -> ActionEffectKey -> GameComputation Identity ()
processActionEffects = processWorldOutcomes

processWorldOutcomes :: GID Agent -> ActionEffectKey -> GameComputation Identity ()
processWorldOutcomes actorGid actionKey = do
  registry <- asks (view (ctxPossibilityGraph . worldOutcomeEffects))
  case lookup actionKey registry of
    Nothing       -> pure ()
    Just outcomes -> mapM_ (processWorldOutcome actorGid) (toList outcomes)

processWorldOutcome :: GID Agent -> WorldOutcome -> GameComputation Identity ()
processWorldOutcome actorGid (NarrationEffect narrationComp) =
  processNarrationEffect actorGid narrationComp
processWorldOutcome actorGid (WitnessEffect narrationComp) =
  processWitnesses actorGid narrationComp

processNarrationEffect :: GID Agent -> NarrationComputation -> GameComputation Identity ()
processNarrationEffect actorGid LookNarration = youSeeM actorGid
processNarrationEffect actorGid (StaticNarration text) =
  modifyAgentNarration actorGid (over actionConsequence (colored White text :))

processWitnesses :: GID Agent -> NarrationComputation -> GameComputation Identity ()
processWitnesses actorGid narrationComp = do
  locMap <- use agentLocationMap
  case lookup actorGid locMap of
    Nothing -> pure ()
    Just sceneGid -> do
      sMap <- use (world . sceneMap . getGIDToDataMap)
      case lookup sceneGid sMap of
        Nothing -> pure ()
        Just scene -> do
          aMap <- use (world . agentMap . getAgentMap)
          wMap <- asks (view (ctxPossibilityGraph . witnessMap))
          let witnesses =
                [ (gid, agent)
                | gid <- toList (view sceneAgents scene)
                , gid /= actorGid
                , Just agent <- [lookup gid aMap]
                , view agentKind agent == Denizen
                ]
          forM_ witnesses $ \(witnessGid, witnessAgent) ->
            case lookupWitness (view agentActionManagement witnessAgent) of
              Nothing -> pure ()
              Just witnessFGid ->
                case lookup witnessFGid wMap of
                  Nothing            -> pure ()
                  Just (WitnessF wf) -> wf witnessGid actorGid narrationComp

processWitnessEffects :: WitnessEffectF
processWitnessEffects witnessGid actorGid LookNarration =
  witnessLookM witnessGid actorGid
processWitnessEffects witnessGid _actorGid (StaticNarration text) =
  modifyAgentNarration witnessGid (over actionConsequence (colored White text :))

lookupImplicitStimulus :: ImplicitStimulusVerb
                       -> ActionManagementFunctions
                       -> Maybe (GID ImplicitStimulusF)
lookupImplicitStimulus verb (ActionManagementFunctions actions) =
  listToMaybe [gid | ISAManagementKey v gid <- toList actions, v == verb]

lookupWitness :: ActionManagementFunctions -> Maybe (GID WitnessF)
lookupWitness (ActionManagementFunctions actions) =
  listToMaybe [gid | WitnessManagementKey gid <- toList actions]
