module Grammar.Parser.Atomics.Verbs
  ( AcquisitionVerb
      ( AcquisitionVerb
      , _fromAcquisitionVerb
      )
  , DirectionalStimulusVerb
      ( DirectionalStimulusVerb
      , _fromDirectionalStimulusVerb
      )
  , DivestmentVerb
      ( DivestmentVerb
      , _fromDivestmentVerb
      )
  , ImplicitStimulusVerb
      ( ImplicitStimulusVerb
      , _fromImplicitStimulusVerb
      )
  ) where

import           Control.DeepSeq (NFData)
import           Data.Eq (Eq)
import           Data.Hashable (Hashable)
import           Data.Kind (Type)
import           Data.Ord (Ord)
import           GHC.Show (Show)
import           Grammar.Lexer (HasLexeme (toLexeme), Lexeme)

type ImplicitStimulusVerb :: Type
newtype ImplicitStimulusVerb = ImplicitStimulusVerb { _fromImplicitStimulusVerb :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme ImplicitStimulusVerb where
  toLexeme = _fromImplicitStimulusVerb

type DirectionalStimulusVerb :: Type
newtype DirectionalStimulusVerb = DirectionalStimulusVerb { _fromDirectionalStimulusVerb :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme DirectionalStimulusVerb where
  toLexeme = _fromDirectionalStimulusVerb

type AcquisitionVerb :: Type
newtype AcquisitionVerb = AcquisitionVerb { _fromAcquisitionVerb :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme AcquisitionVerb where
  toLexeme = _fromAcquisitionVerb

type DivestmentVerb :: Type
newtype DivestmentVerb = DivestmentVerb { _fromDivestmentVerb :: Lexeme }
  deriving stock (Eq, Ord, Show)
  deriving newtype (Hashable, NFData)

instance HasLexeme DivestmentVerb where
  toLexeme = _fromDivestmentVerb
