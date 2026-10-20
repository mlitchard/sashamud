{-# OPTIONS_GHC -Wno-orphans #-}
{-# OPTIONS_GHC -fconstraint-solver-iterations=10 #-}

module ArbitraryOrphans () where

import           Grammar.Gbnf (Gbnf (Gbnf), UnparsedSentence (UnparsedSentence))
import           Grammar.Lexer (Lexeme)
import           Grammar.Parser.Atomics.Adjectives (Adjective (Adjective))
import           Grammar.Parser.Atomics.Misc (Determiner (Determiner))
import           Grammar.Parser.Atomics.Nouns
  ( DirectionalStimulus (DirectionalStimulus)
  )
import           Grammar.Parser.Atomics.Prepositions
  ( DirectionalStimulusMarker (DirectionalStimulusMarker)
  )
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb (AcquisitionVerb)
  , DirectionalStimulusVerb (DirectionalStimulusVerb)
  , DivestmentVerb (DivestmentVerb)
  , ImplicitStimulusVerb (ImplicitStimulusVerb)
  )
import           Grammar.Parser.Composites.Nouns
  ( DirectionalStimulusNounPhrase
  , NounPhrase
  , PlayerName (PlayerName)
  , PlayerNamePhrase (PlayerNamePhrase)
  )
import           Grammar.Parser.GCase (VerbKey)
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Arbitrary.Generic
  ( GenericArbitrary (GenericArbitrary)
  )
import           Test.QuickCheck.Instances.Text ()

deriving newtype instance Arbitrary Gbnf
deriving newtype instance Arbitrary UnparsedSentence
deriving via (GenericArbitrary Lexeme) instance Arbitrary Lexeme
deriving newtype instance Arbitrary DirectionalStimulusMarker
deriving newtype instance Arbitrary DirectionalStimulus
deriving newtype instance Arbitrary Determiner
deriving newtype instance Arbitrary Adjective
deriving newtype instance Arbitrary DirectionalStimulusVerb
deriving newtype instance Arbitrary ImplicitStimulusVerb
deriving newtype instance Arbitrary AcquisitionVerb
deriving newtype instance Arbitrary DivestmentVerb
deriving via (GenericArbitrary (NounPhrase DirectionalStimulus)) instance Arbitrary (NounPhrase DirectionalStimulus)
deriving via (GenericArbitrary DirectionalStimulusNounPhrase) instance Arbitrary DirectionalStimulusNounPhrase
deriving newtype instance Arbitrary PlayerName
deriving via (GenericArbitrary (NounPhrase PlayerName)) instance Arbitrary (NounPhrase PlayerName)
deriving newtype instance Arbitrary PlayerNamePhrase
deriving via (GenericArbitrary VerbKey) instance Arbitrary VerbKey
