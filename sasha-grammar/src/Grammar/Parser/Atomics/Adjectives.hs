module Grammar.Parser.Atomics.Adjectives
  ( Adjective
      ( Adjective
      , _fromAdjective
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type Adjective :: Type
newtype Adjective = Adjective { _fromAdjective :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme Adjective where
  toLexeme = _fromAdjective
