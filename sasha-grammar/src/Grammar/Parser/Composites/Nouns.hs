{- HLINT ignore "Use newtype instead of data" -}
module Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase)
  , NounPhrase (SimpleNounPhrase)
  , PlayerName (PlayerName)
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           Data.Text (Text)
import           GHC.Generics (Generic)
import           GHC.Show (Show)
import           Grammar.Parser.Atomics.Nouns (DirectionalStimulus)
import           Grammar.Parser.Atomics.Prepositions (DirectionalStimulusMarker)

type NounPhrase :: Type -> Type
data NounPhrase a = SimpleNounPhrase a
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type DirectionalStimulusNounPhrase :: Type
data DirectionalStimulusNounPhrase = DirectionalStimulusNounPhrase DirectionalStimulusMarker (NounPhrase DirectionalStimulus)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type PlayerName :: Type
newtype PlayerName = PlayerName Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)
