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
            | DROP
            | FLOOR
            | GET
            | LOOK
            | RED
            | SMALL
            | THE
            | WHITE
            | PLAYERNAME Text
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, Hashable, NFData, ToJSON)

instance Bounded Lexeme where
  minBound = A
  maxBound = WHITE

instance Enum Lexeme where
  toEnum 0  = A
  toEnum 1  = AT
  toEnum 2  = BALL
  toEnum 3  = DROP
  toEnum 4  = FLOOR
  toEnum 5  = GET
  toEnum 6  = LOOK
  toEnum 7  = RED
  toEnum 8  = SMALL
  toEnum 9  = THE
  toEnum 10 = WHITE
  toEnum _  = error "toEnum: no Lexeme at this index"

  fromEnum A              = 0
  fromEnum AT             = 1
  fromEnum BALL           = 2
  fromEnum DROP           = 3
  fromEnum FLOOR          = 4
  fromEnum GET            = 5
  fromEnum LOOK           = 6
  fromEnum RED            = 7
  fromEnum SMALL          = 8
  fromEnum THE            = 9
  fromEnum WHITE          = 10
  fromEnum (PLAYERNAME _) = 11

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
    classify "drop"  = DROP
    classify "floor" = FLOOR
    classify "get"   = GET
    classify "look"  = LOOK
    classify "red"   = RED
    classify "small" = SMALL
    classify "the"   = THE
    classify "white" = WHITE
    classify w       = PLAYERNAME w

word :: Lexer Text
word = Lexer (pack <$> some alphaNumChar) <* sc

tokens :: Lexer [Lexeme]
tokens = sc *> many term <* Lexer eof
