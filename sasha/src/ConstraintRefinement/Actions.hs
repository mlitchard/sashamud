module ConstraintRefinement.Actions
  ( lookF
  , lookDeniedF
  , witnessF
  ) where

import           Engine.Resolution.ActionManagement
  ( processActionEffects
  , processWitnessEffects
  )
import           Model.Core
  ( ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , WitnessF (WitnessF)
  )

lookF :: ImplicitStimulusF
lookF = ImplicitStimulusF processActionEffects

lookDeniedF :: ImplicitStimulusF
lookDeniedF = ImplicitNoStimulusF processActionEffects

witnessF :: WitnessF
witnessF = WitnessF processWitnessEffects
