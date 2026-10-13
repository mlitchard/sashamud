module Grammar.Parser.Atomics.Semantics.Rules.Misc
  ( determinerRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Misc (Determiner (Determiner))
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Text.Earley.Grammar (Grammar, Prod)

determinerRule :: HashSet Determiner -> Grammar r (Prod r Text Lexeme Determiner)
determinerRule dets = parseRule dets Determiner
