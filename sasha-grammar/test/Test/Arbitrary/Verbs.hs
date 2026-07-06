module Test.Arbitrary.Verbs (arbitrary) where

import           Data.HashSet (toList)
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( implicitStimulusVerbs
  )
import           Grammar.Parser.Atomics.Verbs (ImplicitStimulusVerb)
import           Test.QuickCheck (Arbitrary (arbitrary), elements)

instance Arbitrary ImplicitStimulusVerb where
  arbitrary = elements (toList implicitStimulusVerbs)
