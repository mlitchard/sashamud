{-# LANGUAGE TemplateHaskell #-}
module Grammar.Gbnf (Gbnf (Gbnf), UnparsedSentence (UnparsedSentence), generateGbnf) where

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)
import           Data.Bool (Bool)
import           Data.Either (Either (Left, Right))
import           Data.Eq (Eq)
import           Data.Foldable (elem)
import           Data.Function ((.))
import           Data.Functor ((<$>))
import           Data.HashSet (toList)
import           Data.Kind (Type)
import           Data.List (filter)
import           Data.Ord (Ord)
import           Data.Semigroup ((<>))
import           Data.Text (Text, intercalate, pack, toLower, unlines)
import           GHC.Generics (Generic)
import           GHC.Show (Show (show))
import           Grammar.Lexer
  ( HasLexeme (toLexeme)
  , Lexeme (UNKNOWN)
  , lexify
  , tokens
  )
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

generateGbnf :: UnparsedSentence -> [PlayerName] -> Gbnf
generateGbnf (UnparsedSentence sentence) playerNames = Gbnf (unlines (
  [ "root ::= stimulus | acquisition | divestment"
  , "stimulus ::= implicit-stimulus-verb | directional-stimulus-verb \" \" directional-stimulus-marker \" \" directional-stimulus | directional-stimulus-verb \" \" directional-stimulus-marker \" \" determiner \" \" directional-stimulus | directional-stimulus-verb \" \" directional-stimulus-marker \" \" adjective \" \" directional-stimulus | directional-stimulus-verb \" \" directional-stimulus-marker \" \" determiner \" \" adjective \" \" directional-stimulus" <> playerAlternative
  , "acquisition ::=acquisition-verb \" \" object-phrase"
  , "divestment ::= divestment-verb \" \" object-phrase"
  , "object-phrase ::= objective | determiner \" \" objective | adjective \" \" objective | determiner \" \" adjective \" \" objective"
  , "implicit-stimulus-verb ::= " <> wordAlternatives (toList implicitStimulusVerbs)
  , "directional-stimulus-verb ::= " <> wordAlternatives (toList directionalStimulusVerbs)
  , "directional-stimulus-marker ::= " <> wordAlternatives (narrowed (toList directionalStimulusMarkers))
  , "directional-stimulus ::= " <> wordAlternatives (narrowed (toList directionalStimuli))
  ] <> playerNameLines <>
  [ "acquisition-verb ::= " <> wordAlternatives (toList acquisitionVerbs)
  , "divestment-verb ::= " <> wordAlternatives (toList divestmentVerbs)
  , "objective ::= " <> wordAlternatives (narrowed (toList objectives))
  , "determiner ::= " <> wordAlternatives (narrowed (toList determiners))
  , "adjective ::= " <> wordAlternatives (narrowed (toList adjectives))
  ]))
  where
    lexemes :: [Lexeme]
    lexemes = case lexify tokens sentence of
      Left _   -> []
      Right ls -> ls

    narrowed :: (HasLexeme a) => [a] -> [a]
    narrowed ws = case filter recognized ws of
      []   -> ws
      kept -> kept

    recognized :: (HasLexeme a) => a -> Bool
    recognized w = toLexeme w `elem` lexemes

    namedPlayers :: [PlayerName]
    namedPlayers = filter named playerNames

    named :: PlayerName -> Bool
    named (PlayerName txt) = UNKNOWN txt `elem` lexemes

    playerAlternative :: Text
    playerAlternative = case namedPlayers of
      [] -> ""
      _  -> " | directional-stimulus-verb \" \" directional-stimulus-marker \" \" player-name"

    playerNameLines :: [Text]
    playerNameLines = case namedPlayers of
      [] -> []
      _  -> ["player-name ::= " <> playerNameAlternatives]

    wordAlternatives :: (HasLexeme a) => [a] -> Text
    wordAlternatives ws = intercalate " | " (quote . toLower . pack . show . toLexeme <$> ws)

    playerNameAlternatives :: Text
    playerNameAlternatives = intercalate " | " ((\(PlayerName txt) -> quote txt) <$> namedPlayers)

    quote :: Text -> Text
    quote txt = "\"" <> txt <> "\""

derivingTypeScriptDefinition ''Gbnf
derivingTypeScriptDefinition ''UnparsedSentence
