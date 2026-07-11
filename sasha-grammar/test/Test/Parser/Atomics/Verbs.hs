module Test.Parser.Atomics.Verbs (spec) where

import           Control.Applicative (pure)
import           Data.Bool (Bool (False))
import           Data.Either (Either (Left, Right))
import           Data.Foldable (elem)
import           Data.Function (($))
import           Data.Text (pack)
import           Data.Tuple (fst)
import           GHC.Show (show)
import           Grammar.Lexer (HasLexeme (toLexeme), lexify, tokens)
import           Grammar.Parser.Atomics.Semantics.Rules.Verbs
  ( implicitStimulusVerbRule
  )
import           Grammar.Parser.Atomics.Semantics.Verbs.ImplicitStimulus
  ( implicitStimulusVerbs
  )
import           Test.Arbitrary.Verbs ()
import           Test.Hspec (Spec, describe)
import           Test.Hspec.QuickCheck (prop)
import           Test.QuickCheck (Arbitrary (arbitrary))
import           Test.QuickCheck.Gen (Gen)
import           Text.Earley.Parser (fullParses, parser)

checkImplicitStimulusVerb :: Gen Bool
checkImplicitStimulusVerb = do
  implicitStimulusVerb <- arbitrary
  case lexify tokens (pack (show (toLexeme implicitStimulusVerb))) of
    Left _  -> pure False
    Right toks ->
      let parsed = fst (fullParses (parser (implicitStimulusVerbRule implicitStimulusVerbs)) toks)
      in pure (implicitStimulusVerb `elem` parsed)

spec :: Spec
spec = describe "Atomic Verbs Roundtrips" $ do
  prop "Implicit Stimulus Verbs" checkImplicitStimulusVerb
