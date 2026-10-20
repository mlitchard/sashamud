{- HLINT ignore "Use newtype instead of data" -}
module Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase, PlayerDirectionalStimulusNounPhrase)
  , NounPhrase (SimpleNounPhrase, NounPhrase, DescriptiveNounPhrase, DescriptiveNounPhraseDet)
  , ObjectPhrase (ObjectPhrase)
  , PlayerName (PlayerName)
  , PlayerNamePhrase (PlayerNamePhrase)
  ) where

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Eq (Eq)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           Data.Text (Text)
import           GHC.Generics (Generic)
import           GHC.Show (Show)
import           Grammar.Parser.Atomics.Adjectives (Adjective)
import           Grammar.Parser.Atomics.Misc (Determiner)
import           Grammar.Parser.Atomics.Nouns (DirectionalStimulus, Objective)
import           Grammar.Parser.Atomics.Prepositions (DirectionalStimulusMarker)

type NounPhrase :: Type -> Type
data NounPhrase a = SimpleNounPhrase a
                  | NounPhrase Determiner a
                  | DescriptiveNounPhrase Adjective a
                  | DescriptiveNounPhraseDet Determiner Adjective a
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type ObjectPhrase :: Type
newtype ObjectPhrase = ObjectPhrase (NounPhrase Objective)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (NFData)

type DirectionalStimulusNounPhrase :: Type
data DirectionalStimulusNounPhrase = DirectionalStimulusNounPhrase DirectionalStimulusMarker (NounPhrase DirectionalStimulus)
                                   | PlayerDirectionalStimulusNounPhrase DirectionalStimulusMarker PlayerNamePhrase
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type PlayerName :: Type
newtype PlayerName = PlayerName Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type PlayerNamePhrase :: Type
newtype PlayerNamePhrase = PlayerNamePhrase (NounPhrase PlayerName)
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)
