{- HLINT ignore "Use newtype instead of data" -}
module Grammar.Parser.Composites.Model
  ( AcquisitionVerbPhrase (..)
  , DivestmentVerbPhrase (..)
  , StimulusVerbPhrase (..)
  , Imperative (..)
  , Sentence (..)
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Generics (Generic)
import           GHC.Show (Show)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DirectionalStimulusVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase
  , ObjectPhrase
  )

type AcquisitionVerbPhrase :: Type
data AcquisitionVerbPhrase = SimpleAcquisitionVerbPhrase AcquisitionVerb ObjectPhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type DivestmentVerbPhrase :: Type
data DivestmentVerbPhrase = SimpleDivestmentVerbPhrase DivestmentVerb ObjectPhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type StimulusVerbPhrase :: Type
data StimulusVerbPhrase = ImplicitStimulusVerb ImplicitStimulusVerb
                        | DirectStimulusVerbPhrase DirectionalStimulusVerb DirectionalStimulusNounPhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Imperative :: Type
data Imperative = StimulusVerbPhrase StimulusVerbPhrase
                | AcquisitionVerbPhrase' AcquisitionVerbPhrase
                | DivestmentVerbPhrase' DivestmentVerbPhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Sentence :: Type
data Sentence = Imperative Imperative
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
