module Test.Gbnf (spec) where

import           Data.Bool (Bool)
import           Data.Foldable (all)
import           Data.HashSet (toList)
import           Data.Semigroup ((<>))
import           Data.Text (Text, isInfixOf, pack, toLower)
import           GHC.Show (Show (show))
import           Grammar.Gbnf
  ( Gbnf (Gbnf)
  , UnparsedSentence (UnparsedSentence)
  , generateGbnf
  )
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
import           Test.Hspec
  ( Spec
  , describe
  , it
  , shouldNotSatisfy
  , shouldSatisfy
  )

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
  it "leaves out the player name when the sentence names none"
    (gbnf `shouldNotSatisfy` isInfixOf "player-name")
  it "writes the three imperative shapes"
    (gbnf `shouldSatisfy` isInfixOf "root ::= stimulus | acquisition | divestment")
  it "writes the implicit look"
    (gbnf `shouldSatisfy` isInfixOf "stimulus ::= implicit-stimulus-verb | ")
  it "writes look at a noun"
    (gbnf `shouldSatisfy` isInfixOf "| directional-stimulus-verb \" \" directional-stimulus-marker \" \" directional-stimulus |")
  it "writes look at an adjective noun"
    (gbnf `shouldSatisfy` isInfixOf "| directional-stimulus-verb \" \" directional-stimulus-marker \" \" adjective \" \" directional-stimulus |")
  it "writes look at a determiner adjective noun"
    (named `shouldSatisfy` isInfixOf "| directional-stimulus-verb \" \" directional-stimulus-marker \" \" determiner \" \" adjective \" \" directional-stimulus |")
  it "writes look at a player"
    (named `shouldSatisfy` isInfixOf "| directional-stimulus-verb \" \" directional-stimulus-marker \" \" player-name\n")
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
    (gbnf `shouldSatisfy` isInfixOf "| determiner \" \" adjective \" \" objective\n")
  it "keeps BALL as the objective the sentence names"
    (narrowed `shouldSatisfy` isInfixOf "objective ::= \"ball\"\n")
  it "keeps RED as the adjective the sentence names"
    (narrowed `shouldSatisfy` isInfixOf "adjective ::= \"red\"\n")
  it "keeps THE as the determiner the sentence names"
    (narrowed `shouldSatisfy` isInfixOf "determiner ::= \"the\"\n")
  it "drops FLOOR"
    (narrowed `shouldNotSatisfy` isInfixOf "\"floor\"")
  it "drops SMALL"
    (narrowed `shouldNotSatisfy` isInfixOf "\"small\"")
  it "drops WHITE"
    (narrowed `shouldNotSatisfy` isInfixOf "\"white\"")
  it "drops A"
    (narrowed `shouldNotSatisfy` isInfixOf "\"a\"")
  it "keeps the full directional stimulus marker list when the sentence names no marker"
    (narrowed `shouldSatisfy` isInfixOf "directional-stimulus-marker ::= \"at\"\n")
  it "keeps the implicit stimulus verb"
    (narrowed `shouldSatisfy` isInfixOf "implicit-stimulus-verb ::= \"look\"\n")
  it "keeps the directional stimulus verb"
    (narrowed `shouldSatisfy` isInfixOf "directional-stimulus-verb ::= \"look\"\n")
  it "keeps the acquisition verb"
    (narrowed `shouldSatisfy` isInfixOf "acquisition-verb ::= \"get\"\n")
  it "keeps the divestment verb"
    (narrowed `shouldSatisfy` isInfixOf "divestment-verb ::= \"drop\"\n")
  it "keeps the player the sentence names"
    (named `shouldSatisfy` isInfixOf "player-name ::= \"raj\"\n")
  it "leaves out the player name rule when the sentence names no player"
    (unnamed `shouldNotSatisfy` isInfixOf "player-name"))
  where
    gbnf :: Text
    gbnf = case generateGbnf (UnparsedSentence "") [PlayerName "raj"] of
      Gbnf txt -> txt

    narrowed :: Text
    narrowed = case generateGbnf (UnparsedSentence "pick up the red ball") [PlayerName "raj"] of
      Gbnf txt -> txt

    named :: Text
    named = case generateGbnf (UnparsedSentence "look at raj") [PlayerName "raj", PlayerName "bob"] of
      Gbnf txt -> txt

    unnamed :: Text
    unnamed = case generateGbnf (UnparsedSentence "look at the ball") [PlayerName "raj", PlayerName "bob"] of
      Gbnf txt -> txt

    listed :: (HasLexeme a) => a -> Bool
    listed w = ("\"" <> toLower (pack (show (toLexeme w))) <> "\"") `isInfixOf` gbnf
