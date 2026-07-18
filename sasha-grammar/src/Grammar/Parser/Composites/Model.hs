{- HLINT ignore "Use newtype instead of data" -}
module Grammar.Parser.Composites.Model
  ( StimulusVerbPhrase (..)
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
  ( DirectionalStimulusVerb
  , ImplicitStimulusVerb
  )
import           Grammar.Parser.Composites.Nouns (DirectionalStimulusNounPhrase)

type StimulusVerbPhrase :: Type
data StimulusVerbPhrase = ImplicitStimulusVerb ImplicitStimulusVerb
                        | DirectStimulusVerbPhrase DirectionalStimulusVerb DirectionalStimulusNounPhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Imperative :: Type
data Imperative = StimulusVerbPhrase StimulusVerbPhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type Sentence :: Type
data Sentence = Imperative Imperative
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
