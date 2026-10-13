module Grammar.Parser.Atomics.Semantics.Rules.Nouns
  ( directionalStimulusRule
  , objectiveRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus (DirectionalStimulus)
  , Objective (Objective)
  )
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Text.Earley.Grammar (Grammar, Prod)

directionalStimulusRule :: HashSet DirectionalStimulus -> Grammar r (Prod r Text Lexeme DirectionalStimulus)
directionalStimulusRule nouns = parseRule nouns DirectionalStimulus

objectiveRule :: HashSet Objective -> Grammar r (Prod r Text Lexeme Objective)
objectiveRule nouns = parseRule nouns Objective
