module Grammar.Parser.Atomics.Prepositions
  ( DirectionalStimulusMarker
      ( DirectionalStimulusMarker
      , _fromDirectionalStimulusMarker
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type DirectionalStimulusMarker :: Type
newtype DirectionalStimulusMarker = DirectionalStimulusMarker { _fromDirectionalStimulusMarker :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme DirectionalStimulusMarker where
  toLexeme = _fromDirectionalStimulusMarker
