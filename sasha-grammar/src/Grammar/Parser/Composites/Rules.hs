module Grammar.Parser.Composites.Rules
  ( stimulusVerbPhraseRules
  , imperativeRules
  ) where

import           Control.Applicative ((<*>), (<|>))
import           Data.Function (($))
import           Data.Functor ((<$>))
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus
  ( directionalStimuli
  )
import           Grammar.Parser.Atomics.Semantics.Prepositions.DirectionalStimulusMarker
  ( directionalStimulusMarkers
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Nouns
  ( directionalStimulusRule
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Prepositions
  ( directionalStimulusMarkerRule
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( directionalStimulusVerbRule
  , implicitStimulusVerbRule
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.DirectionalStimulus
  ( directionalStimulusVerbs
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( implicitStimulusVerbs
  )
import           Grammar.Parser.Composites.Model
  ( Imperative (StimulusVerbPhrase)
  , StimulusVerbPhrase (DirectStimulusVerbPhrase, ImplicitStimulusVerb)
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase)
  , NounPhrase (SimpleNounPhrase)
  )
import           Text.Earley.Grammar (Grammar, Prod, rule)

stimulusVerbPhraseRules :: Grammar r (Prod r Text Lexeme StimulusVerbPhrase)
stimulusVerbPhraseRules = do
  implicitStimulusVerb <- implicitStimulusVerbRule implicitStimulusVerbs
  directionalStimulusVerb <- directionalStimulusVerbRule directionalStimulusVerbs
  directionalStimulusMarker <- directionalStimulusMarkerRule directionalStimulusMarkers
  directionalStimulus <- directionalStimulusRule directionalStimuli
  rule $ ImplicitStimulusVerb <$> implicitStimulusVerb
     <|> DirectStimulusVerbPhrase
           <$> directionalStimulusVerb
           <*> (DirectionalStimulusNounPhrase
                  <$> directionalStimulusMarker
                  <*> (SimpleNounPhrase <$> directionalStimulus))

imperativeRules :: Grammar r (Prod r Text Lexeme Imperative)
imperativeRules = do
  stimulusVerbPhrase <- stimulusVerbPhraseRules
  rule (StimulusVerbPhrase <$> stimulusVerbPhrase)
