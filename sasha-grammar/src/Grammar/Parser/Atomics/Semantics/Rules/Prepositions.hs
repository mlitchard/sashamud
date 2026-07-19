module Grammar.Parser.Atomics.Semantics.Rules.Prepositions
  ( directionalStimulusMarkerRule
  ) where

import           Data.HashSet (HashSet)
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Prepositions
  ( DirectionalStimulusMarker (DirectionalStimulusMarker)
  )
import           Grammar.Parser.Atomics.Semantics.Rules.ParseRule (parseRule)
import           Text.Earley.Grammar (Grammar, Prod)

directionalStimulusMarkerRule :: HashSet DirectionalStimulusMarker -> Grammar r (Prod r Text Lexeme DirectionalStimulusMarker)
directionalStimulusMarkerRule markers = parseRule markers DirectionalStimulusMarker
