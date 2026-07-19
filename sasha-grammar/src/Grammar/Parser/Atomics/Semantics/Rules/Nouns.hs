module Grammar.Parser.Atomics.Semantics.Rules.Nouns
  ( directionalStimulusRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus (DirectionalStimulus)
  )
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Text.Earley.Grammar (Grammar, Prod)

directionalStimulusRule :: HashSet DirectionalStimulus -> Grammar r (Prod r Text Lexeme DirectionalStimulus)
directionalStimulusRule nouns = parseRule nouns DirectionalStimulus
