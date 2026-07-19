module ConstraintRefinement.Actions
  ( lookAtF
  , lookAtDeniedF
  , lookF
  , lookDeniedF
  , witnessF
  ) where

import           Engine.Resolution.ActionManagement
  ( processActionOutcomeRegistry
  , processWitnessEffects
  )
import           Model.Core
  ( DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , WitnessF (WitnessF)
  )

lookF :: ImplicitStimulusF
lookF = ImplicitStimulusF processActionOutcomeRegistry

lookDeniedF :: ImplicitStimulusF
lookDeniedF = ImplicitNoStimulusF processActionOutcomeRegistry

lookAtF :: DirectionalStimulusF
lookAtF = DirectionalStimulusF processActionOutcomeRegistry

lookAtDeniedF :: DirectionalStimulusF
lookAtDeniedF = DirectionalNoStimulusF processActionOutcomeRegistry

witnessF :: WitnessF
witnessF = WitnessF processWitnessEffects
