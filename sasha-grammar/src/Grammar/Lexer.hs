module Grammar.Lexer
  ( Lexeme (..)
  , HasLexeme (..)
  , Lexer (Lexer, runLexer)
  , lexify
  , tokens
  ) where

import           Control.Applicative (Alternative, many)
import           Control.DeepSeq (NFData)
import           Control.Monad (MonadPlus, void)
import           Data.Hashable (Hashable)
import           Data.Kind (Constraint, Type)
import           Data.Text (Text, pack, toUpper)
import           Data.Void (Void)
import           GHC.Generics (Generic)
import           Text.Megaparsec (Parsec, eof, errorBundlePretty, parse)
import           Text.Megaparsec.Char (spaceChar)
import           Text.Megaparsec.Char.Lexer
  ( skipBlockComment
  , skipLineComment
  , space
  , symbol
  )

type Lexer :: Type -> Type
newtype Lexer a = Lexer { runLexer :: Parsec Void Text a }
  deriving newtype (Alternative, Applicative, Functor, Monad, MonadPlus)

type Lexeme :: Type
data Lexeme
  = LOOK
  deriving stock (Bounded, Enum, Eq, Generic, Ord, Show)
  deriving anyclass (Hashable, NFData)

type HasLexeme :: Type -> Constraint
class HasLexeme a where
  toLexeme :: a -> Lexeme

lexify :: Lexer a -> Text -> Either Text a
lexify (Lexer parser) txt =
  case parse parser "" (toUpper txt) of
    Left err  -> Left (pack (errorBundlePretty err))
    Right res -> Right res

sym :: Text -> Lexer Text
sym = Lexer . symbol (runLexer sc)

sc :: Lexer ()
sc = Lexer (space (void spaceChar) lineCmnt blockCmnt)
  where
    lineCmnt :: Parsec Void Text ()
    lineCmnt = skipLineComment "//"
    blockCmnt :: Parsec Void Text ()
    blockCmnt = skipBlockComment "/*" "*/"

term :: Lexer Lexeme
term = LOOK <$ sym "LOOK"

tokens :: Lexer [Lexeme]
tokens = sc *> many term <* Lexer eof
