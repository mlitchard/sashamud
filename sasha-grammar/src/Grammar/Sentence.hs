module Grammar.Sentence
  ( parseTokens
  , sentenceRules
  ) where

import           Data.Either (Either (Left, Right))
import           Data.Function ((.))

import           Data.Functor ((<$>))
import           Data.Semigroup ((<>))
import           Data.Text (Text, pack, unwords)
import           Data.Tuple (fst)
import           GHC.Show (show)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Composites.Model (Sentence (Imperative))
import           Grammar.Parser.Composites.Rules (imperativeRules)
import           Text.Earley.Grammar (Grammar, Prod, rule)
import           Text.Earley.Parser (fullParses, parser)

parseTokens :: [Lexeme] -> Either Text Sentence
parseTokens toks =
  case sparsed of
    (parsed':_) -> Right parsed'
    []          -> Left ("Nonsense in parsed tokens " <> toks')
  where
    sparsed = fst (fullParses (parser sentenceRules) toks)
    toks' = unwords (pack . show <$> toks)

sentenceRules :: Grammar r (Prod r Text Lexeme Sentence)
sentenceRules = do
  imperative <- imperativeRules
  rule (Imperative <$> imperative)
