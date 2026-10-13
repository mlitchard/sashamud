module Grammar.Parser.Atomics.Semantics.Rules.Adjectives
  ( adjectiveRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Adjectives (Adjective (Adjective))
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Text.Earley.Grammar (Grammar, Prod)

adjectiveRule :: HashSet Adjective -> Grammar r (Prod r Text Lexeme Adjective)
adjectiveRule adjs = parseRule adjs Adjective
