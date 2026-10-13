module Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( acquisitionVerbRule
  , directionalStimulusVerbRule
  , divestmentVerbRule
  , implicitStimulusVerbRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb (AcquisitionVerb)
  , DirectionalStimulusVerb (DirectionalStimulusVerb)
  , DivestmentVerb (DivestmentVerb)
  , ImplicitStimulusVerb (ImplicitStimulusVerb)
  )
import           Text.Earley.Grammar (Grammar, Prod)

acquisitionVerbRule :: HashSet AcquisitionVerb -> Grammar r (Prod r Text Lexeme AcquisitionVerb)
acquisitionVerbRule verbs = parseRule verbs AcquisitionVerb

divestmentVerbRule :: HashSet DivestmentVerb -> Grammar r (Prod r Text Lexeme DivestmentVerb)
divestmentVerbRule verbs = parseRule verbs DivestmentVerb

directionalStimulusVerbRule :: HashSet DirectionalStimulusVerb -> Grammar r (Prod r Text Lexeme DirectionalStimulusVerb)
directionalStimulusVerbRule verbs = parseRule verbs DirectionalStimulusVerb

implicitStimulusVerbRule :: HashSet ImplicitStimulusVerb -> Grammar r (Prod r Text Lexeme ImplicitStimulusVerb)
implicitStimulusVerbRule verbs = parseRule verbs ImplicitStimulusVerb
