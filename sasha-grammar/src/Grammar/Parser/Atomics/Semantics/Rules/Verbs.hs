module Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( implicitStimulusVerbRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Grammar.Parser.Atomics.Verbs
  ( ImplicitStimulusVerb (ImplicitStimulusVerb)
  )
import           Text.Earley.Grammar (Grammar, Prod)

implicitStimulusVerbRule :: HashSet ImplicitStimulusVerb -> Grammar r (Prod r Text Lexeme ImplicitStimulusVerb)
implicitStimulusVerbRule verbs = parseRule verbs ImplicitStimulusVerb
