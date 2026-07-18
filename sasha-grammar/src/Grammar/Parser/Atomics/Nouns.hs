module Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus
      ( DirectionalStimulus
      , _fromDirectionalStimulus
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type DirectionalStimulus :: Type
newtype DirectionalStimulus = DirectionalStimulus { _fromDirectionalStimulus :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme DirectionalStimulus where
  toLexeme = _fromDirectionalStimulus
