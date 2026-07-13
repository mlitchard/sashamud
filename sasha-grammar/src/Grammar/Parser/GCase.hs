{-# OPTIONS_GHC -Wno-unrecognised-pragmas #-}
{-# HLINT ignore "Use newtype instead of data" #-}

module Grammar.Parser.GCase
  ( VerbKey (ImplicitStimulusKey)
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Generics (Generic)
import           GHC.Show (Show)
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)

type VerbKey :: Type
data VerbKey = ImplicitStimulusKey ImplicitStimulusVerb
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
