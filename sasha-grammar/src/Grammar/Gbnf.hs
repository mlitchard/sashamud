{-# LANGUAGE TemplateHaskell #-}
module Grammar.Gbnf (Gbnf (Gbnf), UnparsedSentence (UnparsedSentence), generateGbnf) where

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Eq (Eq)
import           Data.Function ((.))
import           Data.Functor ((<$>))
import           Data.HashSet (toList)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           Data.Semigroup ((<>))
import           Data.Text (Text, intercalate, pack, unlines)
import           GHC.Generics (Generic)
import           GHC.Show (Show (show))
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

type Gbnf :: Type
newtype Gbnf = Gbnf Text
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, Ord, ToJSON)
  deriving anyclass (NFData)

type UnparsedSentence :: Type
newtype UnparsedSentence = UnparsedSentence Text
  deriving stock (Generic, Show)
  deriving newtype (Eq, FromJSON, Ord, ToJSON)
  deriving anyclass (NFData)

generateGbnf :: [PlayerName] -> Gbnf
generateGbnf playerNames = Gbnf (unlines
  [ "root ::= stimulus | acquisition | divestment"
  , "stimulus ::= implicit-stimulus-verb | directional-stimulus-verb \" \" directional-stimulus-marker \" \" directional-stimulus | directional-stimulus-verb \" \" directional-stimulus-marker \" \" player-name"
  , "acquisition ::= acquisition-verb \" \" object-phrase"
  , "divestment ::= divestment-verb \" \" object-phrase"
  , "object-phrase ::= objective | determiner \" \" objective | adjective \" \" objective | determiner \" \" adjective \" \" objective"
  , "implicit-stimulus-verb ::= " <> wordAlternatives (toList implicitStimulusVerbs)
  , "directional-stimulus-verb ::= " <> wordAlternatives (toList directionalStimulusVerbs)
  , "directional-stimulus-marker ::= " <> wordAlternatives (toList directionalStimulusMarkers)
  , "directional-stimulus ::= " <> wordAlternatives (toList directionalStimuli)
  , "player-name ::= " <> playerNameAlternatives
  , "acquisition-verb ::= " <> wordAlternatives (toList acquisitionVerbs)
  , "divestment-verb ::= " <> wordAlternatives (toList divestmentVerbs)
  , "objective ::= " <> wordAlternatives (toList objectives)
  , "determiner ::= " <> wordAlternatives (toList determiners)
  , "adjective ::= " <> wordAlternatives (toList adjectives)
  ])
  where
    wordAlternatives :: (HasLexeme a) => [a] -> Text
    wordAlternatives ws = intercalate " | " (quote . pack . show . toLexeme <$> ws)

    playerNameAlternatives :: Text
    playerNameAlternatives = intercalate " | " ((\(PlayerName txt) -> quote txt) <$> playerNames)

    quote :: Text -> Text
    quote txt = "\"" <> txt <> "\""

derivingTypeScriptDefinition ''Gbnf
derivingTypeScriptDefinition ''UnparsedSentence
