module Engine.Resolution.ActionManagement
  ( processActionEffects
  , lookupImplicitStimulus
  ) where

import           SashaPrelude

import           Control.Monad.Reader (asks)
import           Data.Functor.Identity (Identity)
import           Data.Map.Strict (lookup)
import           Data.Maybe (listToMaybe)
import           Engine.Resolution.Perception (modifyAgentNarration, youSeeM)
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Lens.Micro.Platform (over, use, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement (ISAManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent
  , AgentKind (PlayerAgent)
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookNarration, StaticNarration)
  , WitnessFilter (runWitnessFilter)
  , WitnessGenerate (runWitnessGenerate)
  , WorldOutcome (NarrationEffect)
  , actionConsequence
  , agentCurrentScene
  , agentKind
  , agentMap
  , ctxPossibilityGraph
  , ctxWitnessMap
  , getAgentMap
  , getGIDToDataMap
  , getWitnessMap
  , sceneAgents
  , sceneMap
  , witnessFilter
  , witnessGenerate
  , world
  , worldOutcomeEffects
  )
import           Model.GID (GID)
import           Model.RichText (TextColor (White), colored)

processActionEffects :: GID Agent -> ActionEffectKey -> GameComputation Identity ()
processActionEffects actorGid actionKey = do
  processWorldOutcomes actorGid actionKey
  processWitnessEffects actorGid actionKey

processWorldOutcomes :: GID Agent -> ActionEffectKey -> GameComputation Identity ()
processWorldOutcomes actorGid actionKey = do
  registry <- asks (view (ctxPossibilityGraph . worldOutcomeEffects))
  case lookup actionKey registry of
    Nothing       -> pure ()
    Just outcomes -> mapM_ (processWorldOutcome actorGid) (toList outcomes)

processWorldOutcome :: GID Agent -> WorldOutcome -> GameComputation Identity ()
processWorldOutcome actorGid (NarrationEffect narrationComp) =
  processNarrationEffect actorGid narrationComp

processNarrationEffect :: GID Agent -> NarrationComputation -> GameComputation Identity ()
processNarrationEffect actorGid LookNarration = youSeeM actorGid
processNarrationEffect actorGid (StaticNarration text) =
  modifyAgentNarration actorGid (over actionConsequence (colored White text :))

processWitnessEffects :: GID Agent -> ActionEffectKey -> GameComputation Identity ()
processWitnessEffects actorGid actionKey = do
  wMap <- asks (view (ctxWitnessMap . getWitnessMap))
  case lookup actionKey wMap of
    Nothing -> pure ()
    Just effect -> do
      generatedText <- runWitnessGenerate (view witnessGenerate effect) actorGid
      witnesses <- getWitnesses actorGid
      forM_ witnesses $ \witnessGid -> do
        filteredText <- runWitnessFilter (view witnessFilter effect) generatedText witnessGid
        modifyAgentNarration witnessGid (over actionConsequence (filteredText :))

getWitnesses :: GID Agent -> GameComputation Identity [GID Agent]
getWitnesses actorGid = do
  aMap <- use (world . agentMap . getAgentMap)
  case lookup actorGid aMap of
    Nothing -> pure []
    Just actor -> do
      let sceneGid = view agentCurrentScene actor
      sMap <- use (world . sceneMap . getGIDToDataMap)
      case lookup sceneGid sMap of
        Nothing -> pure []
        Just scene ->
          let otherGids = filter (/= actorGid) (toList (view sceneAgents scene))
          in pure [ gid
                  | gid <- otherGids
                  , Just agent <- [lookup gid aMap]
                  , view agentKind agent == PlayerAgent
                  ]

lookupImplicitStimulus :: ImplicitStimulusVerb
                       -> ActionManagementFunctions
                       -> Maybe (GID ImplicitStimulusF)
lookupImplicitStimulus verb (ActionManagementFunctions actions) =
  listToMaybe [gid | ISAManagementKey v gid <- toList actions, v == verb]
