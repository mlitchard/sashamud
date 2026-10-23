{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Grammar.Parser.GCase
  ( NounKey (DirectionalStimulusKey, DirectionalStimulusPlayerKey, ObjectiveKey)
  , VerbKey (ImperativeKey, ImplicitStimulusKey, AcquisitionKey, DivestmentKey)
  ) where

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, FromJSONKey, ToJSON, ToJSONKey)
import           Data.Eq (Eq)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Generics (Generic)
import           GHC.Show (Show)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus
  , DirectionalStimulusPlayer
  , Objective
  )
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )

type NounKey :: Type
data NounKey = DirectionalStimulusKey DirectionalStimulus
             | DirectionalStimulusPlayerKey DirectionalStimulusPlayer
             | ObjectiveKey Objective
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type VerbKey :: Type
data VerbKey = ImperativeKey DirectionalStimulusVerb
             | ImplicitStimulusKey ImplicitStimulusVerb
             | AcquisitionKey AcquisitionVerb
             | DivestmentKey DivestmentVerb
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, FromJSONKey, NFData, ToJSON, ToJSONKey)
