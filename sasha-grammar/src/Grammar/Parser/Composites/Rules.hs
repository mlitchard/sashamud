module Grammar.Parser.Composites.Rules
  ( NounPhraseRules (NounPhraseRules, _determinerRule, _adjRule, _nounRule)
  , nounPhraseRule
  , objectPhraseRules
  , acquisitionVerbPhraseRules
  , divestmentVerbPhraseRules
  , stimulusVerbPhraseRules
  , imperativeRules
  ) where

import           Control.Applicative ((<*), (<*>), (<|>))
import           Control.Monad ((>>=))
import           Data.Function (($))
import           Data.Functor ((<$>))
import           Data.Kind (Type)
import           Data.Maybe (Maybe (Just, Nothing))
import           Data.Text (Text)
import           Grammar.Lexer (Lexeme (PLAYERNAME))
import           Grammar.Parser.Atomics.Adjectives (Adjective)
import           Grammar.Parser.Atomics.Misc (Determiner)
import           Grammar.Parser.Atomics.Nouns (Objective)
import           Grammar.Parser.Atomics.Semantics.Adjectives (adjectives)
import           Grammar.Parser.Atomics.Semantics.Misc (determiners)
import           Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus
  ( directionalStimuli
  )
import           Grammar.Parser.Atomics.Semantics.Nouns.Objective (objectives)
import           Grammar.Parser.Atomics.Semantics.Prepositions.DirectionalStimulusMarker
  ( directionalStimulusMarkers
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Adjectives
  ( adjectiveRule
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Misc (determinerRule)
import           Grammar.Parser.Atomics.Semantics.Rules.Nouns
  ( directionalStimulusRule
  , objectiveRule
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Prepositions
  ( directionalStimulusMarkerRule
  )
import           Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( acquisitionVerbRule
  , directionalStimulusVerbRule
  , divestmentVerbRule
  , implicitStimulusVerbRule
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.Acquisition
  ( acquisitionVerbs
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.DirectionalStimulus
  ( directionalStimulusVerbs
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.Divestment
  ( divestmentVerbs
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( implicitStimulusVerbs
  )
import           Grammar.Parser.Composites.Model
  ( AcquisitionVerbPhrase (SimpleAcquisitionVerbPhrase)
  , DivestmentVerbPhrase (SimpleDivestmentVerbPhrase)
  , Imperative (AcquisitionVerbPhrase', DivestmentVerbPhrase', StimulusVerbPhrase)
  , StimulusVerbPhrase (AgentStimulusVerbPhrase, DirectStimulusVerbPhrase, ImplicitStimulusVerb)
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase (DirectionalStimulusNounPhrase)
  , NounPhrase (DescriptiveNounPhrase, DescriptiveNounPhraseDet, NounPhrase, SimpleNounPhrase)
  , ObjectPhrase (ObjectPhrase)
  , PlayerName (PlayerName)
  )
import           Text.Earley.Grammar (Grammar, Prod, rule, terminal)

type NounPhraseRules :: Type -> (Type -> Type -> Type -> Type) -> Type
data NounPhraseRules a r = NounPhraseRules
  { _determinerRule :: Prod r Text Lexeme Determiner
  , _adjRule        :: Prod r Text Lexeme Adjective
  , _nounRule       :: Prod r Text Lexeme a
  }

nounPhraseRule :: NounPhraseRules a r
                    -> Grammar r (Prod r Text Lexeme (NounPhrase a))
nounPhraseRule (NounPhraseRules determinerRule' adjRule' nounRule') =
  rule $ SimpleNounPhrase <$> nounRule'
           <|> NounPhrase <$> determinerRule' <*> nounRule'
           <|> DescriptiveNounPhrase <$> adjRule' <*> nounRule'
           <|> DescriptiveNounPhraseDet
                 <$> determinerRule'
                 <*> adjRule'
                 <*> nounRule'

objectPhraseRules :: Prod r Text Lexeme Determiner
                       -> Prod r Text Lexeme Adjective
                       -> Prod r Text Lexeme Objective
                       -> Grammar r (Prod r Text Lexeme ObjectPhrase)
objectPhraseRules determinerRule' adjRule' objectiveRule' =
  nounPhraseRule rules >>= \nounPhrase ->
    rule $ ObjectPhrase <$> nounPhrase
  where
   rules
      = NounPhraseRules
          { _determinerRule = determinerRule'
          , _adjRule = adjRule'
          , _nounRule = objectiveRule'
          }

acquisitionVerbPhraseRules :: Grammar r (Prod r Text Lexeme AcquisitionVerbPhrase)
acquisitionVerbPhraseRules = do
  determiner <- determinerRule determiners
  adj <- adjectiveRule adjectives
  acquisitionVerb <- acquisitionVerbRule acquisitionVerbs
  object <- objectiveRule objectives
  objectPhrase <- objectPhraseRules determiner adj object
  rule $ SimpleAcquisitionVerbPhrase
           <$> acquisitionVerb
           <*> objectPhrase

divestmentVerbPhraseRules :: Grammar r (Prod r Text Lexeme DivestmentVerbPhrase)
divestmentVerbPhraseRules = do
  determiner <- determinerRule determiners
  adj <- adjectiveRule adjectives
  divestmentVerb <- divestmentVerbRule divestmentVerbs
  object <- objectiveRule objectives
  objectPhrase <- objectPhraseRules determiner adj object
  rule $ SimpleDivestmentVerbPhrase
           <$> divestmentVerb
           <*> objectPhrase

stimulusVerbPhraseRules :: Grammar r (Prod r Text Lexeme StimulusVerbPhrase)
stimulusVerbPhraseRules = do
  implicitStimulusVerb <- implicitStimulusVerbRule implicitStimulusVerbs
  directionalStimulusVerb <- directionalStimulusVerbRule directionalStimulusVerbs
  directionalStimulusMarker <- directionalStimulusMarkerRule directionalStimulusMarkers
  directionalStimulus <- directionalStimulusRule directionalStimuli
  playerName <- playerNameRule
  rule $ ImplicitStimulusVerb <$> implicitStimulusVerb
     <|> DirectStimulusVerbPhrase
           <$> directionalStimulusVerb
           <*> (DirectionalStimulusNounPhrase
                  <$> directionalStimulusMarker
                  <*> (SimpleNounPhrase <$> directionalStimulus))
     <|> AgentStimulusVerbPhrase
           <$> directionalStimulusVerb
           <* directionalStimulusMarker
           <*> playerName

playerNameRule :: Grammar r (Prod r Text Lexeme PlayerName)
playerNameRule = rule (terminal (\case
    PLAYERNAME txt -> Just (PlayerName txt)
    _              -> Nothing))

imperativeRules :: Grammar r (Prod r Text Lexeme Imperative)
imperativeRules = do
  stimulusVerbPhrase <- stimulusVerbPhraseRules
  acquisitionVerbPhrase <- acquisitionVerbPhraseRules
  divestmentVerbPhrase <- divestmentVerbPhraseRules
  rule $ StimulusVerbPhrase <$> stimulusVerbPhrase
     <|> AcquisitionVerbPhrase' <$> acquisitionVerbPhrase
     <|> DivestmentVerbPhrase' <$> divestmentVerbPhrase
