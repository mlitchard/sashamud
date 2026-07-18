module Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( directionalStimulusVerbRule
  , implicitStimulusVerbRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Grammar.Parser.Atomics.Verbs
  ( DirectionalStimulusVerb (DirectionalStimulusVerb)
  , ImplicitStimulusVerb (ImplicitStimulusVerb)
  )
import           Text.Earley.Grammar (Grammar, Prod)

directionalStimulusVerbRule :: HashSet DirectionalStimulusVerb -> Grammar r (Prod r Text Lexeme DirectionalStimulusVerb)
directionalStimulusVerbRule verbs = parseRule verbs DirectionalStimulusVerb

implicitStimulusVerbRule :: HashSet ImplicitStimulusVerb -> Grammar r (Prod r Text Lexeme ImplicitStimulusVerb)
implicitStimulusVerbRule verbs = parseRule verbs ImplicitStimulusVerb
