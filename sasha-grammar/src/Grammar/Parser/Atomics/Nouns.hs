module Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus
      ( DirectionalStimulus
      , _fromDirectionalStimulus
      )
  , DirectionalStimulusPlayer
      ( DirectionalStimulusPlayer
      , _fromDirectionalStimulusPlayer
      )
  , Objective
      ( Objective
      , _fromObjective
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type DirectionalStimulus :: Type
newtype DirectionalStimulus = DirectionalStimulus { _fromDirectionalStimulus :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (FromJSON, Hashable, NFData, ToJSON)

instance HasLexeme DirectionalStimulus where
  toLexeme = _fromDirectionalStimulus

type DirectionalStimulusPlayer :: Type
newtype DirectionalStimulusPlayer = DirectionalStimulusPlayer { _fromDirectionalStimulusPlayer :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (FromJSON, Hashable, NFData, ToJSON)

instance HasLexeme DirectionalStimulusPlayer where
  toLexeme = _fromDirectionalStimulusPlayer

type Objective :: Type
newtype Objective = Objective { _fromObjective :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme Objective where
  toLexeme = _fromObjective
