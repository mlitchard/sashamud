{- HLINT ignore "Avoid restricted function" -}
module Grammar.Lexer
  ( Lexeme (..)
  , HasLexeme (..)
  , Lexer (Lexer, runLexer)
  , lexify
  , tokens
  ) where

import           Control.Applicative
  ( Alternative
  , Applicative
  , many
  , some
  , (*>)
  , (<*)
  )
import           Control.DeepSeq (NFData)
import           Control.Monad (Monad, MonadPlus, void)
import           Data.Either (Either (Left, Right))
import           Data.Eq (Eq)
import           Data.Functor (Functor, (<$>))
import           Data.Hashable (Hashable)
import           Data.Kind (Constraint, Type)
import           Data.Ord (Ord)
import           Data.Text (Text, pack, toUpper)
import           Data.Void (Void)
import           GHC.Enum
  ( Bounded (maxBound, minBound)
  , Enum (fromEnum, toEnum)
  )
import           GHC.Err (error)
import           GHC.Generics (Generic)
import           GHC.Show (Show)
import           Text.Megaparsec (Parsec, eof, errorBundlePretty, parse)
import           Text.Megaparsec.Char (alphaNumChar, spaceChar)
import           Text.Megaparsec.Char.Lexer
  ( skipBlockComment
  , skipLineComment
  , space
  )

type Lexer :: Type -> Type
newtype Lexer a = Lexer { runLexer :: Parsec Void Text a }
  deriving newtype (Alternative, Applicative, Functor, Monad, MonadPlus)

type Lexeme :: Type
data Lexeme = AT
            | BALL
            | FLOOR
            | LOOK
            | PLAYERNAME Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (Hashable, NFData)

instance Bounded Lexeme where
  minBound = AT
  maxBound = LOOK

instance Enum Lexeme where
  toEnum 0 = AT
  toEnum 1 = BALL
  toEnum 2 = FLOOR
  toEnum 3 = LOOK
  toEnum _ = error "toEnum: no Lexeme at this index"

  fromEnum AT             = 0
  fromEnum BALL           = 1
  fromEnum FLOOR          = 2
  fromEnum LOOK           = 3
  fromEnum (PLAYERNAME _) = 4

type HasLexeme :: Type -> Constraint
class HasLexeme a where
  toLexeme :: a -> Lexeme

lexify :: Lexer a -> Text -> Either Text a
lexify (Lexer parser) txt =
  case parse parser "" (toUpper txt) of
    Left err  -> Left (pack (errorBundlePretty err))
    Right res -> Right res

sc :: Lexer ()
sc = Lexer (space (void spaceChar) lineCmnt blockCmnt)
  where
    lineCmnt :: Parsec Void Text ()
    lineCmnt = skipLineComment "//"
    blockCmnt :: Parsec Void Text ()
    blockCmnt = skipBlockComment "/*" "*/"

term :: Lexer Lexeme
term = classify <$> word
  where
    classify :: Text -> Lexeme
    classify "AT"    = AT
    classify "BALL"  = BALL
    classify "FLOOR" = FLOOR
    classify "LOOK"  = LOOK
    classify w       = PLAYERNAME w

word :: Lexer Text
word = Lexer (pack <$> some alphaNumChar) <* sc

tokens :: Lexer [Lexeme]
tokens = sc *> many term <* Lexer eof
