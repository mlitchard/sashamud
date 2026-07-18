module ConstraintRefinement.Actions
  ( lookF
  , lookDeniedF
  , witnessF
  ) where

import           Engine.Resolution.ActionManagement
  ( processActionOutcomeRegistry
  , processWitnessEffects
  )
import           Model.Core
  ( ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , WitnessF (WitnessF)
  )

lookF :: ImplicitStimulusF
lookF = ImplicitStimulusF processActionOutcomeRegistry

lookDeniedF :: ImplicitStimulusF
lookDeniedF = ImplicitNoStimulusF processActionOutcomeRegistry

witnessF :: WitnessF
witnessF = WitnessF processWitnessEffects
