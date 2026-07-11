module Grammar.Parser.Composites.Rules
  ( stimulusVerbPhraseRules
  , imperativeRules
  ) where

import           Data.Functor ((<$>))
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( implicitStimulusVerbRule
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( implicitStimulusVerbs
  )
import           Grammar.Parser.Composites.Model
  ( Imperative (StimulusVerbPhrase)
  , StimulusVerbPhrase (ImplicitStimulusVerb)
  )
import           Text.Earley.Grammar (Grammar, Prod, rule)

stimulusVerbPhraseRules :: Grammar r (Prod r Text Lexeme StimulusVerbPhrase)
stimulusVerbPhraseRules = do
  implicitStimulusVerb <- implicitStimulusVerbRule implicitStimulusVerbs
  rule (ImplicitStimulusVerb <$> implicitStimulusVerb)

imperativeRules :: Grammar r (Prod r Text Lexeme Imperative)
imperativeRules = do
  stimulusVerbPhrase <- stimulusVerbPhraseRules
  rule (StimulusVerbPhrase <$> stimulusVerbPhrase)
