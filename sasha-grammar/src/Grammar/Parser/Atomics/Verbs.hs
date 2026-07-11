module Grammar.Parser.Atomics.Verbs
  ( ImplicitStimulusVerb
      ( ImplicitStimulusVerb
      , _fromImplicitStimulusVerb
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type ImplicitStimulusVerb :: Type
newtype ImplicitStimulusVerb = ImplicitStimulusVerb { _fromImplicitStimulusVerb :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme ImplicitStimulusVerb where
  toLexeme = _fromImplicitStimulusVerb
