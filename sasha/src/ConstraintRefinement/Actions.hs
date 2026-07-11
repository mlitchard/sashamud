module ConstraintRefinement.Actions
  ( lookF
  , lookDeniedF
  ) where

import           Engine.Resolution.ActionManagement (processActionEffects)
import           Model.Core
  ( ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  )

lookF :: ImplicitStimulusF
lookF = ImplicitStimulusF processActionEffects

lookDeniedF :: ImplicitStimulusF
lookDeniedF = ImplicitNoStimulusF processActionEffects
