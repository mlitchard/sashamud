{-# OPTIONS_GHC -Wno-orphans #-}

module ArbitraryOrphans () where

import           Grammar.Gbnf (Gbnf (Gbnf), UnparsedSentence (UnparsedSentence))
import           Test.QuickCheck (Arbitrary)
import           Test.QuickCheck.Instances.Text ()

deriving newtype instance Arbitrary Gbnf
deriving newtype instance Arbitrary UnparsedSentence
