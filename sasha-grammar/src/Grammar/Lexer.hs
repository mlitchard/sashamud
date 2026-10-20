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
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Either (Either (Left, Right))
import           Data.Eq (Eq)
import           Data.Functor (Functor, (<$>))
import           Data.Hashable (Hashable)
import           Data.Kind (Constraint, Type)
import           Data.Ord (Ord)
import           Data.Text (Text, pack)
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
data Lexeme = A
            | AT
            | BALL
            | CUP
            | DROP
            | FLOOR
            | GET
            | LOOK
            | RED
            | SMALL
            | TABLE
            | THE
            | WHITE
            | AGENTNAME Text
            | UNKNOWN Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, Hashable, NFData, ToJSON)

instance Bounded Lexeme where
  minBound = A
  maxBound = WHITE

instance Enum Lexeme where
  toEnum 0  = A
  toEnum 1  = AT
  toEnum 2  = BALL
  toEnum 3  = CUP
  toEnum 4  = DROP
  toEnum 5  = FLOOR
  toEnum 6  = GET
  toEnum 7  = LOOK
  toEnum 8  = RED
  toEnum 9  = SMALL
  toEnum 10 = TABLE
  toEnum 11 = THE
  toEnum 12 = WHITE
  toEnum _  = error "toEnum: no Lexeme at this index"

  fromEnum A             = 0
  fromEnum AT            = 1
  fromEnum BALL          = 2
  fromEnum CUP           = 3
  fromEnum DROP          = 4
  fromEnum FLOOR         = 5
  fromEnum GET           = 6
  fromEnum LOOK          = 7
  fromEnum RED           = 8
  fromEnum SMALL         = 9
  fromEnum TABLE         = 10
  fromEnum THE           = 11
  fromEnum WHITE         = 12
  fromEnum (AGENTNAME _) = 13
  fromEnum (UNKNOWN _)   = 14

type HasLexeme :: Type -> Constraint
class HasLexeme a where
  toLexeme :: a -> Lexeme

lexify :: Lexer a -> Text -> Either Text a
lexify (Lexer parser) txt =
  case parse parser "" txt of
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
    classify "a"     = A
    classify "at"    = AT
    classify "ball"  = BALL
    classify "cup"   = CUP
    classify "drop"  = DROP
    classify "floor" = FLOOR
    classify "get"   = GET
    classify "look"  = LOOK
    classify "red"   = RED
    classify "small" = SMALL
    classify "table" = TABLE
    classify "the"   = THE
    classify "white" = WHITE
    classify w       = UNKNOWN w

word :: Lexer Text
word = Lexer (pack <$> some alphaNumChar) <* sc

tokens :: Lexer [Lexeme]
tokens = sc *> many term <* Lexer eof
