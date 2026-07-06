{- HLINT ignore "Avoid restricted function" -}
module Test.Lexer (spec) where

import           Data.Bool (Bool (False, True))
import           Data.Either (Either (Left, Right))
import           Data.Function ((.))
import           Data.Functor ((<$>))
import           Data.Semigroup ((<>))
import           Data.Text (Text, pack, unpack, unwords)
import           Debug.Trace (trace)
import           GHC.Enum (Bounded (maxBound, minBound), Enum (enumFromTo))
import           GHC.Show (Show (show))
import           Grammar.Lexer (Lexeme, lexify, tokens)
import           Test.Hspec (Spec, describe, it, shouldBe)

lexemes :: [Lexeme]
lexemes = enumFromTo minBound maxBound

spec :: Spec
spec = describe "check lexer" (it "lexer parses all tokens" (checkLexer `shouldBe` True))

toText :: (Show a) => a -> Text
toText = pack . show

checkLexer :: Bool
checkLexer = case lexify tokens (unwords (toText <$> lexemes)) of
  Left err -> trace ("ERROR: " <> unpack err) False
  Right _  -> True
