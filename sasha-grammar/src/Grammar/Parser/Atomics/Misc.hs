module Grammar.Parser.Atomics.Misc
  ( Determiner
      ( Determiner
      , _fromDeterminer
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type Determiner :: Type
newtype Determiner = Determiner { _fromDeterminer :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme Determiner where
  toLexeme = _fromDeterminer
