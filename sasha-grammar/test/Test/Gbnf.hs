module Test.Gbnf (spec) where

import           Data.Bool (Bool)
import           Data.Foldable (all)
import           Data.HashSet (toList)
import           Data.Semigroup ((<>))
import           Data.Text (Text, isInfixOf, pack)
import           GHC.Show (Show (show))
import           Grammar.Gbnf (Gbnf (Gbnf), generateGbnf)
import           Grammar.Lexer (HasLexeme (toLexeme))
import           Grammar.Parser.Atomics.Semantics.Adjectives (adjectives)
import           Grammar.Parser.Atomics.Semantics.Misc (determiners)
import           Grammar.Parser.Atomics.Semantics.Nouns.DirectionalStimulus
  ( directionalStimuli
  )
import           Grammar.Parser.Atomics.Semantics.Nouns.Objective (objectives)
import           Grammar.Parser.Atomics.Semantics.Prepositions.DirectionalStimulusMarker
  ( directionalStimulusMarkers
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
import           Grammar.Parser.Composites.Nouns (PlayerName (PlayerName))
import           Test.Hspec (Spec, describe, it, shouldSatisfy)

spec :: Spec
spec = describe "generateGbnf" (do
  it "lists every implicit stimulus verb"
    (toList implicitStimulusVerbs `shouldSatisfy` all listed)
  it "lists every directional stimulus verb"
    (toList directionalStimulusVerbs `shouldSatisfy` all listed)
  it "lists every directional stimulus marker"
    (toList directionalStimulusMarkers `shouldSatisfy` all listed)
  it "lists every directional stimulus"
    (toList directionalStimuli `shouldSatisfy` all listed)
  it "lists every acquisition verb"
    (toList acquisitionVerbs `shouldSatisfy` all listed)
  it "lists every divestment verb"
    (toList divestmentVerbs `shouldSatisfy` all listed)
  it "lists every objective"
    (toList objectives `shouldSatisfy` all listed)
  it "lists every determiner"
    (toList determiners `shouldSatisfy` all listed)
  it "lists every adjective"
    (toList adjectives `shouldSatisfy` all listed)
  it "lists the player name"
    (gbnf `shouldSatisfy` isInfixOf "player-name ::= \"Raj\"")
  it "writes the three imperative shapes"
    (gbnf `shouldSatisfy` isInfixOf "root ::= stimulus | acquisition | divestment")
  it "writes the implicit look"
    (gbnf `shouldSatisfy` isInfixOf "stimulus ::= implicit-stimulus-verb | ")
  it "writes look at a noun"
    (gbnf `shouldSatisfy` isInfixOf "| directional-stimulus-verb \" \" directional-stimulus-marker \" \" directional-stimulus |")
  it "writes look at a player"
    (gbnf `shouldSatisfy` isInfixOf "| directional-stimulus-verb \" \" directional-stimulus-marker \" \" player-name\n")
  it "writes get with an object phrase"
    (gbnf `shouldSatisfy` isInfixOf "acquisition ::= acquisition-verb \" \" object-phrase\n")
  it "writes drop with an object phrase"
    (gbnf `shouldSatisfy` isInfixOf "divestment ::= divestment-verb \" \" object-phrase\n")
  it "writes the bare noun object phrase"
    (gbnf `shouldSatisfy` isInfixOf "object-phrase ::= objective | ")
  it "writes the determiner noun object phrase"
    (gbnf `shouldSatisfy` isInfixOf "| determiner \" \" objective |")
  it "writes the adjective noun object phrase"
    (gbnf `shouldSatisfy` isInfixOf "| adjective \" \" objective |")
  it "writes the determiner adjective noun object phrase"
    (gbnf `shouldSatisfy` isInfixOf "| determiner \" \" adjective \" \" objective\n"))
  where
    gbnf :: Text
    gbnf = case generateGbnf [PlayerName "Raj"] of
      Gbnf txt -> txt

    listed :: (HasLexeme a) => a -> Bool
    listed w = ("\"" <> pack (show (toLexeme w)) <> "\"") `isInfixOf` gbnf
