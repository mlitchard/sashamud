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
import           Lens.Micro.Platform (over, view)
import           Model.Core
  ( ActionEffectKey
  , ActionManagement (ISAManagementKey)
  , ActionManagementFunctions (ActionManagementFunctions)
  , Agent
  , GameComputation
  , ImplicitStimulusF
  , NarrationComputation (LookNarration, StaticNarration)
  , WorldOutcome (NarrationEffect)
  , actionConsequence
  , ctxPossibilityGraph
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
  modifyAgentNarration actorGid (over actionConsequence (colored White text :))

lookupImplicitStimulus :: ImplicitStimulusVerb
                       -> ActionManagementFunctions
                       -> Maybe (GID ImplicitStimulusF)
lookupImplicitStimulus verb (ActionManagementFunctions actions) =
  listToMaybe [gid | ISAManagementKey v gid <- toList actions, v == verb]
