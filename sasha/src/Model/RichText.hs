module Model.RichText
  ( -- * Core Types
    RichText (..)
  , StyledSpan (..)
  , TextStyle (..)
  , TextColor (..)
    -- * Smart Constructors
  , plain
  , colored
  , bold
  , boldColored
  , styled
    -- * Conversion
  , toPlainText
    -- * Default Style
  , defaultStyle
  ) where

import           SashaPrelude

import           Control.DeepSeq (NFData)
import           Data.Aeson (FromJSON, ToJSON)
import           Data.Aeson.TypeScript (derivingTypeScriptDefinition)

type TextColor :: Type
data TextColor
  = Red
  | Green
  | Blue
  | Yellow
  | Cyan
  | Magenta
  | White
  | BrightWhite
  | BrightRed
  | BrightGreen
  | BrightBlue
  | BrightYellow
  | BrightCyan
  | BrightMagenta
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type TextStyle :: Type
data TextStyle = TextStyle
  { tsFgColor :: Maybe TextColor
  , tsBold    :: Bool
  , tsItalic  :: Bool
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

defaultStyle :: TextStyle
defaultStyle = TextStyle
  { tsFgColor = Nothing
  , tsBold    = False
  , tsItalic  = False
  }

type StyledSpan :: Type
data StyledSpan = StyledSpan
  { ssStyle :: TextStyle
  , ssText  :: Text
  }
  deriving stock (Eq, Generic, Ord, Show)
  deriving anyclass (FromJSON, NFData, ToJSON)

type RichText :: Type
newtype RichText = RichText { unRichText :: [StyledSpan] }
  deriving stock (Eq, Generic, Ord, Show)
  deriving newtype (FromJSON, ToJSON)
  deriving anyclass (NFData)

instance Semigroup RichText where
  RichText a <> RichText b = RichText (a <> b)

instance Monoid RichText where
  mempty = RichText []

toPlainText :: RichText -> Text
toPlainText (RichText spans) = mconcat (map ssText spans)

plain :: Text -> RichText
plain t = RichText [StyledSpan defaultStyle t]

colored :: TextColor -> Text -> RichText
colored c t = RichText [StyledSpan defaultStyle { tsFgColor = Just c } t]

bold :: Text -> RichText
bold t = RichText [StyledSpan defaultStyle { tsBold = True } t]

boldColored :: TextColor -> Text -> RichText
boldColored c t = RichText [StyledSpan TextStyle { tsFgColor = Just c, tsBold = True, tsItalic = False } t]

styled :: TextStyle -> Text -> RichText
styled s t = RichText [StyledSpan s t]

derivingTypeScriptDefinition ''TextColor
derivingTypeScriptDefinition ''TextStyle
derivingTypeScriptDefinition ''StyledSpan
derivingTypeScriptDefinition ''RichText
