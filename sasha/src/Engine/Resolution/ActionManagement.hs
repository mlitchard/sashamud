module Engine.Resolution.ActionManagement
  ( processActionEffects
  , processWitnesses
  , processWitnessEffects
  , lookupImplicitStimulus
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
import           Error (throwMaybeM)
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Grammar.Parser.GCase (VerbKey)
import           Lens.Micro.Platform (over, use, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement (ISAManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookNarration, StaticNarration)
  , WitnessEffectF
  , WitnessF (WitnessF)
  , WorldOutcome (NarrationEffect)
  , actionConsequence
  , agentLocationMap
  , agentMap
  , agentWitnessManagement
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

processNarrationEffect :: GID Agent -> NarrationComputation -> GameComputation Identity ()
processNarrationEffect actorGid LookNarration = youSeeM actorGid
processNarrationEffect actorGid (StaticNarration text) =
  modifyAgentNarration actorGid (over actionConsequence (<> [colored White text]))

processWitnesses :: GID Agent -> VerbKey -> GameComputation Identity ()
processWitnesses actorGid verbKey = do
  locMap <- use agentLocationMap
  sceneGid <- throwMaybeM ("Agent location not found: " <> pack (show actorGid))
                (lookup actorGid locMap)
  sMap <- use (world . sceneMap . getGIDToDataMap)
  scene <- throwMaybeM ("Scene not found: " <> pack (show sceneGid))
             (lookup sceneGid sMap)
  aMap <- use (world . agentMap . getAgentMap)
  wMap <- asks (view (ctxPossibilityGraph . witnessMap))
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
          WitnessF wf -> wf witnessGid actorGid

processWitnessEffects :: WitnessEffectF
processWitnessEffects = witnessLookM

lookupImplicitStimulus :: ImplicitStimulusVerb
                       -> ActionManagementFunctions
                       -> Maybe (GID ImplicitStimulusF)
lookupImplicitStimulus verb (ActionManagementFunctions actions) =
  listToMaybe [gid | ISAManagementKey v gid <- toList actions, v == verb]
