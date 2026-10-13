module Test.Arbitrary.Verbs (arbitrary) where

import           Data.HashSet (toList)
import           Grammar.Parser.Atomics.Semantics.Verbs.Acquisition
  ( acquisitionVerbs
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.Divestment
  ( divestmentVerbs
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( implicitStimulusVerbs
  )
import           Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
  , DivestmentVerb
  , ImplicitStimulusVerb
  )
import           Test.QuickCheck (Arbitrary (arbitrary), elements)

instance Arbitrary ImplicitStimulusVerb where
  arbitrary = elements (toList implicitStimulusVerbs)

instance Arbitrary AcquisitionVerb where
  arbitrary = elements (toList acquisitionVerbs)

instance Arbitrary DivestmentVerb where
  arbitrary = elements (toList divestmentVerbs)
