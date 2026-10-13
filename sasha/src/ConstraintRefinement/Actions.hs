module ConstraintRefinement.Actions
  ( lookAtF
  , lookAtDeniedF
  , lookF
  , lookDeniedF
  , getF
  , getDeniedF
  , dropF
  , dropDeniedF
  , witnessF
  ) where

import           Engine.Resolution.ActionManagement
  ( processActionOutcomeRegistry
  , processWitnessEffects
  )
import           Model.Core
  ( AcquisitionF (AcquisitionCannotF, AcquisitionF)
  , DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , DivestmentF (DivestmentCannotF, DivestmentF)
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

getF :: AcquisitionF
getF = AcquisitionF processActionOutcomeRegistry

getDeniedF :: AcquisitionF
getDeniedF = AcquisitionCannotF processActionOutcomeRegistry

dropF :: DivestmentF
dropF = DivestmentF processActionOutcomeRegistry

dropDeniedF :: DivestmentF
dropDeniedF = DivestmentCannotF processActionOutcomeRegistry

witnessF :: WitnessF
witnessF = WitnessF processWitnessEffects
