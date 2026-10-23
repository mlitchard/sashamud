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
  , ActionEffectKeyF (ActionEffectKeyF)
  , DirectionalStimulusF (DirectionalNoStimulusF, DirectionalStimulusF)
  , DivestmentF (DivestmentCannotF, DivestmentF)
  , ImplicitStimulusF (ImplicitNoStimulusF, ImplicitStimulusF)
  , WitnessEffectF (WitnessEffectF)
  , WitnessF (WitnessF)
  )

lookF :: ImplicitStimulusF
lookF = ImplicitStimulusF (ActionEffectKeyF processActionOutcomeRegistry)

lookDeniedF :: ImplicitStimulusF
lookDeniedF = ImplicitNoStimulusF (ActionEffectKeyF processActionOutcomeRegistry)

lookAtF :: DirectionalStimulusF
lookAtF = DirectionalStimulusF (ActionEffectKeyF processActionOutcomeRegistry)

lookAtDeniedF :: DirectionalStimulusF
lookAtDeniedF = DirectionalNoStimulusF (ActionEffectKeyF processActionOutcomeRegistry)

getF :: AcquisitionF
getF = AcquisitionF (ActionEffectKeyF processActionOutcomeRegistry)

getDeniedF :: AcquisitionF
getDeniedF = AcquisitionCannotF (ActionEffectKeyF processActionOutcomeRegistry)

dropF :: DivestmentF
dropF = DivestmentF (ActionEffectKeyF processActionOutcomeRegistry)

dropDeniedF :: DivestmentF
dropDeniedF = DivestmentCannotF (ActionEffectKeyF processActionOutcomeRegistry)

witnessF :: WitnessF
witnessF = WitnessF (WitnessEffectF processWitnessEffects)
